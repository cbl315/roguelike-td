## combat_stats.gd — Master Damage Pipeline（移植自 balance/td_balance/combat/damage.py）
## 完整管线：ATK×ratio×物法伤×技能倍率×final×元素×暴击×护甲，含真伤拆分/多重射递减。
## 与 Python SSOT 一致（balance 已验证）。
extends RefCounted
class_name CombatStats

# 英雄基础属性（SSOT，对应 GDD §3.1）
const BASE_ATK := 50.0
const BASE_CRIT_RATE := 0.05
const BASE_CRIT_DMG := 1.5
const BASE_ATTACK_SPEED := 1.0
const ARMOR_K := 100.0
const CRIT_RATE_CAP := 1.0
const MULTISHOT_PER_PROJ_DMG_MULT := 0.85

# 进攻属性
var atk: float = BASE_ATK
var atk_ratio: float = 1.0
var atk_pct_bonus: float = 0.0          # Σ atk% 加成（resolve 时乘 base）
var physical_dmg_pct: float = 0.0
var magic_dmg_pct: float = 0.0
var skill_mult_pct: float = 0.0
var elemental_pct: float = 0.0
var final_dmg_mults: Array = []          # Array[float]，每条 Π(1+x)
var crit_rate: float = BASE_CRIT_RATE
var crit_dmg: float = BASE_CRIT_DMG
var attack_speed: float = BASE_ATTACK_SPEED
var projectile_count: int = 1
var armor_pen: float = 0.0
var true_dmg_pct: float = 0.0


func apply_atk_bonus() -> void:
	"""把累积的 atk_pct_bonus 应用到 atk（base × (1+Σ%)）。"""
	atk = BASE_ATK * (1.0 + atk_pct_bonus)


func duplicate() -> CombatStats:
	var c := CombatStats.new()
	c.atk = atk; c.atk_ratio = atk_ratio; c.atk_pct_bonus = atk_pct_bonus
	c.physical_dmg_pct = physical_dmg_pct; c.magic_dmg_pct = magic_dmg_pct
	c.skill_mult_pct = skill_mult_pct; c.elemental_pct = elemental_pct
	c.final_dmg_mults = final_dmg_mults.duplicate()
	c.crit_rate = crit_rate; c.crit_dmg = crit_dmg
	c.attack_speed = attack_speed; c.projectile_count = projectile_count
	c.armor_pen = armor_pen; c.true_dmg_pct = true_dmg_pct
	return c


# ── 公式分解（每步独立，便于走查）──

static func mitigation(armor: float) -> float:
	if armor <= 0.0:
		return 0.0
	return armor / (armor + ARMOR_K)


static func defense_mult(armor: float, armor_pen: float) -> float:
	var pen: float = clampf(armor_pen, 0.0, 1.0)
	return maxf(0.0, 1.0 - mitigation(armor) * (1.0 - pen))


static func crit_factor(crit_rate_: float, crit_dmg_: float) -> float:
	var rate: float = clampf(crit_rate_, 0.0, CRIT_RATE_CAP)
	return 1.0 + rate * (crit_dmg_ - 1.0)


static func final_mult(mults: Array) -> float:
	var result := 1.0
	for x in mults:
		result *= (1.0 + float(x))
	return result


func expected_hit_dmg(enemy_armor: float) -> float:
	"""单发期望伤害（含暴击期望、护甲、真伤拆分）。"""
	var cf: float = crit_factor(crit_rate, crit_dmg)
	var dm: float = defense_mult(enemy_armor, armor_pen)
	var fm: float = final_mult(final_dmg_mults)
	var dmg_type := 1.0 + physical_dmg_pct + magic_dmg_pct
	var skill := 1.0 + skill_mult_pct
	var elem := 1.0 + elemental_pct
	var base := atk * atk_ratio
	var pre_def := base * dmg_type * skill * fm * elem * cf
	var after_def := pre_def * dm
	if true_dmg_pct > 0.0:
		var tp: float = clampf(true_dmg_pct, 0.0, 1.0)
		# 真伤部分跳过护甲
		return after_def * (1.0 - tp) + pre_def * tp
	return after_def


func expected_dps(enemy_armor: float) -> float:
	"""期望 DPS = 单发×攻速×弹数（含散射递减）。"""
	var n := maxi(1, projectile_count)
	var proj_mult := 1.0 + (n - 1) * MULTISHOT_PER_PROJ_DMG_MULT
	return expected_hit_dmg(enemy_armor) * attack_speed * proj_mult
