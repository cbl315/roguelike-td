# 07_combined.gd
# Demo 07 — Combined Juicy Shot on a real 3D scene.
#
# Scene shape:
#   • Root is a Node3D. Environment, lights, floor, scenery and the
#     Camera3D are authored in 07_combined.tscn.
#   • FeedbackPlayer holds all 8 feedback entries (6 feedback types
#     total — two flashes and two audios stagger across the timeline).
#   • HUD is a CanvasLayer overlay: candy display (Scale Punch target)
#     + Shoot button + intensity slider + status line.
#
# Timeline (single play() call):
#   •   0 ms — Audio (pop) + Camera Shake + Yellow Screen Flash
#   • 120 ms — Hit Pause (0.08× for 120 ms) + Audio (confetti) +
#              Call on_candy_hit() + Scale Punch on candy + Pink Flash
#
# Key wiring:
#   • Camera Shake uses AUTO selection — works because the
#     FeedbackPlayer lives directly under the main viewport with the
#     Camera3D right next to it.
#   • Scale Punch targets the candy TextureRect, which is built in
#     code (so the HUD layout can be tweaked without the scene). The
#     target NodePath is resolved at runtime in _wire_scale_punch_target.
#   • Call on_candy_hit() — target NodePath("..") → this Demo root,
#     where on_candy_hit() swaps the sprite and bumps the counter.

extends Node3D

const _SOLDIER_SCENE: String = \
		"res://addons/sparkle_lite/samples/assets/models/sparklelite_soldier.gltf"
const _CANDY_STAGE_1: String = \
		"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_1.png"
const _CANDY_STAGE_3: String = \
		"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_3.png"
const _CANDY_STAGE_RAINBOW: String = \
		"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_special_rain.png"

@onready var _feedback_player: FeedbackPlayerLite = $FeedbackPlayer

var _anim_player: AnimationPlayer
var _candy_display: TextureRect
var _status_label: Label
var _hit_label: Label
var _intensity_label: Label

var _hit_count: int = 0
var _intensity: float = 1.0


func _ready() -> void:
	_spawn_soldier()
	_build_hud()
	_wire_scale_punch_target()
	_apply_stage(_CANDY_STAGE_1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event
		if key.keycode == KEY_SPACE:
			_on_shoot_pressed()
		elif key.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://addons/sparkle_lite/samples/sparklelite_main.tscn")


# --- Scene content ---------------------------------------------------

func _spawn_soldier() -> void:
	var scene: PackedScene = load(_SOLDIER_SCENE) as PackedScene
	if scene == null:
		return
	var soldier: Node3D = scene.instantiate() as Node3D
	soldier.position = Vector3(0, 0, 0)
	soldier.rotation_degrees = Vector3(0, 25, 0)
	add_child(soldier)
	SparkleLiteDemoWidgets.keep_rifle_only(soldier)
	_anim_player = soldier.find_child(
			"AnimationPlayer", true, false) as AnimationPlayer
	_play_anim(&"Idle")


# --- HUD overlay -----------------------------------------------------

func _build_hud() -> void:
	var hud: CanvasLayer = CanvasLayer.new()
	hud.name = &"HUD"
	add_child(hud)

	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	_build_top_bar(root)
	_build_candy_card(root)
	_build_bottom_bar(root)
	SparkleLiteDemoWidgets.add_back_button(root, _on_back_pressed)


func _build_top_bar(root: Control) -> void:
	var bar: PanelContainer = PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24
	bar.offset_right = -190
	bar.offset_top = 18
	bar.offset_bottom = 72
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(SparkleLiteDemoPalette.CARD_BG.r, SparkleLiteDemoPalette.CARD_BG.g,
			SparkleLiteDemoPalette.CARD_BG.b, 0.78)
	bg.border_color = SparkleLiteDemoPalette.GRADIENT_PURPLE
	bg.border_width_left = 3
	bg.set_corner_radius_all(10)
	bg.content_margin_left = 18
	bg.content_margin_right = 18
	bg.content_margin_top = 10
	bg.content_margin_bottom = 10
	bar.add_theme_stylebox_override(&"panel", bg)
	root.add_child(bar)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 2)
	bar.add_child(col)

	var title: Label = Label.new()
	title.text = "07 · Combined Juicy Shot"
	title.add_theme_font_size_override(&"font_size", 18)
	title.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.GRADIENT_PURPLE)
	col.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = (
			"All six feedback types in one timeline — muzzle at 0 ms, "
			+ "impact at 120 ms. One play() call."
	)
	subtitle.add_theme_font_size_override(&"font_size", 12)
	subtitle.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	col.add_child(subtitle)


func _build_candy_card(root: Control) -> void:
	# The candy is the Scale Punch target AND the Call-method hook
	# point (on_candy_hit() swaps its texture). We anchor it on the
	# right of the screen so the soldier/scenery stays visible.
	var host: CenterContainer = CenterContainer.new()
	host.anchor_left = 1.0
	host.anchor_right = 1.0
	host.anchor_top = 0.5
	host.anchor_bottom = 0.5
	host.offset_left = -280
	host.offset_right = -40
	host.offset_top = -120
	host.offset_bottom = 120
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(host)

	var card: PanelContainer = PanelContainer.new()
	var card_bg: StyleBoxFlat = StyleBoxFlat.new()
	card_bg.bg_color = Color(SparkleLiteDemoPalette.CARD_BG.r, SparkleLiteDemoPalette.CARD_BG.g,
			SparkleLiteDemoPalette.CARD_BG.b, 0.82)
	card_bg.border_color = SparkleLiteDemoPalette.GRADIENT_PINK
	card_bg.set_border_width_all(2)
	card_bg.set_corner_radius_all(18)
	card_bg.set_content_margin_all(16)
	card.add_theme_stylebox_override(&"panel", card_bg)
	host.add_child(card)

	_candy_display = TextureRect.new()
	_candy_display.custom_minimum_size = Vector2(180, 180)
	_candy_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_candy_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_candy_display.pivot_offset = Vector2(90, 90)
	_candy_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_candy_display)


func _build_bottom_bar(root: Control) -> void:
	var wrap: VBoxContainer = VBoxContainer.new()
	wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	wrap.offset_left = 24
	wrap.offset_right = -24
	wrap.offset_top = -150
	wrap.offset_bottom = -24
	wrap.add_theme_constant_override(&"separation", 8)
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(wrap)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(buttons)

	var shoot: Button = SparkleLiteDemoWidgets.make_primary_button(
			"Shoot (Space)", SparkleLiteDemoPalette.GRADIENT_PURPLE)
	shoot.pressed.connect(_on_shoot_pressed)
	buttons.add_child(shoot)

	var reset: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Reset Candy", SparkleLiteDemoPalette.TEXT_MUTED)
	reset.pressed.connect(_on_reset_pressed)
	buttons.add_child(reset)

	var intensity_row: HBoxContainer = HBoxContainer.new()
	intensity_row.add_theme_constant_override(&"separation", 10)
	intensity_row.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(intensity_row)

	_intensity_label = Label.new()
	_intensity_label.text = "Intensity: 1.00x"
	_intensity_label.custom_minimum_size = Vector2(140, 0)
	_intensity_label.add_theme_font_size_override(&"font_size", 13)
	_intensity_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	intensity_row.add_child(_intensity_label)

	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 2.0
	slider.step = 0.05
	slider.value = 1.0
	slider.custom_minimum_size = Vector2(240, 0)
	slider.value_changed.connect(_on_intensity_changed)
	intensity_row.add_child(slider)

	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.add_theme_constant_override(&"separation", 20)
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(status_row)

	_status_label = Label.new()
	_status_label.text = "Ready. Click Shoot to fire the combined sequence."
	_status_label.add_theme_font_size_override(&"font_size", 13)
	_status_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	status_row.add_child(_status_label)

	_hit_label = Label.new()
	_hit_label.text = "Hits: 0"
	_hit_label.add_theme_font_size_override(&"font_size", 13)
	_hit_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.GRADIENT_PINK)
	status_row.add_child(_hit_label)


func _wire_scale_punch_target() -> void:
	# The candy TextureRect is built in code, so the scene-authored
	# scale punch ships with an empty target. Resolve it now to a
	# NodePath the FeedbackPlayer can follow at play time.
	if _feedback_player == null or _candy_display == null:
		return
	var path: NodePath = _feedback_player.get_path_to(_candy_display)
	for fb in _feedback_player.feedbacks:
		if fb is FeedbackScalePunchLite:
			(fb as FeedbackScalePunchLite).target = path
			return


# --- Button handlers -------------------------------------------------

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://addons/sparkle_lite/samples/sparklelite_main.tscn")


func _on_shoot_pressed() -> void:
	_play_anim(&"Idle_Shoot")
	_feedback_player.play(_intensity)
	_status_label.text = (
			"play(%.2f) — 8 feedbacks across 2 delays" % _intensity
	)


func _on_reset_pressed() -> void:
	_hit_count = 0
	_hit_label.text = "Hits: 0"
	_apply_stage(_CANDY_STAGE_1)
	_status_label.text = "Candy reset to stage 1."


func _on_intensity_changed(value: float) -> void:
	_intensity = value
	if _intensity_label != null:
		_intensity_label.text = "Intensity: %.2fx" % value


# --- Method invoked by FeedbackCallLite (CALL_METHOD) ----------------

func on_candy_hit() -> void:
	# Fired at 120 ms — same frame as the scale punch and hit pause.
	_hit_count += 1
	_hit_label.text = "Hits: %d" % _hit_count
	if _hit_count % 3 == 0:
		_apply_stage(_CANDY_STAGE_RAINBOW)
	else:
		_apply_stage(_CANDY_STAGE_3)


# --- Helpers ---------------------------------------------------------

func _apply_stage(path: String) -> void:
	if _candy_display == null:
		return
	_candy_display.texture = load(path) as Texture2D


func _play_anim(anim: StringName) -> void:
	if _anim_player == null:
		return
	if not _anim_player.has_animation(anim):
		return
	_anim_player.stop()
	_anim_player.play(anim)
