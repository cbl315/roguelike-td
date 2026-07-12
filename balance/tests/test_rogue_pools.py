"""抽取池单测 — 验证羁绊 3 选 1 生成 + 稀有度加权分布 + 重投。"""
from __future__ import annotations

from collections import Counter

from td_balance.rng import RNG
from td_balance.rogue_pools import KIND_BOND, RoguePools


def test_rarity_distribution_matches_weights():
    """稀有度分布接近权重 58/30/9/2.5/0.5（大数定律，容差 5%）。

    5 档统一评价：N/SR/SSR/UR/EX（2026-07-12 修订）。
    """
    pools = RoguePools(RNG(seed=7))
    counts = Counter()
    n = 6000
    for _ in range(n):
        r = pools._weighted_rarity()
        counts[r] += 1
    # N≈58%, SR≈30%, SSR≈9%, UR≈2.5%, EX≈0.5%
    assert abs(counts["N"] / n - 0.58) < 0.05
    assert abs(counts["SR"] / n - 0.30) < 0.05
    assert abs(counts["SSR"] / n - 0.09) < 0.03
    assert abs(counts["UR"] / n - 0.025) < 0.02
    # EX 权重极低（0.5%，6000 次约 30 次）——只断言"出现且占比合理"
    assert counts["EX"] > 0, "EX 档应至少出现一次"
    assert counts["EX"] / n < 0.02, "EX 档占比不应异常偏高"


def test_bond_offers():
    """羁绊 3 选 1 返回 3 个羁绊。"""
    pools = RoguePools(RNG(seed=3))
    offers = pools.draw_bond_offers()
    assert len(offers) == 3
    assert all(o.kind == KIND_BOND for o in offers)


def test_reroll_replaces_all_when_no_lock():
    """无锁定时，重投替换全部 3 个。"""
    pools = RoguePools(RNG(seed=99))
    first = pools.draw_bond_offers()
    second = pools.reroll(first, lambda: pools.draw_bond_offers())
    assert len(second) == 3
    # 极大概率不同（id 集合）
    assert {o.id for o in first} != {o.id for o in second}


def test_reproducible_with_same_seed():
    """同种子 → 同序列（可复现）。"""
    p1 = RoguePools(RNG(seed=123))
    p2 = RoguePools(RNG(seed=123))
    o1 = p1.draw_bond_offers()
    o2 = p2.draw_bond_offers()
    assert [o.id for o in o1] == [o.id for o in o2]
