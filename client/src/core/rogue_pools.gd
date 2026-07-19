## rogue_pools.gd — 抽取引擎（移植自 balance/td_balance/rogue_pools.py）
## 羁绊抽取 + 境界吞噬 + 装备系统。
## （技能抽取已移除：技能改为每体系 1 个起点技能；九秘改为羁绊 zt_jm_*。）
## 数据来自 data/*.json（balance/data 是 SSOT）。
extends RefCounted
class_name RoguePools

var _bonds: Array = []           # Array[Dictionary]（bonds.json 的 bonds 列表）
var _paths: Array = []           # Array[Dictionary]（bonds.json 的 paths，境界树）
var _bond_to_set: Dictionary = {}  # bond_id → set_id
var _path_bond_ids: Dictionary = {}  # path_id → Array[bond_id]
var _all_bond_ids: Array = []
var _rng: RandomNumberGenerator

# 装备数据（M3）
var _equip_affixes: Array = []   # Array[Dictionary]（equipment.json 的 affixes）
var _equip_upgrade: Dictionary = {}  # equipment.json 的 upgrade_curve
var _equip_milestones: Array = []    # equipment.json 的 milestones（[5,10,15,20]）


func _init(rng: RandomNumberGenerator = null) -> void:
	_rng = rng if rng != null else RandomNumberGenerator.new()
	_rng.randomize()
	_load_data()


func _load_data() -> void:
	var bonds_d := _read_json("bonds.json")
	_bonds = bonds_d.get("bonds", [])
	_paths = bonds_d.get("paths", [])
	# M3: 加载装备数据
	var equip_d := _read_json("equipment.json")
	_equip_affixes = equip_d.get("affixes", [])
	_equip_upgrade = equip_d.get("upgrade_curve", {})
	_equip_milestones = equip_d.get("milestones", [5, 10, 15, 20])
	for b in _bonds:
		var bid: String = b.get("id", "")
		_bond_to_set[bid] = b.get("set", "")
		_all_bond_ids.append(bid)
	for p in _paths:
		var pid: String = p.get("id", "")
		var ids: Array = []
		for r in p.get("realms", []):
			for b in r.get("bonds", []):
				ids.append(b)
		_path_bond_ids[pid] = ids


func _read_json(filename: String) -> Dictionary:
	var path := "res://data/%s" % filename
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}


# ── 羁绊抽取 ──
## 返回 n 个羁绊 offer。
## owned_ids: 玩家已拥有的羁绊（不重复抽取）。
## prefer_ids: 当前境界需要的羁绊（有 50% 概率从中抽，保证修炼推进；其余从全池抽，保证多样性）。
## 生成 n 个羁绊选项（严格阶梯抽取，对齐 balance/td_balance/rogue_pools.py）。
## path_realm: {path_id: 已完成境界数}；初始为空 = 所有 path 从境0开始。
## 只能抽 generic 通用符文 + 各 path 当前境界的羁绊；已拥有不重复；突破后解锁下一境界。
## prefer_ids: 兼容旧接口——作为加权偏好叠加在合法池上（不绕过阶梯限制）。
func draw_bond_offers(n: int = 3, prefer_ids: Array = [], owned_ids: Array = [], path_realm: Dictionary = {}) -> Array:
	var offers: Array = []
	var owned: Dictionary = {}
	for bid in owned_ids:
		owned[bid] = true

	# 合法池 = generic + 种子卡（未选体系时可见） + 已选体系当前境界的羁绊
	var legal: Array = []
	for b in _bonds:
		if b.get("set") == "generic":
			legal.append(b.get("id"))
		# 种子卡：始终可见（除非已选了该体系）
		if b.get("is_seed", false):
			var sp: String = b.get("seed_path", "")
			if not path_realm.has(sp):
				legal.append(b.get("id"))
	for p in _paths:
		var pid: String = p.get("id", "")
		# 只允许玩家已选的体系（path_realm 里有记录）的羁绊进池
		if not path_realm.has(pid):
			continue
		var idx: int = int(path_realm[pid])
		var realms: Array = p.get("realms", [])
		if idx < realms.size():
			for bid in realms[idx].get("bonds", []):
				if not legal.has(bid):
					legal.append(bid)

	# 去除已拥有
	var pool: Array = []
	for bid in legal:
		if not owned.has(bid):
			pool.append(bid)

	# 无可抽（当前境界全凑齐未突破）→ fallback 到 generic
	if pool.is_empty():
		for b in _bonds:
			if b.get("set") == "generic" and not owned.has(b.get("id")):
				pool.append(b.get("id"))
	if pool.is_empty():
		return []   # 极端：全满，玩家该去突破

	# prefer 加权（仅放大合法池内条目，不引入非法羁绊）
	var weighted_pool: Array = pool.duplicate()
	if not prefer_ids.is_empty():
		var prefer_legal: Array = []
		for bid in prefer_ids:
			if pool.has(bid) and not prefer_legal.has(bid):
				prefer_legal.append(bid)
		for bid in prefer_legal:
			for _i in range(3):
				weighted_pool.append(bid)

	var picked: Dictionary = {}
	# 实际可选项数 = min(请求数 n, 可选池去重后的大小)
	var max_offers: int = min(n, pool.size())
	for i in max_offers:
		var bid: String = ""
		var tries: int = 0
		while tries < 8:
			bid = weighted_pool[_rng.randi() % weighted_pool.size()]
			if not picked.has(bid):
				break
			tries += 1
		picked[bid] = true
		var b: Dictionary = _find_bond(bid)
		if b.is_empty():
			b = _bonds[_rng.randi() % _bonds.size()]
		var eff: Dictionary = b.get("effect", {})
		var offer_data: Dictionary = {
			"kind": "bond", "id": b.get("id"), "name": b.get("name"),
			"rarity": b.get("rarity", "N"), "effect": eff,
			"desc": _effect_to_text(eff)
		}
		# 种子卡：带上种子字段，让 take_bond_offer 能识别
		if b.get("is_seed", false):
			offer_data["is_seed"] = true
			offer_data["seed_path"] = b.get("seed_path", "")
			offer_data["seed_gold"] = b.get("seed_gold", 0)
		offers.append(offer_data)
	return offers


# ── 装备系统（M3）──

## 装备升级成本 = cost_base + cost_per_level × current_level
func equip_upgrade_cost(current_level: int) -> float:
	var base: float = float(_equip_upgrade.get("cost_base", 15))
	var per: float = float(_equip_upgrade.get("cost_per_level", 4))
	return base + per * float(current_level)

## 装备最大等级
func equip_max_level() -> int:
	return int(_equip_upgrade.get("max_level", 20))

## 该级的固定经济奖励 effect（奇数级 gold_per_sec，偶数级 per_kill_gold）
func equip_level_reward(level: int) -> Dictionary:
	var incomes: Array = _equip_upgrade.get("per_level_income", [])
	if level < 1 or level > incomes.size():
		return {}
	return incomes[level - 1]

## 判断该级是否是里程碑（从 equipment.json 的 milestones 读，不再硬编码）
func is_milestone_level(level: int) -> bool:
	var milestones: Array = _equip_milestones if not _equip_milestones.is_empty() else [5, 10, 15, 20]
	for ms in milestones:
		if int(ms) == level:
			return true
	return false

## +9 是否保底正面
func is_guaranteed_positive(level: int) -> bool:
	return level >= int(_equip_upgrade.get("milestone_guarantee_positive_at", 9))

## 里程碑抽词条选项：返回 3 张候选（正面 70% / 诅咒 30%，+20 保底正面）
## 返回 Array[Dictionary]，每个含 {id, name, polarity, effect, desc}
func draw_milestone_affix_options(guaranteed_positive: bool, n: int = 3) -> Array:
	var positives: Array = []
	var curses: Array = []
	for a in _equip_affixes:
		match a.get("polarity", "positive"):
			"curse":
				curses.append(a)
			_:
				positives.append(a)
	var options: Array = []
	var picked: Dictionary = {}   # 去重
	for i in n:
		var use_positive: bool = guaranteed_positive or _rng.randf() < 0.7
		var pool: Array = positives if use_positive else curses
		if pool.is_empty():
			pool = _equip_affixes
		# 随机抽一张（去重）
		var tries: int = 0
		var chosen: Dictionary = {}
		while tries < 10:
			chosen = pool[_rng.randi() % pool.size()]
			var aid: String = chosen.get("id", str(i))
			if not picked.has(aid):
				picked[aid] = true
				break
			tries += 1
		if chosen.is_empty():
			chosen = pool[_rng.randi() % pool.size()]
		# 诅咒词条：合并 cost + benefit 成 effect（正面词条已有 effect）
		var polarity: String = chosen.get("polarity", "positive")
		if polarity == "curse" and not chosen.has("effect"):
			var merged_eff: Dictionary = {}
			var cost_d: Dictionary = chosen.get("cost", {})
			var benefit_d: Dictionary = chosen.get("benefit", {})
			for k in cost_d:
				merged_eff[k] = cost_d[k]
			for k in benefit_d:
				merged_eff[k] = benefit_d[k]
			chosen["effect"] = merged_eff
		options.append(chosen.duplicate())
	return options


## 里程碑抽词条（旧接口，直接抽一张——保留兼容）
func draw_milestone_affix(guaranteed_positive: bool) -> Dictionary:
	var options := draw_milestone_affix_options(guaranteed_positive, 1)
	return options[0] if not options.is_empty() else {}

## 查装备词条名称
func _find_equip_affix_name(aid: String) -> String:
	for a in _equip_affixes:
		if a.get("id") == aid:
			return a.get("name", aid)
	return aid


# ── 境界吞噬 ──
## 检查是否有可晋升的修炼路径（当前境界羁绊全在池中）。
## path_realm: {path_id: 已完成境界数}。返回 {path_id, realm_idx, needed: Array} 或 null。
func find_devourable(bond_pool: Array, path_realm: Dictionary) -> Variant:
	var pool_set: Dictionary = {}
	for bid in bond_pool:
		pool_set[bid] = true
	for p in _paths:
		var pid: String = p.get("id", "")
		var realms: Array = p.get("realms", [])
		var idx: int = int(path_realm.get(pid, 0))
		if idx >= realms.size():
			continue
		var needed: Array = realms[idx].get("bonds", [])
		if needed.is_empty():
			continue
		var all_in := true
		for b in needed:
			if not pool_set.has(b):
				all_in = false
				break
		if all_in:
			return {"path_id": pid, "realm_idx": idx, "needed": needed.duplicate()}
	return null


## 获取某路径某境界的 reward dict。
func realm_reward(path_id: String, realm_idx: int) -> Dictionary:
	for p in _paths:
		if p.get("id") == path_id:
			var realms: Array = p.get("realms", [])
			if realm_idx < realms.size():
				return realms[realm_idx].get("reward", {})
	return {}


func path_name(path_id: String) -> String:
	for p in _paths:
		if p.get("id") == path_id:
			return p.get("name", path_id)
	return path_id


func realm_name(path_id: String, realm_idx: int) -> String:
	for p in _paths:
		if p.get("id") == path_id:
			var realms: Array = p.get("realms", [])
			if realm_idx < realms.size():
				return realms[realm_idx].get("name", "?")
	return "?"


func path_max_realm(path_id: String) -> int:
	for p in _paths:
		if p.get("id") == path_id:
			return p.get("realms", []).size()
	return 0


func current_realm_bonds(path_id: String, realm_idx: int) -> Array:
	for p in _paths:
		if p.get("id") == path_id:
			var realms: Array = p.get("realms", [])
			if realm_idx < realms.size():
				return realms[realm_idx].get("bonds", [])
	return []


func all_paths() -> Array:
	return _paths


## 判断某羁绊是否属于指定路径的当前境界（用于卡片高亮）。
func bond_in_current_realm(bond_id: String, path_id: String, realm_idx: int) -> bool:
	var needed: Array = current_realm_bonds(path_id, realm_idx)
	return needed.has(bond_id)


## 判断某羁绊是否属于指定路径的任意境界（用于同体系高亮）。
func bond_in_path(bond_id: String, path_id: String) -> bool:
	for p in _paths:
		if p.get("id") == path_id:
			for r in p.get("realms", []):
				if r.get("bonds", []).has(bond_id):
					return true
	return false


## 获取某路径所有境界的全部羁绊 id（用于判断是否已修满排除）
func all_bonds_in_path(path_id: String) -> Array:
	var result: Array = []
	for p in _paths:
		if p.get("id") == path_id:
			for r in p.get("realms", []):
				for b in r.get("bonds", []):
					result.append(b)
	return result


## 获取羁绊的 set 字段。
func bond_set(bond_id: String) -> String:
	return String(_bond_to_set.get(bond_id, ""))


## 从已拥有羁绊中找出匹配最多的路径 id（用于未开始修炼时的进度显示）。
func _detect_path_from_bonds(bond_pool: Array) -> String:
	var best_pid: String = ""
	var best_count: int = 0
	for p in _paths:
		var pid: String = p.get("id", "")
		var count: int = 0
		for r in p.get("realms", []):
			for b in r.get("bonds", []):
				if bond_pool.has(b):
					count += 1
		if count > best_count:
			best_count = count
			best_pid = pid
	return best_pid


## 获取修炼进度摘要（用于卡片/面板显示）。
## 如果有正在修炼的路径（path_realm 非空），显示该路径当前境界进度。
## 如果没有（path_realm 空），扫描已拥有羁绊找出最有潜力的路径。
func cultivation_progress(bond_pool: Array, path_realm: Dictionary) -> Dictionary:
	var pid: String = ""
	var idx: int = 0
	if not path_realm.is_empty():
		pid = path_realm.keys()[0]
		idx = path_realm[pid]
	else:
		# 未开始修炼：找已拥有羁绊所属的路径
		pid = _detect_path_from_bonds(bond_pool)
		if pid == "":
			return {}   # 没有任何体系羁绊
		idx = 0
	var needed: Array = current_realm_bonds(pid, idx)
	var owned_count: int = 0
	var missing: Array = []
	var missing_names: Array = []
	for b in needed:
		if bond_pool.has(b):
			owned_count += 1
		else:
			missing.append(b)
			missing_names.append(_find_bond_name(String(b)))
	return {
		"path_id": pid,
		"path_name": path_name(pid),
		"realm_idx": idx,
		"realm_name": realm_name(pid, idx),
		"max_realm": path_max_realm(pid),
		"needed": needed,
		"owned_count": owned_count,
		"total_count": needed.size(),
		"missing": missing,
		"missing_names": missing_names,
	}


# ── 内部 ──
# effect key → 中文显示模板（% 为数值占位）。数值 >0 显示 +x%，<0 显示 x%。
const _EFFECT_LABELS := {
	"atk_pct_delta": "攻击力 %s",
	"atk_ratio_delta": "技能倍率 ×%s",
	"crit_rate_delta": "暴击率 %s",
	"crit_dmg_delta": "暴击伤害 %s",
	"attack_speed_delta": "攻速 %s",
	"skill_mult_pct_delta": "技能增伤 %s",
	"magic_dmg_pct_delta": "法术伤害 %s",
	"physical_dmg_pct_delta": "物理伤害 %s",
	"elemental_dmg_mult": "元素伤害 %s",
	"elemental_pct": "元素伤害 %s",
	"final_dmg_mult": "最终伤害 %s",
	"true_dmg_pct_delta": "真伤占比 %s",
	"armor_pen_delta": "护甲穿透 %s",
	"projectile_count_delta": "弹数 %s",
	"per_projectile_dmg_mult": "散射递减 ×%s",
	"hp_pct_delta": "生命 %s",
	"lifesteal_pct": "吸血 %s",
	"damage_reduction_delta": "减伤 %s",
	"gold_mult": "金币掉落 %s",
	"gold_per_sec_delta": "每秒金币 %s",
	"per_kill_gold_delta": "击杀金币 %s",
	"double_gold_chance": "双倍金币概率 %s",
	"gold_lump": "一次性金币 %s",
	"bond_draw_cost_delta": "抽羁绊成本 %s",
	"reroll_cost_delta": "刷新成本 %s",
	"equip_upgrade_cost_delta": "升级成本 %s",
	"dmg_taken_mult": "受伤 %s",
	"per_hit_dmg_mult": "单次伤害 %s",
	"draw_cost_mult": "抽取成本 %s",
	"synergy_effect_mult": "联动效果 %s",
}

## 绝对值 effect key（不是百分比，直接显示数值）
const _ABSOLUTE_KEYS := {
	"gold_per_sec_delta": true,
	"per_kill_gold_delta": true,
	"gold_lump": true,
	"bond_draw_cost_delta": true,
	"reroll_cost_delta": true,
	"equip_upgrade_cost_delta": true,
}


## 把 effect 字典翻译成中文加成描述（供卡片显示）。
func _effect_to_text(eff: Dictionary) -> String:
	if eff.is_empty():
		return ""
	var parts: Array = []
	for key in eff.keys():
		if _EFFECT_LABELS.has(key):
			var v: float = float(eff[key])
			var sign: String = ""
			if _ABSOLUTE_KEYS.has(key):
				# 绝对值：直接显示数值（+1, +0.5 等）
				if v == int(v):
					sign = "%+d" % int(v)
				else:
					sign = "%+.1f" % v
			elif key == "atk_ratio_delta":
				sign = "%.2f" % v
			elif key == "projectile_count_delta":
				sign = "%+d" % int(v)
			elif key == "per_projectile_dmg_mult":
				sign = "%.2f" % v
			elif key == "double_gold_chance" or key == "dmg_taken_mult" or key == "draw_cost_mult" or key == "synergy_effect_mult":
				sign = "%+.0f%%" % (v * 100.0)
			else:
				# 百分比类：×100 后显示
				sign = ("%+.0f%%" % (v * 100.0)) if abs(v) < 10.0 else ("%+.0f" % v)
			parts.append(_EFFECT_LABELS[key] % sign)
	if parts.is_empty():
		# 未知 key（联动/状态等 M2.5 接入）：列出原始 key
		for key in eff.keys():
			parts.append(key)
	return "  • ".join(parts)


func _find_bond(bid: String) -> Dictionary:
	for b in _bonds:
		if b.get("id") == bid:
			return b
	return {}


## 查羁绊名称（供 UI 显示）
func _find_bond_name(bid: String) -> String:
	var b: Dictionary = _find_bond(bid)
	if b.is_empty():
		return bid
	return b.get("name", bid)
