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
    # zhutian 有 5 境界，需 path_realm=4（顶级）
    s = _state_with_skills({"emperor_fist": 1})
    s.path_realm = {"zhutian": 3}   # 未满（第 3 境，差 1）
    active = engine.active(s, pools)
    ids = [a.id for a in active]
    assert "zhutian_emperor_fist" not in ids

    s.path_realm = {"zhutian": 4}   # 修满
    active = engine.active(s, pools)
    ids = [a.id for a in active]
    assert "zhutian_emperor_fist" in ids


def test_skill_owned_trigger():
    """skill_owned 条件。"""
    pools = RoguePools(RNG(seed=1))
    engine = SynergyEngine()
    s = _state_with_skills({"bloodlust": 1})
    s.path_realm = {"shouhun": 4}   # 兽魂修满
    active = engine.active(s, pools)
    assert "pack_frenzy" in [a.id for a in active]   # 需 bloodlust


def test_skill_tag_trigger():
    """skill_tag 条件（雷标签）。"""
    pools = RoguePools(RNG(seed=1))
    engine = SynergyEngine()
    # chain_lightning 带 thunder 标签
    s = _state_with_skills({"chain_lightning": 1})
    s.path_realm = {"fengyun": 4}   # 风云修满 → 风雷合击需 thunder
    active = engine.active(s, pools)
    assert "storm_thunder_combo" in [a.id for a in active]


def test_no_trigger_when_conditions_unmet():
    pools = RoguePools(RNG(seed=1))
    engine = SynergyEngine()
    s = _state_with_skills({"emperor_fist": 1})
    s.path_realm = {}   # 没修任何体系
    active = engine.active(s, pools)
    assert all(a.id != "zhutian_emperor_fist" for a in active)
