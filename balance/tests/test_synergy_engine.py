"""联动引擎单测 — 验证境界树对齐后的触发判定。"""
from __future__ import annotations

from td_balance.player import PlayerState
from td_balance.rng import RNG
from td_balance.rogue_pools import RoguePools
from td_balance.synergy_engine import SynergyEngine


def _state_with_skills(skills: dict[str, int]) -> PlayerState:
    s = PlayerState()
    s.skills = skills
    return s


def test_bond_devoured_set_requires_max_realm():
    """修满顶级境界才触发 bond_devoured_set。"""
    pools = RoguePools(RNG(seed=1))
    engine = SynergyEngine()
    # zhutian 有 9 境界，需 path_realm=9（全部完成）
    s = _state_with_skills({"emperor_fist": 1})
    s.path_realm = {"zhutian": 8}   # 未满（第 8 境，差 1）
    active = engine.active(s, pools)
    ids = [a.id for a in active]
    assert "zhutian_emperor_fist" not in ids

    s.path_realm = {"zhutian": 9}   # 修满
    active = engine.active(s, pools)
    ids = [a.id for a in active]
    assert "zhutian_emperor_fist" in ids


def test_no_trigger_when_conditions_unmet():
    pools = RoguePools(RNG(seed=1))
    engine = SynergyEngine()
    s = _state_with_skills({"emperor_fist": 1})
    s.path_realm = {}   # 没修任何体系
    active = engine.active(s, pools)
    assert all(a.id != "zhutian_emperor_fist" for a in active)


def test_triple_synergy_emperor_thunder():
    """三重联动：天帝雷罚（遮天 + 天帝拳 + 联动增幅）。"""
    pools = RoguePools(RNG(seed=1))
    engine = SynergyEngine()
    s = _state_with_skills({"emperor_fist": 1})
    s.path_realm = {"zhutian": 9}
    # 三重联动需要 equipment_affix: synergy_amp
    # 当前 _has_affix 简化为检查 base_affixes，emperor_fist 有 base_affixes 吗？
    active = engine.active(s, pools)
    ids = [a.id for a in active]
    # 天帝之拳（两重）一定触发
    assert "zhutian_emperor_fist" in ids
    # 天帝雷罚（三重）取决于 equipment_affix 检查
    # emperor_fist.base_affixes 包含什么？
    skill = next((sk for sk in pools.skills if sk.id == "emperor_fist"), None)
    if skill and "synergy_amp" in skill.base_affixes:
        assert "emperor_thunder_judgment" in ids
    else:
        # 如果 base_affixes 不含 synergy_amp，三重不触发（equipment_affix 未满足）
        assert "emperor_thunder_judgment" not in ids


def test_all_synergies_require_devoured_set():
    """所有联动都必须有 bond_devoured_set 条件（取消 bond_owned / skill_owned 后的回归测试）。
    重构后：技能改为体系入口，修满体系 = 自动拥有起点技能，故不再有纯 skill_owned 联动。
    """
    pools = RoguePools(RNG(seed=1))
    engine = SynergyEngine()
    for syn in engine.synergies:
        conditions = syn.trigger.get("all", [])
        has_devoured = any("bond_devoured_set" in c for c in conditions)
        assert has_devoured, f"联动 {syn.id} 缺少 bond_devoured_set 条件"


def test_synergy_count():
    """联动总数 = 3（天帝之拳 + 天帝雷罚 + 九秘合一；当前仅遮天体系）。"""
    engine = SynergyEngine()
    assert len(engine.synergies) == 3


# ── Bug 回归测试 ──

def test_bond_owned_not_in_synergy_triggers():
    """Bug: bond_owned 门槛太低（一个羁绊+词条就触发），已取消。
    回归：所有联动都不含 bond_owned 条件。
    """
    engine = SynergyEngine()
    for syn in engine.synergies:
        conditions = syn.trigger.get("all", [])
        for cond in conditions:
            assert "bond_owned" not in cond, f"{syn.id} still has bond_owned"


def test_devour_does_not_disable_synergy():
    """Bug: 吞噬后 bond_owned 联动丢失。已改为 bond_devoured_set。
    回归：修满体系后联动仍触发（bond_devoured_set 不依赖 bond_pool）。
    """
    pools = RoguePools(RNG(seed=1))
    engine = SynergyEngine()
    s = _state_with_skills({"emperor_fist": 1})
    s.path_realm = {"zhutian": 9}  # 修满
    # 即使 bond_pool 为空（全部吞噬了），联动仍然触发
    s.bond_pool = []
    active = engine.active(s, pools)
    ids = [a.id for a in active]
    assert "zhutian_emperor_fist" in ids, "synergy should trigger even with empty bond_pool after devour"


def test_triple_synergies_have_3_conditions():
    """EX 联动的条件数检查（重构后九秘合一=1条件，天帝雷罚=2条件）。"""
    engine = SynergyEngine()
    for syn in engine.synergies:
        conditions = syn.trigger.get("all", [])
        if syn.rarity and syn.rarity.upper() == "EX":
            # 重构后：九秘合一=1条件(bond_devoured_set)，天帝雷罚=2条件(+equipment_affix)
            assert len(conditions) <= 2, f"EX 联动 {syn.id} 条件数 {len(conditions)}，预期 ≤2"
