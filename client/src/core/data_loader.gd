## data_loader.gd — 从 data/*.json 加载全部内容数据（M0 核心件）
## 对应 balance/export_json.py 导出的 JSON（源是 balance/data/*.yaml，Python SSOT）。
##
## 用法：
##   var data := DataLoader.load_all()
##   print(data.skills.size())
extends RefCounted
class_name DataLoader

const DATA_DIR := "res://data"
const GameData := preload("res://src/core/data_types.gd")
# 内部类通过 GameData.X 访问（避免 const 链的解析顺序问题）


## 读取单个 JSON 文件 → Dictionary。文件不存在返回空 dict。
static func _read_json(filename: String) -> Dictionary:
	var path := "%s/%s" % [DATA_DIR, filename]
	if not FileAccess.file_exists(path):
		push_warning("数据文件缺失: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("无法读取: %s" % path)
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("JSON 解析失败: %s" % path)
		return {}
	return parsed as Dictionary
	return parsed


## 加载全部内容数据。返回一个汇总 Dictionary。
static func load_all() -> Dictionary:
	var result := {}
	result["skills"] = load_skills()
	result["affixes"] = load_affixes()
	result["bonds"] = load_bonds()
	result["paths"] = load_paths()
	result["synergies"] = load_synergies()
	result["waves"] = _read_json("waves.json")
	result["economy"] = _read_json("economy.json")
	result["equipment"] = _read_json("equipment.json")
	result["boss_debuffs"] = _read_json("boss_debuffs.json")
	result["consumables"] = _read_json("consumables.json")
	return result


static func load_skills() -> Array:
	var d := _read_json("skills.json")
	var out: Array = []
	for s in d.get("skills", []):
		out.append(GameData.SkillData.from_dict(s))
	return out


static func load_affixes() -> Array:
	var d := _read_json("affixes.json")
	var out: Array = []
	for a in d.get("affixes", []):
		out.append(GameData.AffixData.from_dict(a))
	return out


static func load_bonds() -> Array:
	var d := _read_json("bonds.json")
	var out: Array = []
	for b in d.get("bonds", []):
		out.append(GameData.BondData.from_dict(b))
	return out


static func load_paths() -> Array:
	var d := _read_json("bonds.json")
	var out: Array = []
	for p in d.get("paths", []):
		out.append(GameData.PathData.from_dict(p))
	return out


static func load_synergies() -> Array:
	var d := _read_json("synergies.json")
	var out: Array = []
	for s in d.get("synergies", []):
		out.append(GameData.SynergyData.from_dict(s))
	return out
