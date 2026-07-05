## effect_resolver.gd — 把 effect dict 累加进 CombatStats（移植自 balance/combat_stats.py 的 _apply）
## 覆盖全部已知 key：进攻/暴击/速度/防御/经济/特殊。
extends RefCounted
class_name EffectResolver

const CombatStats := preload("res://src/core/combat_stats.gd")


## 把一个 effect dict 累加进 stats（原地修改）。
static func accumulate(stats, effect: Dictionary) -> void:
	for key in effect.keys():
		_apply(stats, key, effect[key])


static func _apply(stats, key: String, val) -> void:
	var v: float = float(val)
	match key:
		# 进攻 → CombatStats
		"atk_pct_delta":
			stats.atk_pct_bonus += v
		"atk_ratio_delta":
			stats.atk_ratio += v   # 技能倍率（累加 delta，默认 atk_ratio=1.0）
		"crit_rate_delta":
			stats.crit_rate += v
		"crit_dmg_delta":
			stats.crit_dmg += v
		"attack_speed_delta":
			stats.attack_speed += v
		"skill_mult_pct_delta":
			stats.skill_mult_pct += v
		"magic_dmg_pct_delta":
			stats.magic_dmg_pct += v
		"physical_dmg_pct_delta":
			stats.physical_dmg_pct += v
		"elemental_dmg_mult", "elemental_pct":
			stats.elemental_pct += v
		"final_dmg_mult":
			stats.final_dmg_mults.append(v)
		"true_dmg_pct_delta":
			stats.true_dmg_pct += v
		"armor_pen_delta":
			stats.armor_pen += v
		"all_stats_pct_delta":
			stats.atk_pct_bonus += v
			stats.crit_rate += v * 0.5
		# 以下 key 不影响进攻 CombatStats（生存/经济/控制/特殊），M2 暂忽略
		# （M2.5/M3 随生存模型/经济系统接入）
		_:
			pass   # hp_pct_delta/damage_reduction/lifesteal/gold_mult/status/transform 等


## 从 effect 列表批量累加。
static func accumulate_all(stats, effects: Array) -> void:
	for e in effects:
		if e is Dictionary:
			accumulate(stats, e)
