#!/usr/bin/env python3
"""driver.py — godot_mcp 编辑器插件（WebSocket 127.0.0.1:6550）直连客户端。

协议（client/addons/godot_mcp，Coding-Solo v4.x）：
  请求 {"id": <str>, "command": <str>, "params": {}} → 响应 {"id", "status", "result"}

前置条件：
  1. Godot 编辑器打开本项目 client/（插件随编辑器启动并监听 6550）
  2. pip3 install websocket-client（用户级 Python3）

CLI 用法：
  python3 driver.py <command> [json_params] [timeout_sec]
  python3 driver.py get_project_info
  python3 driver.py run_project
  python3 driver.py capture_game_screenshot '{"max_width": 1280}'   # 大响应存 last_response.json
  python3 driver.py exec_run '{"source": "return 1 + 1"}'
"""
import json
import os
import sys
import time

from websocket import create_connection, WebSocketTimeoutException

URI = "ws://127.0.0.1:6550"


class GMcpError(RuntimeError):
    pass


class GMcp:
    """单次命令一连接的轻客户端（编辑器/游戏重启无残留状态）。"""

    def __init__(self, uri: str = URI, timeout: float = 30.0):
        try:
            self.ws = create_connection(uri, timeout=timeout)
        except Exception as e:  # noqa: BLE001 — 统一转成可读错误
            raise GMcpError(
                f"无法连接 {uri}：{e}。请确认 Godot 编辑器已打开 client/ 工程（godot_mcp 插件监听 6550）。"
            ) from e
        self._id = 0

    def call(self, command: str, params=None, timeout: float = 60.0):
        """发一条命令并等待同 id 响应（忽略异步推送帧）。"""
        self._id += 1
        rid = f"c{self._id}"
        self.ws.settimeout(timeout)
        self.ws.send(json.dumps({"id": rid, "command": command, "params": params or {}}))
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                raw = self.ws.recv()
            except WebSocketTimeoutException:
                break
            data = json.loads(raw)
            if data.get("id") == rid:
                return data
        raise GMcpError(f"{command} 超时（{timeout}s 内无同 id 响应）")

    def close(self):
        try:
            self.ws.close()
        except Exception:  # noqa: BLE001
            pass


def call_once(command: str, params=None, timeout: float = 60.0) -> dict:
    """便捷入口：连接 → 调用 → 关闭。"""
    g = GMcp(timeout=timeout)
    try:
        return g.call(command, params, timeout)
    finally:
        g.close()


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    params = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 60.0
    try:
        resp = call_once(cmd, params, timeout)
    except GMcpError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    s = json.dumps(resp, ensure_ascii=False)
    if len(s) > 4000:  # 截图等大响应落盘，stdout 只给摘要
        out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "last_response.json")
        with open(out, "w") as f:
            f.write(s)
        print(f"SAVED {out} ({len(s)} chars), status={resp.get('status')}")
    else:
        print(s)
    return 0


if __name__ == "__main__":
    sys.exit(main())
