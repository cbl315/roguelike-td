## test_synergy.gd — 客户端联动引擎测试（Godot headless 可跑）
## 用法: godot --headless --path client -s tests/test_synergy.gd
extends SceneTree

func _init():
	print("========================================")
	print("  客户端联动引擎测试")
	print("========================================")
	
	# 用 load 显式加载，避免 -s 模式下类解析问题
	var BuildStateScript: Resource = load("res://src/systems/build_state.gd")
	var RoguePoolsScript: Resource = load("res://src/core/rogue_pools.gd")
	
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pools: Object = RoguePoolsScript.new(rng)
	var build: Object = BuildStateScript.new()
	build.setup(pools, rng)
	
	var passed := 0
	var failed := 0
	
	# ── 测试 1：未修满体系 → 联动不触发 ──
	print("\n[测试1] 未修满体系 → 无联动")
	build.owned_skills = ["emperor_fist"]
	build.path_realm = {"zhutian": 3}
	build.assemble_stats()
	if build.active_synergies.is_empty():
		print("  ✅ PASS: 无联动触发")
		passed += 1
	else:
		print("  ❌ FAIL: 不该有联动，但有 %d 条" % build.active_synergies.size())
		failed += 1
	
	# ── 测试 2：修满遮天 + 天帝拳 → 天帝之拳 ──
	print("\n[测试2] 修满遮天 + 天帝拳 → 天帝之拳 (final_dmg +100%)")
	build.path_realm = {"zhutian": 4}
	build.owned_skills = ["emperor_fist"]
	var stats2: Object = build.assemble_stats()
	if _has_synergy(build, "zhutian_emperor_fist"):
		print("  ✅ PASS: 天帝之拳触发, final_mult=%.2f" % _final_mult(stats2))
		passed += 1
	else:
		print("  ❌ FAIL: 天帝之拳未触发")
		failed += 1
	
	# ── 测试 3：修满风云 + 雷链 → 风雷合击 ──
	print("\n[测试3] 修满风云 + 雷链 → 风雷合击 (chain+3)")
	build.path_realm = {"fengyun": 4}
	build.owned_skills = ["chain_lightning"]
	var stats3: Object = build.assemble_stats()
	if _has_synergy(build, "storm_thunder_combo") and stats3.chain_extra_bounces >= 3:
		print("  ✅ PASS: 风雷合击触发, bounces=%d" % stats3.chain_extra_bounces)
		passed += 1
	else:
		print("  ❌ FAIL: 风雷合击未触发或chain不足 (bounces=%d)" % stats3.chain_extra_bounces)
		failed += 1
	
	# ── 测试 4：修满兽魂 + 嗜血 → 兽群狂猎 ──
	print("\n[测试4] 修满兽魂 + 嗜血 → 兽群狂猎 (攻速+30%)")
	build.path_realm = {"shouhun": 4}
	build.owned_skills = ["bloodlust"]
	var stats4: Object = build.assemble_stats()
	if _has_synergy(build, "pack_frenzy") and stats4.attack_speed >= 1.3:
		print("  ✅ PASS: 兽群狂猎触发, as=%.2f" % stats4.attack_speed)
		passed += 1
	else:
		print("  ❌ FAIL: 兽群狂猎未触发 (as=%.2f)" % stats4.attack_speed)
		failed += 1
	
	# ── 测试 5：三重联动 天帝雷罚 ──
	print("\n[测试5] 修满遮天 + 天帝拳 + 联动增幅 → 天帝雷罚 (final +200%)")
	build.path_realm = {"zhutian": 4}
	build.owned_skills = ["emperor_fist"]
	var stats5: Object = build.assemble_stats()
	if _has_synergy(build, "emperor_thunder_judgment"):
		print("  ✅ PASS: 天帝雷罚触发, final_mult=%.2f" % _final_mult(stats5))
		passed += 1
	else:
		_print_active(build)
		print("  ❌ FAIL: 天帝雷罚未触发")
		failed += 1
	
	# ── 测试 6：三重联动 雷暴黄金 ──
	print("\n[测试6] 修满风云 + 雷链 + 金币倍增 → 雷暴黄金 (chain+5)")
	build.path_realm = {"fengyun": 4}
	build.owned_skills = ["chain_lightning"]
	var stats6: Object = build.assemble_stats()
	if _has_synergy(build, "thunder_gold_storm") and stats6.chain_extra_bounces >= 5:
		print("  ✅ PASS: 雷暴黄金触发, bounces=%d" % stats6.chain_extra_bounces)
		passed += 1
	else:
		_print_active(build)
		print("  ❌ FAIL: 雷暴黄金未触发 (bounces=%d)" % stats6.chain_extra_bounces)
		failed += 1
	
	# ── 测试 7：没选对应技能 → 不触发 ──
	print("\n[测试7] 修满遮天但没天帝拳 → 天帝之拳不触发")
	build.path_realm = {"zhutian": 4}
	build.owned_skills = ["basic_strike"]
	build.assemble_stats()
	if not _has_synergy(build, "zhutian_emperor_fist"):
		print("  ✅ PASS: 天帝之拳未触发（技能不匹配）")
		passed += 1
	else:
		print("  ❌ FAIL: 不该触发")
		failed += 1
	
	# ── 测试 8：Bug回归 — 吞噬后联动仍触发（不丢失）──
	print("\n[测试8] Bug回归: 吞噬后联动仍触发")
	build.path_realm = {"zhutian": 4}
	build.owned_skills = ["emperor_fist"]
	build.bond_pool = []  # 全部吞噬了，池为空
	build.devoured_bonds = ["zt_mortal", "zt_saint_body", "zt_sage_fruit", "zt_king_blood", "zt_king_bone", "zt_king_soul", "zt_emperor_cauldron", "zt_emperor_throne", "zt_emperor_seal", "zt_heaven_emperor"]
	var stats8: Object = build.assemble_stats()
	if _has_synergy(build, "zhutian_emperor_fist"):
		print("  ✅ PASS: 联动在吞噬后仍触发")
		passed += 1
	else:
		print("  ❌ FAIL: 吞噬后联动丢失")
		failed += 1

	# ── 测试 9：Bug回归 — 所有联动走 bond_devoured_set ──
	print("\n[测试9] Bug回归: 所有联动走 bond_devoured_set")
	# 未修满任何体系时不应触发任何联动
	build.path_realm = {}
	build.owned_skills = ["emperor_fist", "chain_lightning", "bloodlust"]
	build.bond_pool = ["zt_saint_body"]
	build.assemble_stats()
	if build.active_synergies.is_empty():
		print("  ✅ PASS: 无体系修满时无联动触发")
		passed += 1
	else:
		_print_active(build)
		print("  ❌ FAIL: 不该有联动触发")
		failed += 1

	# ── 总结 ──
	print("\n========================================")
	print("  结果: %d passed, %d failed" % [passed, failed])
	if failed == 0:
		print("  🎉 全部通过！")
	else:
		print("  ⚠️ 有 %d 个失败" % failed)
	print("========================================")
	quit()


func _has_synergy(build: Object, sid: String) -> bool:
	for syn in build.active_synergies:
		if syn.get("id") == sid:
			return true
	return false


func _final_mult(stats: Object) -> float:
	var result := 1.0
	for x in stats.final_dmg_mults:
		result *= (1.0 + float(x))
	return result


func _print_active(build: Object) -> void:
	var ids: Array = []
	for syn in build.active_synergies:
		ids.append(syn.get("id"))
	print("  (已触发: %s)" % str(ids))
