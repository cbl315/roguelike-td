# roguelike-td

横屏 **Roguelike 塔防**：英雄即核心（可移动、自动战斗 + 手动大招），30 波防守，
四小说体系构筑（遮天/星辰变/宠魅/斗破）+ 符文融合万金油。Godot 4.6 客户端 +
Python 数值模拟双端同步（同一套数据 SSOT）。

## 当前状态（2026-11）

- **核心玩法全闭环**：种子选体系 → 羁绊三选一 → 突破守关者考核升境 → Boss Debuff 应对（换/删）→ 手动大招
- **数值**：整体胜率 ~51-53%（1000 局蒙特卡洛，目标带 50-55%）
- **测试**：Python 109 用例 + Godot headless 7 套 + MCP 交互回归 10/10，全绿
- 已完成 Web 导出 + 虚拟摇杆；iOS/Android 打包与服务端在 TODO

## 目录结构

```
client/    Godot 4.6 客户端（GDScript，数据驱动：data/*.json）
balance/   Python 数值验证与蒙特卡洛模拟（data/*.yaml 是 SSOT）
tools/     gmcp（godot_mcp 自动化实测工具集）、gen_art（AI 素材管线）
docs/      GDD / 技术架构 / TODO
site/      数值报告静态站点
```

## 快速开始

```bash
# 客户端：Godot 4.6 打开 client/ 工程，F5 运行
#   调试键：G=+500金 B=跳Boss波 N=秒杀 Q=大招 R=重开 M=静音

# 数值端：
cd balance
python3 validate.py            # 全部单测 + 曲线表
python3 run_report.py -n 1000  # 蒙特卡洛胜率报告
python3 diag_paths.py -n 300   # 分体系胜率诊断
python3 export_json.py         # yaml → client/data/*.json 同步
```

## 文档

- [游戏设计 GDD](docs/GAME_DESIGN.md)（§14 = 最新实现状态实录）
- [技术架构](docs/TECHNICAL_ARCHITECTURE.md)
- [待办 TODO](docs/TODO.md)（Boss 波设计、BGM、服务端等）
- [数值工具](balance/README.md) · [gmcp 实测工具](tools/gmcp/README.md)
