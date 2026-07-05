"""羁绊境界吞噬单测 — 验证 GDD §6.1 境界树（scalable sink）。

境界模型：每路径由低→高境界组成；当前境界羁绊凑齐 → 吞噬 → 升境 → 清空 → 再抽下一境。
这解决有限 sink 问题（每路径 5 境界 × 8 路径 = 40+ 次吞噬机会）。
"""
from __future__ import annotations

from td_balance.player import PlayerState
from td_balance.rng import RNG
from td_balance.rogue_pools import RoguePools


def test_find_devourable_when_first_realm_complete():
    """遮天第 0 境(凡体, 需 zt_mortal)凑齐 → 可吞噬。"""
    pools = RoguePools(RNG(seed=1))
    pool = ["zt_mortal"]
    dev = pools.find_devourable(pool, path_realm={})
    assert dev is not None
    assert dev[0] == "zhutian"
    assert dev[1] == 0                       # 第 0 境
    assert dev[2] == ["zt_mortal"]


def test_no_devourable_when_realm_incomplete():
    """遮天第 1 境(圣体, 需 2 个)只凑 1 个 → 不可吞噬。"""
    pools = RoguePools(RNG(seed=1))
    # path_realm 指向第 1 境（圣体），需 zt_saint_body + zt_sage_fruit，只放 1 个
    pool = ["zt_saint_body"]
    dev = pools.find_devourable(pool, path_realm={"zhutian": 1})
    assert dev is None


def test_devour_advances_realm():
    """吞噬后升境：第 0 境 → 第 1 境。"""
    pools = RoguePools(RNG(seed=1))
    pool = ["zt_mortal", "common_atk"]
    dev = pools.find_devourable(pool, path_realm={})
    path_id, idx, needed = dev
    removed = pools.devour(pool, needed)
    assert removed == ["zt_mortal"]
    assert "zt_mortal" not in pool
    assert "common_atk" in pool               # 通用羁绊不动


def test_multiple_realms_scalable():
    """一局里同一路径可多次吞噬（升多境）—— 这是 scalable sink 的关键。"""
    pools = RoguePools(RNG(seed=1))
    state = PlayerState(gold=10000.0)
    # 模拟连续升 3 境：凡体→圣体→王体
    realm_bonds_seq = [
        ["zt_mortal"],
        ["zt_saint_body", "zt_sage_fruit"],
        ["zt_king_blood", "zt_king_bone", "zt_king_soul"],
    ]
    devours = 0
    for needed in realm_bonds_seq:
        state.bond_pool = list(needed)
        dev = pools.find_devourable(state.bond_pool, state.path_realm)
        assert dev is not None, f"第 {devours} 境应可吞噬"
        _, idx, need = dev
        pools.devour(state.bond_pool, need)
        state.path_realm["zhutian"] = idx + 1
        devours += 1
    assert devours == 3
    assert state.path_realm["zhutian"] == 3


def test_current_realm_bonds():
    """查路径某境界的羁绊列表。"""
    pools = RoguePools(RNG(seed=1))
    bonds0 = pools.current_realm_bonds("zhutian", 0)
    assert bonds0 == ["zt_mortal"]
    bonds1 = pools.current_realm_bonds("zhutian", 1)
    assert set(bonds1) == {"zt_saint_body", "zt_sage_fruit"}
    # 越界返回空（已修满）
    assert pools.current_realm_bonds("zhutian", 99) == []


def test_devour_loop_runs_full_game():
    """端到端：境界树策略能跑完整局，且产生吞噬操作（不卡死）。

    收入二次校准后囤积本就低（~255），吞噬是否进一步降低取决于 RNG，
    故此测试只验证"能正常吞噬 + 跑完"，囤积达标由 economy_report 验证。
    """
    from td_balance.economy import load_economy_params, wave_income
    from td_balance.strategy import SimpleStrategy

    econ = load_economy_params()
    total_devours = 0
    for seed in range(10):
        state = PlayerState(gold=0.0)
        pools = RoguePools(RNG(seed=seed))
        strat = SimpleStrategy()
        for wave in range(1, 31):
            income = wave_income(wave, econ)
            state.add_gold(income["total"])
            state.begin_wave()
            strat.spend_lobby(state, pools, econ, skill_upgrades_available=2 if income["is_boss"] else 1)
        total_devours += sum(1 for h in state.history for a in h if a.type == "devour")
    # 10 局里应至少有一些吞噬发生（境界树生效）
    assert total_devours > 0, "境界树吞噬从未触发——逻辑可能有 bug"
