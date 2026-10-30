# 05_scale_punch.gd
# Demo 05 — Scale Punch.
#
# What this demo shows:
#   • Four candy cards, each driven by a scene-authored FeedbackPlayer
#     whose FeedbackScalePunchLite targets that specific Control via
#     a NodePath.
#   • Click a candy — it pops. Click it again before the pop finishes
#     — the previous runner stops, the new one starts from the baseline
#     (last-starts-wins per target).
#   • "Punch All" fires every player in the same frame for a kick-line
#     effect.
#
# Key concepts:
#   • target is a NodePath. If empty, the punch applies to the player
#     itself (requires the player to be a Node2D / Node3D / Control —
#     FeedbackPlayerLite is a plain Node, so an explicit target is
#     required for Control / sprite work).
#   • Scale punch caches the baseline scale on first play and restores
#     it on completion. Safe to retrigger while the pop is running.

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
	"Upgrade 1 (light pop)",
	"Upgrade 2 (default pop)",
	"Upgrade 3 (heavy pop)",
	"Rainbow (long pop)",
]

@onready var _players: Array[FeedbackPlayerLite] = [
	$Players/PunchPlayer1,
	$Players/PunchPlayer2,
	$Players/PunchPlayer3,
	$Players/PunchPlayer4,
]

@onready var _candies: Array[Button] = [
	$CandyRow/Candy1,
	$CandyRow/Candy2,
	$CandyRow/Candy3,
	$CandyRow/Candy4,
]

var _status_label: Label
var _click_counter: int = 0


func _ready() -> void:
	SparkleLiteDemoWidgets.paint_page_background(self)
	_build_ui()
	_decorate_candies()
	# _build_ui() re-parented the CandyRow under the UI column, which
	# invalidates the NodePath("../../CandyRow/CandyN") targets authored
	# in the .tscn. Re-wire each ScalePunch's target to the candy's
	# new path so it resolves at play time.
	_wire_punch_targets()


func _wire_punch_targets() -> void:
	for i in range(_players.size()):
		var player: FeedbackPlayerLite = _players[i]
		var candy: Button = _candies[i]
		if player == null or candy == null:
			continue
		var path: NodePath = player.get_path_to(candy)
		for fb in player.feedbacks:
			if fb is FeedbackScalePunchLite:
				(fb as FeedbackScalePunchLite).target = path


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
	header.title_text = "05 · Scale Punch"
	header.subtitle_text = (
			"Elastic scale pop on UI candies. Rapid-clicking the same "
			+ "card cancels the running pop and starts a fresh one."
	)
	header.accent_color = SparkleLiteDemoPalette.ACCENT_SCALE_PUNCH
	column.add_child(header)

	column.add_child(SparkleLiteDemoWidgets.make_info_callout(
		"What to try",
		(
			"• Click any candy — its FeedbackPlayer fires a scale punch "
			+ "targeted at that Control.\n"
			+ "• Click the same candy rapidly — the last press wins; the "
			+ "running runner is cancelled and the punch restarts.\n"
			+ "• Punch All — every player fires in the same frame, each "
			+ "pointed at its own target."
		),
		SparkleLiteDemoPalette.ACCENT_SCALE_PUNCH
	))

	# The candy row lives in the .tscn at $CandyRow; we re-parent it
	# under the UI column here so it participates in the vertical flow.
	var candy_row: HBoxContainer = $CandyRow
	remove_child(candy_row)
	column.add_child(candy_row)

	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override(&"separation", 12)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(controls)

	var punch_all: Button = SparkleLiteDemoWidgets.make_primary_button(
			"Punch All", SparkleLiteDemoPalette.ACCENT_SCALE_PUNCH)
	punch_all.pressed.connect(_on_punch_all_pressed)
	controls.add_child(punch_all)

	var rapid: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Rapid-Fire Candy 1 (×10)",
			SparkleLiteDemoPalette.ACCENT_SCALE_PUNCH)
	rapid.pressed.connect(_on_rapid_pressed)
	controls.add_child(rapid)

	_status_label = Label.new()
	_status_label.text = "Ready."
	_status_label.add_theme_font_size_override(&"font_size", 13)
	_status_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	column.add_child(_status_label)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	column.add_child(SparkleLiteDemoWidgets.make_code_block(
		"Equivalent runtime code",
		(
			"# Build a punch in code and target a specific Control:\n"
			+ "var punch := FeedbackScalePunchLite.new()\n"
			+ "punch.target = NodePath(\"../CandyRow/Candy2\")\n"
			+ "punch.punch_scale = Vector3(1.25, 1.25, 1.0)\n"
			+ "punch.elasticity = 0.4\n"
			+ "punch.duration_ms = 420.0\n\n"
			+ "$Players/PunchPlayer2.clear_feedbacks()\n"
			+ "$Players/PunchPlayer2.add_feedback(punch)\n"
			+ "$Players/PunchPlayer2.play()"
		),
		SparkleLiteDemoPalette.ACCENT_SCALE_PUNCH
	))


func _decorate_candies() -> void:
	for i in range(_candies.size()):
		var btn: Button = _candies[i]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(200, 240)
		btn.clip_text = true
		btn.pivot_offset = btn.custom_minimum_size * 0.5

		var color: Color = _CANDY_COLORS[i]
		var normal: StyleBoxFlat = StyleBoxFlat.new()
		normal.bg_color = SparkleLiteDemoPalette.CARD_BG
		normal.border_color = color
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(18)
		normal.set_content_margin_all(12)
		btn.add_theme_stylebox_override(&"normal", normal)
		var hover: StyleBoxFlat = normal.duplicate()
		hover.bg_color = SparkleLiteDemoPalette.PANEL_BG
		btn.add_theme_stylebox_override(&"hover", hover)
		var pressed: StyleBoxFlat = hover.duplicate()
		pressed.bg_color = SparkleLiteDemoPalette.BG
		btn.add_theme_stylebox_override(&"pressed", pressed)

		var col: VBoxContainer = VBoxContainer.new()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override(&"separation", 10)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(col)

		var icon: TextureRect = TextureRect.new()
		icon.texture = load(_CANDY_PATHS[i]) as Texture2D
		icon.custom_minimum_size = Vector2(0, 140)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(icon)

		var label: Label = Label.new()
		label.text = _CANDY_LABELS[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override(&"font_color", color)
		label.add_theme_font_size_override(&"font_size", 13)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(label)

		btn.pressed.connect(_on_candy_pressed.bind(i))


# --- Button handlers -------------------------------------------------

func _on_candy_pressed(index: int) -> void:
	_players[index].play()
	_click_counter += 1
	_status_label.text = (
			"Clicked %s — play() #%d (last-starts-wins on retrigger)"
			% [_CANDY_LABELS[index], _click_counter]
	)


func _on_punch_all_pressed() -> void:
	for player in _players:
		player.play()
	_status_label.text = "All four players fired in the same frame."


func _on_rapid_pressed() -> void:
	# 10 plays at 40 ms apart — shorter than the punch duration, so
	# you will see the first candy visibly "breathe" as each new call
	# cancels the previous runner and restarts from baseline.
	for i in range(10):
		get_tree().create_timer(i * 0.04).timeout.connect(func() -> void:
			if is_instance_valid(_players[0]):
				_players[0].play()
		)
	_status_label.text = (
			"Rapid-fire burst on Candy 1 — watch the last-starts-wins "
			+ "behaviour prevent stacking."
	)
