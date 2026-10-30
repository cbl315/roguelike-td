# 04_audio.gd
# Demo 04 — Audio.
#
# What this demo shows:
#   • Seven sound buttons, each fires a scene-authored FeedbackPlayer
#     whose only feedback is a FeedbackAudioLite pointing at a
#     different stream. Pitch is randomised between min/max on every
#     play, so rapid taps never sound robotic.
#   • A loading-mode comparison panel triggers the same sound three
#     times with POOL / CACHE / ONE_TIME allocation so you can hear
#     the difference at machine-gun tempo.
#
# Key concepts:
#   • POOL pre-warms pool_size players and evicts the oldest when the
#     max_simultaneous cap is hit. Safe for shooters and UI alike.
#   • CACHE grows on demand and never evicts (capped at 64 internally).
#     Use for rare-but-long sounds you don't want cut off.
#   • ONE_TIME creates a throw-away player per call. Use for truly
#     fire-and-forget moments.
#
# Pool parents live under the SparkleLitePresets autoload, so audio
# never cuts off when you change scene mid-play.

extends Control

const _CLICK_TITLES: Array[String] = [
	"click-b",
	"tap-a",
	"tap-b",
	"switch-a",
	"switch-b",
	"pop",
	"confetti",
]

const _CLICK_COLORS: Array[Color] = [
	Color("#FFE17A"),
	Color("#FF6FA8"),
	Color("#A24AE2"),
	Color("#4A90E2"),
	Color("#8AF0E8"),
	Color("#FF8A4A"),
	Color("#E24A4A"),
]

@onready var _sound_players: Array[FeedbackPlayerLite] = [
	$Sounds/ClickB,
	$Sounds/TapA,
	$Sounds/TapB,
	$Sounds/SwitchA,
	$Sounds/SwitchB,
	$Sounds/Pop,
	$Sounds/Confetti,
]

@onready var _mode_pool: FeedbackPlayerLite = $ModeCompare/Pool
@onready var _mode_cache: FeedbackPlayerLite = $ModeCompare/Cache
@onready var _mode_one_time: FeedbackPlayerLite = $ModeCompare/OneTime

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
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var outer: MarginContainer = MarginContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override(&"margin_left", 32)
	outer.add_theme_constant_override(&"margin_right", 32)
	outer.add_theme_constant_override(&"margin_top", 24)
	outer.add_theme_constant_override(&"margin_bottom", 24)
	scroll.add_child(outer)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 16)
	outer.add_child(column)

	var header: SparkleLiteDemoHeader = SparkleLiteDemoHeader.new()
	header.title_text = "04 · Audio"
	header.subtitle_text = (
			"Pooled one-shots with pitch randomisation. Rapid clicks "
			+ "land back-to-back without clipping each other off."
	)
	header.accent_color = SparkleLiteDemoPalette.ACCENT_AUDIO
	column.add_child(header)

	column.add_child(SparkleLiteDemoWidgets.make_info_callout(
		"What to try",
		(
			"• Tap any sound rapidly — pitch shifts randomly inside the "
			+ "[pitch_min, pitch_max] window you authored.\n"
			+ "• Hold a button (retrigger) — POOL caps concurrent "
			+ "playbacks at max_simultaneous and evicts the oldest.\n"
			+ "• Mode-compare panel — spam POOL / CACHE / ONE_TIME on "
			+ "the same stream to feel the difference."
		),
		SparkleLiteDemoPalette.ACCENT_AUDIO
	))

	var sound_grid: GridContainer = GridContainer.new()
	sound_grid.columns = 4
	sound_grid.add_theme_constant_override(&"h_separation", 14)
	sound_grid.add_theme_constant_override(&"v_separation", 14)
	column.add_child(sound_grid)
	for i in range(_CLICK_TITLES.size()):
		sound_grid.add_child(_build_sound_button(i))

	var mode_header: Label = Label.new()
	mode_header.text = "Loading modes — same sound, three allocation strategies"
	mode_header.add_theme_font_size_override(&"font_size", 16)
	mode_header.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT)
	column.add_child(mode_header)

	var mode_row: HBoxContainer = HBoxContainer.new()
	mode_row.add_theme_constant_override(&"separation", 12)
	column.add_child(mode_row)

	mode_row.add_child(_build_mode_card(
		"POOL",
		"Fixed pre-warm, evicts oldest at cap.",
		SparkleLiteDemoPalette.ACCENT_CYAN,
		_on_mode_pool_pressed
	))
	mode_row.add_child(_build_mode_card(
		"CACHE",
		"Grows on demand, never evicts (cap 64).",
		SparkleLiteDemoPalette.GRADIENT_PURPLE,
		_on_mode_cache_pressed
	))
	mode_row.add_child(_build_mode_card(
		"ONE_TIME",
		"Fresh player per call, freed when done.",
		SparkleLiteDemoPalette.ACCENT_WARM,
		_on_mode_one_time_pressed
	))

	_status_label = Label.new()
	_status_label.text = "Tap any sound to play."
	_status_label.add_theme_font_size_override(&"font_size", 13)
	_status_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	column.add_child(_status_label)

	column.add_child(SparkleLiteDemoWidgets.make_code_block(
		"Equivalent runtime code",
		(
			"# Build a FeedbackAudioLite in pure code and play it:\n"
			+ "var pop := FeedbackAudioLite.new()\n"
			+ "pop.stream = preload(\"res://addons/sparkle_lite/samples/assets/sounds/sparklelite_pop.mp3\")\n"
			+ "pop.volume_db = -2.0\n"
			+ "pop.pitch_min = 0.85\n"
			+ "pop.pitch_max = 1.15\n"
			+ "pop.loading_mode = FeedbackAudioLite.LoadingMode.POOL\n"
			+ "pop.pool_size = 6\n"
			+ "pop.max_simultaneous = 6\n\n"
			+ "$Sounds/Pop.clear_feedbacks()\n"
			+ "$Sounds/Pop.add_feedback(pop)\n"
			+ "$Sounds/Pop.play()"
		),
		SparkleLiteDemoPalette.ACCENT_AUDIO
	))


func _build_sound_button(index: int) -> Control:
	var color: Color = _CLICK_COLORS[index]
	var btn: Button = SparkleLiteDemoWidgets.make_primary_button(
			_CLICK_TITLES[index], color)
	btn.custom_minimum_size = Vector2(160, 64)
	btn.pressed.connect(_on_sound_pressed.bind(index))
	return btn


func _build_mode_card(
		title: String,
		body: String,
		accent: Color,
		handler: Callable
) -> Control:
	var card: PanelContainer = PanelContainer.new()
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = SparkleLiteDemoPalette.CARD_BG
	bg.border_color = accent
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(10)
	bg.content_margin_left = 16.0
	bg.content_margin_right = 16.0
	bg.content_margin_top = 14.0
	bg.content_margin_bottom = 14.0
	card.add_theme_stylebox_override(&"panel", bg)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	card.add_child(col)

	var title_lbl: Label = Label.new()
	title_lbl.text = title
	title_lbl.add_theme_color_override(&"font_color", accent)
	title_lbl.add_theme_font_size_override(&"font_size", 18)
	col.add_child(title_lbl)

	var body_lbl: Label = Label.new()
	body_lbl.text = body
	body_lbl.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	body_lbl.add_theme_font_size_override(&"font_size", 12)
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body_lbl)

	var btn: Button = SparkleLiteDemoWidgets.make_primary_button(
			"Spam (×6)", accent)
	btn.custom_minimum_size = Vector2(0, 40)
	btn.pressed.connect(handler)
	col.add_child(btn)
	return card


# --- Button handlers -------------------------------------------------

func _on_sound_pressed(index: int) -> void:
	_sound_players[index].play()
	_status_label.text = "Played: %s (pitch randomised)" % _CLICK_TITLES[index]


func _on_mode_pool_pressed() -> void:
	_burst(_mode_pool, "POOL")


func _on_mode_cache_pressed() -> void:
	_burst(_mode_cache, "CACHE")


func _on_mode_one_time_pressed() -> void:
	_burst(_mode_one_time, "ONE_TIME")


func _burst(player: FeedbackPlayerLite, mode_name: String) -> void:
	for i in range(6):
		# Stagger six plays 40 ms apart so you can hear the allocation
		# behaviour without them landing on the same frame.
		get_tree().create_timer(i * 0.04).timeout.connect(func() -> void:
			if is_instance_valid(player):
				player.play()
		)
	_status_label.text = "Burst of 6 on %s mode." % mode_name
