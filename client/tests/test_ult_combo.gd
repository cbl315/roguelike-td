## test_ult_combo.gd — 三件套单测：roll_hit_dmg 分布一致性（--script 独立可跑）
extends SceneTree


func _init() -> void:
	var fails: int = 0
	var CS := load("res://src/core/combat_stats.gd")

	# 测试1：roll 均值 ≈ expected（大数定律，5 万发，容差 3%）
	var stats = CS.new()
	stats.apply_atk_bonus()
	stats.crit_rate = 0.45          # 高暴击率放大差异可见性
	stats.crit_dmg = 2.2
	stats.armor_pen = 0.3
	stats.final_dmg_mults = [0.15, -0.1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var expected: float = stats.expected_hit_dmg(60.0)
	var n := 50000
	var sum: float = 0.0
	var crits: int = 0
	for i in n:
		var rolled: Dictionary = stats.roll_hit_dmg(60.0, rng)
		sum += rolled["dmg"]
		if rolled["crit"]:
			crits += 1
	var avg: float = sum / n
	var err_pct: float = absf(avg - expected) / expected * 100.0
	if err_pct > 3.0:
		print("  FAIL: roll 均值 %.2f vs expected %.2f（偏差 %.1f%%）" % [avg, expected, err_pct])
		fails += 1
	else:
		print("  PASS: roll 均值 ≈ expected（%.2f vs %.2f，偏差 %.1f%%，暴击率 %.1f%%）" % [avg, expected, err_pct, crits * 100.0 / n])

	# 测试2：零暴击率时 roll == expected（确定性）
	stats.crit_rate = 0.0
	var e0: float = stats.expected_hit_dmg(20.0)
	var r0: Dictionary = stats.roll_hit_dmg(20.0, rng)
	if absf(r0["dmg"] - e0) > 0.001 or r0["crit"]:
		print("  FAIL: 0暴击率应无随机（%.2f vs %.2f）" % [r0["dmg"], e0])
		fails += 1
	else:
		print("  PASS: 0 暴击率时确定性 == expected")

	# 测试3：必暴击时 roll == expected×crit_dmg/crit_factor
	stats.crit_rate = 1.0
	var e1: float = stats.expected_hit_dmg(20.0)
	var r1: Dictionary = stats.roll_hit_dmg(20.0, rng)
	# expected 的 crit_factor = 1 + 1.0×(crit_dmg-1) = crit_dmg → roll 应相等
	if absf(r1["dmg"] - e1) > 0.001 or not r1["crit"]:
		print("  FAIL: 100%%暴击 roll %.2f vs expected %.2f" % [r1["dmg"], e1])
		fails += 1
	else:
		print("  PASS: 100% 暴击时 roll == expected")

	print("\n========================================")
	if fails == 0:
		print("  三件套数值测试: 全部通过")
	else:
		print("  三件套数值测试: %d 失败" % fails)
	quit(1 if fails > 0 else 0)
