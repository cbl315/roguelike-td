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
# 境界吞噬完成（不直接引用 EventBus autoload——headless -s 测试模式不加载 autoload，
# 由 game_manager 桥接到 EventBus.bond_devoured）
signal realm_devoured(path_id: String, realm_idx: int, realm_name: String)
# 突破怪机制：集齐境界卡 → pending（卡池锁定）→ 打赢突破怪 → apply_breakthrough 才升境
signal breakthrough_ready(path_id: String, realm_idx: int)
signal equip_guard_required(milestone_level: int)   # 装备里程碑守卫：打赢才可升级拿词条
signal third_pet_required()   # 千年境（realm7）：第三魂宠三选一（小蛰龙/善恶花王/缚风灵）
var third_pet_id: String = ""   # 选中的第三魂宠（dragon/flower/wind；空=未选）
var equip_guard_milestone: int = 0   # 待挑战的里程碑级（5/10/15/20；0=无）
var equip_guard_cleared: int = 0     # 已通过的里程碑级（本级守卫已死）

var gold: float = 0.0
var accumulated_effects: Array = []    # Array[Dictionary] 累积的 effect（境界 reward + 装备词条）
var bond_pool: Array = []              # Array[String] 当前羁绊 id（上限 10）
var bond_pool_capacity: int = 10
var devoured_bonds: Array = []         # Array[String] 已吞噬的羁绊 id（仍算 owned，联动不丢失）
var bonds_drawn: int = 0               # 本局已抽羁绊次数（用于递增成本）
var path_realm: Dictionary = {}        # {path_id: 已完成境界数}
var rng: RandomNumberGenerator
var pools: RoguePools = null
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
	# 数值轮定稿：所有收入 ×1.03（敌人行为多样化后的玩家侧补偿，与模拟 PLAYER_ECON_MULT 一致）
	gold += amount * 1.03
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
		# 羁绊突破：自动升境（爽感优先——2026-11-03 改版：守关者考核移到装备里程碑）
		_apply_devour(pid, idx, needed)


## 吞噬升境（自动）：移卡/reward/演出/召唤事件
func _apply_devour(pid: String, idx: int, needed: Array) -> void:
	for b in needed:
		bond_pool.erase(b)
		if not devoured_bonds.has(b):
			devoured_bonds.append(b)
	path_realm[pid] = idx + 1
	var reward: Dictionary = pools.realm_reward(pid, idx)
	if not reward.is_empty():
		accumulated_effects.append(reward)
	realm_devoured.emit(pid, idx + 1, pools.realm_name(pid, idx))
	if pid == "chongmei":
		if idx + 1 == 1:
			summon_unit_requested.emit("baiyanmeng", "白魇魔")
		elif idx + 1 == 6:
			summon_unit_devoured.emit("baiyanmeng")
		elif idx + 1 == 7:
			third_pet_required.emit()   # 千年境：白魇魔已吞噬，第三魂宠登场三选一


## 第三魂宠三选一（千年境）：选中即得实体 + 专属卡直接入池（另两张永不出现）
const THIRD_PETS := {
	"dragon": {"name": "小蛰龙", "card": "cm_third_dragon", "buff": {"pet_atk_pct_delta": 0.18, "physical_dmg_pct_delta": 0.08}},
	"flower": {"name": "善恶花王", "card": "cm_third_flower", "buff": {"pet_atk_pct_delta": 0.14, "hp_pct_delta": 0.08}},
	"wind":   {"name": "缚风灵", "card": "cm_third_wind", "buff": {"pet_atk_pct_delta": 0.16, "attack_speed_delta": 0.08}},
}


func choose_third_pet(pet_key: String) -> void:
	if not THIRD_PETS.has(pet_key) or not third_pet_id.is_empty():
		return
	third_pet_id = pet_key
	var def: Dictionary = THIRD_PETS[pet_key]
	# 专属卡直接入 devoured（视为已拥有的强化，不占池/不占吞噬）
	if not devoured_bonds.has(def["card"]):
		devoured_bonds.append(def["card"])
	summon_unit_requested.emit("third_" + pet_key, def["name"])
	changed.emit()


## 宠魅三区：宠物基础攻击系数（与 Python 端 SUMMON_BASE_ATK_RATIO 一致）
const SUMMON_BASE_ATK_RATIO := 0.65   # 与 Python 严格一致（宠魅中期塌方轮 0.55→0.65）


## 卡的 pet_scope（宠魅三区；非宠魅卡恒为 body）
func _bond_scope(bid: String) -> String:
	if pools == null:
		return "body"
	var b: Dictionary = pools._find_bond(bid)
	return str(b.get("pet_scope", "body"))


## 白魇魔是否已被吞噬（魂朽境 realm 6 → 半魔，加成并入本体）
func baiyanmeng_devoured() -> bool:
	return int(path_realm.get("chongmei", 0)) >= 6


## 组装当前 CombatStats（完整管线 + 联动重算）——本体区。
## 宠魅三区卡不进本体：莫邪恒为独立实体；白魇魔在 realm 2-5 独立，
## 魂朽境（realm 6）吞噬后并入本体（半魔）。
func assemble_stats() -> CombatStats:
	var stats := CombatStats.new()
	# 累加所有 effect（技能词条 + 境界 reward + 装备词条）
	EffectResolver.accumulate_all(stats, accumulated_effects)
	# 羁绊 effect 从 bond_pool + devoured_bonds 实时查（吞噬后属性保留）
	if pools != null:
		var bym_merged := baiyanmeng_devoured()
		for bid in bond_pool:
			var scope := _bond_scope(bid)
			if scope == "moxie":
				continue   # 莫邪：独立实体
			if scope == "baiyanmeng" and not bym_merged:
				continue   # 白魇魔：realm 1-5 独立；吞噬后并入本体
			var b: Dictionary = pools._find_bond(bid)
			if not b.is_empty():
				var eff: Dictionary = b.get("effect", {})
				if not eff.is_empty():
					EffectResolver.accumulate_all(stats, [eff])
		for bid in devoured_bonds:
			var scope := _bond_scope(bid)
			if scope == "moxie":
				continue
			if scope == "baiyanmeng" and not bym_merged:
				continue
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


## 组装宠物区 CombatStats（宠魅三区独立数值）。
## pet: "moxie"（莫邪，常驻）| "baiyanmeng"（白魇魔，realm 2-5；吞噬后返回 null stats → 实体已被移除）
## 基础 = 裸 CombatStats × SUMMON_BASE_ATK_RATIO + 该 pet_scope 池（bond_pool + devoured_bonds）的 effect。
## 不吃境界 reward / 装备词条 / 联动（那些是本体的）。
func assemble_pet_stats(pet: String) -> CombatStats:
	var stats := CombatStats.new()
	# 第三魂宠：基础攻速/伤害倾向按类型分化（物理高攻/法术高速/控制中庸）
	if pet.begins_with("third_"):
		match pet:
			"third_dragon":
				stats.atk_pct_bonus += 0.35   # 物理高攻（AOE 折算）
			"third_flower":
				stats.atk_pct_bonus += 0.15
				stats.hp_pct_bonus += 0.30   # 控制系肉度（贴身减速）
			"third_wind":
				stats.atk_pct_bonus += 0.20
				stats.attack_speed += 0.50   # 法术速攻
	if pools != null:
		for bid in bond_pool:
			if _bond_scope(bid) == pet:
				var b: Dictionary = pools._find_bond(bid)
				var eff: Dictionary = b.get("effect", {})
				if not eff.is_empty():
					EffectResolver.accumulate_all(stats, [eff])
		for bid in devoured_bonds:
			if _bond_scope(bid) == pet:
				var b: Dictionary = pools._find_bond(bid)
				var eff: Dictionary = b.get("effect", {})
				if not eff.is_empty():
					EffectResolver.accumulate_all(stats, [eff])
	# apply_atk_bonus 会重置为 BASE_ATK×(1+Σ)——先加成、再乘宠物基础比例
	stats.apply_atk_bonus()
	stats.atk = stats.atk * SUMMON_BASE_ATK_RATIO
	# 召唤系符文加成：宠物攻击 ×(1 + pet_atk_pct)（本体 assemble_stats 聚合后传入）
	var body: CombatStats = assemble_stats()
	if body.pet_atk_pct > 0.0:
		stats.atk *= (1.0 + body.pet_atk_pct)
	return stats


# ── 装备系统（M3）──

## 装备升级：花金币 → 升级 → 固定经济加成 → 里程碑抽词条
func equip_upgrade() -> Dictionary:
	if pools == null or equip_level >= pools.equip_max_level():
		return {}
	# 里程碑守卫：下一级是里程碑(+5/10/15/20)且该级守卫未通过 → 拦截，
	# 通知 game_manager 生成突破守关者（不扣费；打赢后 clear_equip_guard 升级）
	var next_level: int = equip_level + 1
	if pools.is_milestone_level(next_level) and equip_guard_cleared < next_level:
		if equip_guard_milestone != next_level:
			equip_guard_milestone = next_level
			equip_guard_required.emit(next_level)
		return {"blocked": true, "milestone": next_level}
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
## 装备里程碑守卫被击杀 → 解锁该里程碑（下一次 equip_upgrade 正常通过并出词条）
func clear_equip_guard(milestone: int) -> void:
	equip_guard_cleared = maxi(equip_guard_cleared, milestone)
	equip_guard_milestone = 0
	changed.emit()


func take_milestone_affix(affix: Dictionary) -> void:
	equip_affixes.append(affix)
	var aff: Dictionary = affix.get("effect", {})
	if not aff.is_empty():
		# 一次性词条（GDD §5）：立即结算，不进持续属性池
		if aff.has("gold_lump"):
			add_gold(float(aff["gold_lump"]))
		else:
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
