## test_bugfix.gd — Bug 回归测试（覆盖 2026-07-12/13 反馈的客户端修复）
## 用法: godot --headless --path client -s tests/test_bugfix.gd
##
## 用 load() 加载类（避免 -s 模式下 autoload 解析问题），和 test_synergy.gd 一致。
extends SceneTree


func _init():
	print("========================================")
	print("  Bug 回归测试")
	print("========================================")

	var passed := 0
	var failed := 0

	# 用 load 显式加载（-s 模式下 autoload 可能延迟）
	var RoguePoolsScript: Resource = load("res://src/core/rogue_pools.gd")
	var pools: Object = RoguePoolsScript.new(RandomNumberGenerator.new())
	pools._rng.randomize()

	# ── 测试 1：装备 max_level=20 ──
	print("\n[测试1] 装备 max_level=20")
	if pools.equip_max_level() == 20:
		print("  ✅ PASS: max_level=20")
		passed += 1
	else:
		print("  ❌ FAIL: max_level=%d" % pools.equip_max_level())
		failed += 1

	# ── 测试 2：里程碑在 [5,10,15,20] ──
	print("\n[测试2] 里程碑判断")
	var ms_ok: bool = pools.is_milestone_level(5) and pools.is_milestone_level(10) and pools.is_milestone_level(15) and pools.is_milestone_level(20)
	var ms_not: bool = not pools.is_milestone_level(3) and not pools.is_milestone_level(6) and not pools.is_milestone_level(9)
	if ms_ok and ms_not:
		print("  ✅ PASS: 里程碑=[5,10,15,20]，旧的[3,6,9]不触发")
		passed += 1
	else:
		print("  ❌ FAIL: 5=%s 10=%s 3=%s 6=%s" % [pools.is_milestone_level(5), pools.is_milestone_level(10), pools.is_milestone_level(3), pools.is_milestone_level(6)])
		failed += 1

	# ── 测试 3：里程碑 3 选 1 ──
	print("\n[测试3] draw_milestone_affix_options 返回 3 张候选")
	var options: Array = pools.draw_milestone_affix_options(false, 3)
	if options.size() == 3:
		print("  ✅ PASS: 返回 %d 张候选" % options.size())
		passed += 1
	else:
		print("  ❌ FAIL: 返回 %d 张（应为 3）" % options.size())
		failed += 1

	# ── 测试 4：CombatStats 生存字段 ──
	print("\n[测试4] CombatStats 生存字段")
	var CombatStatsScript: Resource = load("res://src/core/combat_stats.gd")
	var stats: Object = CombatStatsScript.new()
	if stats.has_method("effective_max_hp"):
		var base_hp: float = stats.effective_max_hp()
		stats.hp_pct_bonus = 0.50
		var boosted_hp: float = stats.effective_max_hp()
		if boosted_hp > base_hp:
			print("  ✅ PASS: effective_max_hp %.0f → %.0f" % [base_hp, boosted_hp])
			passed += 1
		else:
			print("  ❌ FAIL: hp_pct 不生效")
			failed += 1
	else:
		print("  ❌ FAIL: 无 effective_max_hp")
		failed += 1

	# ── 测试 5：EffectResolver 处理生存 effect ──
	print("\n[测试5] EffectResolver 处理 hp_pct/lifesteal/damage_reduction")
	var stats2: Object = CombatStatsScript.new()
	EffectResolver.accumulate(stats2, {"hp_pct_delta": 0.30, "lifesteal_pct": 0.07, "damage_reduction_delta": 0.10})
	if stats2.hp_pct_bonus > 0.0 and stats2.lifesteal_pct > 0.0 and stats2.damage_reduction > 0.0:
		print("  ✅ PASS: hp=%.2f ls=%.2f dr=%.2f" % [stats2.hp_pct_bonus, stats2.lifesteal_pct, stats2.damage_reduction])
		passed += 1
	else:
		print("  ❌ FAIL: hp=%.2f ls=%.2f dr=%.2f" % [stats2.hp_pct_bonus, stats2.lifesteal_pct, stats2.damage_reduction])
		failed += 1

	# ── 测试 6：苦海 effect 是 hp_pct_delta ──
	print("\n[测试6] 苦海羁绊 effect")
	var kuhai: Dictionary = pools._find_bond("zt_lunhai_kuhai")
	if kuhai.has("effect") and kuhai["effect"].has("hp_pct_delta") and not kuhai["effect"].has("gold_per_sec_delta"):
		print("  ✅ PASS: 苦海 = hp_pct_delta")
		passed += 1
	else:
		print("  ❌ FAIL: 苦海=%s" % str(kuhai.get("effect", {})))
		failed += 1

	# ── 测试 7：羁绊无资源效果 ──
	print("\n[测试7] 所有羁绊无资源类 effect")
	var resource_keys: Array = ["gold_per_sec_delta", "per_kill_gold_delta", "gold_mult", "gold_lump", "double_gold_chance"]
	var no_resource: bool = true
	for b in pools._bonds:
		var bond_eff: Dictionary = b.get("effect", {})
		for rk in resource_keys:
			if bond_eff.has(rk):
				no_resource = false
	if no_resource:
		print("  ✅ PASS: 所有羁绊无资源效果")
		passed += 1
	else:
		print("  ❌ FAIL: 有羁绊含资源效果")
		failed += 1

	# ── 测试 8：无 common_gold ──
	print("\n[测试8] common_gold 已删除")
	var has_cg: bool = false
	for b in pools._bonds:
		if b.get("id", "") == "common_gold":
			has_cg = true
	if not has_cg:
		print("  ✅ PASS")
		passed += 1
	else:
		print("  ❌ FAIL: common_gold 仍存在")
		failed += 1

	# ── 测试 9：九秘是羁绊 zt_jm_* ──
	print("\n[测试9] 九秘是羁绊 zt_jm_*")
	var jm_count: int = 0
	for b in pools._bonds:
		if b.get("id", "").begins_with("zt_jm_"):
			jm_count += 1
	if jm_count == 9:
		print("  ✅ PASS: %d 个" % jm_count)
		passed += 1
	else:
		print("  ❌ FAIL: %d 个（应 9）" % jm_count)
		failed += 1

	# ── 测试 10：_effect_to_text 不双 %% ──
	print("\n[测试10] _effect_to_text 格式化")
	var desc: String = pools._effect_to_text({"atk_pct_delta": 0.10})
	if desc.find("%%") == -1 and desc.find("+10%") >= 0:
		print("  ✅ PASS: '%s'" % desc)
		passed += 1
	else:
		print("  ❌ FAIL: '%s'" % desc)
		failed += 1

	# ── 测试 11：draw_skill_offers 已删除 ──
	print("\n[测试11] draw_skill_offers 已删除")
	if not pools.has_method("draw_skill_offers"):
		print("  ✅ PASS")
		passed += 1
	else:
		print("  ❌ FAIL: 仍存在")
		failed += 1

	# ── 测试 12：unlock_jt_secret 已删除 ──
	print("\n[测试12] unlock_jt_secret 已删除")
	if not pools.has_method("unlock_jt_secret"):
		print("  ✅ PASS")
		passed += 1
	else:
		print("  ❌ FAIL: 仍存在")
		failed += 1

	# ── 测试 13：装备升级成本公式 ──
	print("\n[测试13] 装备升级成本 20+8×lv")
	if pools.equip_upgrade_cost(0) == 20.0 and pools.equip_upgrade_cost(4) == 52.0:
		print("  ✅ PASS: lv0=20, lv4=52")
		passed += 1
	else:
		print("  ❌ FAIL: lv0=%.0f lv4=%.0f" % [pools.equip_upgrade_cost(0), pools.equip_upgrade_cost(4)])
		failed += 1

	# ── 总结 ──
	print("\n========================================")
	print("  结果: %d 通过 / %d 失败" % [passed, failed])
	print("========================================")
	if failed > 0:
		quit(1)
	else:
		quit(0)
