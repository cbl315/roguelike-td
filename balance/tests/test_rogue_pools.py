"""抽取池单测 — 验证 3 选 1 生成 + 稀有度加权分布 + 重投。"""
from __future__ import annotations

from collections import Counter

from td_balance.rng import RNG
from td_balance.rogue_pools import KIND_BOND, KIND_NEW_SKILL, KIND_SKILL_AFFIX, RoguePools


def test_skill_offers_count_and_kinds():
    """技能 3 选 1 总返回 3 个，类型合法。"""
    pools = RoguePools(RNG(seed=42))
    offers = pools.draw_skill_offers(owned_skill_ids=set())
    assert len(offers) == 3
    assert all(o.kind in (KIND_NEW_SKILL, KIND_SKILL_AFFIX) for o in offers)


def test_skill_offers_new_skill_when_empty():
    """无任何技能时，新技能池非空，应能抽到 new_skill。"""
    pools = RoguePools(RNG(seed=1))
    kinds = []
    for _ in range(100):
        for o in pools.draw_skill_offers(owned_skill_ids=set()):
            kinds.append(o.kind)
    # 大量抽取应有 new_skill 出现
    assert KIND_NEW_SKILL in kinds


def test_rarity_distribution_matches_weights():
    """稀有度分布接近 60/30/8/2（大数定律，容差 5%）。"""
    pools = RoguePools(RNG(seed=7))
    counts = Counter()
    n = 6000
    for _ in range(n):
        r = pools._weighted_rarity()
        counts[r] += 1
    # common≈60%, rare≈30%, epic≈8%, legendary≈2%
    assert abs(counts["common"] / n - 0.60) < 0.05
    assert abs(counts["rare"] / n - 0.30) < 0.05
    assert abs(counts["epic"] / n - 0.08) < 0.03
    assert abs(counts["legendary"] / n - 0.02) < 0.02


def test_bond_offers():
    """羁绊 3 选 1 返回 3 个羁绊。"""
    pools = RoguePools(RNG(seed=3))
    offers = pools.draw_bond_offers()
    assert len(offers) == 3
    assert all(o.kind == KIND_BOND for o in offers)


def test_reroll_replaces_all_when_no_lock():
    """无锁定时，重投替换全部 3 个。"""
    pools = RoguePools(RNG(seed=99))
    first = pools.draw_skill_offers(set())
    second = pools.reroll(first, lambda: pools.draw_skill_offers(set()))
    assert len(second) == 3
    # 极大概率不同（id 集合）
    assert {o.id for o in first} != {o.id for o in second}


def test_reproducible_with_same_seed():
    """同种子 → 同序列（可复现）。"""
    p1 = RoguePools(RNG(seed=123))
    p2 = RoguePools(RNG(seed=123))
    o1 = p1.draw_skill_offers(set())
    o2 = p2.draw_skill_offers(set())
    assert [o.id for o in o1] == [o.id for o in o2]
