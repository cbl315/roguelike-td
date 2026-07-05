## target_priority.gd — 目标优先级枚举 + 选择函数（GDD §5 微操）
extends RefCounted
class_name TargetPriority

enum Mode { NEAREST, WEAKEST, BOSS }

static var _labels := {
	Mode.NEAREST: "最近",
	Mode.WEAKEST: "最脆",
	Mode.BOSS: "Boss",
}


static func label(m: Mode) -> String:
	return _labels.get(m, "?")

static func next_mode(m: Mode) -> Mode:
	# 循环切换：NEAREST → WEAKEST → BOSS → NEAREST
	return Mode.values()[(m + 1) % Mode.values().size()]


## 从候选敌人中按策略选一个。enemies: Array[Enemy]（已过滤到范围内）。
## hero_pos: 英雄全局坐标（用于 NEAREST）。
static func pick(enemies: Array, mode: Mode, hero_pos: Vector2) -> Node2D:
	if enemies.is_empty():
		return null
	match mode:
		Mode.NEAREST:
			var best: Node2D = enemies[0]
			var best_d: float = best.global_position.distance_to(hero_pos)
			for e in enemies:
				var en: Node2D = e
				var d: float = en.global_position.distance_to(hero_pos)
				if d < best_d:
					best = en
					best_d = d
			return best
		Mode.WEAKEST:
			var best: Node2D = enemies[0]
			for e in enemies:
				var en: Node2D = e
				if en.get("current_hp") != null and en.get("current_hp") < best.get("current_hp"):
					best = en
			return best
		Mode.BOSS:
			# 优先 Boss/精英，无则最近
			for e in enemies:
				var en: Node2D = e
				if en.get("is_boss") == true or en.get("is_elite") == true:
					return en
			return pick(enemies, Mode.NEAREST, hero_pos)
	return enemies[0]
