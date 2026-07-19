## test_winrate.gd — 自动通关率模拟测试（Godot headless，不依赖 BuildState）
## 用法: godot --headless --path client -s tests/test_winrate.gd
##
## 纯数据模拟：选体系→抽羁绊→升装备→战斗结算→统计通关率。
## 不加载 BuildState（避免 EventBus autoload 问题），直接操作 JSON 数据。
extends SceneTree


const WAVES := 30
const RUNS_PER_CONFIG := 10

const WAVE_INCOME_BASE := 138.0
const WAVE_INCOME_GROWTH := 1.12
const BOSS_BONUS := 1.5
const BOSS_EVERY := 5
const BOND_DRAW_BASE := 30.0
const BOND_DRAW_INC := 10.0
const BOND_DRAW_CAP := 60.0
const EQUIP_COST_BASE := 20.0
const EQUIP_COST_PER := 8.0
const DEVOUR_COST := 50.0
const ENEMY_HP_BASE := 100.0
const ENEMY_HP_GROWTH := 1.07
const ENEMY_COUNT_BASE := 8
const ENEMY_COUNT_PER_WAVE := 1.5
const WAVE_DURATION_BASE := 25
const WAVE_DURATION_PER := 1
const LEAK_DMG_BASE := 30.0
const LEAK_DMG_PER_WAVE := 5.0


func _init():
	print("========================================")
	print("  通关率模拟测试")
	print("========================================")

	var configs: Array = [
		{"name": "单修-遮天", "paths": ["zhutian"]},
		{"name": "单修-星辰变", "paths": ["xingchenbian"]},
		{"name": "单修-宠魅", "paths": ["chongmei"]},
		{"name": "双修-遮天+星辰变", "paths": ["zhutian", "xingchenbian"]},
		{"name": "双修-遮天+宠魅", "paths": ["zhutian", "chongmei"]},
		{"name": "三修", "paths": ["zhutian", "xingchenbian", "chongmei"]},
	]

	for config in configs:
		var cleared := 0
		var death_waves: Array = []
		var max_realms: Array = []

		for run in RUNS_PER_CONFIG:
			var seed_val: int = run * 1000 + abs(config.name.hash())
			var result := _simulate_one_run(config.paths, seed_val)
			if result["cleared"]:
				cleared += 1
			else:
				death_waves.append(result["death_wave"])
			max_realms.append(result["max_realm"])

		var rate: float = float(cleared) / RUNS_PER_CONFIG * 100.0
		var avg_realm: float = _avg(max_realms)
		print("\n[%s] %d/%d = %.0f%% | 平均境%.1f | 死亡: %s" % [
			config.name, cleared, RUNS_PER_CONFIG, rate, avg_realm,
			str(death_waves) if death_waves else "无"
		])

	print("\n========================================")
	quit(0)


func _simulate_one_run(chosen_paths: Array, seed_val: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var pools := RoguePools.new(rng)

	# 简单状态（不用 BuildState）
	var path_realm: Dictionary = {}
	for pid in chosen_paths:
		path_realm[pid] = 0
	var accumulated_effects: Array = []
	var bond_pool: Array = []
	var devoured: Array = []
	var equip_level := 0
	var gold := 0.0
	var hp := 1000.0
	var bond_times_drawn := 0
	var death_wave := 0

	for wave in range(1, WAVES + 1):
		# 收入
		var income: float = WAVE_INCOME_BASE * pow(WAVE_INCOME_GROWTH, wave - 1)
		if wave % BOSS_EVERY == 0:
			income *= BOSS_BONUS
		gold += income

		# 大厅操作
		var guard := 0
		while gold > 0 and guard < 50:
			guard += 1

			# 1) 吞噬
			var dev: Variant = pools.find_devourable(bond_pool, path_realm)
			if dev != null and dev is Dictionary and not dev.is_empty():
				if gold >= DEVOUR_COST:
					gold -= DEVOUR_COST
					var needed: Array = dev.get("needed", [])
					for b in needed:
						bond_pool.erase(b)
						if not devoured.has(b):
							devoured.append(b)
					var pid: String = dev.get("path_id", "")
					var idx: int = int(dev.get("realm_idx", 0))
					path_realm[pid] = idx + 1
					var reward: Dictionary = pools.realm_reward(pid, idx)
					if not reward.is_empty():
						accumulated_effects.append(reward)
					continue

			# 2) 抽羁绊
			var draw_cost: float = minf(BOND_DRAW_CAP, BOND_DRAW_BASE + BOND_DRAW_INC * bond_times_drawn)
			if gold >= draw_cost and bond_pool.size() < 10:
				gold -= draw_cost
				bond_times_drawn += 1
				var excluded: Array = bond_pool.duplicate()
				for d in devoured:
					if not excluded.has(d):
						excluded.append(d)
				# prefer：当前所有体系当前境界还缺的羁绊（优先选有用的）
				var prefer: Array = []
				for p in pools._paths:
					var pid: String = p.get("id", "")
					if not path_realm.has(pid):
						continue
					var idx: int = path_realm[pid]
					var realms: Array = p.get("realms", [])
					if idx < realms.size():
						for bid in realms[idx].get("bonds", []):
							if not bond_pool.has(bid) and not devoured.has(bid):
								prefer.append(bid)
				var offers: Array = pools.draw_bond_offers(3, prefer, excluded, path_realm)
				if offers.size() > 0:
					# 优先选当前境界需要的，其次 generic，最后种子
					var chosen: Dictionary = offers[0]
					for o in offers:
						var oid: String = o.get("id", "")
						if prefer.has(oid):
							chosen = o
							break
					if not chosen.get("is_seed", false):
						# 池满时丢 generic
						if bond_pool.size() >= 10:
							for i in bond_pool.size():
								if pools._bond_to_set.get(bond_pool[i]) == "generic":
									bond_pool.remove_at(i)
									break
						bond_pool.append(chosen.get("id", ""))
				continue

			# 3) 升装备
			var ec: float = EQUIP_COST_BASE + EQUIP_COST_PER * equip_level
			if gold >= ec and equip_level < 20:
				gold -= ec
				equip_level += 1
				var reward: Dictionary = pools.equip_level_reward(equip_level)
				var clean: Dictionary = {}
				for k in reward:
					if k != "level" and k != "milestone" and k != "milestone_guaranteed_positive":
						clean[k] = reward[k]
				if not clean.is_empty():
					accumulated_effects.append(clean)
				continue
			break

		# 算属性
		var stats := CombatStats.new()
		EffectResolver.accumulate_all(stats, accumulated_effects)
		for bid in bond_pool:
			var b: Dictionary = pools._find_bond(bid)
			if not b.is_empty():
				var eff: Dictionary = b.get("effect", {})
				if not eff.is_empty():
					EffectResolver.accumulate_all(stats, [eff])
		for bid in devoured:
			var b: Dictionary = pools._find_bond(bid)
			if not b.is_empty():
				var eff: Dictionary = b.get("effect", {})
				if not eff.is_empty():
					EffectResolver.accumulate_all(stats, [eff])
		stats.apply_atk_bonus()

		var max_hp: float = stats.effective_max_hp()
		hp = minf(hp, max_hp)

		# DPS
		var dps: float = stats.expected_dps(20.0)
		# 宠魅召唤单位加成
		if path_realm.has("chongmei"):
			var rcm: int = path_realm["chongmei"]
			if rcm >= 1:
				dps *= 1.7  # 莫邪
			if rcm >= 4:
				dps *= 1.4  # 白魇魔
			if rcm >= 7:
				dps *= 1.3  # 第三魂宠

		# 敌人
		var is_boss: bool = (wave % BOSS_EVERY == 0)
		var e_hp: float = ENEMY_HP_BASE * pow(ENEMY_HP_GROWTH, wave - 1)
		var e_count: int = int(ENEMY_COUNT_BASE + ENEMY_COUNT_PER_WAVE * wave)
		if is_boss:
			e_hp *= 3.0
			e_count = max(1, e_count / 3)
		var total_enemy_hp: float = e_hp * e_count
		var duration: float = WAVE_DURATION_BASE + WAVE_DURATION_PER * wave
		var dmg_dealt: float = dps * duration

		if dmg_dealt < total_enemy_hp:
			var remaining: float = total_enemy_hp - dmg_dealt
			var leaked: int = max(1, int(remaining / e_hp))
			var leak_dmg: float = LEAK_DMG_BASE + LEAK_DMG_PER_WAVE * wave
			hp -= leak_dmg * leaked * 0.3

		if hp <= 0:
			death_wave = wave
			break
		hp = minf(max_hp, hp + max_hp * 0.02)

	var cleared: bool = (death_wave == 0)
	var max_realm: int = 0
	for pid in path_realm:
		max_realm = max(max_realm, path_realm[pid])
	return {"cleared": cleared, "death_wave": death_wave if death_wave > 0 else WAVES + 1, "max_realm": max_realm}


func _avg(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s: float = 0.0
	for v in arr:
		s += v
	return s / arr.size()
