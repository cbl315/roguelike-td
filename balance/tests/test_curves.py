"""敌人曲线单测 — 对照 GDD §3.3 的数值表，锁定回归基线。

GDD §3.3 表的关键点（用默认 WaveParams：base=100, growth=1.05，B-3 校准值）：
  count = round(8 + 1.5×wave)   [公式为 SSOT；Python banker's rounding]
  wave 1  hp=100,     count=10   (round(9.5)=10)
  wave 5  hp≈121.6,   count=16   (round(15.5)=16)
  wave 10 hp≈155.1,   count=23
  wave 15 hp≈198.0,   count=30   (round(30.5)=30, banker's rounding)
  wave 30 hp≈411.6,   count=53
"""
from __future__ import annotations

import math

from td_balance import curves
from td_balance.loader import load_wave_params


def test_default_params_from_yaml():
    p = load_wave_params()
    assert p.hp_base == 100.0
    assert p.hp_growth == 1.05    # B-3 校准：1.18→1.05
    assert p.count_base == 8
    assert p.count_per_wave == 1.5
    assert p.boss_every_n == 10
    assert p.boss_share == 0.4


def test_enemy_hp_curve():
    p = curves.WaveParams()
    assert curves.enemy_hp(1, p) == 100.0
    assert math.isclose(curves.enemy_hp(5, p), 121.6, rel_tol=0.01)
    assert math.isclose(curves.enemy_hp(10, p), 155.1, rel_tol=0.01)
    assert math.isclose(curves.enemy_hp(15, p), 198.0, rel_tol=0.01)
    assert math.isclose(curves.enemy_hp(30, p), 411.6, rel_tol=0.01)


def test_enemy_count_curve():
    p = curves.WaveParams()
    assert curves.enemy_count(1, p) == 10       # round(9.5) = 10
    assert curves.enemy_count(5, p) == 16        # round(15.5) = 16
    assert curves.enemy_count(10, p) == 23       # round(23.0) = 23
    assert curves.enemy_count(15, p) == 30       # round(30.5) = 30 (banker's)
    assert curves.enemy_count(30, p) == 53       # round(53.0) = 53


def test_required_dps_monotonic_increase():
    """所需 DPS 随波次严格递增（指数曲线）。"""
    p = curves.WaveParams()
    prev = 0.0
    for w in range(1, 31):
        d = curves.required_dps(w, p)
        assert d > prev
        prev = d


def test_required_dps_anchor_values():
    """对照公式 SSOT 的所需 DPS 锚点（允许 ±1% 容差）。
    实际值（脚本算出，作为回归基线；growth=1.05，B-3 校准值）：
      wave 1:  100×10/26     = 38.5
      wave 5:  121.6×16/30   = 64.8
      wave 10: 155.1×23/35   = 101.9
      wave 15: 198.0×30/40   = 148.5
      wave 30: 411.6×53/55   = 396.6
    """
    p = curves.WaveParams()
    anchors = {1: 38.5, 5: 64.8, 10: 101.9, 15: 148.5, 30: 396.6}
    for w, expected in anchors.items():
        actual = curves.required_dps(w, p)
        assert math.isclose(actual, expected, rel_tol=0.01), \
            f"wave {w}: 期望 {expected}, 实际 {actual:.1f}"


def test_boss_and_elite_detection():
    p = curves.WaveParams()
    assert curves.is_boss_wave(10, p)
    assert curves.is_boss_wave(20, p)
    assert curves.is_boss_wave(30, p)
    assert not curves.is_boss_wave(15, p)
    # 精英波：5,15,25（非 Boss）
    assert curves.is_elite_wave(5, p)
    assert curves.is_elite_wave(15, p)
    assert curves.is_elite_wave(25, p)
    # 10/20/30 是 Boss 不是精英
    assert not curves.is_elite_wave(10, p)


def test_curve_table_length():
    p = curves.WaveParams()
    table = curves.curve_table(range(1, 31), p)
    assert len(table) == 30
    assert table[0]["wave"] == 1
    assert table[-1]["wave"] == 30
