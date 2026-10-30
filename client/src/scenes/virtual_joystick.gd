## virtual_joystick.gd — 移动端浮动虚拟摇杆（B站 H5 / 触屏设备）。
## 触摸屏幕左侧 60% 区域 → 摇杆在指尖出现；拖动 → 控制英雄移动方向；松手 → 摇杆消失。
## 输出走静态变量 VirtualJoystick.dir（hero 直接读，无需节点引用/信号接线）。
## 仅触屏设备显示（DisplayServer.is_touchscreen_available），桌面自动隐藏（force_show 可调试）。
extends Control
class_name VirtualJoystick

## 输出方向（单位圆内，-1..1）。hero 每帧读取。
static var dir: Vector2 = Vector2.ZERO

const MAX_RADIUS := 130.0     # 摇杆最大拖动半径（像素）
const DEAD_ZONE := 0.15       # 死区：低于此幅度视为不动（防误触）
const ACTIVATE_ZONE := 0.6    # 屏幕左侧 60% 区域可触发（右侧留给点击目标）

var _active: bool = false
var _touch_index: int = -1
var _base_pos: Vector2 = Vector2.ZERO     # 摇杆中心（视口坐标）
var _knob_offset: Vector2 = Vector2.ZERO  # 旋钮相对中心的偏移

@export var force_show: bool = false   # 调试：桌面强制显示


func _ready() -> void:
	# 不挡 GUI：羁绊/装备/角色按钮必须能点到（mouse_filter=IGNORE 时 GUI 不消费本节点）
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = force_show or DisplayServer.is_touchscreen_available()


func _exit_tree() -> void:
	dir = Vector2.ZERO   # R 重开/场景重载时清零，避免残留移动


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed and not _active:
			# 左侧区域按下 → 摇杆在指尖出现（浮动式）
			if event.position.x < get_viewport_rect().size.x * ACTIVATE_ZONE:
				_active = true
				_touch_index = event.index
				_base_pos = event.position
				_knob_offset = Vector2.ZERO
				dir = Vector2.ZERO
				queue_redraw()
		elif not event.pressed and event.index == _touch_index:
			_reset()
	elif event is InputEventScreenDrag and _active and event.index == _touch_index:
		_knob_offset = event.position - _base_pos
		if _knob_offset.length() > MAX_RADIUS:
			_knob_offset = _knob_offset.normalized() * MAX_RADIUS
		var d := _knob_offset / MAX_RADIUS
		dir = d if d.length() >= DEAD_ZONE else Vector2.ZERO
		queue_redraw()


func _reset() -> void:
	_active = false
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	dir = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	# 底盘（半透明圆 + 描边）
	draw_circle(_base_pos, MAX_RADIUS, Color(0.08, 0.1, 0.18, 0.28))
	draw_arc(_base_pos, MAX_RADIUS, 0, TAU, 48, Color(0.6, 0.7, 0.9, 0.55), 2.0)
	# 旋钮（跟随手指）
	var knob := _base_pos + _knob_offset
	draw_circle(knob, 52, Color(0.78, 0.83, 0.96, 0.5))
	draw_arc(knob, 52, 0, TAU, 32, Color(1, 1, 1, 0.7), 2.0)
