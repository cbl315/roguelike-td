## shockwave.gd — 大招清屏冲击波（金色圆环扩散 + 中心辉光，0.6s 一次性）。
extends Node2D
class_name Shockwave

var _t: float = 0.0
const LIFE := 0.6
const MAX_R := 1600.0   # 覆盖全屏（1920×1080 对角线 ~2201，取 1600 视觉足够）


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var p: float = clampf(_t / LIFE, 0.0, 1.0)
	var ease_out: float = 1.0 - pow(1.0 - p, 3.0)        # ease-out-cubic（前快后慢）
	var r: float = MAX_R * ease_out
	var alpha: float = (1.0 - p) * (1.0 - p)             # 平方衰减
	# 中心辉光（早段最强）
	if p < 0.5:
		var glow_a: float = (1.0 - p * 2.0) * 0.35
		draw_circle(Vector2.ZERO, r * 0.35, Color(1.0, 0.85, 0.4, glow_a))
		draw_circle(Vector2.ZERO, r * 0.18, Color(1.0, 0.95, 0.6, glow_a * 1.2))
	# 主环（粗、亮）
	draw_arc(Vector2.ZERO, r, 0, TAU, 96, Color(1.0, 0.88, 0.45, alpha), 14.0)
	# 外层薄环（拖尾感）
	draw_arc(Vector2.ZERO, r * 0.92, 0, TAU, 96, Color(1.0, 0.7, 0.3, alpha * 0.5), 5.0)
	# 内层细环
	draw_arc(Vector2.ZERO, r * 0.8, 0, TAU, 96, Color(1.0, 0.95, 0.7, alpha * 0.7), 3.0)
