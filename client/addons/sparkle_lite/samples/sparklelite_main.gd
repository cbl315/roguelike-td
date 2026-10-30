# sparklelite_main.gd
# Sample hub — the landing scene. Shows the plugin logo, lists every
# sample as a clickable card, and links back to the full Sparkle plugin
# on itch.io.
#
# Tutorial entry point: nothing on this screen uses Sparkle Lite
# directly. Pick a card and read the matching sparklelite_*.gd under
# samples/scenes/ — each sample is self-contained and commented top-to-
# bottom. Recommended reading order follows the card order below.

extends Control

const _LOGO_PATH: String = "res://addons/sparkle_lite/samples/assets/sparklelite_logo.png"
const _ITCH_URL: String = "https://neohex-interactive.itch.io/sparkle"

## One catalogue entry per demo card. Mirrors the reading order we
## suggest in the README: start with Camera Shake, end with the pure-
## code API example.
const _DEMOS: Array[Dictionary] = [
	{
		"number": "01",
		"title": "Camera Shake",
		"subtitle": "3D Camera3D shake with per-axis amplitudes.",
		"scene": "res://addons/sparkle_lite/samples/scenes/sparklelite_01_camera_shake.tscn",
		"accent": SparkleLiteDemoPalette.ACCENT_CAMERA_SHAKE,
		"icon": "res://addons/sparkle_lite/editor/icons/camera_shake.svg",
	},
	{
		"number": "02",
		"title": "Camera Shake 2D",
		"subtitle": "Camera2D position + rotation shake with pixel amplitudes.",
		"scene": "res://addons/sparkle_lite/samples/scenes/sparklelite_09_camera_shake_2d.tscn",
		"accent": SparkleLiteDemoPalette.ACCENT_CAMERA_SHAKE,
		"icon": "res://addons/sparkle_lite/editor/icons/camera_shake.svg",
	},
	{
		"number": "03",
		"title": "Hit Pause",
		"subtitle": "Engine time-scale drop for hit-stop impact.",
		"scene": "res://addons/sparkle_lite/samples/scenes/sparklelite_02_hit_pause.tscn",
		"accent": SparkleLiteDemoPalette.ACCENT_HIT_PAUSE,
		"icon": "res://addons/sparkle_lite/editor/icons/hit_pause.svg",
	},
	{
		"number": "04",
		"title": "Screen Flash 2D",
		"subtitle": "Colored full-viewport flash with ADD / MODULATE blend.",
		"scene": "res://addons/sparkle_lite/samples/scenes/sparklelite_03_screen_flash.tscn",
		"accent": SparkleLiteDemoPalette.GRADIENT_PINK,
		"icon": "res://addons/sparkle_lite/editor/icons/screen_flash_2d.svg",
	},
	{
		"number": "05",
		"title": "Audio",
		"subtitle": "Pooled one-shots with pitch randomisation.",
		"scene": "res://addons/sparkle_lite/samples/scenes/sparklelite_04_audio.tscn",
		"accent": SparkleLiteDemoPalette.ACCENT_AUDIO,
		"icon": "res://addons/sparkle_lite/editor/icons/audio.svg",
	},
	{
		"number": "06",
		"title": "Scale Punch",
		"subtitle": "Elastic scale pop with last-starts-wins per target.",
		"scene": "res://addons/sparkle_lite/samples/scenes/sparklelite_05_scale_punch.tscn",
		"accent": SparkleLiteDemoPalette.ACCENT_SCALE_PUNCH,
		"icon": "res://addons/sparkle_lite/editor/icons/scale_punch.svg",
	},
	{
		"number": "07",
		"title": "Call",
		"subtitle": "Bridge the feedback timeline to your gameplay code.",
		"scene": "res://addons/sparkle_lite/samples/scenes/sparklelite_06_call.tscn",
		"accent": SparkleLiteDemoPalette.ACCENT_CALL,
		"icon": "res://addons/sparkle_lite/editor/icons/call.svg",
	},
	{
		"number": "08",
		"title": "Combined Juicy Shot",
		"subtitle": "Six feedbacks woven into one sequence. The sell.",
		"scene": "res://addons/sparkle_lite/samples/scenes/sparklelite_07_combined.tscn",
		"accent": SparkleLiteDemoPalette.GRADIENT_PURPLE,
		"icon": "",
	},
	{
		"number": "09",
		"title": "Full Runtime API",
		"subtitle": "Build players, feedbacks, and presets in pure code.",
		"scene": "res://addons/sparkle_lite/samples/scenes/sparklelite_08_full_api.tscn",
		"accent": SparkleLiteDemoPalette.ACCENT_CYAN,
		"icon": "",
	},
]


func _ready() -> void:
	SparkleLiteDemoWidgets.paint_page_background(self)
	_build_layout()


func _build_layout() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var outer: MarginContainer = MarginContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override(&"margin_left", 48)
	outer.add_theme_constant_override(&"margin_right", 48)
	outer.add_theme_constant_override(&"margin_top", 40)
	outer.add_theme_constant_override(&"margin_bottom", 40)
	scroll.add_child(outer)

	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 28)
	outer.add_child(column)

	column.add_child(_build_header())
	column.add_child(_build_intro_callout())
	column.add_child(_build_demo_grid())
	column.add_child(_build_footer())


func _build_header() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var logo: TextureRect = TextureRect.new()
	logo.texture = load(_LOGO_PATH) as Texture2D
	logo.custom_minimum_size = Vector2(220, 220)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(logo)

	var text_col: VBoxContainer = VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.add_theme_constant_override(&"separation", 6)
	row.add_child(text_col)

	var title: Label = Label.new()
	title.text = "Sparkle Lite"
	title.add_theme_font_size_override(&"font_size", 44)
	title.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.GRADIENT_PINK)
	text_col.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = (
			"Juice your game in one click. Seven drop-in feedbacks, "
			+ "authored in the inspector, driven by one "
			+ "FeedbackPlayerLite node."
	)
	subtitle.add_theme_font_size_override(&"font_size", 16)
	subtitle.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size = Vector2(520, 0)
	text_col.add_child(subtitle)

	var tagline: Label = Label.new()
	tagline.text = "Pick a card below to see the feedback in action."
	tagline.add_theme_font_size_override(&"font_size", 13)
	tagline.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.ACCENT_CYAN)
	text_col.add_child(tagline)

	return row


func _build_intro_callout() -> Control:
	return SparkleLiteDemoWidgets.make_info_callout(
			"How the demos are structured",
			(
				"• Each demo ships one FeedbackPlayerLite authored in "
				+ "the inspector — open the scene to see the live list.\n"
				+ "• Every script (sparklelite_*.gd) is commented top-to-bottom "
				+ "and highlights the exact API calls it uses.\n"
				+ "• The last demo builds everything from pure code, "
				+ "with no inspector-authored feedbacks at all."
			),
			SparkleLiteDemoPalette.ACCENT_CYAN
	)


func _build_demo_grid() -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 20)
	grid.add_theme_constant_override(&"v_separation", 20)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for demo in _DEMOS:
		grid.add_child(_build_demo_card(demo))
	return grid


func _build_demo_card(demo: Dictionary) -> Control:
	var card: Button = Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(400, 116)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.clip_text = false

	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = SparkleLiteDemoPalette.CARD_BG
	normal.border_color = demo["accent"]
	normal.set_border_width_all(1)
	normal.border_width_left = 6
	normal.set_corner_radius_all(12)
	card.add_theme_stylebox_override(&"normal", normal)

	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = SparkleLiteDemoPalette.PANEL_BG
	hover.border_color = demo["accent"]
	card.add_theme_stylebox_override(&"hover", hover)

	var pressed: StyleBoxFlat = hover.duplicate()
	pressed.bg_color = SparkleLiteDemoPalette.BG
	card.add_theme_stylebox_override(&"pressed", pressed)

	# Button children don't auto-layout — we set full-rect anchors on
	# a MarginContainer that respects the 6 px left accent stripe and
	# leaves visible padding on the other three sides.
	var padding: MarginContainer = MarginContainer.new()
	padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	padding.add_theme_constant_override(&"margin_left", 20)
	padding.add_theme_constant_override(&"margin_right", 18)
	padding.add_theme_constant_override(&"margin_top", 14)
	padding.add_theme_constant_override(&"margin_bottom", 14)
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(padding)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_child(row)

	var icon_holder: PanelContainer = PanelContainer.new()
	icon_holder.custom_minimum_size = Vector2(56, 56)
	icon_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_bg: StyleBoxFlat = StyleBoxFlat.new()
	icon_bg.bg_color = Color(
			demo["accent"].r, demo["accent"].g, demo["accent"].b, 0.15)
	icon_bg.set_corner_radius_all(12)
	icon_bg.set_content_margin_all(8)
	icon_holder.add_theme_stylebox_override(&"panel", icon_bg)
	row.add_child(icon_holder)

	var icon: TextureRect = TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(40, 40)
	icon.modulate = demo["accent"]
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_path: String = demo["icon"]
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path) as Texture2D
	else:
		# Scenes without a per-feedback icon (combined / full-api) get
		# the plugin mark instead.
		icon.texture = load(
				"res://addons/sparkle_lite/icon.svg") as Texture2D
	icon_holder.add_child(icon)

	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override(&"separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var num_title: HBoxContainer = HBoxContainer.new()
	num_title.add_theme_constant_override(&"separation", 10)
	num_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(num_title)

	var number: Label = Label.new()
	number.text = demo["number"]
	number.add_theme_font_size_override(&"font_size", 13)
	number.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	num_title.add_child(number)

	var title: Label = Label.new()
	title.text = demo["title"]
	title.add_theme_font_size_override(&"font_size", 22)
	title.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT)
	num_title.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = demo["subtitle"]
	subtitle.add_theme_font_size_override(&"font_size", 13)
	subtitle.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(subtitle)

	var open: Label = Label.new()
	open.text = "Open \u2192"
	open.add_theme_font_size_override(&"font_size", 13)
	open.add_theme_color_override(&"font_color", demo["accent"])
	open.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(open)

	card.pressed.connect(_on_card_pressed.bind(demo["scene"]))
	return card


func _build_footer() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = SparkleLiteDemoPalette.CARD_BG
	bg.border_color = SparkleLiteDemoPalette.ITCH_PINK
	bg.set_border_width_all(1)
	bg.border_width_bottom = 4
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 24.0
	bg.content_margin_right = 24.0
	bg.content_margin_top = 18.0
	bg.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override(&"panel", bg)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	panel.add_child(row)

	var text_col: VBoxContainer = VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override(&"separation", 2)
	row.add_child(text_col)

	var title: Label = Label.new()
	title.text = "Like Sparkle Lite? Unlock the full plugin."
	title.add_theme_font_size_override(&"font_size", 18)
	title.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT)
	text_col.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = (
			"20+ feedback types, containers, presets, pick-weight "
			+ "randomisation, 2D/3D flashes, emission, and more — on itch.io."
	)
	subtitle.add_theme_font_size_override(&"font_size", 13)
	subtitle.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(subtitle)

	var btn: Button = SparkleLiteDemoWidgets.make_primary_button(
			"Get Sparkle on itch.io",
			SparkleLiteDemoPalette.ITCH_PINK
	)
	btn.custom_minimum_size = Vector2(240, 52)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(_on_itch_pressed)
	row.add_child(btn)

	return panel


func _on_card_pressed(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		push_warning(
				"Sparkle Lite demo: scene not found: %s" % scene_path)
		return
	get_tree().change_scene_to_file(scene_path)


func _on_itch_pressed() -> void:
	OS.shell_open(_ITCH_URL)
