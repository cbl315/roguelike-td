## combat_math.gd — 简化伤害计算（M1）
## 移植自 balance/td_balance/combat/damage.py，但 M1 只用基础 ATK×ratio×护甲。
## 预留乘区接口（physical_dmg_pct / final_mults / crit），M2 随 build 接入。
extends RefCounted
class_name CombatMath

const ARMOR_K := 100.0


## 护甲减伤比例 = armor/(armor+K)
static func mitigation(armor: float) -> float:
	if armor <= 0.0:
		return 0.0
	return armor / (armor + ARMOR_K)


## 实际减伤乘子 = 1 - mitigation×(1-穿甲)
static func defense_mult(armor: float, armor_pen: float = 0.0) -> float:
	var pen := clampf(armor_pen, 0.0, 1.0)
	return maxf(0.0, 1.0 - mitigation(armor) * (1.0 - pen))


## M1 单次命中伤害（简化）：
## dmg = atk × atk_ratio × (1 + physical_dmg_pct) × Π(1+final) × 护甲
## M1 物伤/final 默认 0；M2 由 build 填充。
static func hit_damage(
		atk: float,
		atk_ratio: float,
		enemy_armor: float,
		physical_dmg_pct: float = 0.0,
		final_mults: Array = [],   # Array[float]，每条 +x
		armor_pen: float = 0.0
	) -> float:
	var final_mult := 1.0
	for x in final_mults:
		final_mult *= (1.0 + float(x))
	var raw := atk * atk_ratio * (1.0 + physical_dmg_pct) * final_mult
	return raw * defense_mult(enemy_armor, armor_pen)


## 期望 DPS = 单发 × 攻速 × 弹数（含散射递减）
## M1 弹数=1；M2 多重射接入。
static func expected_dps(
		atk: float, atk_ratio: float, attack_speed: float,
		enemy_armor: float, projectile_count: int = 1,
		physical_dmg_pct: float = 0.0, final_mults: Array = [],
		armor_pen: float = 0.0
	) -> float:
	var n := maxi(1, projectile_count)
	var proj_mult := 1.0 + (n - 1) * 0.85   # 散射递减
	return hit_damage(atk, atk_ratio, enemy_armor, physical_dmg_pct, final_mults, armor_pen) \
		* attack_speed * proj_mult
