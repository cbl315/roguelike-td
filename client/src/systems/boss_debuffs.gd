## boss_debuffs.gd — Boss Debuff 系统（GDD §12，Balatro 式规则破坏）。
## 每局从池中抽 3 个 debuff 绑定到 Boss 波（10/20/30），Boss 波内生效、波结束自动恢复。
## 三原则：可见性（波前横幅预告）/ 应变性（削弱一方面逼多元构筑）/ 痛但不致命（减免非失效）。
##
## 效果挂接（13 个已实现，4 个待对应系统落地后启用）：
##   CombatStats×4   暴伤/暴率/穿甲/弹数 → modify_stats()（波内每次 assemble 后叠加）
##   乘区×1          羁绊压制 → modify_stats() 塞 final_dmg_mults
##   经济×1          贪婪之噬 → modify_gold()
##   敌人×3          急行/不灭/回春 → modify_enemy()
##   惩罚×3          镜面反弹/反噬之力/禁疗之印 → reflect_dmg()/extra_core_loss()/healing_mult()
##   抽取×1          封印之手 → reroll_cap_delta()
extends RefCounted
class_name BossDebuffs

const DATA_PATH := "res://data/boss_debuffs.json"

## 依赖系统未落地、暂不进入抽取池的效果 key（后续启用）：
##   immune_cc（无控制技能）ult_energy_mult（无大招）
##   magic/physical_dmg_taken_mult（无伤害类型系统）
const _UNSUPPORTED_KEYS := ["immune_cc", "ult_energy_mult", "magic_dmg_taken_mult", "physical_dmg_taken_mult"]

var _pool: Array = []            # 可抽取的 boss debuff 定义（过滤后）
var _picked: Array = []          # 本局抽中的 3 个（顺序=波次顺序）
var _boss_waves: Array = [10, 20, 30]
var _active_idx: int = -1        # 当前生效的 _picked 下标（-1 = 非 Boss 波）


func setup(rng: RandomNumberGenerator) -> void:
	_load_pool()
	_pick_three(rng)


func _load_pool() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("boss_debuffs: 无法读取 %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_boss_waves = parsed.get("main_quest", {}).get("boss_waves", [10, 20, 30])
		for b in parsed.get("bosses", []):
			var keys: Dictionary = b.get("debuff", {})
			# 过滤依赖缺失系统的（含任一 unsupported key 则整条不进池）
			var supported := true
			for k in keys:
				if k in _UNSUPPORTED_KEYS:
					supported = false
					break
			if supported:
				_pool.append(b)


## 每局抽 3 个（顺序随机 = 出场顺序随机，天然由抽序决定）
func _pick_three(rng: RandomNumberGenerator) -> void:
	_picked.clear()
	var shuffled := _pool.duplicate()
	shuffled.shuffle()
	var count: int = mini(3, shuffled.size())
	for i in count:
		_picked.append(shuffled[i])


# ── 波次生命周期（game_manager 调用）──

## 波次开始：若是 Boss 波则激活对应 debuff，返回 debuff（非 Boss 波返回 null）
func on_wave_started(wave: int) -> Dictionary:
	_active_idx = -1
	for i in _picked.size():
		if int(_boss_waves[i]) == wave:
			_active_idx = i
			return _picked[i]
	return {}

## 波次结束：清除激活（属性类效果随下次 assemble_stats 自然恢复）
func on_wave_finished() -> void:
	_active_idx = -1


func active() -> Dictionary:
	if _active_idx >= 0 and _active_idx < _picked.size():
		return _picked[_active_idx]
	return {}

func is_active() -> bool:
	return not active().is_empty()


## 下一个 Boss 波的预告信息（当前 wave 之后）。无则返回 {}
func next_boss(wave: int) -> Dictionary:
	for i in _picked.size():
		var bw: int = int(_boss_waves[i])
		if bw > wave:
			return {"wave": bw, "name": _picked[i].get("name", ""), "id": _picked[i].get("id", "")}
	return {}


# ── 效果应用（Boss 波内 game_manager/spawner 调用，非 Boss 波全部空操作）──

func _d(key: String, default: Variant = null) -> Variant:
	var deb: Dictionary = active()
	if deb.is_empty():
		return default
	return deb.get("debuff", {}).get(key, default)


## 属性类：叠加到 CombatStats（暴伤/暴率/穿甲/弹数/羁绊压制乘区）
func modify_stats(stats: CombatStats) -> void:
	if not is_active():
		return
	var cd: float = _d("crit_dmg_mult_delta", 0.0)
	if cd != 0.0:
		stats.crit_dmg = maxf(1.0, stats.crit_dmg + cd)
	var cr: float = _d("crit_rate_delta", 0.0)
	if cr != 0.0:
		stats.crit_rate = maxf(0.0, stats.crit_rate + cr)
	var ap: float = _d("armor_pen_mult_delta", 0.0)
	if ap != 0.0:
		stats.armor_pen = maxf(0.0, stats.armor_pen + ap)
	var pj: int = _d("projectile_delta", 0)
	if pj != 0:
		stats.projectile_count = maxi(1, stats.projectile_count + pj)
	var be: float = _d("bond_effect_mult_delta", 0.0)
	if be != 0.0:
		stats.final_dmg_mults.append(1.0 + be)   # -0.3 → ×0.7 乘区


## 经济类：贪婪之噬（Boss 波内击杀金币）
func modify_gold(reward: float) -> float:
	var g: float = _d("gold_gain_mult_delta", 0.0)
	if g == 0.0:
		return reward
	return reward * (1.0 + g)


## 敌人类：急行之令（全怪移速）/ 不灭之躯（Boss 血量）/ 回春之核（Boss 回血）
func modify_enemy(enemy: Enemy, is_boss: bool) -> void:
	if not is_active():
		return
	var sp: float = _d("enemy_speed_mult", 0.0)
	if sp > 0.0:
		enemy.move_speed *= sp
	if is_boss:
		var hm: float = _d("boss_hp_mult", 0.0)
		if hm > 0.0:
			enemy.max_hp *= hm
			enemy.current_hp = enemy.max_hp
		var rg: float = _d("boss_regen_pct_per_5s", 0.0)
		if rg > 0.0:
			enemy.regen_pct_per_5s = rg


## 镜面之甲：命中敌人时反弹伤害（返回对英雄的伤害值，0 = 无）
func reflect_dmg(hit_dmg: float) -> float:
	var r: float = _d("reflect_pct", 0.0)
	if r <= 0.0:
		return 0.0
	return hit_dmg * r


## 反噬之力：英雄被怪碰时额外掉核心血（返回额外伤害）
func extra_core_loss(max_hp: float) -> float:
	var p: float = _d("core_hp_loss_per_hit", 0.0)
	if p <= 0.0:
		return 0.0
	return max_hp * p


## 禁疗之印：回血效果倍率
func healing_mult() -> float:
	return _d("healing_mult", 1.0)


## 封印之手：Boss 波后的大厅刷新次数增减
func reroll_cap_delta() -> int:
	return _d("draw_reroll_delta", 0)
