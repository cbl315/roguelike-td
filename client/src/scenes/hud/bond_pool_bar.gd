## bond_pool_bar.gd — 底部羁绊池展示条（按体系分组 + 体系色边框）。
## 显示当前 bond_pool 未吞噬羁绊的迷你卡：组头=体系名×数量，卡边框=体系色。
## 数据驱动：build.changed / 波次开始时刷新；tooltip 显示卡名与效果。
extends CanvasLayer
class_name BondPoolBar

const GROUP_ORDER := ["zhutian", "xingchenbian", "chongmei", "doupo", "generic"]
const GROUP_COLORS := {
	"zhutian": Color(1.0, 0.78, 0.35),      # 遮天·金
	"xingchenbian": Color(0.4, 0.65, 1.0),  # 星辰变·蓝
	"chongmei": Color(0.8, 0.45, 0.95),     # 宠魅·紫
	"doupo": Color(1.0, 0.5, 0.3),          # 斗破·焰红
	"generic": Color(0.55, 0.7, 0.6),       # 符文·灰绿
}
const GROUP_NAMES := {
	"zhutian": "遮天", "xingchenbian": "星辰变", "chongmei": "宠魅",
	"doupo": "斗破", "generic": "符文",
}

var _root: HBoxContainer = null
var _build = null
var _pools = null


func setup(build, pools) -> void:
	_build = build
	_pools = pools
	layer = 8   # HUD 之上、lobby 遮罩之下
	_root = HBoxContainer.new()
	_root.position = Vector2(16, 1004)          # 底部细条（全宽容器、内容居中）
	_root.size = Vector2(1888, 68)
	_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_theme_constant_override("separation", 10)
	add_child(_root)
	if build != null:
		build.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if _root == null or _build == null or _pools == null:
		return
	for c in _root.get_children():
		c.queue_free()
	if _build.bond_pool.is_empty():
		var empty := Label.new()
		empty.text = "羁绊池空（抽羁绊/凑齐同体系触发吞噬）"
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		_root.add_child(empty)
		return
	# 按 set 分组（保持抽取顺序的组内排序）
	var groups: Dictionary = {}
	for bid in _build.bond_pool:
		var set_id: String = "generic"
		var b: Dictionary = _pools._find_bond(bid)
		if not b.is_empty():
			set_id = str(b.get("set", "generic"))
		if set_id not in GROUP_ORDER:
			set_id = "generic"
		if not groups.has(set_id):
			groups[set_id] = []
		groups[set_id].append(bid)
	# 组渲染（固定体系顺序）
	for set_id in GROUP_ORDER:
		if not groups.has(set_id):
			continue
		_root.add_child(_make_group(set_id, groups[set_id]))


func _make_group(set_id: String, bids: Array) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	# 组头：体系名 ×数量（体系色小字，竖向贴左）
	var head := Label.new()
	head.text = "%s\n×%d" % [GROUP_NAMES.get(set_id, set_id), bids.size()]
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", GROUP_COLORS.get(set_id, Color.WHITE))
	head.custom_minimum_size = Vector2(44, 60)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	for bid in bids:
		box.add_child(_make_mini_card(bid, set_id))
	return box


func _make_mini_card(bid: String, set_id: String) -> Control:
	var b: Dictionary = _pools._find_bond(bid)
	var rar: String = str(b.get("rarity", "N"))
	var name: String = str(b.get("name", bid))
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(58, 60)
	var style := StyleBoxFlat.new()
	var border: Color = GROUP_COLORS.get(set_id, Color.WHITE)
	style.bg_color = Color(0.08, 0.1, 0.14, 0.85)
	style.border_width_left = 3; style.border_width_right = 3
	style.border_width_top = 2; style.border_width_bottom = 2
	style.border_color = border
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = name.substr(0, mini(4, name.length()))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(lbl)
	# tooltip：全名 + 效果文本 + 品质
	var eff_text: String = ""
	if _pools != null:
		eff_text = _pools._effect_to_text(b.get("effect", {}))
	panel.tooltip_text = "[%s] %s\n%s" % [rar, name, eff_text]
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	return panel
