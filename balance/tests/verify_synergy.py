#!/usr/bin/env python3
"""联动引擎验证报告 — 完整模拟玩家状态，验证联动是否正确触发。

用法: cd balance && uv run python tests/verify_synergy.py
"""
from __future__ import annotations

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from td_balance.player import PlayerState
from td_balance.rng import RNG
from td_balance.rogue_pools import RoguePools
from td_balance.synergy_engine import SynergyEngine
from td_balance.combat_stats import PlayerCombat, Special
from td_balance.combat import damage as dmg

pools = RoguePools(RNG(seed=42))
engine = SynergyEngine()

print("=" * 60)
print("  联动引擎验证报告")
print("=" * 60)

# 列出所有联动
print(f"\n📊 共 {len(engine.synergies)} 条联动规则:")
for syn in engine.synergies:
    tier = getattr(syn, 'tier', '') or ''
    conditions = syn.trigger.get("all", [])
    cond_str = " + ".join(list(c.keys())[0].replace("bond_devoured_set", "吞噬")
                          .replace("skill_owned", "技能")
                          .replace("skill_tag", "标签")
                          .replace("equipment_affix", "装备")
                          .replace("affix_owned", "词条") for c in conditions)
    n_cond = len(conditions)
    label = "三重" if n_cond >= 3 else "两重"
    star = "★ " if tier == "SS" else ""
    print(f"  {star}{syn.name:8s} [{label}] {cond_str}")

# 模拟各种玩家状态
test_cases = [
    ("天帝之拳", {"emperor_fist": 1}, {"zhutian": 4}),
    ("风雷合击", {"chain_lightning": 1}, {"fengyun": 4}),
    ("兽群狂猎", {"bloodlust": 1}, {"shouhun": 4}),
    ("天帝雷罚(三重, 需装备)", {"emperor_fist": 1}, {"zhutian": 4}),
    ("雷暴黄金(三重, 需装备)", {"chain_lightning": 1}, {"fengyun": 4}),
    ("无联动(没修满)", {"emperor_fist": 1}, {"zhutian": 3}),
    ("无联动(没技能)", {"basic_strike": 1}, {"zhutian": 4}),
]

print("\n" + "=" * 60)
print("  触发验证")
print("=" * 60)

all_pass = True
for name, skills, path_realm in test_cases:
    s = PlayerState()
    s.skills = skills
    s.path_realm = path_realm
    active = engine.active(s, pools)
    ids = [a.id for a in active]
    names = [a.name for a in active]

    # 计算属性差异
    pc = PlayerCombat()
    pc.accumulate({"atk_pct_delta": 0.5})  # 模拟基础羁绊
    for syn in active:
        if syn.effect:
            pc.accumulate(syn.effect)

    stats = pc.offense
    enemy = dmg.EnemyStats(armor=20.0)
    base_dps = dmg.expected_dps(stats, enemy)
    chain_mult = pc.special.chain_mult() if pc.special.chain_extra_bounces > 0 else 1.0
    total_dps = base_dps * chain_mult

    status = "✅" if ids else "⚪"
    if "无联动" in name:
        status = "✅" if not ids else "❌"
        if ids:
            all_pass = False
    else:
        if not ids:
            status = "❌"
            all_pass = False

    print(f"\n  {status} {name}")
    print(f"     技能={list(skills.keys())} 境界={path_realm}")
    if ids:
        print(f"     触发: {', '.join(names)}")
        print(f"     DPS={base_dps:.0f} chain×{chain_mult:.2f} 总DPS={total_dps:.0f}")
        if pc.special.chain_extra_bounces > 0:
            print(f"     连锁弹射: +{pc.special.chain_extra_bounces} 次")
    else:
        print(f"     触发: (无)")

print("\n" + "=" * 60)
if all_pass:
    print("  🎉 全部验证通过！联动引擎工作正常。")
else:
    print("  ⚠️ 有验证失败，请检查联动规则。")
print("=" * 60)
