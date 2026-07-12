"""装备系统测试 — 验证升级曲线、里程碑词条抽取、经济效果。

数据来源: balance/data/equipment.yaml（SSOT），由 loader/export 导出。
"""
from __future__ import annotations

import pytest
import yaml
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"


def _load_equipment() -> dict:
    return yaml.safe_load((DATA / "equipment.yaml").read_text())


def test_upgrade_curve_structure():
    """升级曲线结构完整。"""
    eq = _load_equipment()
    curve = eq["upgrade_curve"]
    assert curve["cost_base"] == 15
    assert curve["cost_per_level"] == 4
    assert curve["max_level"] == 9
    incomes = curve["per_level_income"]
    assert len(incomes) == 9


def test_upgrade_cost_formula():
    """升级成本 = 15 + 4 × current_level。"""
    eq = _load_equipment()
    curve = eq["upgrade_curve"]
    base = curve["cost_base"]
    per = curve["cost_per_level"]
    # level 0 → cost to +1 = 15
    assert base + per * 0 == 15
    # level 8 → cost to +9 = 47
    assert base + per * 8 == 47


def test_milestone_levels():
    """里程碑在 +3/+6/+9。"""
    eq = _load_equipment()
    assert eq["milestones"] == [3, 6, 9]
    assert eq["milestone_guarantee_positive_at"] == 9


def test_odd_levels_give_gold_per_sec():
    """奇数级给 gold_per_sec_delta。"""
    eq = _load_equipment()
    incomes = eq["upgrade_curve"]["per_level_income"]
    for i, inc in enumerate(incomes):
        level = i + 1
        if level % 2 == 1:
            assert "gold_per_sec_delta" in inc, f"level {level} should have gold_per_sec_delta"


def test_even_levels_give_kill_gold():
    """偶数级给 per_kill_gold_delta。"""
    eq = _load_equipment()
    incomes = eq["upgrade_curve"]["per_level_income"]
    for i, inc in enumerate(incomes):
        level = i + 1
        if level % 2 == 0:
            assert "per_kill_gold_delta" in inc, f"level {level} should have per_kill_gold_delta"


def test_affix_count():
    """装备词条数 = 27（19 正面 + 8 诅咒）。"""
    eq = _load_equipment()
    affixes = eq["affixes"]
    assert len(affixes) == 27
    positives = [a for a in affixes if a.get("polarity", "positive") != "curse"]
    curses = [a for a in affixes if a.get("polarity") == "curse"]
    assert len(positives) == 19
    assert len(curses) == 8


def test_curse_affixes_have_cost_and_benefit():
    """诅咒词条有 cost + benefit 字段。"""
    eq = _load_equipment()
    curses = [a for a in eq["affixes"] if a.get("polarity") == "curse"]
    for c in curses:
        assert "cost" in c, f"curse {c['id']} missing cost"
        assert "benefit" in c, f"curse {c['id']} missing benefit"


def test_positive_affixes_have_effect():
    """正面词条有 effect 字段。"""
    eq = _load_equipment()
    positives = [a for a in eq["affixes"] if a.get("polarity", "positive") != "curse"]
    for p in positives:
        assert "effect" in p, f"positive {p['id']} missing effect"


def test_level9_guaranteed_positive():
    """+9 保底正面词条。"""
    eq = _load_equipment()
    incomes = eq["upgrade_curve"]["per_level_income"]
    level9 = incomes[8]  # index 8 = level 9
    assert level9.get("milestone_guaranteed_positive") is True


def test_milestone_levels_marked():
    """+3/+6/+9 在 per_level_income 里标注 milestone: true。"""
    eq = _load_equipment()
    incomes = eq["upgrade_curve"]["per_level_income"]
    for idx in [2, 5, 8]:  # level 3, 6, 9
        assert incomes[idx].get("milestone") is True, f"level {idx+1} should be milestone"


def test_synergy_amp_affix_exists():
    """联动增幅词条存在（三重联动天帝雷罚需要）。"""
    eq = _load_equipment()
    ids = [a["id"] for a in eq["affixes"]]
    assert "synergy_amp" in ids


def test_gold_multiplier_affix_exists():
    """金币倍增词条存在（三重联动雷暴黄金需要）。"""
    eq = _load_equipment()
    ids = [a["id"] for a in eq["affixes"]]
    assert "gold_multiplier" in ids


def test_total_upgrade_cost_to_max():
    """升满 +9 的总成本。"""
    eq = _load_equipment()
    curve = eq["upgrade_curve"]
    base = curve["cost_base"]
    per = curve["cost_per_level"]
    total = sum(base + per * lv for lv in range(9))
    # 15+19+23+27+31+35+39+43+47 = 279
    assert total == 279


# ── Bug 回归测试 ──

def test_gold_per_sec_delta_is_absolute_not_percentage():
    """Bug: gold_per_sec_delta=1.0 被当成百分比显示 +100%。
    验证：gold_per_sec_delta 的值是绝对值（每秒 +1 金币），不是 0.01(=1%)。
    """
    eq = _load_equipment()
    incomes = eq["upgrade_curve"]["per_level_income"]
    for inc in incomes:
        if "gold_per_sec_delta" in inc:
            val = inc["gold_per_sec_delta"]
            # 绝对值应该是 1.0, 5.0 等，不应该是 0.01 这种百分比小数
            assert val >= 1.0, f"gold_per_sec_delta={val} looks like percentage, expected absolute"


def test_per_kill_gold_delta_is_absolute_not_percentage():
    """Bug: per_kill_gold_delta=0.5 被当成百分比显示 +50%。
    验证：per_kill_gold_delta 是绝对值。
    """
    eq = _load_equipment()
    incomes = eq["upgrade_curve"]["per_level_income"]
    for inc in incomes:
        if "per_kill_gold_delta" in inc:
            val = inc["per_kill_gold_delta"]
            assert val > 0.0
            # 0.5 = 每次击杀额外 0.5 金币，不是 +50%
            assert val <= 5.0, f"per_kill_gold_delta={val} seems too high for absolute"


def test_absolute_keys_not_confused_with_pct():
    """Bug: delta key 统一当百分比处理，但 gold_per_sec/per_kill 是绝对值。
    验证：经济类 delta key 的值域符合绝对值语义，不是 0.0-1.0 的百分比。
    """
    eq = _load_equipment()
    absolute_keys = {"gold_per_sec_delta", "per_kill_gold_delta", "gold_lump"}
    for affix in eq["affixes"]:
        effect = affix.get("effect", {})
        for k in absolute_keys:
            if k in effect:
                val = effect[k]
                # gold_lump 可以是 80/200，gold_per_sec 是 1-5
                assert val > 0.5, f"{k}={val} in {affix['id']} should be absolute (>0.5)"


def test_economy_effect_keys_exist():
    """验证装备经济效果的 key 集合完整（防止拼写错误）。"""
    eq = _load_equipment()
    all_keys = set()
    for affix in eq["affixes"]:
        effect = affix.get("effect", {})
        if effect:
            all_keys.update(effect.keys())
        cost = affix.get("cost", {})
        if cost:
            all_keys.update(cost.keys())
        benefit = affix.get("benefit", {})
        if benefit:
            all_keys.update(benefit.keys())
    # 至少包含这些核心经济 key
    expected = {"gold_per_sec_delta", "per_kill_gold_delta", "gold_mult"}
    assert expected.issubset(all_keys), f"missing keys: {expected - all_keys}"
