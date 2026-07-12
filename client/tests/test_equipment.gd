## test_equipment.gd — 客户端装备系统测试（Godot headless 或编辑器运行）
## 验证：升级曲线、里程碑词条抽取、经济效果汇总。
extends SceneTree


func _init():
	print("========================================")
	print("  客户端装备系统测试")
	print("========================================")

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pools := RoguePools.new(rng)
	var build := BuildState.new()
	build.setup(pools, rng)

	var passed := 0
	var failed := 0

	# ── 测试 1：初始等级 0，升级成本 15 ──
	print("\n[测试1] 初始状态")
	if build.equip_level == 0 and pools.equip_upgrade_cost(0) == 15.0:
		print("  ✅ PASS: equip_level=0, cost=15")
		passed += 1
	else:
		print("  ❌ FAIL: level=%d cost=%.0f" % [build.equip_level, pools.equip_upgrade_cost(0)])
		failed += 1

	# ── 测试 2：升级到 +1，获得 gold_per_sec ──
	print("\n[测试2] 升级到 +1 → gold_per_sec")
	build.add_gold(1000)
	var r1: Dictionary = build.equip_upgrade()
	if build.equip_level == 1 and build.gold_per_sec() >= 1.0:
		print("  ✅ PASS: level=%d, gold_per_sec=%.1f" % [build.equip_level, build.gold_per_sec()])
		passed += 1
	else:
		print("  ❌ FAIL: level=%d gps=%.1f" % [build.equip_level, build.gold_per_sec()])
		failed += 1

	# ── 测试 3：升级到 +2，获得 per_kill_gold ──
	print("\n[测试3] 升级到 +2 → per_kill_bonus")
	var r2: Dictionary = build.equip_upgrade()
	if build.equip_level == 2 and build.per_kill_bonus() >= 0.5:
		print("  ✅ PASS: level=%d, per_kill=%.1f" % [build.equip_level, build.per_kill_bonus()])
		passed += 1
	else:
		print("  ❌ FAIL: level=%d pkb=%.1f" % [build.equip_level, build.per_kill_bonus()])
		failed += 1

	# ── 测试 4：升级到 +3（里程碑），抽到词条 ──
	print("\n[测试4] 升级到 +3（里程碑）→ 抽词条")
	var r3: Dictionary = build.equip_upgrade()
	var ms3: Dictionary = r3.get("milestone", {})
	if build.equip_level == 3 and not ms3.is_empty():
		print("  ✅ PASS: level=3, milestone=%s (%s)" % [ms3.get("name", "?"), ms3.get("polarity", "?")])
		passed += 1
	else:
		print("  ❌ FAIL: level=%d milestone=%s" % [build.equip_level, str(ms3)])
		failed += 1

	# ── 测试 5：升满 +9 ──
	print("\n[测试5] 升满到 +9")
	while build.equip_level < 9:
		build.add_gold(1000)
		var r := build.equip_upgrade()
		if r.is_empty():
			print("  ❌ FAIL: upgrade failed at level %d" % build.equip_level)
			failed += 1
			break
	if build.equip_level == 9:
		# 尝试再升级应失败
		var r10: Dictionary = build.equip_upgrade()
		if r10.is_empty():
			print("  ✅ PASS: max level 9, upgrade blocked")
			passed += 1
		else:
			print("  ❌ FAIL: exceeded max level")
			failed += 1
	else:
		failed += 1

	# ── 测试 6：里程碑词条数 ≥ 3（+3/+6/+9 各抽一个）──
	print("\n[测试6] 里程碑词条数")
	if build.equip_affixes.size() >= 3:
		print("  ✅ PASS: %d affixes from milestones" % build.equip_affixes.size())
		passed += 1
	else:
		print("  ❌ FAIL: only %d affixes (expected >=3)" % build.equip_affixes.size())
		failed += 1

	# ── 测试 7：经济属性汇总正确 ──
	print("\n[测试7] 经济属性汇总")
	var gps: float = build.gold_per_sec()
	var pkb: float = build.per_kill_bonus()
	var gm: float = build.gold_multiplier()
	if gps > 0.0 and gm >= 1.0:
		print("  ✅ PASS: gps=%.1f pkb=%.1f gold_mult=%.2f" % [gps, pkb, gm])
		passed += 1
	else:
		print("  ❌ FAIL: gps=%.1f pkb=%.1f gold_mult=%.2f" % [gps, pkb, gm])
		failed += 1

	# ── 测试 8：Bug回归 — gold_per_sec 显示绝对值不是百分比 ──
	print("\n[测试8] Bug回归: 经济效果值是绝对值")
	# gold_per_sec_delta=1.0 应该是"每秒+1金币"，不是"+100%"
	var test_eff: Dictionary = {"gold_per_sec_delta": 1.0}
	var desc: String = pools._effect_to_text(test_eff)
	if desc.find("+1") >= 0 and desc.find("100") < 0:
		print("  ✅ PASS: '%s' 显示绝对值" % desc)
		passed += 1
	else:
		print("  ❌ FAIL: '%s' 应显示 +1 不是百分比" % desc)
		failed += 1

	# ── 测试 9：Bug回归 — 升级奖励不含非effect字段 ──
	print("\n[测试9] Bug回归: 升级奖励过滤非effect字段")
	var raw_reward: Dictionary = pools.equip_level_reward(3)
	# level 3 的 per_level_income 含 milestone: true 等非effect字段
	# _clean_reward 应该过滤掉它们
	# 直接检查 build 的 accumulated_effects 没有混入 level/milestone 字段
	var has_junk := false
	for eff in build.accumulated_effects:
		if eff.has("level") or eff.has("milestone") or eff.has("milestone_guaranteed_positive"):
			has_junk = true
			break
	if not has_junk:
		print("  ✅ PASS: accumulated_effects 无非effect字段")
		passed += 1
	else:
		print("  ❌ FAIL: accumulated_effects 含 level/milestone 等垃圾字段")
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
