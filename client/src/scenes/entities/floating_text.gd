## floating_text.gd — 飘字伤害数字（Brotato/VS 标配 juice）。
## 普通=白字，暴击=金色大字+弹出缩放，大招=金红巨字。
## 纯 _draw 渲染（draw_string），无 Label/Tween 开销，0.7s 自动释放。
extends Node2D
class_name FloatingText

var text: String = ""
var crit: bool = false
var ult: bool = false          # 大招数字（最大号金红）
var _t: float = 0.0
const LIFE := 0.7

const FONT_PATH := "res://src/assets/fonts/NotoSansSC-subset.otf"
static var _font: Font = null


static func spawn(parent: Node, world_pos: Vector2, txt: String, is_crit: bool = false, is_ult: bool = false) -> void:
	var ft := FloatingText.new()
	ft.text = txt
	ft.crit = is_crit
	ft.ult = is_ult
	# 轻微随机偏移，连续命中不重叠
	ft.position = world_pos + Vector2(randf_range(-14, 14), randf_range(-10, 4))
	ft.z_index = 60   # 敌人/弹道之上
	parent.add_child(ft)


func _ready() -> void:
	if _font == null:
		_font = load(FONT_PATH)


func _process(delta: float) -> void:
	_t += delta
	position.y -= 55.0 * delta   # 上飘
	if _t >= LIFE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	var life_t: float = _t / LIFE
	# 淡出（后半程）
	var alpha: float = 1.0 if life_t < 0.55 else 1.0 - (life_t - 0.55) / 0.45
	# 弹出：前 0.15s 从 1.4→1.0 回弹
	var pop: float = 1.0
	if _t < 0.15:
		pop = 1.4 - 0.4 * (_t / 0.15)
	var size: int = 24
	var col := Color(1, 1, 1, alpha)
	if ult:
		size = 40
		col = Color(1.0, 0.62, 0.25, alpha)      # 金红
	elif crit:
		size = 32
		col = Color(1.0, 0.85, 0.3, alpha)       # 金色
	size = int(size * pop)
	var w: float = size * 2.0   # 文本框宽（CENTER 对齐锚点在框左缘 → 左移 w/2 实现原点居中）
	# 阴影（深色 +1,+1 提高任何背景上的可读性）
	_font.draw_string(get_canvas_item(), Vector2(1 - w * 0.5, 1), text,
		HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(0, 0, 0, alpha * 0.8))
	_font.draw_string(get_canvas_item(), Vector2(-w * 0.5, 0), text,
		HORIZONTAL_ALIGNMENT_CENTER, w, size, col)
