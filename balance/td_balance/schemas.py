"""数据 dataclass 定义（对应 data/*.yaml）。

这些是 content data 的类型；战斗运行态用 combat.damage.CombatStats。
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class AffixDef:
    id: str
    name: str
    rarity: str                 # N/SR/SSR/UR/EX（统一评价档，2026-07-12 修订）
    stacking: str               # add/mult/independent/chance/replace
    effect: dict[str, Any]      # 修改 CombatStats 哪些字段
    note: str = ""


@dataclass(frozen=True)
class SkillDef:
    id: str
    name: str
    rarity: str                 # N/SR/SSR/UR/EX
    tags: list[str]
    atk_ratio: float
    base_affixes: list[str]     # 自带词条 id
    note: str = ""


@dataclass(frozen=True)
class BondDef:
    id: str
    name: str
    set: str
    effect: dict[str, Any]
    rarity: str = "N"           # N/SR/SSR/UR/EX（按 path 境界深度标档）
    is_seed: bool = False       # 是否体系种子（点了解锁体系）
    seed_path: str = ""         # 种子解锁的体系 path id
    seed_gold: float = 0.0      # 选了种子给的金币奖励


@dataclass(frozen=True)
class RealmDef:
    """修炼路径里的一个境界。"""
    name: str
    bonds: list[str]              # 此境界需要的羁绊 id
    reward: dict[str, Any] = field(default_factory=dict)
    synergy_unlock: str = ""      # 顶级境界触发的联动 id


@dataclass(frozen=True)
class PathDef:
    """修炼路径（境界树）。由低→高多个境界组成。"""
    id: str
    name: str
    realms: list[RealmDef]


@dataclass(frozen=True)
class SetTier:          # 保留旧名兼容（已不再用于新逻辑，loader 仍提供）
    count: int
    devour: bool = False
    effect: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class SetDef:
    id: str
    name: str
    tiers: list[SetTier]


@dataclass(frozen=True)
class SynergyDef:
    id: str
    name: str
    trigger: dict[str, Any]     # { all: [...] }
    effect: dict[str, Any]
    note: str = ""
    rarity: str = "N"           # N/SR/SSR/UR/EX（统一评价档；原 tier 字段合并，SS→EX）


@dataclass(frozen=True)
class EnemyHpCurve:
    base: float
    growth: float


@dataclass(frozen=True)
class EnemyCountCurve:
    base: int
    per_wave: float


@dataclass(frozen=True)
class WaveDurationCurve:
    base_seconds: int
    per_wave_seconds: int


@dataclass(frozen=True)
class WaveConfig:
    enemy_hp: EnemyHpCurve
    enemy_count: EnemyCountCurve
    wave_duration: WaveDurationCurve
    boss_every_n: int
    boss_total_hp_share: float
    elite_every_n: int
    main_quest_waves: int


@dataclass(frozen=True)
class IncomeDef:
    base_passive: float
    per_kill: float
    per_wave_clear: float
    elite_bonus: float
    boss_bonus: float


@dataclass(frozen=True)
class CostDef:
    draw_bond: float
    bond_draw_increment: float
    bond_draw_cap: float = 60.0          # 抽取成本上限
    equipment_upgrade_base: float = 15.0
    equipment_upgrade_per_level: float = 4.0
    skill_skip_reward: float = 20.0
    devour: float = 50.0
