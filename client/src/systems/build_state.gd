## build_state.gd — 玩家 build 状态（M2 核心）
## 跟踪：金币、累积的 effect、羁绊池、修炼境界进度。
## （技能抽取/九秘解锁字段已移除：技能改为每体系 1 个起点技能；九秘改为羁绊。）
## hero 每波从这里 assemble CombatStats（完整管线）。
extends RefCounted
class_name BuildState

signal changed

# 召唤单位（宠魅体系）：build_state 不直接创建节点，通过信号通知 game_manager
signal summon_unit_requested(unit_id: String, unit_name: String)
signal summon_unit_devoured(unit_id: String)   # 白魇魔被吞噬

var gold: float = 0.0
var accumulated_effects: Array = []    # Array[Dictionary] 累积的 effect（境界 reward + 装备词条）
var bond_pool: Array = []              # Array[String] 当前羁绊 id（上限 10）
var bond_pool_capacity: int = 10
var devoured_bonds: Array = []         # Array[String] 已吞噬的羁绊 id（仍算 owned，联动不丢失）
var bonds_drawn: int = 0               # 本局已抽羁绊次数（用于递增成本）
var path_realm: Dictionary = {}        # {path_id: 已完成境界数}
var rng: RandomNumberGenerator
var pools: Variant = null              # RoguePools 实例
var synergy_engine: SynergyEngine = null  # 联动引擎
var active_synergies: Array = []       # 当前已触发的联动（缓存，供 UI 显示）
var equip_level: int = 0               # 装备等级 0-9
var equip_affixes: Array = []          # 里程碑抽到的词条 [{id, name, polarity, effect}]

# 抽羁绊成本：30 + 10×已抽次数，上限 60（GDD §4.4 / DESIGN L145,L158）
const BOND_DRAW_BASE := 30.0
const BOND_DRAW_INC := 10.0
const BOND_DRAW_CAP := 60.0


## 下一次抽羁绊的成本（30→40→50→60→60...）
func bond_draw_cost() -> float:
	return minf(BOND_DRAW_CAP, BOND_DRAW_BASE + BOND_DRAW_INC * bonds_drawn)


## 退回上一次抽羁绊的扣款（取消选择时用）：退款 + 回退 bonds_drawn。
func refund_bond_draw() -> void:
	if bonds_drawn > 0:
		bonds_drawn -= 1
		# 退回当时实际扣的金额 = 回退后的 bond_draw_cost()
		add_gold(minf(BOND_DRAW_CAP, BOND_DRAW_BASE + BOND_DRAW_INC * bonds_drawn))


func setup(p_pools: Variant, p_rng: RandomNumberGenerator) -> void:
	pools = p_pools
	rng = p_rng
	synergy_engine = SynergyEngine.new()
	# generic_fusion 默认解锁（所有玩家可吞噬 generic 羁绊）
	path_realm["generic_fusion"] = 0


## 选体系（开局/种子）：获得起点技能的 effect + 初始化 path_realm。
func choose_path(path_id: String) -> void:
	path_realm[path_id] = 0
	choose_path_effect(path_id)
	changed.emit()


## 给起点技能加 effect（种子和 choose_path 共用）
func choose_path_effect(path_id: String) -> void:
	match path_id:
		"zhutian":
			accumulated_effects.append({"atk_ratio_delta": 0.5})
		"xingchenbian":
			accumulated_effects.append({"atk_ratio_delta": 0.5})
		"chongmei":
			accumulated_effects.append({"atk_ratio_delta": 0.3})
			summon_unit_requested.emit("moxie", "莫邪")


func add_gold(amount: float) -> void:
	gold += amount
	changed.emit()


func spend(amount: float) -> bool:
	if gold < amount:
		return false
	gold -= amount
	changed.emit()
	return true


## 选了一个羁绊 offer。池满时返回 false（调用方应进替换流程）。
## 羁绊 effect 不存 accumulated_effects——assemble_stats 时从 bond_pool 实时查，
## 这样丢弃/替换羁绊自动更新属性（无需反向撤销）。
func take_bond_offer(offer: Dictionary) -> bool:
	var bid: String = offer.get("id")
	# 种子卡：不进 bond_pool，直接解锁体系 + 给金币（不加属性）
	if offer.get("is_seed", false):
		var seed_path: String = offer.get("seed_path", "")
		var seed_gold: float = float(offer.get("seed_gold", 0))
		path_realm[seed_path] = 0   # 解锁体系
		add_gold(seed_gold)          # 给金币奖励
		# 宠魅种子：生成莫邪召唤单位
		if seed_path == "chongmei":
			summon_unit_requested.emit("moxie", "莫邪")
		changed.emit()
		return true
	if bond_pool.size() >= bond_pool_capacity:
		return false   # 池满——调用方应弹替换 UI
	bond_pool.append(bid)
	# bonds_drawn 在 open_bond 时已递增（扣款时机 = 打开面板）
	# 检查境界吞噬
	_try_devour()
	changed.emit()
	return true


## 替换羁绊：丢掉 discard_id，加入 offer（池满时用）。
func replace_bond(discard_id: String, offer: Dictionary) -> void:
	bond_pool.erase(discard_id)
	var bid: String = offer.get("id")
	bond_pool.append(bid)
	# bonds_drawn 在 open_bond 时已递增
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
		# 吞噬：从池中移除，但记录到 devoured_bonds（联动仍算 owned）
		for b in needed:
			bond_pool.erase(b)
			if not devoured_bonds.has(b):
				devoured_bonds.append(b)
		# 升境 + 累加 reward
		path_realm[pid] = idx + 1
		var reward: Dictionary = pools.realm_reward(pid, idx)
		if not reward.is_empty():
			accumulated_effects.append(reward)
		EventBus.bond_devoured.emit(pid, idx + 1, pools.realm_name(pid, idx))
		# 宠魅体系境界 → 召唤单位生命周期
		if pid == "chongmei":
			# 魂师境（realm==2）：白魇魔降生（设计文档：魂师境界自动获得）
			if idx + 1 == 2:
				summon_unit_requested.emit("baiyanmeng", "白魇魔")
			# 魂朽境（realm==6）：白魇魔被吞噬
			elif idx + 1 == 6:
				summon_unit_devoured.emit("baiyanmeng")


## 组装当前 CombatStats（完整管线 + 联动重算）。
func assemble_stats() -> CombatStats:
	var stats := CombatStats.new()
	# 累加所有 effect（技能词条 + 境界 reward + 装备词条）
	EffectResolver.accumulate_all(stats, accumulated_effects)
	# 羁绊 effect 从 bond_pool + devoured_bonds 实时查（吞噬后属性保留）
	if pools != null:
		for bid in bond_pool:
			var b: Dictionary = pools._find_bond(bid)
			if not b.is_empty():
				var eff: Dictionary = b.get("effect", {})
				if not eff.is_empty():
					EffectResolver.accumulate_all(stats, [eff])
		for bid in devoured_bonds:
			var b: Dictionary = pools._find_bond(bid)
			if not b.is_empty():
				var eff: Dictionary = b.get("effect", {})
				if not eff.is_empty():
					EffectResolver.accumulate_all(stats, [eff])
	# 联动重算：检查当前状态触发了哪些联动，追加其 effect
	if synergy_engine != null and pools != null:
		var active: Array = synergy_engine.active(self, pools)
		active_synergies = active
		for syn in active:
			var eff: Dictionary = syn.get("effect", {})
			if not eff.is_empty():
				EffectResolver.accumulate_all(stats, [eff])
	# 应用 ATK 百分比加成
	stats.apply_atk_bonus()
	return stats


# ── 装备系统（M3）──

## 装备升级：花金币 → 升级 → 固定经济加成 → 里程碑抽词条
func equip_upgrade() -> Dictionary:
	if pools == null or equip_level >= pools.equip_max_level():
		return {}
	# 算成本（含 equip_upgrade_cost_delta 折扣）
	var cost: float = pools.equip_upgrade_cost(equip_level)
	cost += _sum_effect("equip_upgrade_cost_delta")
	cost = maxf(1.0, cost)
	if not spend(cost):
		return {}
	equip_level += 1
	# 累加该级固定经济奖励
	var reward: Dictionary = pools.equip_level_reward(equip_level)
	# per_level_income 里的 level/milestone/milestone_guaranteed_positive 字段不是 effect，过滤掉
	var clean_reward: Dictionary = {}
	for k in reward:
		if k != "level" and k != "milestone" and k != "milestone_guaranteed_positive":
			clean_reward[k] = reward[k]
	if not clean_reward.is_empty():
		accumulated_effects.append(clean_reward)
	# 里程碑（+5/+10/+15/+20）抽词条——返回 3 选 1 候选，不直接抽
	var milestone_options: Array = []
	if pools.is_milestone_level(equip_level):
		var gp: bool = pools.is_guaranteed_positive(equip_level)
		milestone_options = pools.draw_milestone_affix_options(gp, 3)
	changed.emit()
	return {"level": equip_level, "cost": cost, "reward": clean_reward, "milestone_options": milestone_options}


## 玩家从里程碑 3 选 1 里选了一张词条
func take_milestone_affix(affix: Dictionary) -> void:
	equip_affixes.append(affix)
	var aff: Dictionary = affix.get("effect", {})
	if not aff.is_empty():
		accumulated_effects.append(aff)
	changed.emit()


# ── 经济属性 getter（从 accumulated_effects 汇总）──

func gold_per_sec() -> float:
	return _sum_effect("gold_per_sec_delta")

func per_kill_bonus() -> float:
	return _sum_effect("per_kill_gold_delta")

func gold_multiplier() -> float:
	var mult := 1.0
	for eff in accumulated_effects:
		var v: Variant = eff.get("gold_mult", null)
		if v != null:
			mult *= (1.0 + float(v))
	return mult

func double_gold_chance() -> float:
	return clampf(_sum_effect("double_gold_chance"), 0.0, 1.0)


## 从 accumulated_effects 汇总某 key 的总和
func _sum_effect(key: String) -> float:
	var total := 0.0
	for eff in accumulated_effects:
		var v: Variant = eff.get(key, null)
		if v != null:
			total += float(v)
	return total


## 概要字符串（HUD 用）。
func summary() -> String:
	return "羁绊%d 境界%d 金%d" % [bond_pool.size(), path_realm.size(), int(gold)]
