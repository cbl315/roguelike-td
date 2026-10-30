# sparklelite_demo_widgets.gd
# Tiny helper library that builds the chrome used by every sample scene:
# info callouts, code blocks, buttons, separators. Keeps the actual
# sample scripts focused on Sparkle Lite calls instead of UI plumbing.
#
# Tutorial note: pure cosmetic/sample code — none of this is Sparkle Lite.

class_name SparkleLiteDemoWidgets
extends RefCounted


## Builds a rounded info callout with a header accent bar. Use for
## "what to try" hints at the top of a demo.
static func make_info_callout(
		title: String,
		body: String,
		accent: Color = SparkleLiteDemoPalette.ACCENT_CYAN
) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = SparkleLiteDemoPalette.CARD_BG
	bg.border_color = SparkleLiteDemoPalette.STROKE
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(10)
	bg.content_margin_left = 18.0
	bg.content_margin_right = 18.0
	bg.content_margin_top = 14.0
	bg.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override(&"panel", bg)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	panel.add_child(row)

	var accent_rect: ColorRect = ColorRect.new()
	accent_rect.color = accent
	accent_rect.custom_minimum_size = Vector2(4, 0)
	accent_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(accent_rect)

	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 4)
	row.add_child(col)

	var title_lbl: Label = Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override(&"font_size", 15)
	title_lbl.add_theme_color_override(&"font_color", accent)
	col.add_child(title_lbl)

	var body_lbl: Label = Label.new()
	body_lbl.text = body
	body_lbl.add_theme_font_size_override(&"font_size", 13)
	body_lbl.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT)
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body_lbl)

	return panel


## Builds a monospace code block showing the "same thing in code"
## version of whatever the demo just did in the inspector.
static func make_code_block(
		title: String,
		code: String,
		accent: Color = SparkleLiteDemoPalette.ACCENT_CAMERA_SHAKE
) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = SparkleLiteDemoPalette.BG
	bg.border_color = SparkleLiteDemoPalette.STROKE
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(10)
	bg.content_margin_left = 18.0
	bg.content_margin_right = 18.0
	bg.content_margin_top = 12.0
	bg.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override(&"panel", bg)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	panel.add_child(col)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	col.add_child(header)

	var dot: ColorRect = ColorRect.new()
	dot.color = accent
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(dot)

	var header_lbl: Label = Label.new()
	header_lbl.text = title
	header_lbl.add_theme_font_size_override(&"font_size", 12)
	header_lbl.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	header.add_child(header_lbl)

	var code_lbl: Label = Label.new()
	code_lbl.text = code
	code_lbl.add_theme_font_size_override(&"font_size", 13)
	code_lbl.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.CODE_TEXT)
	code_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(code_lbl)

	return panel


## Builds an accent-colored primary-action button. Use for the main
## "play the feedback" trigger in a demo.
static func make_primary_button(
		text: String, accent: Color
) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(220, 52)

	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = accent
	normal.set_corner_radius_all(10)
	normal.set_content_margin_all(10)
	btn.add_theme_stylebox_override(&"normal", normal)

	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = accent.lightened(0.1)
	btn.add_theme_stylebox_override(&"hover", hover)

	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = accent.darkened(0.15)
	btn.add_theme_stylebox_override(&"pressed", pressed)

	var contrast_text: Color = (
			SparkleLiteDemoPalette.BG if accent.get_luminance() > 0.6
			else SparkleLiteDemoPalette.TEXT
	)
	btn.add_theme_color_override(&"font_color", contrast_text)
	btn.add_theme_color_override(&"font_hover_color", contrast_text)
	btn.add_theme_color_override(&"font_pressed_color", contrast_text)
	btn.add_theme_font_size_override(&"font_size", 16)
	return btn


## Secondary button: outlined, for "play at half intensity" etc.
static func make_secondary_button(
		text: String, accent: Color = SparkleLiteDemoPalette.TEXT_MUTED
) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(180, 44)

	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = SparkleLiteDemoPalette.CARD_BG
	normal.border_color = accent
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(8)
	btn.add_theme_stylebox_override(&"normal", normal)

	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = SparkleLiteDemoPalette.PANEL_BG
	btn.add_theme_stylebox_override(&"hover", hover)

	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = SparkleLiteDemoPalette.BG
	btn.add_theme_stylebox_override(&"pressed", pressed)

	btn.add_theme_color_override(&"font_color", accent)
	btn.add_theme_color_override(&"font_hover_color", accent.lightened(0.2))
	btn.add_theme_color_override(&"font_pressed_color", accent.darkened(0.1))
	btn.add_theme_font_size_override(&"font_size", 14)
	return btn


## Builds a compact "← Menu" button and anchors it to the top-right of
## [param root]. Three 3D demos share the same navigation pattern, so
## the geometry lives here once. The caller still owns the press — pass
## a Callable that changes back to main.tscn (or whatever they need).
static func add_back_button(root: Control, on_press: Callable) -> Button:
	var btn: Button = make_secondary_button(
			"\u2190 Menu (Esc)", SparkleLiteDemoPalette.TEXT_MUTED)
	btn.custom_minimum_size = Vector2(150, 38)
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -174
	btn.offset_right = -24
	btn.offset_top = 18
	btn.offset_bottom = 56
	btn.pressed.connect(on_press)
	root.add_child(btn)
	return btn


## Names of the weapon meshes bundled inside sparklelite_soldier.gltf.
## The model ships with every weapon visible; samples only want the
## rifle, so [method keep_rifle_only] hides the rest.
const _SOLDIER_WEAPON_NAMES: PackedStringArray = [
	"AK", "GrenadeLauncher", "Knife_1", "Knife_2", "Pistol",
	"Revolver", "Revolver_Small", "RocketLauncher", "ShortCannon",
	"Shotgun", "Shovel", "SMG", "Sniper", "Sniper_2",
]
const _SOLDIER_KEEP_WEAPON: String = "AK"


## Walks the soldier glTF tree and hides every weapon sub-mesh except
## the rifle (AK). Call once after instantiating the model so the
## character is shown holding a single weapon.
static func keep_rifle_only(soldier: Node) -> void:
	if soldier == null:
		return
	for weapon_name in _SOLDIER_WEAPON_NAMES:
		if weapon_name == _SOLDIER_KEEP_WEAPON:
			continue
		var node: Node = soldier.find_child(weapon_name, true, false)
		if node is Node3D:
			(node as Node3D).visible = false


## Sets the root Control's background to the shared dark page fill.
## Called by every demo's _ready() as the first line so there is no
## default-grey flash on scene change.
static func paint_page_background(target: Control) -> void:
	var bg: ColorRect = ColorRect.new()
	bg.name = &"_PageBg"
	bg.color = SparkleLiteDemoPalette.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(bg)
	target.move_child(bg, 0)
