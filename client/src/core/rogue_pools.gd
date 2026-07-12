## rogue_pools.gd — 抽取引擎（移植自 balance/td_balance/rogue_pools.py）
## 技能 3 选 1（50% 新技能/50% 已有词条，加权 60/30/8/2）+ 羁绊抽取 + 境界吞噬。
## 数据来自 data/*.json（balance/data 是 SSOT）。
extends RefCounted
class_name RoguePools

const RARITIES := ["common", "rare", "epic", "legendary"]
const RARITY_WEIGHTS := {"common": 60, "rare": 30, "epic": 8, "legendary": 2}

var _skills: Array = []          # Array[Dictionary]（skills.json 的 skills 列表）
var _bonds: Array = []           # Array[Dictionary]（bonds.json 的 bonds 列表）
var _affixes: Array = []         # Array[Dictionary]（affixes.json 的 affixes 列表）
var _paths: Array = []           # Array[Dictionary]（bonds.json 的 paths，境界树）
var _bond_to_set: Dictionary = {}  # bond_id → set_id
var _path_bond_ids: Dictionary = {}  # path_id → Array[bond_id]
var _all_bond_ids: Array = []
var _rng: RandomNumberGenerator

# 装备数据（M3）
var _equip_affixes: Array = []   # Array[Dictionary]（equipment.json 的 affixes）
var _equip_upgrade: Dictionary = {}  # equipment.json 的 upgrade_curve


func _init(rng: RandomNumberGenerator = null) -> void:
	_rng = rng if rng != null else RandomNumberGenerator.new()
	_rng.randomize()
	_load_data()


func _load_data() -> void:
	var skills_d := _read_json("skills.json")
	_skills = skills_d.get("skills", [])
	var bonds_d := _read_json("bonds.json")
	_bonds = bonds_d.get("bonds", [])
	_paths = bonds_d.get("paths", [])
	var affixes_d := _read_json("affixes.json")
	_affixes = affixes_d.get("affixes", [])
	# M3: 加载装备数据
	var equip_d := _read_json("equipment.json")
	_equip_affixes = equip_d.get("affixes", [])
	_equip_upgrade = equip_d.get("upgrade_curve", {})
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


# ── 技能 3 选 1 ──
## 返回 3 个 offer（Dictionary：kind/id/name/rarity）。
## kind: "new_skill" 或 "skill_affix"。owned_skill_ids: 已拥有技能 id 集合。
func draw_skill_offers(owned_skill_ids: Array, n: int = 3) -> Array:
	var offers: Array = []
	var unowned: Array = []
	for s in _skills:
		if not owned_skill_ids.has(s.get("id")):
			unowned.append(s)
	for i in n:
		var roll: float = _rng.randf()
		if roll < 0.5 and not unowned.is_empty():
			# 新技能：带 atk_ratio + 效果（atk_ratio 转成 atk_ratio_delta 供显示/结算）
			var rarity := _weighted_rarity()
			var pool := _filter_by_rarity(unowned, rarity)
			if pool.is_empty():
				pool = unowned
			var s: Dictionary = pool[_rng.randi() % pool.size()]
			var ratio: float = float(s.get("atk_ratio", 1.0))
			var eff: Dictionary = {}
			# atk_ratio 是技能伤害倍率（默认1.0）。转成 delta = ratio-1，累加到 CombatStats.atk_ratio。
			if ratio != 1.0:
				eff["atk_ratio_delta"] = ratio - 1.0
			offers.append({
				"kind": "new_skill", "id": s.get("id"), "name": s.get("name"),
				"rarity": s.get("rarity", "common"), "effect": eff,
				"desc": "倍率 ×%.2f" % ratio
			})
		else:
			# 词条：从真实 affixes.json 池按稀有度抽，带 effect
			var rarity := _weighted_rarity()
			var apool := _filter_by_rarity(_affixes, rarity)
			if apool.is_empty():
				apool = _affixes
			if apool.is_empty():
				# 无词条数据兜底
				offers.append({"kind": "skill_affix", "id": "affix_" + rarity, "name": rarity + " 词条", "rarity": rarity, "effect": {}, "desc": ""})
			else:
				var a: Dictionary = apool[_rng.randi() % apool.size()]
				offers.append({
					"kind": "skill_affix", "id": a.get("id"), "name": a.get("name"),
					"rarity": a.get("rarity", rarity), "effect": a.get("effect", {}),
					"desc": _effect_to_text(a.get("effect", {}))
				})
	return offers


# ── 羁绊抽取 ──
## 返回 n 个羁绊 offer。
## owned_ids: 玩家已拥有的羁绊（不重复抽取）。
## prefer_ids: 当前境界需要的羁绊（有 50% 概率从中抽，保证修炼推进；其余从全池抽，保证多样性）。
func draw_bond_offers(n: int = 3, prefer_ids: Array = [], owned_ids: Array = []) -> Array:
	var offers: Array = []
	# 可用池 = 全部 - 已拥有
	var avail: Array = []
	for bid in _all_bond_ids:
		if not owned_ids.has(bid):
			avail.append(bid)
	if avail.is_empty():
		avail = _all_bond_ids.duplicate()   # 全拥有则放行（极少见）
	# prefer 池 = 境界羁绊 - 已拥有
	var prefer: Array = []
	for bid in prefer_ids:
		if avail.has(bid):
			prefer.append(bid)
	var picked: Dictionary = {}   # 本轮已抽中 id，避免 n 张里重复
	for i in n:
		var bid: String = ""
		# 50% 走 prefer（修炼推进），50% 走全池（多样性）
		var tries: int = 0
		while tries < 8:
			if not prefer.is_empty() and _rng.randf() < 0.5:
				bid = prefer[_rng.randi() % prefer.size()]
			else:
				bid = avail[_rng.randi() % avail.size()]
			if not picked.has(bid):
				break
			tries += 1
		picked[bid] = true
		var b: Dictionary = _find_bond(bid)
		if b.is_empty():
			b = _bonds[_rng.randi() % _bonds.size()]
		var eff: Dictionary = b.get("effect", {})
		offers.append({
			"kind": "bond", "id": b.get("id"), "name": b.get("name"),
			"rarity": b.get("rarity", "common"), "effect": eff,
			"desc": _effect_to_text(eff)
		})
	return offers


# ── 装备系统（M3）──

## 装备升级成本 = cost_base + cost_per_level × current_level
func equip_upgrade_cost(current_level: int) -> float:
	var base: float = float(_equip_upgrade.get("cost_base", 15))
	var per: float = float(_equip_upgrade.get("cost_per_level", 4))
	return base + per * float(current_level)

## 装备最大等级
func equip_max_level() -> int:
	return int(_equip_upgrade.get("max_level", 9))

## 该级的固定经济奖励 effect（奇数级 gold_per_sec，偶数级 per_kill_gold）
func equip_level_reward(level: int) -> Dictionary:
	var incomes: Array = _equip_upgrade.get("per_level_income", [])
	if level < 1 or level > incomes.size():
		return {}
	return incomes[level - 1]

## 判断该级是否是里程碑（+3/+6/+9）
func is_milestone_level(level: int) -> bool:
	var milestones: Array = [3, 6, 9]
	return milestones.has(level)

## +9 是否保底正面
func is_guaranteed_positive(level: int) -> bool:
	return level >= int(_equip_upgrade.get("milestone_guarantee_positive_at", 9))

## 里程碑抽词条：正面 70% / 诅咒 30%（+9 保底正面）
## 返回 {id, name, polarity, effect, desc}
func draw_milestone_affix(guaranteed_positive: bool) -> Dictionary:
	var positives: Array = []
	var curses: Array = []
	for a in _equip_affixes:
		match a.get("polarity", "positive"):
			"curse":
				curses.append(a)
			_:
				positives.append(a)
	var chosen: Dictionary = {}
	if guaranteed_positive or _rng.randf() < 0.7:
		# 正面词条
		if positives.is_empty():
			chosen = _equip_affixes[_rng.randi() % _equip_affixes.size()]
		else:
			chosen = positives[_rng.randi() % positives.size()]
	else:
		# 诅咒词条
		if curses.is_empty():
			chosen = positives[_rng.randi() % positives.size()] if not positives.is_empty() else {}
		else:
			chosen = curses[_rng.randi() % curses.size()]
	if chosen.is_empty():
		return {}
	# 构造 effect：正面用 effect，诅咒合并 cost + benefit
	var eff: Dictionary = {}
	var polarity: String = chosen.get("polarity", "positive")
	if polarity == "curse":
		var cost: Dictionary = chosen.get("cost", {})
		var benefit: Dictionary = chosen.get("benefit", {})
		for k in cost:
			eff[k] = cost[k]
		for k in benefit:
			eff[k] = benefit[k]
	else:
		eff = chosen.get("effect", {}).duplicate()
	var desc_text: String = _effect_to_text(eff)
	if polarity == "curse":
		desc_text = "代价换收益！\n" + desc_text
	return {
		"id": chosen.get("id", ""), "name": chosen.get("name", ""),
		"polarity": polarity, "effect": eff, "desc": desc_text
	}

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
func _weighted_rarity() -> String:
	var total := 0
	for r in RARITIES:
		total += int(RARITY_WEIGHTS[r])
	var roll := _rng.randi() % total
	var acc := 0
	for r in RARITIES:
		acc += int(RARITY_WEIGHTS[r])
		if roll < acc:
			return r
	return "common"


func _filter_by_rarity(items: Array, rarity: String) -> Array:
	var out: Array = []
	for s in items:
		if s.get("rarity") == rarity:
			out.append(s)
	return out


# effect key → 中文显示模板（% 为数值占位）。数值 >0 显示 +x%，<0 显示 x%。
const _EFFECT_LABELS := {
	"atk_pct_delta": "攻击力 %s%%",
	"atk_ratio_delta": "技能倍率 ×%s",
	"crit_rate_delta": "暴击率 %s%%",
	"crit_dmg_delta": "暴击伤害 %s%%",
	"attack_speed_delta": "攻速 %s%%",
	"skill_mult_pct_delta": "技能增伤 %s%%",
	"magic_dmg_pct_delta": "法术伤害 %s%%",
	"physical_dmg_pct_delta": "物理伤害 %s%%",
	"elemental_dmg_mult": "元素伤害 %s%%",
	"elemental_pct": "元素伤害 %s%%",
	"final_dmg_mult": "最终伤害 %s%%",
	"true_dmg_pct_delta": "真伤占比 %s%%",
	"armor_pen_delta": "护甲穿透 %s%%",
	"projectile_count_delta": "弹数 %s",
	"per_projectile_dmg_mult": "散射递减 ×%s",
	"hp_pct_delta": "生命 %s%%",
	"lifesteal_pct": "吸血 %s%%",
	"damage_reduction_delta": "减伤 %s%%",
	"gold_mult": "金币掉落 %s%%",
	"gold_per_sec_delta": "每秒金币 %s",
	"per_kill_gold_delta": "击杀金币 %s",
	"double_gold_chance": "双倍金币概率 %s%%",
	"gold_lump": "一次性金币 %s",
	"bond_draw_cost_delta": "抽羁绊成本 %s",
	"reroll_cost_delta": "刷新成本 %s",
	"equip_upgrade_cost_delta": "升级成本 %s",
	"dmg_taken_mult": "受伤 %s%%",
	"per_hit_dmg_mult": "单次伤害 %s%%",
	"draw_cost_mult": "抽取成本 %s%%",
	"synergy_effect_mult": "联动效果 %s%%",
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


## 查技能数据 by id
func _find_skill(sid: String) -> Dictionary:
	for s in _skills:
		if s.get("id") == sid:
			return s
	return {}


## 查技能名称（供 UI 显示）
func _find_skill_name(sid: String) -> String:
	var s: Dictionary = _find_skill(sid)
	if s.is_empty():
		return sid
	return s.get("name", sid)
