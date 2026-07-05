## build_state.gd — 玩家 build 状态（M2 核心）
## 跟踪：金币、拥有的技能、累积的 effect、羁绊池、修炼境界进度。
## hero 每波从这里 assemble CombatStats（完整管线）。
extends RefCounted
class_name BuildState

signal changed

var gold: float = 0.0
var owned_skills: Array = []           # Array[String] 技能 id
var accumulated_effects: Array = []    # Array[Dictionary] 累积的 effect（技能词条+羁绊）
var bond_pool: Array = []              # Array[String] 当前羁绊 id（上限 10）
var bond_pool_capacity: int = 10
var bonds_drawn: int = 0               # 本局已抽羁绊次数（用于递增成本）
var path_realm: Dictionary = {}        # {path_id: 已完成境界数}
var rng: RandomNumberGenerator
var pools: Variant = null              # RoguePools 实例

# 抽羁绊成本：30 + 10×已抽次数，上限 60（GDD §4.4 / DESIGN L145,L158）
const BOND_DRAW_BASE := 30.0
const BOND_DRAW_INC := 10.0
const BOND_DRAW_CAP := 60.0


## 下一次抽羁绊的成本（30→40→50→60→60...）
func bond_draw_cost() -> float:
	return minf(BOND_DRAW_CAP, BOND_DRAW_BASE + BOND_DRAW_INC * bonds_drawn)


func setup(p_pools: Variant, p_rng: RandomNumberGenerator) -> void:
	pools = p_pools
	rng = p_rng


func add_gold(amount: float) -> void:
	gold += amount
	changed.emit()


func spend(amount: float) -> bool:
	if gold < amount:
		return false
	gold -= amount
	changed.emit()
	return true


## 选了一个技能 offer（新技能 or 词条）。
func take_skill_offer(offer: Dictionary) -> void:
	if offer.get("kind") == "new_skill":
		if not owned_skills.has(offer.get("id")):
			owned_skills.append(offer.get("id"))
			# 新技能：应用其 atk_ratio（作为 atk_ratio_delta effect）
			var eff: Dictionary = offer.get("effect", {})
			if not eff.is_empty():
				accumulated_effects.append(eff)
			changed.emit()
	else:
		# 词条：累积真实 effect（来自 affixes.json）
		var aeff: Dictionary = offer.get("effect", {})
		if not aeff.is_empty():
			accumulated_effects.append(aeff)
		changed.emit()


## 选了一个羁绊 offer。
func take_bond_offer(offer: Dictionary) -> void:
	if bond_pool.size() >= bond_pool_capacity:
		return   # 池满
	var bid: String = offer.get("id")
	bond_pool.append(bid)
	bonds_drawn += 1   # 递增抽羁绊成本
	# 累积羁绊 effect
	var eff: Dictionary = offer.get("effect", {})
	if not eff.is_empty():
		accumulated_effects.append(eff)
	# 检查境界吞噬
	_try_devour()
	changed.emit()


## 尝试境界吞噬（凑齐当前境界 → 升境，reward 累加）。
func _try_devour() -> void:
	if pools == null:
		return
	while true:
		var dev: Variant = pools.find_devourable(bond_pool, path_realm)
		if dev == null or not dev is Dictionary or dev.is_empty():
			break
		var dev_d: Dictionary = dev
		var pid: String = dev_d.get("path_id")
		var idx: int = int(dev_d.get("realm_idx"))
		var needed: Array = dev_d.get("needed", [])
		# 从池中移除 needed 羁绊
		for b in needed:
			bond_pool.erase(b)
		# 升境 + 累加 reward
		path_realm[pid] = idx + 1
		var reward: Dictionary = pools.realm_reward(pid, idx)
		if not reward.is_empty():
			accumulated_effects.append(reward)
		EventBus.bond_devoured.emit(pid, idx + 1)


## 组装当前 CombatStats（完整管线）。
func assemble_stats() -> CombatStats:
	var stats := CombatStats.new()
	# 累加所有 effect（技能词条 + 羁绊 effect + 境界 reward）
	EffectResolver.accumulate_all(stats, accumulated_effects)
	# 应用 ATK 百分比加成
	stats.apply_atk_bonus()
	return stats


## 概要字符串（HUD 用）。
func summary() -> String:
	return "技能%d 羁绊%d 境界%d 金%d" % [owned_skills.size(), bond_pool.size(), path_realm.size(), int(gold)]
