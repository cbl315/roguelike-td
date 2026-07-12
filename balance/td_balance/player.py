"""玩家状态 + 动作记录（B-2 经济模拟用）。

只跟踪经济/抽取相关的状态（金币、技能、羁绊池、装备等级、操作历史），
**不**含战斗数值（那是 B-3 的事）。
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class ActionType(str, Enum):
    """大厅里玩家可做的操作（GDD §4.4 / §5 / §6）。"""
    DRAW_BOND = "draw_bond"          # 抽羁绊（3 选 1）
    UPGRADE_EQUIP = "upgrade_equip"  # 升装备（保底轨）
    BOND_REROLL = "bond_reroll"      # 羁绊 3 选 1 重投
    SKIP_SKILL = "skip_skill"        # 跳过 3 选 1 换金
    DEVOUR = "devour"                # 吞噬羁绊组合（金币 sink，GDD §6.1）


@dataclass
class Action:
    """一次大厅操作的记录（供统计）。"""
    type: ActionType
    cost: float = 0.0          # 花的金币（skill_level 用免费机会则 0）
    detail: str = ""           # 如抽到的稀有度、升到几级


@dataclass
class PlayerState:
    """一局玩家的经济/构筑状态。"""
    gold: float = 0.0
    # 羁绊池（id 列表，上限来自 bonds.yaml bond_pool.capacity）
    bond_pool: list[str] = field(default_factory=list)
    bond_pool_capacity: int = 10
    # 已吞噬池（套系 id）—— 旧字段，保留兼容
    devoured_sets: list[str] = field(default_factory=list)
    # 修炼路径进度：{path_id: 当前境界索引}（境界树，GDD §6.1）
    path_realm: dict[str, int] = field(default_factory=dict)
    # 技能（id → level）
    skills: dict[str, int] = field(default_factory=dict)
    # 装备等级（0–9）
    equip_level: int = 0
    # 本波统计
    rerolls_this_wave: int = 0
    # 全局操作历史（每波一组）
    history: list[list[Action]] = field(default_factory=list)

    @property
    def bond_pool_full(self) -> bool:
        return len(self.bond_pool) >= self.bond_pool_capacity

    def begin_wave(self) -> None:
        """每波开始：重置本波重投计数，开新的操作组。"""
        self.rerolls_this_wave = 0
        self.history.append([])

    def add_gold(self, amount: float) -> None:
        self.gold += amount

    def spend(self, amount: float) -> bool:
        """花钱；不够返回 False 不扣。"""
        if self.gold < amount:
            return False
        self.gold -= amount
        return True

    def record(self, action: Action) -> None:
        if self.history:
            self.history[-1].append(action)

    def ops_this_wave(self) -> list[Action]:
        return self.history[-1] if self.history else []
