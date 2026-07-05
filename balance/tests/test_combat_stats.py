"""PlayerCombat + effect resolver 单测。"""
from __future__ import annotations

from td_balance.combat.damage import CombatStats
from td_balance.combat_stats import PlayerCombat, Survival


def test_accumulate_offense_keys():
    pc = PlayerCombat()
    pc.accumulate({"atk_pct_delta": 0.20, "crit_rate_delta": 0.15, "crit_dmg_delta": 0.50})
    assert abs(pc.offense.crit_rate - 0.20) < 1e-9   # 0.05 + 0.15
    assert abs(pc.offense.crit_dmg - 2.0) < 1e-9      # 1.5 + 0.50


def test_accumulate_final_dmg_mult_into_list():
    pc = PlayerCombat()
    pc.accumulate({"final_dmg_mult": 0.15})
    pc.accumulate({"final_dmg_mult": 0.20})
    assert pc.offense.final_dmg_mults == [0.15, 0.20]


def test_accumulate_survival_keys():
    pc = PlayerCombat()
    pc.accumulate({"hp_pct_delta": 0.30, "damage_reduction_delta": 0.15, "lifesteal_pct": 0.03})
    assert abs(pc.survival._hp_pct_bonus - 0.30) < 1e-9
    assert abs(pc.survival.damage_reduction - 0.15) < 1e-9
    assert abs(pc.survival.lifesteal_pct - 0.03) < 1e-9
    # effective_max_hp 受 hp_pct 加成
    assert abs(pc.survival.effective_max_hp - 1000 * 1.30) < 1e-6


def test_damage_reduction_capped_at_75():
    pc = PlayerCombat()
    pc.accumulate({"damage_reduction_delta": 0.90})  # 超 75% 封顶
    assert abs(pc.survival.damage_reduction - 0.75) < 1e-9


def test_accumulate_economy_keys():
    pc = PlayerCombat()
    pc.accumulate({"gold_mult": 0.15})
    assert abs(pc.economy.gold_mult - 1.15) < 1e-9


def test_all_stats_pct_delta_applies_multiple():
    pc = PlayerCombat()
    pc.accumulate({"all_stats_pct_delta": 0.05})
    # atk 和 hp 都加 5%
    assert abs(getattr(pc.offense, "_atk_pct_bonus", 0) - 0.05) < 1e-9
    assert abs(pc.survival._hp_pct_bonus - 0.05) < 1e-9


def test_unknown_key_ignored():
    """未知 key 不报错（静默忽略）。"""
    pc = PlayerCombat()
    pc.accumulate({"totally_unknown_key": 999})
    # 不抛异常即通过


def test_status_recorded():
    pc = PlayerCombat()
    pc.accumulate({"status": "heaven_emperor"})
    assert "heaven_emperor" in pc.special.statuses
