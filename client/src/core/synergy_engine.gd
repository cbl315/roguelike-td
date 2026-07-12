## synergy_engine.gd — 联动规则引擎（移植自 Python synergy_engine.py）
## 根据玩家状态（羁绊吞噬/技能/词条）重算 active 联动规则。
## 所有联动统一走 bond_devoured_set（修满体系）+ 跨系统条件。
## 纯逻辑，不依赖节点。
extends RefCounted
class_name SynergyEngine

var _synergies: Array = []           # Array[Dictionary]（synergies.json）
var _skill_tags: Dictionary = {}     # skill_id → Array[String] tags（缓存）


func _init() -> void:
	_load_data()


func _load_data() -> void:
	var path := "res://data/synergies.json"
	if not FileAccess.file_exists(path):
		push_error("synergy_engine: 无法读取 %s" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_synergies = parsed.get("synergies", [])
	# 加载技能 tags 缓存（用于 skill_tag 条件检查）
	_load_skill_tags()


func _load_skill_tags() -> void:
	var path := "res://data/skills.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var skills: Array = parsed.get("skills", [])
		for s in skills:
			_skill_tags[s.get("id", "")] = s.get("tags", [])


## 返回当前所有满足触发条件的联动（Array[Dictionary]）。
## build: BuildState；pools: RoguePools（查 path realms）
func active(build, pools) -> Array:
	var result: Array = []
	for syn in _synergies:
		if _check(syn, build, pools):
			result.append(syn)
	return result


## 返回 active 联动的 id + name 列表（供 UI 显示）。
func active_names(build, pools) -> Array:
	var result: Array = []
	for syn in _synergies:
		if _check(syn, build, pools):
			result.append({"id": syn.get("id", ""), "name": syn.get("name", ""), "tier": syn.get("tier", "")})
	return result


## 检查一条联动：trigger.all 里所有条件都满足。
func _check(syn: Dictionary, build, pools) -> bool:
	var conditions: Array = syn.get("trigger", {}).get("all", [])
	for cond in conditions:
		if not _check_one(cond, build, pools):
			return false
	return true


## 检查单个触发条件。cond 是 {key: value} 单键 dict。
func _check_one(cond: Dictionary, build, pools) -> bool:
	for key in cond.keys():
		var val: String = String(cond[key])
		match key:
			"bond_devoured_set":
				# 该体系已修满顶级境界
				var max_realm: int = pools.path_max_realm(val)
				if max_realm <= 0:
					return false
				return int(build.path_realm.get(val, 0)) >= max_realm - 1
			"skill_owned":
				return build.owned_skills.has(val)
			"skill_tag":
				return _has_skill_tag(val, build)
			"affix_owned", "equipment_affix":
				# M3 装备系统未做，当前简化：检查技能 base_affixes
				return _has_affix(val, build)
	return false


func _has_skill_tag(tag: String, build) -> bool:
	for sid in build.owned_skills:
		var tags: Array = _skill_tags.get(String(sid), [])
		if tags.has(tag):
			return true
	return false


func _has_affix(affix_id: String, build) -> bool:
	# 简化：检查 accumulated_effects 里有没有对应词条
	# M2 的技能词条 effect 已经累加到 accumulated_effects
	# 这里做近似匹配——检查 effect dict 里有没有和 affix_id 相关的 key
	# 真正的 affix 追踪需要 M3 装备系统
	# 当前：返回 true（让联动可触发，等 M3 做精确检查）
	# TODO M3: 从 build.tracked_affixes 精确查询
	return true
