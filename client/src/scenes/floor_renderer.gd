## floor_renderer.gd — 程序化地板渲染（直接 draw_rect，无烘焙贴图）。
## 逐帧绘制棋盘格 + 网格线 + 暗角 + 边框发光。
## 828 个格子（36×23）每帧 draw_rect，零纹理零缩放零模糊。
extends Node2D
class_name FloorRenderer

var room_rect := GameConst.ROOM_RECT
const GRID_SIZE := 80.0

const COL_FLOOR_A := Color(0.10, 0.105, 0.14)
const COL_FLOOR_B := Color(0.085, 0.09, 0.125)
const COL_GRID := Color(0.13, 0.14, 0.18)
const COL_VIGNETTE := Color(0.02, 0.02, 0.04)
const COL_BORDER_GLOW := Color(0.2, 0.25, 0.4, 0.15)


func _ready() -> void:
	z_index = -1


func _draw() -> void:
	var pos := room_rect.position
	var sz := room_rect.size
	# 底色
	draw_rect(Rect2(pos, sz), COL_FLOOR_B)
	# 棋盘格（直接 draw_rect，格子边缘精确到像素）
	var cols: int = ceili(sz.x / GRID_SIZE)
	var rows: int = ceili(sz.y / GRID_SIZE)
	for gy in range(rows):
		for gx in range(cols):
			if (gx + gy) % 2 == 0:
				var r := Rect2(
					pos.x + gx * GRID_SIZE, pos.y + gy * GRID_SIZE,
					minf(GRID_SIZE, sz.x - gx * GRID_SIZE),
					minf(GRID_SIZE, sz.y - gy * GRID_SIZE)
				)
				draw_rect(r, COL_FLOOR_A)
	# 网格线
	for gx in range(cols + 1):
		var x := pos.x + gx * GRID_SIZE
		draw_line(Vector2(x, pos.y), Vector2(x, pos.y + sz.y), COL_GRID, 1.0)
	for gy in range(rows + 1):
		var y := pos.y + gy * GRID_SIZE
		draw_line(Vector2(pos.x, y), Vector2(pos.x + sz.x, y), COL_GRID, 1.0)
	# 边框发光（4 层递减）
	var rect := Rect2(pos, sz)
	for i in range(4):
		var expand: float = (i + 1) * 6.0
		var r2 := rect.grow(expand)
		var a: float = COL_BORDER_GLOW.a * (1.0 - float(i) / 4.0)
		draw_rect(r2, Color(COL_BORDER_GLOW.r, COL_BORDER_GLOW.g, COL_BORDER_GLOW.b, a), false, 2.0)


## 兼容接口（gm 调用——当前无操作，背景贴图功能已移除）
func set_bg_mode(_mode: String) -> void:
	pass
