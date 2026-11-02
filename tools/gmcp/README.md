# gmcp — godot_mcp 直连工具集（游戏自动化实测）

绕过 ZCode MCP 桥，直接驱动 `client/addons/godot_mcp` 插件（Coding-Solo v4.x）的
WebSocket 服务（`ws://127.0.0.1:6550`，编辑器打开 client/ 工程时自动监听）。
2026-10-31 用这套链路完成了斗破体系 / 三伤害类型 / 应对道具 / 大招充能的全交互回归。

## 组成

| 文件 | 用途 |
|---|---|
| `driver.py` | 直连客户端 + CLI（`python3 driver.py <command> [json_params] [timeout]`） |
| `mcp_bridge.py` | stdio MCP server（ZCode 原生工具接入，见下） |
| `regression.py` | 交互回归剧本：抽卡→吞噬→Boss debuff→换删道具→大招（一键跑通） |

## 依赖

```bash
pip3 install --user websocket-client
```

## 直连用法（driver.py）

```bash
cd tools/gmcp
python3 driver.py get_project_info                    # 连通自检
python3 driver.py run_project                         # 启动游戏（=F5）
python3 driver.py execute_input_sequence '{"inputs": [{"key": "g", "start_ms": 0, "duration_ms": 60}]}'  # G+500金
python3 driver.py exec_run '{"source": "var gm = root.get_node(\"/root/GameRoot/GameManager\")\nreturn gm._build.gold"}'
python3 driver.py capture_game_screenshot '{"max_width": 1280}'   # 存 last_response.json（base64 PNG）
python3 driver.py stop_project
```

常用 exec 速查（游戏运行时，绑定 `root`/`tree`/autoload）：

| 目标 | source |
|---|---|
| 读状态 | `var gm = root.get_node("/root/GameRoot/GameManager")` → `gm._build.gold / gm._build.path_realm / int(gm.state)`（state: 1=战斗 4=败） |
| 抽卡三选一 | `root.get_node("/root/GameRoot/UILayer/Lobby")._bond_offers` |
| 选卡 | 同上 `_on_pick(idx)`（种子卡自动 +30 金并解锁体系） |
| 读大招能量 | `gm._ult_energy`（1.0 = 满） |
| 读 Boss debuff | `gm._boss_debuffs._picked` / `.active()` / `.is_active()` |
| 跳 Boss 波 | `root.get_node("/root/DebugKeys").jump_to_boss()`（clear_wave()=秒杀当前波） |

## ZCode 原生 MCP 工具接入

`.zcode/config.json` 已注册（重启会话后生效，Settings → MCP 可见 `godot`）：

```json
{"mcp": {"servers": {"godot": {
  "type": "stdio", "command": "/usr/bin/python3",
  "args": ["<repo>/tools/gmcp/mcp_bridge.py"], "enabled": true
}}}}
```

暴露 7 个工具：`godot_run_project` / `godot_stop_project` / `godot_press_key`
/ `godot_exec` / `godot_screenshot`（返回图片，模型直接看）
/ `godot_get_log` / `godot_get_project_info`。

> 历史：曾配 `@satelliteoflove/godot-mcp`（npx），协议与插件 v4.x 不匹配导致
> "node_repl 空调用"退化——已移除。npm 上的 godot-mcp 系包均停在 0.1.x，勿回退。

## 注意

- 编辑器必须保持打开（插件即服务端）；一次一条命令，无会话状态
- `exec_run` 在游戏暂停时依然可用（读状态/驱动 lobby 都行）；按键注入要求未暂停
- 调试键：G=+500金 B=跳Boss波 N=秒杀 Q=大招 R=重开（仅结算画面生效）M=静音
