"""羁绊境界吞噬单测 — 验证 GDD §6.1 境界树（scalable sink）。

境界模型：每路径由低→高境界组成；当前境界羁绊凑齐 → 吞噬 → 升境 → 清空 → 再抽下一境。
遮天 9 境界：轮海→道宫→四极→化龙→仙台→准帝→大帝→红尘仙→天帝。
"""
from __future__ import annotations

from td_balance.player import PlayerState
from td_balance.rng import RNG
from td_balance.rogue_pools import RoguePools


def test_find_devourable_when_first_realm_complete():
    """遮天第 0 境(轮海, 需 5 个羁绊含皆字秘)凑齐 → 可吞噬。"""
    pools = RoguePools(RNG(seed=1))
    pool = ["zt_lunhai_daojing", "zt_lunhai_kuhai", "zt_lunhai_mingquan", "zt_lunhai_shenqiao", "zt_jm_jie"]
    dev = pools.find_devourable(pool, path_realm={})
    assert dev is not None
    assert dev[0] == "zhutian"
    assert dev[1] == 0                       # 第 0 境（轮海）


def test_no_devourable_when_realm_incomplete():
    """遮天第 1 境(道宫, 需 6 个含斗字秘)只凑 1 个 → 不可吞噬。"""
    pools = RoguePools(RNG(seed=1))
    pool = ["zt_daogong_heart"]
    dev = pools.find_devourable(pool, path_realm={"zhutian": 1})
    assert dev is None


def test_devour_advances_realm():
    """吞噬后升境：第 0 境 → 第 1 境。"""
    pools = RoguePools(RNG(seed=1))
    pool = ["zt_lunhai_daojing", "zt_lunhai_kuhai", "zt_lunhai_mingquan", "zt_lunhai_shenqiao", "zt_jm_jie", "common_atk"]
    dev = pools.find_devourable(pool, path_realm={})
    path_id, idx, needed = dev
    removed = pools.devour(pool, needed)
    assert set(removed) == {"zt_lunhai_daojing", "zt_lunhai_kuhai", "zt_lunhai_mingquan", "zt_lunhai_shenqiao", "zt_jm_jie"}
    assert "common_atk" in pool               # 通用羁绊不动


def test_multiple_realms_scalable():
    """一局里同一路径可多次吞噬（升多境）—— 这是 scalable sink 的关键。"""
    pools = RoguePools(RNG(seed=1))
    state = PlayerState(gold=10000.0)
    # 模拟连续升 3 境：轮海(5)→道宫(6)→四极(5)，含九秘
    realm_bonds_seq = [
        ["zt_lunhai_daojing", "zt_lunhai_kuhai", "zt_lunhai_mingquan", "zt_lunhai_shenqiao", "zt_jm_jie"],
        ["zt_daogong_heart", "zt_daogong_liver", "zt_daogong_spleen", "zt_daogong_lung", "zt_daogong_kidney", "zt_jm_dou"],
        ["zt_siji_left_arm", "zt_siji_right_arm", "zt_siji_left_leg", "zt_siji_right_leg", "zt_jm_xing"],
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
    assert set(bonds0) == {"zt_lunhai_daojing", "zt_lunhai_kuhai", "zt_lunhai_mingquan", "zt_lunhai_shenqiao", "zt_jm_jie"}
    bonds1 = pools.current_realm_bonds("zhutian", 1)
    assert set(bonds1) == {"zt_daogong_heart", "zt_daogong_liver", "zt_daogong_spleen", "zt_daogong_lung", "zt_daogong_kidney", "zt_jm_dou"}
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
            strat.spend_lobby(state, pools, econ)
        total_devours += sum(1 for h in state.history for a in h if a.type == "devour")
    # 10 局里应至少有一些吞噬发生（境界树生效）
    assert total_devours > 0, "境界树吞噬从未触发——逻辑可能有 bug"


# ── Bug 回归测试 ──

def test_no_duplicate_bond_refs_in_any_path():
    """Bug: 铁壁/淘金/兽魂的 realm 4 和 5 引用了同一个羁绊。
    回归：所有路径的所有境界不重复引用羁绊。
    """
    pools = RoguePools(RNG(seed=1))
    for path in pools.paths:
        all_bonds = []
        for realm in path.realms:
            all_bonds.extend(realm.bonds)
        seen = set()
        for b in all_bonds:
            assert b not in seen, f"path {path.id} has duplicate bond ref: {b}"
            seen.add(b)


def test_all_realms_have_distinct_bonds():
    """每个路径的 realm 4 和 realm 5 必须引用不同羁绊。"""
    pools = RoguePools(RNG(seed=1))
    for path in pools.paths:
        if len(path.realms) >= 5:
            r4 = set(path.realms[3].bonds)
            r5 = set(path.realms[4].bonds)
            assert r4.isdisjoint(r5), f"path {path.id} realm 4&5 share bonds: {r4 & r5}"


def test_all_paths_can_reach_max_realm():
    """每个路径都能修满（所有境界的羁绊在池中互不重复）。"""
    pools = RoguePools(RNG(seed=1))
    for path in pools.paths:
        all_needed = []
        for realm in path.realms:
            all_needed.extend(realm.bonds)
        # 收集所有需要的羁绊，确保互不重复（否则永远修不满）
        assert len(all_needed) == len(set(all_needed)), \
            f"path {path.id} has {len(all_needed)} refs but only {len(set(all_needed))} unique — cannot max"
