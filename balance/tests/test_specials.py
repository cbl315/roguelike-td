"""特殊效果精确建模单测 — transform/chain/followup 的 DPS 乘数。"""
from __future__ import annotations

import math

from td_balance.combat_stats import Special


def test_chain_mult_no_bounces():
    sp = Special()
    assert sp.chain_mult() == 1.0


def test_chain_mult_with_bounces():
    """3 弹，decay 0.7：1 + 0.7 + 0.49 + 0.343 = 2.533。"""
    sp = Special(chain_extra_bounces=3)
    m = sp.chain_mult(decay=0.7)
    assert math.isclose(m, 2.533, rel_tol=0.01)


def test_followup_mult():
    """每 3 击追击 1.0 倍 → 1 + 1/3 = 1.333。"""
    sp = Special(followup_hit_ratio=1.0, followup_every_n_hits=3)
    assert math.isclose(sp.followup_mult(), 1.0 + 1.0 / 3, rel_tol=0.01)


def test_followup_mult_zero_when_no_ratio():
    sp = Special(followup_hit_ratio=0.0, followup_every_n_hits=3)
    assert sp.followup_mult() == 1.0


def test_transform_uptime_single_cycle():
    """cooldown > wave_duration：最多 1 次，持续 min(duration, wave)。"""
    sp = Special(transform_duration=8.0, transform_cooldown=60.0)
    # 波长 40s，8s 变身 → uptime 8/40 = 0.2
    assert math.isclose(sp.transform_uptime(40.0), 0.2, rel_tol=0.01)


def test_transform_uptime_multiple_cycles():
    """cooldown < wave_duration：可多次触发。"""
    sp = Special(transform_duration=5.0, transform_cooldown=10.0)
    # 波长 30s，每 10s 一次 5s 变身 = 3 次 × 5s = 15s → uptime 0.5
    assert math.isclose(sp.transform_uptime(30.0), 0.5, rel_tol=0.01)


def test_transform_uptime_zero_when_no_transform():
    sp = Special()
    assert sp.transform_uptime(40.0) == 0.0


def test_transform_uptime_capped_at_1():
    """变身持续 > 波长 → uptime 封顶 1.0。"""
    sp = Special(transform_duration=100.0, transform_cooldown=100.0)
    assert sp.transform_uptime(30.0) == 1.0


def test_resolve_player_picks_up_realm_reward():
    """resolve_player 应把境界 reward 的属性累加进 PlayerCombat。
    path_realm[id] = 已完成的境界数；修满 = len(realms)（全部完成）。
    当前仅遮天体系：修满后应拾取帝体 reward（final_dmg_mult + status: heaven_emperor）。
    """
    from td_balance.combat_stats import resolve_player
    from td_balance.player import PlayerState
    from td_balance.rng import RNG
    from td_balance.rogue_pools import RoguePools
    pools = RoguePools(RNG(seed=1))
    state = PlayerState()
    # 找 zhutian path，设为全部完成（path_realm = len(realms)）
    for p in pools.paths:
        if p.id == "zhutian":
            state.path_realm = {"zhutian": len(p.realms)}   # 全部境界完成
            break
    pc = resolve_player(state, pools)
    # 遮天各境界 reward 累加进 offense.final_dmg_mults（王体 0.35 + 皇体 0.7 + 帝体 1.75 …）
    assert len(pc.offense.final_dmg_mults) > 0
    # status heaven_emperor 应被拾取（帝体 reward）
    assert "heaven_emperor" in pc.special.statuses
