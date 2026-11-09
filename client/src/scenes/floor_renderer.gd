## floor_renderer.gd — 程序化地图地板渲染（Brotato/VS 风格的简洁地面）。
## 挂在 GridLines 节点上（main.tscn 里已有的空 Node2D）。
## 一次烘焙到纹理，缓存复用，避免每帧重绘。
extends Node2D
class_name FloorRenderer

## 房间区域（与 main.tscn RoomBorder 一致）
var room_rect := GameConst.ROOM_RECT

## 格子大小（像素）
const GRID_SIZE := 80.0

# 地板色板（暗色调，和深色背景融合）
const COL_FLOOR_A := Color(0.10, 0.105, 0.14)      # 浅格
const COL_FLOOR_B := Color(0.085, 0.09, 0.125)     # 深格
const COL_GRID := Color(0.13, 0.14, 0.18)          # 网格线（叠加在格子上）
const COL_VIGNETTE := Color(0.02, 0.02, 0.04)      # 边缘暗角
const COL_BORDER_GLOW := Color(0.2, 0.25, 0.4, 0.15) # 边框外发光

var _texture: Texture2D = null
var _baked: bool = false


var _bg_sprite: TextureRect = null


func _ready() -> void:
	z_index = -1   # 在所有游戏元素下面
	_bake_floor()
	# VFX 批次二：背景图暂移除（1440px 拉到 2840×1840 必糊——
	# 需要 2840+ 原生分辨率或九宫格平铺方案，待高分辨率素材后恢复）
	pass


## Boss 波切换背景（gm 波开始调用）：arena（Boss 波）/ heaven（w20+）
func set_bg_mode(mode: String) -> void:
	if _bg_sprite == null:
		return
	var atlas := get_node_or_null("/root/SpriteAtlas")
	if atlas == null:
		return
	if mode == "none":
		_bg_sprite.modulate = Color(1, 1, 1, 0.0)
		return
	var key := "arena" if mode == "boss" else ("heaven" if mode == "final" else "dungeon")
	var tex: Texture2D = atlas.get_bg(key)
	if tex:
		_bg_sprite.texture = tex
		_bg_sprite.modulate = Color(1, 1, 1, 0.0)   # 1024 拉伸到 2840 会糊——暂禁用，待高分辨率背景


## 烘焙地板纹理（一次渲染，缓存复用）
func _bake_floor() -> void:
	if _baked:
		return
	_baked = true
	var tex_w: int = ceili(room_rect.size.x)
	var tex_h: int = ceili(room_rect.size.y)

	# 全分辨率烘焙（2840×1840 ≈ 5.2M 像素，一次性无每帧开销）
	# 此前 scale_down=4 烘焙后 4× 上采样导致格子/网格线模糊（"马赛克"根因）
	var scale_down: int = 1
	var bw: int = ceili(tex_w / float(scale_down))
	var bh: int = ceili(tex_h / float(scale_down))
	var bgrid: float = GRID_SIZE / float(scale_down)

	var img := Image.create(bw, bh, false, Image.FORMAT_RGBA8)

	# 1. 棋盘格地板（用 fill_rect 批量填充）
	var grid_cols: int = ceili(bw / bgrid)
	var grid_rows: int = ceili(bh / bgrid)
	for gy in range(grid_rows):
		for gx in range(grid_cols):
			var col: Color = COL_FLOOR_A if (gx + gy) % 2 == 0 else COL_FLOOR_B
			var x0: int = int(gx * bgrid)
			var y0: int = int(gy * bgrid)
			var x1: int = mini(x0 + int(bgrid), bw)
			var y1: int = mini(y0 + int(bgrid), bh)
			for py in range(y0, y1):
				for px in range(x0, x1):
					img.set_pixel(px, py, col)

	# 2. 网格线
	for gx in range(grid_cols + 1):
		var x: int = int(gx * bgrid)
		if x >= bw:
			continue
		for py in range(bh):
			var c: Color = img.get_pixel(x, py)
			img.set_pixel(x, py, c.lerp(COL_GRID, 0.4))
	for gy in range(grid_rows + 1):
		var y: int = int(gy * bgrid)
		if y >= bh:
			continue
		for px in range(bw):
			var c: Color = img.get_pixel(px, y)
			img.set_pixel(px, y, c.lerp(COL_GRID, 0.4))

	# 3. 暗角
	var cx: float = bw / 2.0
	var cy: float = bh / 2.0
	var max_dist: float = sqrt(cx * cx + cy * cy)
	for py in range(bh):
		for px in range(bw):
			var dx: float = px - cx
			var dy: float = py - cy
			var dist: float = sqrt(dx * dx + dy * dy)
			var vignette: float = clampf((dist / max_dist - 0.5) * 2.0, 0.0, 1.0)
			if vignette > 0.0:
				var c: Color = img.get_pixel(px, py)
				c = c.lerp(COL_VIGNETTE, vignette * 0.4)
				img.set_pixel(px, py, c)

	# 放大回原始尺寸
	img.resize(tex_w, tex_h, Image.INTERPOLATE_NEAREST)
	_texture = ImageTexture.create_from_image(img)


func _draw() -> void:
	if _texture:
		# 地板纹理画在 room_rect 起始位置
		draw_texture(_texture, room_rect.position)
	# 房间边框外发光（4 层递减 alpha 的描边）
	var rect := Rect2(room_rect.position, room_rect.size)
	for i in range(4):
		var expand: float = (i + 1) * 6.0
		var r := rect.grow(expand)
		var a: float = COL_BORDER_GLOW.a * (1.0 - float(i) / 4.0)
		draw_rect(r, Color(COL_BORDER_GLOW.r, COL_BORDER_GLOW.g, COL_BORDER_GLOW.b, a), false, 2.0)
