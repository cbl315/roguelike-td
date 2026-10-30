# 01_camera_shake.gd
# Demo 01 — Camera Shake on a real 3D scene.
#
# Scene shape:
#   • Root is a Node3D (the actual game world). WorldEnvironment,
#     lights, floor, scenery and the Camera3D are authored directly
#     in 01_camera_shake.tscn — look there first to see what the
#     demo targets.
#   • FeedbackPlayer is a Node child of the world with one
#     FeedbackCameraShakeLite configured in the inspector.
#   • The HUD is a CanvasLayer overlay built in _ready(). Keeping
#     UI in a CanvasLayer means the game view stays untouched — the
#     buttons sit ON the scene, not BESIDE it.
#
# Why AUTO camera selection works here:
#   FeedbackCameraShakeLite calls player.get_viewport().get_camera_3d()
#   on play. Because the FeedbackPlayer lives directly in the main
#   viewport (no SubViewport in between), that call resolves to the
#   Camera3D in the scene and the shake just works.
#
# What to touch:
#   • Pick the FeedbackPlayer in the scene dock, open the Feedbacks
#     array in the inspector, tweak amplitudes / randomness / duration.
#   • Press Shoot (or Space) to fire. The soldier GLB plays its
#     Idle_Shoot animation at the same instant so the shake has a
#     gameplay reason to exist.

extends Node3D

const _SOLDIER_SCENE: String = \
		"res://addons/sparkle_lite/samples/assets/models/sparklelite_soldier.gltf"

@onready var _feedback_player: FeedbackPlayerLite = $FeedbackPlayer
@onready var _camera: Camera3D = $Camera

var _anim_player: AnimationPlayer
var _status_label: Label


func _ready() -> void:
	_spawn_soldier()
	_build_hud()
	_update_status("Ready. Click Shoot or press Space.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event
		if key.keycode == KEY_SPACE:
			_on_shoot_pressed()
		elif key.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://addons/sparkle_lite/samples/sparklelite_main.tscn")


# --- Soldier ---------------------------------------------------------

func _spawn_soldier() -> void:
	# The soldier is a glTF model with an embedded AnimationPlayer.
	# We instance it here (rather than authoring an inherited scene)
	# because the import pipeline can rename internal nodes; find_child
	# for the AnimationPlayer is the robust option.
	var scene: PackedScene = load(_SOLDIER_SCENE) as PackedScene
	if scene == null:
		return
	var soldier: Node3D = scene.instantiate() as Node3D
	soldier.position = Vector3(0, 0, 0)
	soldier.rotation_degrees = Vector3(0, 20, 0)
	add_child(soldier)
	SparkleLiteDemoWidgets.keep_rifle_only(soldier)
	_anim_player = soldier.find_child(
			"AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player != null and _anim_player.has_animation(&"Idle"):
		_anim_player.play(&"Idle")


# --- HUD overlay -----------------------------------------------------

func _build_hud() -> void:
	# CanvasLayer sits on top of the 3D world with its own 2D root. We
	# keep the HUD minimal: a compact title bar, a centre crosshair, a
	# small button strip, and a status line. The 3D scene is the demo.
	var hud: CanvasLayer = CanvasLayer.new()
	hud.name = &"HUD"
	add_child(hud)

	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	_build_top_bar(root)
	_build_crosshair(root)
	_build_bottom_bar(root)
	SparkleLiteDemoWidgets.add_back_button(root, _on_back_pressed)


func _build_top_bar(root: Control) -> void:
	var bar: PanelContainer = PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24
	bar.offset_right = -190
	bar.offset_top = 18
	bar.offset_bottom = 70
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(SparkleLiteDemoPalette.CARD_BG.r, SparkleLiteDemoPalette.CARD_BG.g,
			SparkleLiteDemoPalette.CARD_BG.b, 0.78)
	bg.border_color = SparkleLiteDemoPalette.ACCENT_CAMERA_SHAKE
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
	title.text = "01 · Camera Shake"
	title.add_theme_font_size_override(&"font_size", 18)
	title.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.ACCENT_CAMERA_SHAKE)
	col.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = (
			"FeedbackCameraShakeLite on the scene-authored player — "
			+ "Camera3D is picked via AUTO selection."
	)
	subtitle.add_theme_font_size_override(&"font_size", 12)
	subtitle.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	col.add_child(subtitle)


func _build_crosshair(root: Control) -> void:
	var dot: ColorRect = ColorRect.new()
	dot.color = Color(1, 1, 1, 0.7)
	dot.custom_minimum_size = Vector2(6, 6)
	dot.size = Vector2(6, 6)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position = Vector2(-3, -3)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)


func _build_bottom_bar(root: Control) -> void:
	var wrap: VBoxContainer = VBoxContainer.new()
	wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	wrap.offset_left = 24
	wrap.offset_right = -24
	wrap.offset_top = -120
	wrap.offset_bottom = -24
	wrap.add_theme_constant_override(&"separation", 8)
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(wrap)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(buttons)

	var shoot: Button = SparkleLiteDemoWidgets.make_primary_button(
			"Shoot (Space)", SparkleLiteDemoPalette.ACCENT_CAMERA_SHAKE)
	shoot.pressed.connect(_on_shoot_pressed)
	buttons.add_child(shoot)

	var soft: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Soft Shot (0.4)", SparkleLiteDemoPalette.ACCENT_CAMERA_SHAKE)
	soft.pressed.connect(_on_soft_pressed)
	buttons.add_child(soft)

	var heavy: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Heavy Shot (1.8)", SparkleLiteDemoPalette.ACCENT_CAMERA_SHAKE)
	heavy.pressed.connect(_on_heavy_pressed)
	buttons.add_child(heavy)

	var rebuild: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Rebuild From Code", SparkleLiteDemoPalette.ACCENT_CYAN)
	rebuild.pressed.connect(_on_rebuild_pressed)
	buttons.add_child(rebuild)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override(&"font_size", 13)
	_status_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	wrap.add_child(_status_label)


# --- Button handlers -------------------------------------------------

func _on_shoot_pressed() -> void:
	_play_anim(&"Idle_Shoot")
	_feedback_player.play()
	_update_status("play() — intensity 1.0")


func _on_soft_pressed() -> void:
	_play_anim(&"Idle_Shoot")
	_feedback_player.play(0.4)
	_update_status("play(0.4) — soft")


func _on_heavy_pressed() -> void:
	_play_anim(&"Idle_Shoot")
	_feedback_player.play(1.8)
	_update_status("play(1.8) — heavy")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://addons/sparkle_lite/samples/sparklelite_main.tscn")


func _on_rebuild_pressed() -> void:
	_play_anim(&"Idle_Shoot")
	# Full runtime API: build a fresh FeedbackCameraShakeLite in code
	# and replace whatever was authored in the inspector.
	var shake: FeedbackCameraShakeLite = FeedbackCameraShakeLite.new()
	shake.label = "Rebuilt From Code"
	shake.duration_ms = 550.0
	shake.position_amplitude = Vector3(0.25, 0.25, 0.0)
	shake.rotation_amplitude = Vector3(0.0, 0.0, 4.0)
	shake.rotation_randomness = Vector3(0.7, 0.7, 0.7)
	_feedback_player.clear_feedbacks()
	_feedback_player.add_feedback(shake)
	_feedback_player.play(1.2)
	_update_status("Rebuilt feedback list via add_feedback() + play(1.2)")


# --- Helpers ---------------------------------------------------------

func _play_anim(anim: StringName) -> void:
	if _anim_player == null:
		return
	if not _anim_player.has_animation(anim):
		return
	_anim_player.stop()
	_anim_player.play(anim)


func _update_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
