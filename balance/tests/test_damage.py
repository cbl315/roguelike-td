"""伤害管线单测 — 验证 Master Damage Pipeline 各乘区正确。

对照 GDD §3.1 / §3.2。每条测试锁定一个公式的预期行为。
"""
from __future__ import annotations

import math

from td_balance.combat.damage import (
    BASE_ATK,
    BASE_CRIT_DMG,
    BASE_CRIT_RATE,
    CombatStats,
    EnemyStats,
    breakdown,
    crit_factor,
    defense_mult,
    expected_dps,
    expected_hit_dmg,
    final_mult,
    mitigation,
)


def test_base_constants_match_gdd():
    """基础属性锁 GDD §3.1：ATK=50, 暴击率=5%, 暴伤=150%。"""
    assert BASE_ATK == 50.0
    assert BASE_CRIT_RATE == 0.05
    assert BASE_CRIT_DMG == 1.5


def test_mitigation_curve():
    """护甲减伤 = armor/(armor+K)，K=100。"""
    assert mitigation(0) == 0.0
    assert math.isclose(mitigation(100), 0.5)       # 50% 软上限点
    assert math.isclose(mitigation(300), 0.75)      # 高甲递减
    assert mitigation(1000) < 0.92                   # 永远 <1


def test_defense_mult_with_armor_pen():
    """穿甲按比例减免护甲减伤。"""
    # armor=100 → mit=0.5；无穿甲 defense=0.5
    assert math.isclose(defense_mult(100, 0.0), 0.5)
    # 穿甲 100% → 减伤完全无效 → defense=1.0
    assert math.isclose(defense_mult(100, 1.0), 1.0)
    # 穿甲 50% → 减伤剩一半 → defense=0.75
    assert math.isclose(defense_mult(100, 0.5), 0.75)


def test_crit_factor():
    """暴击期望因子。"""
    # 0% 暴击 → 因子 1.0
    assert math.isclose(crit_factor(0.0, 2.0), 1.0)
    # 100% 暴击 暴伤 2.0 → 因子 2.0
    assert math.isclose(crit_factor(1.0, 2.0), 2.0)
    # 30% 暴击 暴伤 2.1 → 1 + 0.3×1.1 = 1.33
    assert math.isclose(crit_factor(0.30, 2.10), 1.33, abs_tol=0.01)
    # 暴击率封顶 100%（输入 1.5 不爆）
    assert math.isclose(crit_factor(1.5, 2.0), 2.0)


def test_final_mult_is_multiplicative():
    """最终伤害乘区 = Π(1+x)，每条乘法。"""
    assert final_mult([]) == 1.0
    assert math.isclose(final_mult([0.15]), 1.15)
    # 0.15 与 0.20 → 1.15×1.20 = 1.38（不是加法的 1.35）
    assert math.isclose(final_mult([0.15, 0.20]), 1.38)


def test_dmg_type_additive():
    """物伤% + 法伤% 同源加法叠加（都进 dmg_type）。"""
    # 无暴击(率0/伤1)、无穿甲、无甲：hit = ATK × (1+物伤%)
    base = CombatStats(atk=100, physical_dmg_pct=0.30, crit_rate=0.0, crit_dmg=1.0)
    no_enemy = EnemyStats(armor=0)
    assert math.isclose(expected_hit_dmg(base, no_enemy), 130.0)


def test_multishot_diminishing_returns():
    """多重射：每额外弹 ×0.85。n=2 → 1+0.85=1.85 倍。"""
    s1 = CombatStats(atk=100, crit_rate=0.0, crit_dmg=1.0, projectile_count=1)
    s2 = CombatStats(atk=100, crit_rate=0.0, crit_dmg=1.0, projectile_count=2)
    e = EnemyStats(armor=0)
    ratio = expected_dps(s2, e) / expected_dps(s1, e)
    assert math.isclose(ratio, 1.85)


def test_true_damage_skips_armor():
    """真伤跳过护甲。100% 真伤 + 高甲 → 不被减免。"""
    full_true = CombatStats(atk=100, crit_rate=0.0, crit_dmg=1.0, true_dmg_pct=1.0)
    no_true = CombatStats(atk=100, crit_rate=0.0, crit_dmg=1.0, true_dmg_pct=0.0)
    heavy_armor = EnemyStats(armor=900)   # mit≈0.9
    e_true = expected_hit_dmg(full_true, heavy_armor)
    e_normal = expected_hit_dmg(no_true, heavy_armor)
    assert e_true > e_normal * 5          # 真伤远高于被重甲减免的普伤


def test_breakdown_matches_dps():
    """breakdown 的 dps 字段与 expected_dps 一致。"""
    s = CombatStats(
        atk=67.5, physical_dmg_pct=0.60, skill_mult_pct=0.25,
        final_dmg_mults=[0.15], crit_rate=0.30, crit_dmg=2.10,
        attack_speed=1.2, projectile_count=2,
    )
    e = EnemyStats(armor=33)
    b = breakdown(s, e)
    assert math.isclose(b["dps"], expected_dps(s, e))
