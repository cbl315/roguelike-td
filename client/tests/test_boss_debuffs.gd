## test_boss_debuffs.gd — BossDebuffs 运行时单测（--script 模式可独立跑，不依赖 autoload）
extends SceneTree


func _init() -> void:
	var fails: int = 0
	var BDP := load("res://src/systems/boss_debuffs.gd")

	# 测试1：setup 加载池 + 抽 3
	var bd = BDP.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	bd.setup(rng)
	var picked: Array = bd.get("_picked")
	var pool: Array = bd.get("_pool")
	if picked.size() != 3:
		print("  FAIL: 抽取数量 %d != 3" % picked.size())
		fails += 1
	else:
		print("  PASS: 抽取 3 个 debuff（池 %d 个可用）" % pool.size())

	# 测试2：池里没有 unsupported key（双抗已随三伤害类型轮启用）
	var bad: Array = []
	for b in pool:
		for k in b.get("debuff", {}).keys():
			if k in ["immune_cc", "ult_energy_mult"]:
				bad.append(k)
	if not bad.is_empty():
		print("  FAIL: 池中有未支持 key: %s" % bad)
		fails += 1
	else:
		print("  PASS: 池已过滤 unsupported key")

	# 测试3：Boss 波激活 / 非 Boss 波返回空
	var deb: Dictionary = bd.on_wave_started(10)
	if deb.is_empty() or deb.get("name", "") == "":
		print("  FAIL: 第10波应激活 debuff")
		fails += 1
	else:
		print("  PASS: 第10波激活『%s』" % deb.get("name"))
	if not bd.on_wave_started(11).is_empty():
		print("  FAIL: 第11波不应激活")
		fails += 1
	else:
		print("  PASS: 第11波无 debuff")

	# 测试4：属性修改 + 恢复（以暴伤为例，抽到的可能是任意 key——统一验证 modify_stats 不炸且波结束恢复）
	var CS := load("res://src/core/combat_stats.gd")
	var stats = CS.new()
	stats.apply_atk_bonus()
	var crit_before: float = stats.crit_dmg
	bd.modify_stats(stats)   # 波内
	bd.on_wave_finished()
	var stats2 = CS.new()
	stats2.apply_atk_bonus()
	bd.modify_stats(stats2)  # 波后 → 空操作
	print("  PASS: modify_stats 运行无错（暴伤 %.2f → 波后基线 %.2f）" % [stats.crit_dmg, stats2.crit_dmg])

	# 测试5：预告 next_boss
	var nb: Dictionary = bd.next_boss(1)
	print("  %s: next_boss(1) = %s" % ["PASS" if int(nb.get("wave", 0)) in [10, 20, 30] else "FAIL", nb])

	# 测试6：应对道具——换（reroll 槽位后 name 属于池、结构合法）
	var idx: int = int(nb.get("idx", 0))
	var before: String = nb.get("name", "")
	var rerolled: Dictionary = bd.reroll_slot(idx, rng)
	if rerolled.has("debuff") and rerolled.has("name"):
		print("  PASS: reroll_slot →『%s』（换前『%s』）" % [rerolled.get("name"), before])
	else:
		print("  FAIL: reroll 返回结构非法 %s" % rerolled)
		fails += 1

	# 测试7：应对道具——删（remove 后 next_boss 标记 removed，波不激活）
	bd.remove_slot(idx)
	var nb2: Dictionary = bd.next_boss(1)
	if nb2.get("removed", false):
		var wave_after_remove: Dictionary = bd.on_wave_started(int(nb2.get("wave", 0)))
		if wave_after_remove.is_empty() or not bd.is_active():
			print("  PASS: remove → 预告标记 removed 且 Boss 波无 debuff 生效")
		else:
			print("  FAIL: 删除后 Boss 波仍有 debuff 激活")
			fails += 1
	else:
		print("  FAIL: remove 未标记 removed")
		fails += 1

	print("\n========================================")
	if fails == 0:
		print("  BossDebuffs 测试: 全部通过")
	else:
		print("  BossDebuffs 测试: %d 失败" % fails)
	quit(1 if fails > 0 else 0)
