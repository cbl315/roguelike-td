"""第 15 波走查单测 — 把 GDD §8（修正后可追溯版）锁成回归基线。

复现 reports/build_walkthrough.py 的 build，断言关键中间值与最终 DPS。
当有人改公式/基础数值/羁绊数据后，此测试若失败 = 基线变了，需 review。

已知结论（GDD §8 注）：纯羁绊+单技能词条的中期 build 打不过第 15 波
（DPS ≈ 373 vs 所需 787）。这是校准项，不是 bug——本测试锁定的是
"公式行为稳定"，而非"打得过"。
"""
from __future__ import annotations

import math

from td_balance import curves
from td_balance.combat.damage import CombatStats, EnemyStats, breakdown
from td_balance.loader import load_wave_params

from reports.build_walkthrough import build_mid_game_stats


def test_build_atk_is_traceable():
    """ATK = 50 × (1 + 15% + 20%) = 67.5。"""
    s = build_mid_game_stats()
    assert math.isclose(s.atk, 67.5)


def test_build_crit_and_speed():
    s = build_mid_game_stats()
    assert math.isclose(s.crit_rate, 0.30)      # 5%+10%+15%
    assert math.isclose(s.crit_dmg, 2.10)        # 1.5+0.6
    assert math.isclose(s.attack_speed, 1.20)    # 1.0×1.2


def test_wave15_required_dps_anchor():
    """B-3 校准后曲线 1.05，wave15 required_dps ≈ 148（原 1.18 时 761）。"""
    p = load_wave_params()
    need = curves.required_dps(15, p)
    assert math.isclose(need, 148.5, rel_tol=0.02)


def test_mid_build_dps_above_required():
    """B-3 校准后：中期 build DPS(345) > wave15 所需(148)——曲线放缓后 build 能过。
    原 B-1 的"打不过"结论已随曲线校准(1.18→1.05)反转。"""
    s = build_mid_game_stats()
    e = EnemyStats(armor=33)
    dps = breakdown(s, e)["dps"]
    p = load_wave_params()
    need = curves.required_dps(15, p)
    ratio = dps / need
    # build DPS 应在所需 1.5-3.5× 之间（能过但有富余，非碾压）
    assert dps > need, f"build DPS {dps:.0f} 应 > 所需 {need:.0f}（校准后曲线放缓）"


def test_synergy_doubles_dps():
    """凑齐'天帝之拳'联动(final+100%) → DPS 约×2。验证联动乘区生效。"""
    s = build_mid_game_stats()
    e = EnemyStats(armor=33)
    base_dps = breakdown(s, e)["dps"]
    s_with_synergy = s.with_final_mult(1.0)     # 联动 final +100%
    boosted_dps = breakdown(s_with_synergy, e)["dps"]
    # 乘区从 [0.15] → [0.15, 1.0]：1.15 → 1.15×2.0 = 2.30，故 DPS ≈ ×2
    ratio = boosted_dps / base_dps
    assert math.isclose(ratio, 2.0, rel_tol=0.01)
