# 08_full_api.gd
# Demo 08 — Full Runtime API.
#
# What this demo shows:
#   • The FeedbackPlayerLite is created in code — this scene ships with
#     NO inspector-authored feedbacks. Everything you see is built via
#     FeedbackPlayerLite.new() + add_feedback(...).
#   • Three "recipes" rebuild the feedback list at runtime with
#     clear_feedbacks() + add_feedback(). Swapping feedback stacks mid-
#     session is a one-liner.
#   • A live log panel taps the player's signals — started, completed,
#     feedback_started(index), feedback_completed(index) — so you can
#     see exactly what fired and when.
#   • is_playing() and get_total_duration() drive the status row.
#
# Use this as the reference for any runtime scenario: spawning players
# for freshly-created actors, swapping feedback stacks per weapon /
# skill, letting the server push a feedback recipe down to the client
# as JSON, etc.

extends Control

const _CANDY_STAGE_1: String = "res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_1.png"
const _CANDY_STAGE_3: String = "res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_3.png"
const _LOG_MAX_LINES: int = 10

var _player: FeedbackPlayerLite
var _candy_display: TextureRect
var _status_label: Label
var _duration_label: Label
var _recipe_label: Label
var _log_label: Label
var _log_lines: Array[String] = []
var _current_recipe: String = "(none)"


func _ready() -> void:
	SparkleLiteDemoWidgets.paint_page_background(self)
	_build_ui()
	_build_player()
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event
		if key.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://addons/sparkle_lite/samples/sparklelite_main.tscn")


func _process(_delta: float) -> void:
	_update_status()


# --- Runtime player --------------------------------------------------

func _build_player() -> void:
	# Everything below is what this demo is about. Two lines to have a
	# fully working player; zero .tscn involvement.
	_player = FeedbackPlayerLite.new()
	_player.name = &"RuntimePlayer"
	add_child(_player)

	# Full signal set is available out of the box. Connect whatever you
	# care about — we connect all four here so the log panel can narrate.
	_player.started.connect(_on_started)
	_player.completed.connect(_on_completed)
	_player.feedback_started.connect(_on_feedback_started)
	_player.feedback_completed.connect(_on_feedback_completed)


# --- Recipes ---------------------------------------------------------

func _on_recipe_pop_pressed() -> void:
	# Recipe 1: Audio + Scale Punch, both at delay 0. Shows parallel
	# execution: two feedbacks firing on the same frame, different
	# targets, no sequencing work by the caller.
	_player.clear_feedbacks()

	var audio: FeedbackAudioLite = FeedbackAudioLite.new()
	audio.label = "Pop sound"
	audio.stream = load(
			"res://addons/sparkle_lite/samples/assets/sounds/sparklelite_pop.mp3") as AudioStream
	audio.volume_db = -3.0
	audio.pitch_min = 0.85
	audio.pitch_max = 1.15
	audio.loading_mode = FeedbackAudioLite.LoadingMode.POOL
	audio.pool_size = 4
	audio.max_simultaneous = 4
	_player.add_feedback(audio)

	var punch: FeedbackScalePunchLite = FeedbackScalePunchLite.new()
	punch.label = "Candy pop"
	punch.duration_ms = 500.0
	punch.punch_scale = Vector3(1.4, 1.4, 1.0)
	punch.elasticity = 0.55
	punch.use_unscaled_time = true
	punch.target = _player.get_path_to(_candy_display)
	_player.add_feedback(punch)

	_current_recipe = "Quick Pop (Audio + Scale Punch)"
	_recipe_label.text = "Recipe: %s" % _current_recipe
	_append_log("Built: Quick Pop (%d feedbacks)" % _player.feedbacks.size())


func _on_recipe_sequence_pressed() -> void:
	# Recipe 2: staggered sequence. Each feedback has a different delay,
	# so they fire like beats on a drum — the player itself does the
	# timing, no Timer / await dance in user code.
	_player.clear_feedbacks()

	var flash_a: FeedbackScreenFlash2DLite = FeedbackScreenFlash2DLite.new()
	flash_a.label = "Opening flash"
	flash_a.flash_color = Color(0.541, 0.941, 0.91, 1.0)
	flash_a.flash_intensity = 0.3
	flash_a.fade_in_duration_ms = 30.0
	flash_a.hold_duration_ms = 20.0
	flash_a.fade_out_duration_ms = 200.0
	flash_a.blend_mode = FeedbackScreenFlash2DLite.BlendMode.ADD
	_player.add_feedback(flash_a)

	var call: FeedbackCallLite = FeedbackCallLite.new()
	call.label = "Swap candy"
	call.delay_ms = 220.0
	call.mode = FeedbackCallLite.CallMode.CALL_METHOD
	call.target = _player.get_path_to(self)
	call.method_or_signal = &"upgrade_candy"
	_player.add_feedback(call)

	var audio: FeedbackAudioLite = FeedbackAudioLite.new()
	audio.label = "Confetti"
	audio.delay_ms = 220.0
	audio.stream = load(
			"res://addons/sparkle_lite/samples/assets/sounds/sparklelite_confetti_pop.mp3") as AudioStream
	audio.pitch_min = 0.9
	audio.pitch_max = 1.1
	audio.loading_mode = FeedbackAudioLite.LoadingMode.POOL
	audio.pool_size = 2
	audio.max_simultaneous = 2
	_player.add_feedback(audio)

	var flash_b: FeedbackScreenFlash2DLite = FeedbackScreenFlash2DLite.new()
	flash_b.label = "Closing flash"
	flash_b.delay_ms = 450.0
	flash_b.flash_color = Color(1.0, 0.435, 0.659, 1.0)
	flash_b.flash_intensity = 0.22
	flash_b.fade_in_duration_ms = 40.0
	flash_b.hold_duration_ms = 20.0
	flash_b.fade_out_duration_ms = 280.0
	flash_b.blend_mode = FeedbackScreenFlash2DLite.BlendMode.ADD
	_player.add_feedback(flash_b)

	_current_recipe = "Sequence (4 feedbacks, 0 / 220 / 450 ms)"
	_recipe_label.text = "Recipe: %s" % _current_recipe
	_append_log("Built: Sequence (%d feedbacks)" % _player.feedbacks.size())


func _on_recipe_impact_pressed() -> void:
	# Recipe 3: 2D hit impact. Flash + Audio fire immediately; 80 ms in,
	# the hit pause drops time_scale and the scale punch pops with
	# use_unscaled_time so it reads through the freeze.
	_player.clear_feedbacks()

	var flash: FeedbackScreenFlash2DLite = FeedbackScreenFlash2DLite.new()
	flash.label = "Impact flash"
	flash.flash_color = Color(1.0, 0.92, 0.55, 1.0)
	flash.flash_intensity = 0.35
	flash.fade_in_duration_ms = 20.0
	flash.hold_duration_ms = 40.0
	flash.fade_out_duration_ms = 220.0
	flash.blend_mode = FeedbackScreenFlash2DLite.BlendMode.ADD
	_player.add_feedback(flash)

	var audio: FeedbackAudioLite = FeedbackAudioLite.new()
	audio.label = "Impact"
	audio.stream = load(
			"res://addons/sparkle_lite/samples/assets/sounds/sparklelite_pop.mp3") as AudioStream
	audio.volume_db = -1.0
	audio.pitch_min = 0.8
	audio.pitch_max = 0.95
	audio.loading_mode = FeedbackAudioLite.LoadingMode.POOL
	audio.pool_size = 3
	audio.max_simultaneous = 3
	_player.add_feedback(audio)

	var pause: FeedbackHitPauseLite = FeedbackHitPauseLite.new()
	pause.label = "Hit-stop"
	pause.delay_ms = 80.0
	pause.duration_ms = 140.0
	pause.time_scale_during_pause = 0.05
	_player.add_feedback(pause)

	var punch: FeedbackScalePunchLite = FeedbackScalePunchLite.new()
	punch.label = "Candy pop (survives pause)"
	punch.delay_ms = 80.0
	punch.duration_ms = 600.0
	punch.punch_scale = Vector3(1.5, 1.5, 1.0)
	punch.elasticity = 0.6
	punch.use_unscaled_time = true
	punch.target = _player.get_path_to(_candy_display)
	_player.add_feedback(punch)

	_current_recipe = "Hit Impact (Flash + Audio + Hit Pause + Punch)"
	_recipe_label.text = "Recipe: %s" % _current_recipe
	_append_log("Built: Hit Impact (%d feedbacks)" % _player.feedbacks.size())


# --- Transport -------------------------------------------------------

func _on_play_pressed() -> void:
	if _player.feedbacks.is_empty():
		_append_log("play() skipped — no recipe built yet")
		return
	_player.play()


func _on_play_half_pressed() -> void:
	if _player.feedbacks.is_empty():
		_append_log("play(0.5) skipped — no recipe built yet")
		return
	_player.play(0.5)


func _on_stop_pressed() -> void:
	_player.stop()
	_append_log("stop() called")


func _on_reset_pressed() -> void:
	_apply_stage(_CANDY_STAGE_1)
	_append_log("Candy reset to stage 1.")


# --- Call targets ----------------------------------------------------

func upgrade_candy() -> void:
	# Invoked by the CALL_METHOD feedback inside the Sequence recipe.
	_apply_stage(_CANDY_STAGE_3)
	_append_log("upgrade_candy() invoked (CALL_METHOD)")


# --- Signal handlers -------------------------------------------------

func _on_started() -> void:
	_append_log("▶ started — %d feedbacks, %.0f ms total" % [
			_player.feedbacks.size(),
			_player.get_total_duration() * 1000.0
	])


func _on_completed() -> void:
	_append_log("■ completed")


func _on_feedback_started(index: int) -> void:
	var fb: FeedbackBaseLite = _player.feedbacks[index]
	_append_log("  → [%d] %s started" % [index, fb.get_display_label()])


func _on_feedback_completed(index: int) -> void:
	var fb: FeedbackBaseLite = _player.feedbacks[index]
	_append_log("  ← [%d] %s completed" % [index, fb.get_display_label()])


# --- UI --------------------------------------------------------------

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
	column.add_theme_constant_override(&"separation", 14)
	outer.add_child(column)

	var header: SparkleLiteDemoHeader = SparkleLiteDemoHeader.new()
	header.title_text = "08 · Full Runtime API"
	header.subtitle_text = (
			"No inspector-authored feedbacks. Build the player and its "
			+ "feedback stack entirely from GDScript."
	)
	header.accent_color = SparkleLiteDemoPalette.ACCENT_CYAN
	column.add_child(header)

	column.add_child(SparkleLiteDemoWidgets.make_info_callout(
		"What to try",
		(
			"• Build a recipe — rebuilds the feedback list via "
			+ "clear_feedbacks() + add_feedback(...).\n"
			+ "• Play / Play @ 0.5x — one call fires the current stack "
			+ "at full or scaled intensity.\n"
			+ "• Stop — cancels every active feedback immediately.\n"
			+ "• The log panel taps all four player signals — you can "
			+ "see every feedback start and finish in real time."
		),
		SparkleLiteDemoPalette.ACCENT_CYAN
	))

	var candy_host: CenterContainer = CenterContainer.new()
	candy_host.custom_minimum_size = Vector2(0, 200)
	column.add_child(candy_host)

	var candy_card: PanelContainer = PanelContainer.new()
	var candy_bg: StyleBoxFlat = StyleBoxFlat.new()
	candy_bg.bg_color = SparkleLiteDemoPalette.CARD_BG
	candy_bg.border_color = SparkleLiteDemoPalette.ACCENT_CYAN
	candy_bg.set_border_width_all(2)
	candy_bg.set_corner_radius_all(14)
	candy_bg.set_content_margin_all(16)
	candy_card.add_theme_stylebox_override(&"panel", candy_bg)
	candy_host.add_child(candy_card)

	_candy_display = TextureRect.new()
	_candy_display.custom_minimum_size = Vector2(160, 160)
	_candy_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_candy_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_candy_display.pivot_offset = Vector2(80, 80)
	_candy_display.texture = load(_CANDY_STAGE_1) as Texture2D
	candy_card.add_child(_candy_display)

	var recipes_header: Label = Label.new()
	recipes_header.text = "Recipes (build & swap the feedback list)"
	recipes_header.add_theme_font_size_override(&"font_size", 15)
	recipes_header.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT)
	column.add_child(recipes_header)

	var recipe_row: HBoxContainer = HBoxContainer.new()
	recipe_row.add_theme_constant_override(&"separation", 10)
	column.add_child(recipe_row)

	var btn_pop: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Quick Pop", SparkleLiteDemoPalette.GRADIENT_YELLOW)
	btn_pop.pressed.connect(_on_recipe_pop_pressed)
	recipe_row.add_child(btn_pop)

	var btn_seq: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Sequence", SparkleLiteDemoPalette.GRADIENT_PINK)
	btn_seq.pressed.connect(_on_recipe_sequence_pressed)
	recipe_row.add_child(btn_seq)

	var btn_imp: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Hit Impact", SparkleLiteDemoPalette.GRADIENT_PURPLE)
	btn_imp.pressed.connect(_on_recipe_impact_pressed)
	recipe_row.add_child(btn_imp)

	var transport_header: Label = Label.new()
	transport_header.text = "Transport"
	transport_header.add_theme_font_size_override(&"font_size", 15)
	transport_header.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT)
	column.add_child(transport_header)

	var transport_row: HBoxContainer = HBoxContainer.new()
	transport_row.add_theme_constant_override(&"separation", 10)
	column.add_child(transport_row)

	var btn_play: Button = SparkleLiteDemoWidgets.make_primary_button(
			"Play", SparkleLiteDemoPalette.ACCENT_CYAN)
	btn_play.pressed.connect(_on_play_pressed)
	transport_row.add_child(btn_play)

	var btn_play_half: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Play @ 0.5x", SparkleLiteDemoPalette.ACCENT_CYAN)
	btn_play_half.pressed.connect(_on_play_half_pressed)
	transport_row.add_child(btn_play_half)

	var btn_stop: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Stop", SparkleLiteDemoPalette.ITCH_PINK)
	btn_stop.pressed.connect(_on_stop_pressed)
	transport_row.add_child(btn_stop)

	var btn_reset: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Reset Candy", SparkleLiteDemoPalette.TEXT_MUTED)
	btn_reset.pressed.connect(_on_reset_pressed)
	transport_row.add_child(btn_reset)

	_recipe_label = Label.new()
	_recipe_label.text = "Recipe: (none built yet)"
	_recipe_label.add_theme_font_size_override(&"font_size", 13)
	_recipe_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.ACCENT_CYAN)
	column.add_child(_recipe_label)

	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.add_theme_constant_override(&"separation", 20)
	column.add_child(status_row)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override(&"font_size", 13)
	_status_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	status_row.add_child(_status_label)

	_duration_label = Label.new()
	_duration_label.add_theme_font_size_override(&"font_size", 13)
	_duration_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	status_row.add_child(_duration_label)

	var log_title: Label = Label.new()
	log_title.text = "Player signal log"
	log_title.add_theme_font_size_override(&"font_size", 13)
	log_title.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT)
	column.add_child(log_title)

	var log_panel: PanelContainer = PanelContainer.new()
	var log_bg: StyleBoxFlat = StyleBoxFlat.new()
	log_bg.bg_color = SparkleLiteDemoPalette.CARD_BG
	log_bg.border_color = SparkleLiteDemoPalette.STROKE
	log_bg.set_border_width_all(1)
	log_bg.set_corner_radius_all(8)
	log_bg.set_content_margin_all(10)
	log_panel.add_theme_stylebox_override(&"panel", log_bg)
	column.add_child(log_panel)

	_log_label = Label.new()
	_log_label.custom_minimum_size = Vector2(0, 170)
	_log_label.add_theme_font_size_override(&"font_size", 12)
	_log_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.CODE_TEXT)
	_log_label.text = "(empty — build a recipe and press Play)"
	log_panel.add_child(_log_label)

	column.add_child(SparkleLiteDemoWidgets.make_code_block(
		"Equivalent runtime code",
		(
			"# Full runtime construction — this scene has ZERO feedbacks\n"
			+ "# authored in the inspector. Everything below is code.\n\n"
			+ "var player := FeedbackPlayerLite.new()\n"
			+ "add_child(player)\n"
			+ "player.completed.connect(func(): print(\"done\"))\n\n"
			+ "var audio := FeedbackAudioLite.new()\n"
			+ "audio.stream = load(\"res://sfx/pop.mp3\")\n"
			+ "audio.pitch_min = 0.85\n"
			+ "audio.pitch_max = 1.15\n"
			+ "audio.loading_mode = FeedbackAudioLite.LoadingMode.POOL\n"
			+ "player.add_feedback(audio)\n\n"
			+ "var punch := FeedbackScalePunchLite.new()\n"
			+ "punch.punch_scale = Vector3(1.4, 1.4, 1.0)\n"
			+ "punch.elasticity = 0.55\n"
			+ "punch.target = player.get_path_to(target_ctrl)\n"
			+ "player.add_feedback(punch)\n\n"
			+ "# Camera shake example (needs an active Camera3D):\n"
			+ "var shake := FeedbackCameraShakeLite.new()\n"
			+ "shake.duration_ms = 400.0\n"
			+ "shake.rotation_amplitude = Vector3(0, 0, 2.5)\n"
			+ "player.add_feedback(shake)\n\n"
			+ "player.play()                 # fire the whole stack\n"
			+ "player.play(1.5)              # with intensity\n"
			+ "player.stop()                 # cancel in-flight\n"
			+ "player.clear_feedbacks()      # rebuild from scratch"
		),
		SparkleLiteDemoPalette.ACCENT_CYAN
	))


# --- Helpers ---------------------------------------------------------

func _apply_stage(path: String) -> void:
	if _candy_display == null:
		return
	_candy_display.texture = load(path) as Texture2D


func _append_log(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > _LOG_MAX_LINES:
		_log_lines.pop_front()
	if _log_label != null:
		_log_label.text = "\n".join(_log_lines)


func _update_status() -> void:
	if _player == null:
		return
	if _status_label != null:
		if _player.is_playing():
			_status_label.text = "is_playing(): true"
		else:
			_status_label.text = "is_playing(): false"
	if _duration_label != null:
		var duration: float = _player.get_total_duration()
		_duration_label.text = (
				"get_total_duration(): %.0f ms" % (duration * 1000.0)
		)
