# 06_call.gd
# Demo 06 — Call.
#
# What this demo shows:
#   • A scene-authored upgrade sequence. Every step is a
#     FeedbackCallLite — no other feedback types — so the focus is
#     on how Call connects the sequence timeline to gameplay code.
#   • CALL_METHOD at 0/220/440 ms swaps the candy sprite between
#     stages by invoking set_stage_2/3/rainbow() on the demo root.
#   • EMIT_SIGNAL at 700 ms fires "upgrade_finished(stage)" so any
#     listener — analytics, achievement code, UI — can react.
#
# Key concepts:
#   • FeedbackCallLite.target is a NodePath resolved relative to the
#     player first, then the current scene. Empty means "the player".
#   • method_or_signal must exist on the target. Missing names warn
#     once and skip (no crashes).
#   • Calls are skipped during editor preview so designers don't
#     accidentally mutate save state. Runtime only.

extends Control

const _CANDY_STAGES: Array[String] = [
	"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_1.png",
	"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_2.png",
	"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_3.png",
	"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_special_rain.png",
]

signal upgrade_finished(final_stage: int)

@onready var _upgrade_player: FeedbackPlayerLite = $UpgradePlayer
@onready var _signal_player: FeedbackPlayerLite = $SignalPlayer

var _stage: int = 0
var _candy_sprite: TextureRect
var _stage_label: Label
var _status_label: Label
var _log_label: Label
var _log_lines: Array[String] = []
var _pulse_tween: Tween


func _ready() -> void:
	SparkleLiteDemoWidgets.paint_page_background(self)
	_build_ui()
	_apply_stage(0)
	upgrade_finished.connect(_on_upgrade_finished_signal)


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
	header.title_text = "06 · Call"
	header.subtitle_text = (
			"Bridge the feedback timeline to gameplay code. Every "
			+ "entry in the scene-authored sequence is a FeedbackCallLite."
	)
	header.accent_color = SparkleLiteDemoPalette.ACCENT_CALL
	column.add_child(header)

	column.add_child(SparkleLiteDemoWidgets.make_info_callout(
		"What to try",
		(
			"• Upgrade Sequence — three CALL_METHOD entries (0 / 220 / "
			+ "440 ms) invoke set_stage_N() on this demo script, "
			+ "advancing the candy sprite between stages.\n"
			+ "• Emit Finished Signal — a single EMIT_SIGNAL entry at "
			+ "500 ms fires \"upgrade_finished(stage)\" — handled below "
			+ "and logged to the console area.\n"
			+ "• Reset — pushes the candy back to stage 1."
		),
		SparkleLiteDemoPalette.ACCENT_CALL
	))

	var candy_host: CenterContainer = CenterContainer.new()
	candy_host.custom_minimum_size = Vector2(0, 240)
	column.add_child(candy_host)

	var candy_col: VBoxContainer = VBoxContainer.new()
	candy_col.add_theme_constant_override(&"separation", 6)
	candy_host.add_child(candy_col)

	_candy_sprite = TextureRect.new()
	_candy_sprite.custom_minimum_size = Vector2(180, 180)
	_candy_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_candy_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_candy_sprite.pivot_offset = Vector2(90, 90)
	candy_col.add_child(_candy_sprite)

	_stage_label = Label.new()
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_label.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT)
	_stage_label.add_theme_font_size_override(&"font_size", 18)
	candy_col.add_child(_stage_label)

	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override(&"separation", 12)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(controls)

	var upgrade_btn: Button = SparkleLiteDemoWidgets.make_primary_button(
			"Upgrade Sequence (CALL_METHOD)",
			SparkleLiteDemoPalette.ACCENT_CALL)
	upgrade_btn.pressed.connect(_on_upgrade_pressed)
	controls.add_child(upgrade_btn)

	var emit_btn: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Emit Finished Signal",
			SparkleLiteDemoPalette.ACCENT_CALL)
	emit_btn.pressed.connect(_on_emit_pressed)
	controls.add_child(emit_btn)

	var reset_btn: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Reset", SparkleLiteDemoPalette.TEXT_MUTED)
	reset_btn.pressed.connect(_on_reset_pressed)
	controls.add_child(reset_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override(&"font_size", 13)
	_status_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	column.add_child(_status_label)

	_log_label = Label.new()
	_log_label.add_theme_font_size_override(&"font_size", 12)
	_log_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.CODE_TEXT)
	column.add_child(_log_label)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	column.add_child(SparkleLiteDemoWidgets.make_code_block(
		"Equivalent runtime code",
		(
			"# CALL_METHOD — scene points at set_stage_2() on this demo:\n"
			+ "var call := FeedbackCallLite.new()\n"
			+ "call.delay_ms = 220.0\n"
			+ "call.mode = FeedbackCallLite.CallMode.CALL_METHOD\n"
			+ "call.target = NodePath(\"..\")         # demo root\n"
			+ "call.method_or_signal = &\"set_stage_2\"\n"
			+ "call.arguments = []\n\n"
			+ "# EMIT_SIGNAL — the demo exposes upgrade_finished(stage):\n"
			+ "var sig := FeedbackCallLite.new()\n"
			+ "sig.delay_ms = 500.0\n"
			+ "sig.mode = FeedbackCallLite.CallMode.EMIT_SIGNAL\n"
			+ "sig.target = NodePath(\"..\")\n"
			+ "sig.method_or_signal = &\"upgrade_finished\"\n"
			+ "sig.arguments = [3]                    # passed to handlers"
		),
		SparkleLiteDemoPalette.ACCENT_CALL
	))


# --- Button handlers -------------------------------------------------

func _on_upgrade_pressed() -> void:
	_apply_stage(0)
	_log("play() — upgrade sequence")
	_upgrade_player.play()


func _on_emit_pressed() -> void:
	_log("play() — signal-only sequence")
	_signal_player.play()


func _on_reset_pressed() -> void:
	_apply_stage(0)
	_log("Reset to stage 1.")


# --- Methods invoked by FeedbackCallLite (CALL_METHOD) ---------------

func set_stage_1() -> void:
	_apply_stage(0)
	_log("set_stage_1() received (CALL_METHOD)")


func set_stage_2() -> void:
	_apply_stage(1)
	_log("set_stage_2() received (CALL_METHOD)")


func set_stage_3() -> void:
	_apply_stage(2)
	_log("set_stage_3() received (CALL_METHOD)")


func set_stage_rainbow() -> void:
	_apply_stage(3)
	_log("set_stage_rainbow() received (CALL_METHOD)")


func emit_done_for_stage(stage: int) -> void:
	# Helper the signal sequence calls with CALL_METHOD before it
	# fires the actual signal — demonstrates the same player mixing
	# CALL_METHOD and EMIT_SIGNAL entries.
	upgrade_finished.emit(stage)


# --- Signal handler (EMIT_SIGNAL path) -------------------------------

func _on_upgrade_finished_signal(final_stage: int) -> void:
	_log("upgrade_finished(%d) received (EMIT_SIGNAL)" % final_stage)


# --- Helpers ---------------------------------------------------------

func _apply_stage(stage: int) -> void:
	_stage = stage
	if _candy_sprite != null:
		_candy_sprite.texture = load(_CANDY_STAGES[stage]) as Texture2D
		_pulse()
	if _stage_label != null:
		_stage_label.text = "Stage %d" % (stage + 1)
	if _status_label != null:
		_status_label.text = "Stage %d" % (stage + 1)


func _pulse() -> void:
	# Pure cosmetic tween — nothing to do with Sparkle Lite. Makes the
	# sprite swap read visually so you see *when* the call fires.
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_candy_sprite.scale = Vector2(1.2, 1.2)
	_pulse_tween = create_tween()
	_pulse_tween.set_trans(Tween.TRANS_ELASTIC)
	_pulse_tween.set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(
			_candy_sprite, "scale", Vector2.ONE, 0.3)


func _log(line: String) -> void:
	_log_lines.append("• %s" % line)
	while _log_lines.size() > 6:
		_log_lines.pop_front()
	if _log_label != null:
		_log_label.text = "\n".join(_log_lines)
