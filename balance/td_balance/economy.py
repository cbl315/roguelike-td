"""经济系统 — 收入模型 (GDD §3.4)。

每波金币收入 = 被动(每秒) + 击杀(每只) + 清波奖励 + 精英/Boss 加成。
公式严格对应 data/economy.yaml + data/waves.yaml。

纯逻辑、可单测。复用 curves（波次属性）与 loader（经济参数）。

本模块只算"这一波能拿多少金币"，不管"怎么花"（那是 strategy + rogue_pools）。
"""
from __future__ import annotations

from dataclasses import dataclass

from . import curves
from .loader import load_costs, load_income, load_wave_params


@dataclass(frozen=True)
class EconomyParams:
    """经济参数（来自 economy.yaml）。"""
    base_passive: float        # 金/秒
    per_kill: float
    per_wave_clear: float
    elite_bonus: float
    boss_bonus: float
    # 支出
    draw_bond: float
    bond_draw_increment: float
    bond_draw_cap: float            # 抽取成本上限
    equip_upgrade_base: float
    equip_upgrade_per_level: float
    skill_skip_reward: float
    devour: float                  # 吞噬消耗（金币 sink）
    # 商店刷新（GDD §4.4）
    bond_reroll_base: float
    bond_reroll_increment: float
    reroll_cap_per_wave: int
    lock_cost: float


def load_economy_params() -> EconomyParams:
    """从 economy.yaml 构造 EconomyParams。"""
    inc = load_income()
    cost = load_costs()
    shop = _load_shop()
    return EconomyParams(
        base_passive=inc.base_passive,
        per_kill=inc.per_kill,
        per_wave_clear=inc.per_wave_clear,
        elite_bonus=inc.elite_bonus,
        boss_bonus=inc.boss_bonus,
        draw_bond=cost.draw_bond,
        bond_draw_increment=cost.bond_draw_increment,
        bond_draw_cap=cost.bond_draw_cap,
        equip_upgrade_base=cost.equipment_upgrade_base,
        equip_upgrade_per_level=cost.equipment_upgrade_per_level,
        skill_skip_reward=cost.skill_skip_reward,
        devour=cost.devour,
        bond_reroll_base=shop["bond_reroll_base"],
        bond_reroll_increment=shop["bond_reroll_increment"],
        reroll_cap_per_wave=shop["reroll_cap_per_wave"],
        lock_cost=shop["lock_cost"],
    )


def _load_shop() -> dict:
    """读 economy.yaml 的 shop_reroll 段。"""
    from .loader import _load
    return _load("economy")["shop_reroll"]


# ── 收入计算 ──

def wave_income(wave: int, econ: EconomyParams | None = None) -> dict:
    """返回某波的金币收入明细 + 总额。

    返回 dict 便于报告展示每项贡献。
    """
    if econ is None:
        econ = load_economy_params()
    p = load_wave_params()
    duration = curves.wave_duration(wave, p)
    count = curves.enemy_count(wave, p)
    is_boss = curves.is_boss_wave(wave, p)
    is_elite = curves.is_elite_wave(wave, p)

    passive = econ.base_passive * duration
    kills = econ.per_kill * count
    clear = econ.per_wave_clear
    elite = econ.elite_bonus if is_elite else 0.0
    boss = econ.boss_bonus if is_boss else 0.0
    total = passive + kills + clear + elite + boss

    return {
        "wave": wave,
        "duration": duration,
        "enemy_count": count,
        "is_boss": is_boss,
        "is_elite": is_elite,
        "passive": round(passive, 1),
        "kills": round(kills, 1),
        "clear": clear,
        "elite_bonus": elite,
        "boss_bonus": boss,
        "total": round(total, 1),
    }


# ── 支出成本 ──

def bond_draw_cost(times_drawn: int, econ: EconomyParams) -> float:
    """抽羁绊成本。base + increment×times，封顶 cap（防后期不敢抽）。"""
    return min(econ.draw_bond + econ.bond_draw_increment * times_drawn, econ.bond_draw_cap)


def equip_upgrade_cost(current_level: int, econ: EconomyParams) -> float:
    """升装备：cost = base + per_level × current_level。"""
    return econ.equip_upgrade_base + econ.equip_upgrade_per_level * current_level


def devour_cost(econ: EconomyParams) -> float:
    """吞噬羁绊组合消耗（金币 sink，GDD §6.1）。固定值。"""
    return econ.devour


def reroll_cost(times_rerolled: int, base: float, increment: float) -> float:
    """重投成本（递增）：第 n 次重投 = base + increment×(已重投次数)。"""
    return base + increment * times_rerolled


def bond_reroll_cost(times: int, econ: EconomyParams) -> float:
    return reroll_cost(times, econ.bond_reroll_base, econ.bond_reroll_increment)
