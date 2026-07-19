"""经济模型单测 — 验证 GDD §3.4 收入公式 + 支出成本。"""
from __future__ import annotations

import math

from td_balance import curves
from td_balance.economy import (
    EconomyParams,
    bond_draw_cost,
    equip_upgrade_cost,
    load_economy_params,
    reroll_cost,
    wave_income,
)


def test_load_params_from_yaml():
    """锁定 B-3 校准后的 economy.yaml 值（收入恢复 ×3，curve 1.05）。"""
    e = load_economy_params()
    assert e.base_passive == 3          # B-3 恢复（原 1→3）
    assert e.per_kill == 1.5            # 0.5→1.5
    assert e.per_wave_clear == 60       # 平衡调参：45→60
    assert e.boss_bonus == 120          # 40→120
    assert e.elite_bonus == 30          # 10→30
    assert e.draw_bond == 30
    assert e.bond_draw_cap == 60
    assert e.devour == 80
    assert e.reroll_cap_per_wave == 3


def test_wave_income_normal_wave():
    """wave 5（精英波）收入 = 3×30 + 1.5×16 + 60 + 30 = 204。"""
    e = load_economy_params()
    d = wave_income(5, e)
    assert abs(d["total"] - 204.0) < 1.0
    assert d["is_elite"] is True
    assert d["is_boss"] is False


def test_wave_income_boss_wave():
    """wave 10（Boss 波）含 Boss 加成 120。"""
    e = load_economy_params()
    d = wave_income(10, e)
    duration = curves.wave_duration(10)
    count = curves.enemy_count(10)
    expected = 3 * duration + 1.5 * count + 60 + 120
    assert abs(d["total"] - expected) < 1.0
    assert d["is_boss"] is True


def test_wave_income_monotonic_growth_within_wave_type():
    """同类型波（普通/精英/Boss）的收入随波次增长。
    注意：Boss 波有 +150 激增，故跨类型不单调（Boss→下一普通会跌），
    这是真实设计（Boss 是金币高潮），不算 bug。
    """
    e = load_economy_params()
    # 只比普通波（非精英非Boss）
    normal_totals = [wave_income(w, e)["total"] for w in range(1, 31)
                     if not wave_income(w, e)["is_boss"] and not wave_income(w, e)["is_elite"]]
    prev = 0.0
    for t in normal_totals:
        assert t > prev, f"普通波收入非单调: {t} <= {prev}"
        prev = t
    # Boss 波收入应远高于相邻普通波（激增）
    boss10 = wave_income(10, e)["total"]
    norm11 = wave_income(11, e)["total"]
    assert boss10 > norm11   # Boss 波 > 下一普通波（金币高潮设计）


def test_bond_draw_cost_uses_yaml_increment_with_cap():
    """抽羁绊成本 = base + increment×times_drawn，封顶 cap。
    increment=10, cap=60：第 0 次 30，第 3 次 60（封顶），第 5 次仍 60。
    """
    e = load_economy_params()
    assert bond_draw_cost(0, e) == 30
    assert bond_draw_cost(3, e) == 60   # 30+10×3=60，恰好封顶
    assert bond_draw_cost(5, e) == 60   # 30+10×5=80 但封顶 60
    assert bond_draw_cost(100, e) == 60 # 永不超过 cap


def test_equip_upgrade_cost_formula():
    """升装备 = 15 + 4×level。"""
    e = load_economy_params()
    assert equip_upgrade_cost(0, e) == 15   # +1
    assert equip_upgrade_cost(1, e) == 19   # +2
    assert equip_upgrade_cost(8, e) == 47   # +9


def test_reroll_cost_increments():
    """重投递增：base + increment×times。"""
    e = load_economy_params()
    # 技能重投：10, 13, 16, 19...
    assert math.isclose(reroll_cost(0, 10, 3), 10)
    assert math.isclose(reroll_cost(2, 10, 3), 16)
    # 羁绊重投：8, 11, 14...
    assert math.isclose(reroll_cost(0, 8, 3), 8)
    assert math.isclose(reroll_cost(1, 8, 3), 11)
