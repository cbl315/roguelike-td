# 03_screen_flash.gd
# Demo 03 — Screen Flash 2D.
#
# What this demo shows:
#   • One FeedbackPlayerLite per candy, each holding a single
#     FeedbackScreenFlash2DLite authored in the inspector (yellow /
#     pink / cyan / purple).
#   • Rapid clicks make several flashes overlap. The shared ColorRect
#     coordinator composes them by max-intensity + weighted-color, so
#     two simultaneous flashes read as one blended flash.
#   • A "blend mode" toggle swaps ADD (brighten) and MODULATE (tint)
#     at runtime.
#
# Key concepts:
#   • FeedbackScreenFlash2DLite lives on a CanvasLayer parented to the
#     SparkleLitePresets autoload — flashes survive scene changes.
#   • Multiple flashes at the same canvas_layer share one overlay.
#     Change canvas_layer between instances if you need independent
#     overlays that don't blend.

extends Control

const _CANDY_PATHS: Array[String] = [
	"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_1.png",
	"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_2.png",
	"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_3.png",
	"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_special_rain.png",
]

const _CANDY_COLORS: Array[Color] = [
	Color("#FFE17A"),
	Color("#FF6FA8"),
	Color("#A24AE2"),
	Color("#8AF0E8"),
]

const _CANDY_LABELS: Array[String] = [
	"Yellow Drop",
	"Pink Hearts",
	"Purple Rocks",
	"Cyan Rain",
]

@onready var _flash_players: Array[FeedbackPlayerLite] = [
	$Flashes/Flash1,
	$Flashes/Flash2,
	$Flashes/Flash3,
	$Flashes/Flash4,
]

var _blend_mode: FeedbackScreenFlash2DLite.BlendMode = \
		FeedbackScreenFlash2DLite.BlendMode.ADD
var _status_label: Label


func _ready() -> void:
	SparkleLiteDemoWidgets.paint_page_background(self)
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event
		if key.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://addons/sparkle_lite/samples/sparklelite_main.tscn")


func _build_ui() -> void:
	var outer: MarginContainer = MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override(&"margin_left", 32)
	outer.add_theme_constant_override(&"margin_right", 32)
	outer.add_theme_constant_override(&"margin_top", 24)
	outer.add_theme_constant_override(&"margin_bottom", 24)
	add_child(outer)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 16)
	outer.add_child(column)

	var header: SparkleLiteDemoHeader = SparkleLiteDemoHeader.new()
	header.title_text = "03 · Screen Flash 2D"
	header.subtitle_text = (
			"Click any candy to flash the viewport with that candy's "
			+ "color. Multiple clicks compose on the shared overlay."
	)
	header.accent_color = SparkleLiteDemoPalette.GRADIENT_PINK
	column.add_child(header)

	column.add_child(SparkleLiteDemoWidgets.make_info_callout(
		"What to try",
		(
			"• Click any candy — fires its FeedbackPlayer (scene-authored "
			+ "FeedbackScreenFlash2DLite).\n"
			+ "• Tap two candies quickly — the flashes share one overlay "
			+ "and the color blends.\n"
			+ "• ADD / MODULATE — toggle blend mode on every flash at "
			+ "runtime using the full API."
		),
		SparkleLiteDemoPalette.GRADIENT_PINK
	))

	var candy_row: HBoxContainer = HBoxContainer.new()
	candy_row.add_theme_constant_override(&"separation", 18)
	candy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(candy_row)

	for i in range(_CANDY_PATHS.size()):
		candy_row.add_child(_build_candy_card(i))

	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override(&"separation", 12)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(controls)

	var blend_add: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Blend: ADD (brighten)", SparkleLiteDemoPalette.GRADIENT_YELLOW)
	blend_add.pressed.connect(_on_blend_changed.bind(
			FeedbackScreenFlash2DLite.BlendMode.ADD))
	controls.add_child(blend_add)

	var blend_mod: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Blend: MODULATE (tint)", SparkleLiteDemoPalette.GRADIENT_PURPLE)
	blend_mod.pressed.connect(_on_blend_changed.bind(
			FeedbackScreenFlash2DLite.BlendMode.MODULATE))
	controls.add_child(blend_mod)

	var rainbow: Button = SparkleLiteDemoWidgets.make_primary_button(
			"Rainbow Burst (all four)", SparkleLiteDemoPalette.GRADIENT_PINK)
	rainbow.pressed.connect(_on_rainbow_pressed)
	controls.add_child(rainbow)

	_status_label = Label.new()
	_status_label.text = "Blend mode: ADD"
	_status_label.add_theme_font_size_override(&"font_size", 13)
	_status_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status_label)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	column.add_child(SparkleLiteDemoWidgets.make_code_block(
		"Equivalent runtime code",
		(
			"# One flash per candy, same shape as the scene-authored ones:\n"
			+ "var flash := FeedbackScreenFlash2DLite.new()\n"
			+ "flash.flash_color = Color(\"#FFE17A\")\n"
			+ "flash.flash_intensity = 0.35\n"
			+ "flash.fade_in_duration_ms = 40.0\n"
			+ "flash.hold_duration_ms = 40.0\n"
			+ "flash.fade_out_duration_ms = 200.0\n"
			+ "flash.blend_mode = FeedbackScreenFlash2DLite.BlendMode.ADD\n"
			+ "$Flashes/Flash1.clear_feedbacks()\n"
			+ "$Flashes/Flash1.add_feedback(flash)\n"
			+ "$Flashes/Flash1.play()"
		),
		SparkleLiteDemoPalette.GRADIENT_PINK
	))


func _build_candy_card(index: int) -> Control:
	var card: Button = Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(200, 240)
	card.flat = false

	var color: Color = _CANDY_COLORS[index]
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = SparkleLiteDemoPalette.CARD_BG
	normal.border_color = color
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(18)
	normal.set_content_margin_all(12)
	card.add_theme_stylebox_override(&"normal", normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = SparkleLiteDemoPalette.PANEL_BG
	card.add_theme_stylebox_override(&"hover", hover)
	var pressed: StyleBoxFlat = hover.duplicate()
	pressed.bg_color = SparkleLiteDemoPalette.BG
	card.add_theme_stylebox_override(&"pressed", pressed)

	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	var icon: TextureRect = TextureRect.new()
	icon.texture = load(_CANDY_PATHS[index]) as Texture2D
	icon.custom_minimum_size = Vector2(0, 140)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon)

	var label: Label = Label.new()
	label.text = _CANDY_LABELS[index]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_font_size_override(&"font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(label)

	card.pressed.connect(_on_candy_pressed.bind(index))
	return card


# --- Button handlers -------------------------------------------------

func _on_candy_pressed(index: int) -> void:
	# The entire demo trigger: play the scene-authored FeedbackPlayer
	# that owns a single FeedbackScreenFlash2DLite. The overlay is
	# shared, so repeated clicks compose.
	_flash_players[index].play()
	_status_label.text = "Flashed: %s" % _CANDY_LABELS[index]


func _on_rainbow_pressed() -> void:
	# Fire all four flashes in the same frame — the shared overlay
	# blends their colors together rather than stacking layers.
	for player in _flash_players:
		player.play()
	_status_label.text = "All four flashes composed on one overlay."


func _on_blend_changed(
		mode: FeedbackScreenFlash2DLite.BlendMode
) -> void:
	# Runtime-API mutation: reach into every scene-authored player,
	# grab its first feedback, and change blend mode. This is the
	# exact resource the inspector exposes.
	_blend_mode = mode
	for player in _flash_players:
		for fb in player.feedbacks:
			if fb is FeedbackScreenFlash2DLite:
				(fb as FeedbackScreenFlash2DLite).blend_mode = mode
	_status_label.text = "Blend mode: %s" % (
			"ADD"
			if mode == FeedbackScreenFlash2DLite.BlendMode.ADD
			else "MODULATE"
	)
