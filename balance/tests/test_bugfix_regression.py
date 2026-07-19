"""Bug 回归测试 — 覆盖 2026-07-12/13 反馈的 bug 修复。

每个 test 对应一个具体 bug，防止回退：
  1. 装备 max_level=20（原9，太快满级）
  2. 装备里程碑在 [5,10,15,20]（原硬编码 [3,6,9]）
  3. 装备总成本=1920（原279）
  4. 羁绊无资源类 effect（gold_per_sec/gold_mult 等，全归装备）
  5. bonds 无 common_gold（财富符文已删）
  6. 轮海 reward 无 gold_per_sec
  7. 苦海 effect 是 hp_pct_delta（不是 gold_per_sec）
  8. 九秘是羁绊 zt_jm_*（不是技能 jt_*）
  9. skills 只有 emperor_fist（1 个起点技能）
  10. 联动触发用 bond_devoured_set（不是 skill_owned）
"""
from __future__ import annotations

from pathlib import Path

import yaml

from td_balance.loader import load_bonds, load_paths, load_skills, load_synergies

_DATA_DIR = Path(__file__).resolve().parent.parent / "data"


def _load_equipment() -> dict:
    with (_DATA_DIR / "equipment.yaml").open(encoding="utf-8") as f:
        return yaml.safe_load(f)


# ── 装备经济（Bug #1,2,3）──

def test_equipment_max_level_20():
    """Bug: 装备升级太快（9级279金就满）。修复：20级1920金。"""
    eq = _load_equipment()
    assert eq["upgrade_curve"]["max_level"] == 20


def test_equipment_milestones_5_10_15_20():
    """Bug: 里程碑硬编码 [3,6,9]。修复：从数据读 [5,10,15,20]。"""
    eq = _load_equipment()
    assert eq["milestones"] == [5, 10, 15, 20]


def test_equipment_total_cost_1920():
    """Bug: 总成本太低（279）。修复：20+28+...+172=1920。"""
    eq = _load_equipment()
    curve = eq["upgrade_curve"]
    base = curve["cost_base"]
    per = curve["cost_per_level"]
    total = sum(base + per * lv for lv in range(curve["max_level"]))
    assert total == 1920


def test_equipment_cost_formula():
    """成本公式 = 20 + 8×lv。"""
    eq = _load_equipment()
    curve = eq["upgrade_curve"]
    assert curve["cost_base"] == 20
    assert curve["cost_per_level"] == 8


# ── 羁绊无资源效果（Bug #4,5,6,7）──

def test_bonds_no_resource_effects():
    """Bug: 羁绊有 gold_per_sec/gold_mult 等资源效果。修复：资源全归装备。"""
    bonds = load_bonds()
    resource_keys = {"gold_per_sec_delta", "per_kill_gold_delta", "gold_mult", "gold_lump", "double_gold_chance"}
    for b in bonds:
        for key in b.effect:
            assert key not in resource_keys, f"羁绊 {b.id} 不该有资源效果 {key}"


def test_no_common_gold_bond():
    """Bug: common_gold（财富符文）已删。"""
    bonds = load_bonds()
    ids = {b.id for b in bonds}
    assert "common_gold" not in ids


def test_lunhai_reward_no_gold_per_sec():
    """Bug: 轮海 reward 有 gold_per_sec_delta。修复：已删。"""
    paths = load_paths()
    zhutian = [p for p in paths if p.id == "zhutian"][0]
    lunhai_reward = zhutian.realms[0].reward
    assert "gold_per_sec_delta" not in lunhai_reward


def test_kuhai_effect_is_hp():
    """Bug: 苦海 effect 是 gold_per_sec_delta。修复：改成 hp_pct_delta。"""
    bonds = load_bonds()
    kuhai = [b for b in bonds if b.id == "zt_lunhai_kuhai"][0]
    assert "hp_pct_delta" in kuhai.effect
    assert "gold_per_sec_delta" not in kuhai.effect


# ── 九秘转羁绊（Bug #8）──

def test_nine_secrets_are_bonds():
    """Bug: 九秘是技能 jt_*。修复：转成羁绊 zt_jm_*。"""
    bonds = load_bonds()
    jm_bonds = [b for b in bonds if b.id.startswith("zt_jm_")]
    assert len(jm_bonds) == 9, f"九秘羁绊应有 9 个，实际 {len(jm_bonds)}"
    expected = {"zt_jm_jie", "zt_jm_dou", "zt_jm_xing", "zt_jm_bing", "zt_jm_zu",
                "zt_jm_qian", "zt_jm_lin", "zt_jm_zhe", "zt_jm_shu"}
    actual = {b.id for b in jm_bonds}
    assert actual == expected, f"九秘羁绊不匹配: 缺 {expected - actual}"


def test_nine_secrets_distributed_in_realms():
    """九秘分散在遮天 9 个境界（每境 1 个）。"""
    paths = load_paths()
    zhutian = [p for p in paths if p.id == "zhutian"][0]
    for i, realm in enumerate(zhutian.realms):
        jm_in_realm = [b for b in realm.bonds if b.startswith("zt_jm_")]
        assert len(jm_in_realm) == 1, f"境界{i} {realm.name} 应有1个九秘，实际{len(jm_in_realm)}"


# ── 技能精简为起点技能（Bug #9）──

def test_skills_only_starting_skills():
    """起点技能：遮天 emperor_fist + 星辰变 xc_xingchenbian。"""
    skills = load_skills()
    ids = {s.id for s in skills}
    assert "emperor_fist" in ids
    assert "xc_xingchenbian" in ids
    assert "basic_strike" not in ids


def test_no_basic_strike():
    """basic_strike 已删除。"""
    skills = load_skills()
    ids = {s.id for s in skills}
    assert "basic_strike" not in ids


def test_no_jt_skill_ids():
    """jt_* 九秘技能 id 已删除（转成 zt_jm_* 羁绊）。"""
    skills = load_skills()
    for s in skills:
        assert not s.id.startswith("jt_"), f"技能 {s.id} 不该以 jt_ 开头"


# ── 联动触发条件（Bug #10）──

def test_synergies_no_skill_owned():
    """Bug: 联动用 skill_owned 触发。修复：改用 bond_devoured_set。"""
    syns = load_synergies()
    for syn in syns:
        conditions = syn.trigger.get("all", [])
        for cond in conditions:
            assert "skill_owned" not in cond, f"联动 {syn.id} 不该用 skill_owned"
            assert "skill_tag" not in cond, f"联动 {syn.id} 不该用 skill_tag"


def test_synergies_use_bond_devoured_set():
    """联动触发用 bond_devoured_set。"""
    syns = load_synergies()
    for syn in syns:
        conditions = syn.trigger.get("all", [])
        has_devoured = any("bond_devoured_set" in c for c in conditions)
        assert has_devoured, f"联动 {syn.id} 缺 bond_devoured_set 条件"


# ── 体系数据规模（回归基线）──

def test_zhutian_bond_count():
    """遮天羁绊总数 = 43（含9九秘 + 6 generic = 49 总，遮天 43）。"""
    bonds = load_bonds()
    zt = [b for b in bonds if b.set == "zhutian"]
    assert len(zt) == 43, f"遮天羁绊应有 43 个，实际 {len(zt)}"


def test_generic_bond_count():
    """generic 通用羁绊 = 5（原6，删了 common_gold）。"""
    bonds = load_bonds()
    generic = [b for b in bonds if b.set == "generic"]
    assert len(generic) == 5, f"generic 羁绊应有 5 个，实际 {len(generic)}"


def test_zhutian_nine_realms():
    """遮天 9 境界。"""
    paths = load_paths()
    zhutian = [p for p in paths if p.id == "zhutian"][0]
    assert len(zhutian.realms) == 9
