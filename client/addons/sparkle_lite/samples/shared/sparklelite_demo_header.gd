# sparklelite_demo_header.gd
# Top bar used at the top of every sample scene — back arrow, title,
# and a one-line description. Keeps navigation identical across every
# example so users always know how to return to the hub.
#
# Tutorial note: this is pure sample chrome — not part of Sparkle Lite.
# If you're reading the source to learn the plugin, skip this file;
# jump to any sparklelite_*.gd under samples/scenes instead.

class_name SparkleLiteDemoHeader
extends PanelContainer

const _HUB_SCENE_PATH: String = "res://addons/sparkle_lite/samples/sparklelite_main.tscn"

@export var title_text: String = "Demo":
	set(value):
		title_text = value
		if is_inside_tree():
			_title_label.text = value

@export_multiline var subtitle_text: String = "":
	set(value):
		subtitle_text = value
		if is_inside_tree():
			_subtitle_label.text = value

@export var accent_color: Color = SparkleLiteDemoPalette.GRADIENT_PURPLE:
	set(value):
		accent_color = value
		if is_inside_tree():
			_apply_accent()


var _title_label: Label
var _subtitle_label: Label
var _accent_rect: ColorRect
var _back_button: Button


func _ready() -> void:
	_build_ui()
	_apply_accent()


func _build_ui() -> void:
	add_theme_constant_override(&"margin_left", 24)
	add_theme_constant_override(&"margin_right", 24)
	add_theme_constant_override(&"margin_top", 16)
	add_theme_constant_override(&"margin_bottom", 16)

	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = SparkleLiteDemoPalette.CARD_BG
	bg.border_color = SparkleLiteDemoPalette.STROKE
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 20.0
	bg.content_margin_right = 20.0
	bg.content_margin_top = 14.0
	bg.content_margin_bottom = 14.0
	add_theme_stylebox_override(&"panel", bg)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	add_child(row)

	_back_button = Button.new()
	_back_button.text = "  \u2190  Back to Hub  "
	_back_button.custom_minimum_size = Vector2(160, 44)
	_back_button.focus_mode = Control.FOCUS_NONE
	_style_back_button(_back_button)
	_back_button.pressed.connect(_on_back_pressed)
	row.add_child(_back_button)

	_accent_rect = ColorRect.new()
	_accent_rect.custom_minimum_size = Vector2(4, 44)
	row.add_child(_accent_rect)

	var text_col: VBoxContainer = VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override(&"separation", 2)
	row.add_child(text_col)

	_title_label = Label.new()
	_title_label.text = title_text
	_title_label.add_theme_font_size_override(&"font_size", 22)
	_title_label.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT)
	text_col.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.text = subtitle_text
	_subtitle_label.add_theme_font_size_override(&"font_size", 13)
	_subtitle_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(_subtitle_label)


func _style_back_button(btn: Button) -> void:
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = SparkleLiteDemoPalette.PANEL_BG
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(8)
	normal.border_color = SparkleLiteDemoPalette.STROKE
	normal.set_border_width_all(1)
	btn.add_theme_stylebox_override(&"normal", normal)

	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = SparkleLiteDemoPalette.STROKE
	btn.add_theme_stylebox_override(&"hover", hover)

	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = SparkleLiteDemoPalette.BG
	btn.add_theme_stylebox_override(&"pressed", pressed)

	btn.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT)
	btn.add_theme_color_override(&"font_hover_color", SparkleLiteDemoPalette.TEXT)


func _apply_accent() -> void:
	if _accent_rect != null:
		_accent_rect.color = accent_color


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_HUB_SCENE_PATH)
