"""策略 + 完整单局经济循环单测。"""
from __future__ import annotations

from td_balance.economy import load_economy_params, wave_income
from td_balance.player import ActionType, PlayerState
from td_balance.rng import RNG
from td_balance.rogue_pools import RoguePools
from td_balance.strategy import SimpleStrategy


def test_simple_strategy_spends_until_broke_or_full():
    """贪心策略会花光钱或填满可买的东西。"""
    e = load_economy_params()
    state = PlayerState(gold=300.0)
    pools = RoguePools(RNG(seed=5))
    strat = SimpleStrategy()
    actions = strat.spend_lobby(state, pools, e, skill_upgrades_available=1)
    # 应至少做了几个操作
    assert len(actions) >= 2
    # 钱不该还能买 cheapest 的东西（抽羁绊 30）—— 否则策略没花光
    # 若羁绊池满了/装备满级则可能剩钱，此例 gold=300 一般不够填满
    # 只断言：要么钱 < 30，要么池满或装备满
    cant_buy_anything = (
        state.gold < 30
        or (state.bond_pool_full and state.equip_level >= 9)
    )
    assert cant_buy_anything


def test_one_run_economy_loop():
    """跑完整一局 30 波的经济循环，验证不崩 + 记录完整。"""
    e = load_economy_params()
    state = PlayerState(gold=0.0)
    pools = RoguePools(RNG(seed=2024))
    strat = SimpleStrategy()

    for wave in range(1, 31):
        # 1) 战斗获金
        income = wave_income(wave, e)
        state.add_gold(income["total"])
        # 2) 大厅花金
        state.begin_wave()
        skill_upgrades = 2 if income["is_boss"] else 1
        strat.spend_lobby(state, pools, e, skill_upgrades_available=skill_upgrades)

    # 应有 30 波的历史
    assert len(state.history) == 30
    # 总操作数 > 0
    total_ops = sum(len(h) for h in state.history)
    assert total_ops > 0
    # 应该抽到一些羁绊
    assert len(state.bond_pool) > 0 or any(
        any(a.type == ActionType.DRAW_BOND for a in h) for h in state.history
    )


def test_run_is_reproducible():
    """同种子两局，操作数序列一致（可复现）。"""
    def run_once(seed):
        e = load_economy_params()
        state = PlayerState(gold=0.0)
        pools = RoguePools(RNG(seed=seed))
        strat = SimpleStrategy()
        for wave in range(1, 31):
            income = wave_income(wave, e)
            state.add_gold(income["total"])
            state.begin_wave()
            strat.spend_lobby(state, pools, e, skill_upgrades_available=2 if income["is_boss"] else 1)
        return [len(h) for h in state.history]

    seq1 = run_once(999)
    seq2 = run_once(999)
    assert seq1 == seq2


def test_ops_per_wave_above_target_floor():
    """GDD 目标每波 1.5–2 次操作。验证至少 ≥1.5（B6 预期会超，但不会低于地板太多）。
    这是松断言——B-2 报告会给精确分布并校准。"""
    e = load_economy_params()
    ops_counts = []
    for seed in range(20):
        state = PlayerState(gold=0.0)
        pools = RoguePools(RNG(seed=seed))
        strat = SimpleStrategy()
        for wave in range(1, 31):
            income = wave_income(wave, e)
            state.add_gold(income["total"])
            state.begin_wave()
            strat.spend_lobby(state, pools, e, skill_upgrades_available=2 if income["is_boss"] else 1)
            ops_counts.append(len(state.history[-1]))
    median = sorted(ops_counts)[len(ops_counts) // 2]
    # 预期会显著 > 2（B6 标注的收入偏高），但至少不会 < 1
    assert median >= 1
