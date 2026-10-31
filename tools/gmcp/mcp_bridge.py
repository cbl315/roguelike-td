#!/usr/bin/env python3
"""mcp_bridge.py — stdio MCP server：把 godot_mcp 插件（ws://127.0.0.1:6550）接入 ZCode。

ZCode 配置（<repo>/.zcode/config.json，schema 严格，未知 key 会被丢弃）：
  {
    "mcp": {
      "servers": {
        "godot": {
          "type": "stdio",
          "command": "/usr/bin/python3",
          "args": ["<repo>/tools/gmcp/mcp_bridge.py"],
          "enabled": true
        }
      }
    }
  }

暴露的工具（透传到插件同名 command）：
  godot_run_project / godot_stop_project   启停游戏（等价 F5 / 停止）
  godot_press_key                           注入按键（真实键盘事件，走游戏输入管线）
  godot_exec                                在运行中的游戏里执行 GDScript（读状态/驱动逻辑）
  godot_screenshot                          截图（返回 image content，模型直接可见）
  godot_get_log                             读取游戏日志（错误排查）
  godot_get_project_info                    工程信息（连通性自检）
"""
import json
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from driver import call_once, GMcpError  # noqa: E402

PROTOCOL_VERSION = "2024-11-05"

# MCP 工具名 → (插件 command, 描述, JSON Schema)
TOOLS = {
    "godot_run_project": ("run_project", "启动游戏（等价 F5，从编辑器带 debugger 启动）",
                          {"type": "object", "properties": {}}),
    "godot_stop_project": ("stop_project", "停止运行中的游戏", {"type": "object", "properties": {}}),
    "godot_press_key": ("execute_input_sequence",
                        "注入按键序列（真实键盘事件）。keys: 如 [\"g\",\"b\",\"q\"]，hold_ms 默认 60",
                        {"type": "object",
                         "properties": {"keys": {"type": "array", "items": {"type": "string"}},
                                        "hold_ms": {"type": "number", "default": 60}},
                         "required": ["keys"]}),
    "godot_exec": ("exec_run",
                   "在运行中的游戏内执行 GDScript 源码（同步、禁 OS/文件写）。"
                   "绑定：autoload 按名 + tree/root + holder；return 的值回传。"
                   "例：'var gm = root.get_node(\"/root/GameRoot/GameManager\")\\nreturn gm._build.gold'",
                   {"type": "object", "properties": {"source": {"type": "string"}},
                  "required": ["source"]}),
    "godot_screenshot": ("capture_game_screenshot", "截取游戏画面（base64 PNG）",
                         {"type": "object",
                          "properties": {"max_width": {"type": "number", "default": 1280}}}),
    "godot_get_log": ("get_log_messages", "读取游戏运行日志（含脚本错误）",
                      {"type": "object", "properties": {}}),
    "godot_get_project_info": ("get_project_info", "Godot 工程信息（连通性自检）",
                               {"type": "object", "properties": {}}),
}


def build_params(tool: str, args: dict) -> dict:
    """MCP 工具参数 → 插件 command params。"""
    if tool == "godot_press_key":
        hold = float(args.get("hold_ms", 60))
        inputs = [{"key": k, "start_ms": i * 200, "duration_ms": hold}
                  for i, k in enumerate(args.get("keys", []))]
        return {"inputs": inputs}
    if tool == "godot_screenshot":
        return {"max_width": int(args.get("max_width", 1280))}
    return dict(args)


def to_content(tool: str, resp: dict) -> list:
    """插件响应 → MCP content 数组（截图转 image，其余转 text）。"""
    if tool == "godot_screenshot" and resp.get("status") == "success":
        r = resp.get("result") or {}
        for k in ("image_base64", "image", "base64"):
            if r.get(k):
                return [{"type": "image", "data": r[k], "mimeType": "image/png"}]
    return [{"type": "text", "text": json.dumps(resp, ensure_ascii=False)[:8000]}]


def reply(ws_id, result=None, error=None):
    out = {"jsonrpc": "2.0", "id": ws_id}
    if error is not None:
        out["error"] = error
    else:
        out["result"] = result
    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        method = msg.get("method", "")
        ws_id = msg.get("id")

        if method == "initialize":
            reply(ws_id, {"protocolVersion": PROTOCOL_VERSION,
                          "capabilities": {"tools": {}},
                          "serverInfo": {"name": "godot-gmcp-bridge", "version": "1.0.0"}})
        elif method == "notifications/initialized":
            pass  # 通知，无响应
        elif method == "tools/list":
            reply(ws_id, {"tools": [
                {"name": name, "description": desc, "inputSchema": schema}
                for name, (_cmd, desc, schema) in TOOLS.items()]})
        elif method == "tools/call":
            name = (msg.get("params") or {}).get("name", "")
            args = (msg.get("params") or {}).get("arguments") or {}
            if name not in TOOLS:
                reply(ws_id, error={"code": -32602, "message": f"unknown tool: {name}"})
                continue
            command, _d, _s = TOOLS[name]
            try:
                resp = call_once(command, build_params(name, args), timeout=90.0)
                reply(ws_id, {"content": to_content(name, resp),
                              "isError": resp.get("status") != "success"})
            except GMcpError as e:
                reply(ws_id, {"content": [{"type": "text", "text": f"ERROR: {e}"}], "isError": True})
        elif method == "ping":
            reply(ws_id, {})
        # 其他方法静默忽略


if __name__ == "__main__":
    main()
