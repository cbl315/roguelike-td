## test_draw_debug.gd — 调试遮天阶梯抽取进度
extends SceneTree

func _init():
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var pools := RoguePools.new(rng)

	var path_realm := {"zhutian": 0}
	var bond_pool: Array = []

	print("=== 遮天轮海阶梯抽取（每波抽3次）===")
	for wave in range(1, 16):
		var excluded: Array = bond_pool.duplicate()
		var offers: Array = pools.draw_bond_offers(3, [], excluded, path_realm)
		var ids: Array = []
		for o in offers:
			ids.append(o.get("id", "?"))
		# 选第一个
		if offers.size() > 0:
			var chosen: Dictionary = offers[0]
			if not chosen.get("is_seed", false):
				bond_pool.append(chosen.get("id", ""))

		# 轮海进度
		var lunhai := ["zt_lunhai_daojing", "zt_lunhai_kuhai", "zt_lunhai_mingquan", "zt_lunhai_shenqiao", "zt_jm_jie"]
		var have: int = 0
		for l in lunhai:
			if bond_pool.has(l):
				have += 1
		# 检查能否突破
		var dev: Variant = pools.find_devourable(bond_pool, path_realm)
		var can_break: String = "⚡可突破" if dev != null else ""
		print("波%d: offers=%s | pool=%d个 | 轮海%d/5 %s" % [wave, str(ids), bond_pool.size(), have, can_break])

		# 如果能突破，模拟突破
		if dev != null and dev is Dictionary:
			var needed: Array = dev.get("needed", [])
			for b in needed:
				bond_pool.erase(b)
			path_realm["zhutian"] = 1
			print("  → 突破到道宫！")

	print("\n最终 path_realm: %s" % str(path_realm))
	print("最终 bond_pool: %s" % str(bond_pool))
	quit(0)
