# td-balance — 数值验证工具

把《roguelike-td》GDD（`docs/GAME_DESIGN.md`）里的**战斗公式、敌人曲线、经济数值、抽取权重**编码成可执行、可单测的 Python 代码，在写任何游戏代码之前先验证数值自洽。

这套代码 + `data/*.yaml` 是未来 **Godot 客户端 + 服务端校验器共享的 single source of truth**（同一套公式/数值表）。

> 对应技术文档 `docs/TECHNICAL_ARCHITECTURE.md` 中"B 路线"。当前是 **B-1**：公式与曲线验证。
> B-2（经济/抽取池）、B-3（完整 Run 模拟 + 联动引擎 + 蒙特卡洛）为后续批次。

---

## 安装

需要 Python 3.11+。本子项目用 **uv** 作包管理（应用项目，`uv.lock` 已提交以保证环境一致）。

```bash
cd balance

# 用 uv（推荐）
uv sync --extra dev --extra reports   # dev=pytest, reports=matplotlib；两个 extra 都要

# 跑命令时用 uv 执行（无需手动 activate）
uv run pytest                         # 仅测试
uv run python validate.py             # 测试 + 生成 JSON
uv run python validate.py --site      # 同上 + 生成 site/ 静态站点
```

> ⚠️ `uv sync` 会**替换** extra 集合（不是追加）。需要测试就 `--extra dev`，需要建站就再加 `--extra reports`，两个都要就都写。

> 没有 uv？先装：`curl -LsSf https://astral.sh/uv/install.sh | sh`
> 实在不想装 uv，也可用标准 pip：`python -m venv .venv && source .venv/bin/activate && pip install -e ".[dev]"`

## 运行

```bash
# 一键：跑全部单测 + 打印 30 波曲线表 + 第 15 波走查
python validate.py

# 仅跑测试
pytest
```

## 产出

- **30 波曲线表**（血量 / 总血量 / 时长 / 所需 DPS）—— 对照 GDD §3.3。
- **第 15 波 build 走查**（逐步展开每个乘区）—— 对照 GDD §8。
- 测试失败 = GDD 数值与代码不一致，需 review。

## 目录

```
balance/
  data/*.yaml      内容数据（SSOT，策划改这里）
  td_balance/      核心纯逻辑（combat/damage.py, curves.py ...）
  reports/         曲线表 / build 走查输出
  tests/           单测（含把 GDD §8 锁成回归基线）
  validate.py      一键验证
```

## 修改流程

1. 改 `data/*.yaml`（数值）或 `td_balance/`（公式）。
2. 跑 `python validate.py`。
3. 若 `test_walkthrough` 失败 → 你改动了 GDD 已锁定的基线，确认是否真的要改 GDD，还是改错了代码。
