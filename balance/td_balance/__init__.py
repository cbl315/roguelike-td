"""td_balance — roguelike-td 数值验证核心包。

纯逻辑、无引擎依赖、可单测、可种子复现。
对应 GDD 的 Core 层（docs/GAME_DESIGN.md §3）。

公开子模块：
    combat.damage  — 伤害主公式 (Master Damage Pipeline)
    curves         — 敌人 HP / 总血量 / 所需 DPS 曲线
    schemas        — 数据 dataclass 定义
    loader         — YAML → dataclass
    rng            — 可种子化随机源
"""

__version__ = "0.1.0"
