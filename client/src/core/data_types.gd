## data_types.gd — 纯数据类（对应 balance/td_balance/schemas.py）
## 这些是 content data 的类型；战斗运行态在 M1 起的 combat 模块。
## 用 RefCounted（轻量，无节点开销）。所有字段从 JSON 加载。
extends RefCounted
class_name GameData


# ── 技能 ──
class SkillData:
	var id: String
	var name: String
	var rarity: String         # common/rare/epic/legendary
	var tags: PackedStringArray
	var atk_ratio: float
	var base_affixes: PackedStringArray
	var note: String

	static func from_dict(d: Dictionary) -> SkillData:
		var s := SkillData.new()
		s.id = d.get("id", "")
		s.name = d.get("name", "")
		s.rarity = d.get("rarity", "common")
		s.tags = PackedStringArray(d.get("tags", []))
		s.atk_ratio = float(d.get("atk_ratio", 1.0))
		s.base_affixes = PackedStringArray(d.get("base_affixes", []))
		s.note = d.get("note", "")
		return s


# ── 词条 ──
class AffixData:
	var id: String
	var name: String
	var rarity: String
	var stacking: String       # add/mult/independent/chance/replace
	var effect: Dictionary
	var note: String

	static func from_dict(d: Dictionary) -> AffixData:
		var a := AffixData.new()
		a.id = d.get("id", "")
		a.name = d.get("name", "")
		a.rarity = d.get("rarity", "common")
		a.stacking = d.get("stacking", "add")
		a.effect = d.get("effect", {})
		a.note = d.get("note", "")
		return a


# ── 羁绊 ──
class BondData:
	var id: String
	var name: String
	var set: String
	var effect: Dictionary

	static func from_dict(d: Dictionary) -> BondData:
		var b := BondData.new()
		b.id = d.get("id", "")
		b.name = d.get("name", "")
		b.set = d.get("set", "")
		b.effect = d.get("effect", {})
		return b


# ── 修炼境界 ──
class RealmData:
	var name: String
	var bonds: PackedStringArray
	var reward: Dictionary
	var synergy_unlock: String

	static func from_dict(d: Dictionary) -> RealmData:
		var r := RealmData.new()
		r.name = d.get("name", "")
		r.bonds = PackedStringArray(d.get("bonds", []))
		r.reward = d.get("reward", {})
		r.synergy_unlock = d.get("synergy_unlock", "")
		return r


# ── 修炼路径（境界树）──
class PathData:
	var id: String
	var name: String
	var realms: Array = []   # Array[RealmData]（内部类类型数组在 Godot 不稳定，用 untyped）

	static func from_dict(d: Dictionary) -> PathData:
		var p := PathData.new()
		p.id = d.get("id", "")
		p.name = d.get("name", "")
		for r in d.get("realms", []):
			p.realms.append(RealmData.from_dict(r))
		return p


# ── 联动 ──
class SynergyData:
	var id: String
	var name: String
	var trigger: Dictionary     # { all: [...] }
	var effect: Dictionary
	var note: String

	static func from_dict(d: Dictionary) -> SynergyData:
		var s := SynergyData.new()
		s.id = d.get("id", "")
		s.name = d.get("name", "")
		s.trigger = d.get("trigger", {})
		s.effect = d.get("effect", {})
		s.note = d.get("note", "")
		return s
