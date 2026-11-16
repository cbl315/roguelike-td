## game_theme.gd — 暗色魔幻 UI 主题（方案 A）
## 统一色板 + Panel/Button/Label 样式 → 替代 Godot 默认裸控件
##
## 色板：
##   底色   #0A0E1A（深蓝黑）
##   强调   #FFB830（金色）
##   正文   #E8E4F0（暖白）
##   危险   #C44030（暗红）
##   成功   #40C470（翠绿）
class_name GameTheme

const BG_DARK := Color("0A0E1A")
const BG_PANEL := Color("121626")
const BG_PANEL_HOVER := Color("1A1F35")
const ACCENT := Color("FFB830")
const TEXT_MAIN := Color("E8E4F0")
const TEXT_DIM := Color("8890A8")
const DANGER := Color("C44030")
const SUCCESS := Color("40C470")
const BORDER_GLOW := Color("FFB830")

## 稀有度颜色
const RARITY := {
	"N":   Color("707890"),
	"SR":  Color("4488FF"),
	"SSR": Color("AA55FF"),
	"UR":  Color("FF8830"),
	"EX":  Color("FF4455"),
}


static func make_panel_style(bg := BG_PANEL, border := ACCENT, border_w := 2, radius := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(bg.r, bg.g, bg.b, 0.92)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 4
	return s


static func make_button_style(bg := BG_PANEL, border := ACCENT) -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = Color(border.r, border.g, border.b, 0.5)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6

	var hover := normal.duplicate()
	hover.bg_color = BG_PANEL_HOVER
	hover.border_color = border
	hover.shadow_color = Color(border.r, border.g, border.b, 0.3)
	hover.shadow_size = 6

	var pressed := normal.duplicate()
	pressed.bg_color = Color(bg.r * 0.7, bg.g * 0.7, bg.b * 0.7, 0.95)

	var disabled := normal.duplicate()
	disabled.bg_color = Color(bg.r * 0.5, bg.g * 0.5, bg.b * 0.5, 0.5)
	disabled.border_color = Color(border.r, border.g, border.b, 0.2)

	return {"normal": normal, "hover": hover, "pressed": pressed, "disabled": disabled}


static func make_progress_style(fill := ACCENT, bg := BG_DARK) -> Dictionary:
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = bg
	bg_style.set_corner_radius_all(4)
	bg_style.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3)
	bg_style.set_border_width_all(1)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill
	fill_style.set_corner_radius_all(4)

	return {"background": bg_style, "fill": fill_style}


## 应用到 Theme 资源
static func build_theme() -> Theme:
	var t := Theme.new()

	# Panel
	t.set_stylebox("panel", "PanelContainer", make_panel_style())
	t.set_stylebox("panel", "Panel", make_panel_style())

	# Button
	var btn := make_button_style()
	t.set_stylebox("normal", "Button", btn["normal"])
	t.set_stylebox("hover", "Button", btn["hover"])
	t.set_stylebox("pressed", "Button", btn["pressed"])
	t.set_stylebox("disabled", "Button", btn["disabled"])
	t.set_color("font_color", "Button", TEXT_MAIN)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_font_size("font_size", "Button", 18)

	# Label 默认色（各处可覆盖）
	t.set_color("font_color", "Label", TEXT_MAIN)
	t.set_font_size("font_size", "Label", 17)

	# ProgressBar
	var pb := make_progress_style()
	t.set_stylebox("background", "ProgressBar", pb["background"])
	t.set_stylebox("fill", "ProgressBar", pb["fill"])

	# LineEdit
	var le_bg := make_panel_style(BG_PANEL, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3), 1, 6)
	t.set_stylebox("normal", "LineEdit", le_bg)
	t.set_color("font_color", "LineEdit", TEXT_MAIN)

	# TabContainer
	t.set_stylebox("panel", "TabContainer", make_panel_style())
	t.set_color("font_color", "TabContainer", TEXT_MAIN)

	return t


## HUD 底板样式（信息区叠在地板上时的半透明底）
static func make_hud_backdrop(width: float, height: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, height)
	p.add_theme_stylebox_override("panel", make_panel_style(BG_PANEL, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.15), 1, 8))
	return p


## 卡片稀有度边框发光
static func rarity_glow(rarity: String) -> StyleBoxFlat:
	var col: Color = RARITY.get(rarity, RARITY["N"])
	var s := StyleBoxFlat.new()
	s.bg_color = Color(BG_PANEL.r, BG_PANEL.g, BG_PANEL.b, 0.94)
	s.border_color = col
	s.set_border_width_all(3)
	s.set_corner_radius_all(10)
	s.shadow_color = Color(col.r, col.g, col.b, 0.4)
	s.shadow_size = 8
	return s
