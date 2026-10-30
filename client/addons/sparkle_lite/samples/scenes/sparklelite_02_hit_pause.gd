# 02_hit_pause.gd
# Demo 02 — Hit Pause on a real 3D scene.
#
# Scene shape:
#   • Root is a Node3D. Floor, platform, lights and the Camera3D are
#     authored in 02_hit_pause.tscn.
#   • An OrbitPivot Node3D marks the centre of a glowing ring of
#     cubes. The cubes are built in code so we can tune their count
#     and colour without editing the scene.
#   • FeedbackPlayer has two authored feedbacks: a Camera Shake at
#     0 ms (use_unscaled_time=true — keeps animating during the
#     freeze) and a Hit Pause at 50 ms (time_scale drops to 0.05 for
#     120 ms).
#
# Why the ring matters:
#   Hit pause is invisible without something on-screen that moves at
#   the normal time scale. The orbit rig is always spinning with
#   SCALED delta, so Engine.time_scale dropping during the pause
#   visibly freezes the whole ring regardless of when you press
#   Shoot. Camera shake ignores that time-scale drop and keeps going.

extends Node3D

const _SOLDIER_SCENE: String = \
		"res://addons/sparkle_lite/samples/assets/models/sparklelite_soldier.gltf"
const _ORBIT_COUNT: int = 6
const _ORBIT_RADIUS: float = 1.6
const _ORBIT_SPIN_SPEED: float = 1.4

@onready var _feedback_player: FeedbackPlayerLite = $FeedbackPlayer
@onready var _orbit_pivot: Node3D = $OrbitPivot

var _anim_player: AnimationPlayer
var _orbit_cubes: Array[MeshInstance3D] = []
var _status_label: Label


func _ready() -> void:
	_spawn_soldier()
	_build_orbit_rig()
	_build_hud()
	_feedback_player.completed.connect(_on_sequence_completed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event
		if key.keycode == KEY_SPACE:
			_on_shoot_pressed()
		elif key.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://addons/sparkle_lite/samples/sparklelite_main.tscn")


func _process(delta: float) -> void:
	# SCALED delta — the whole point of this demo. When HitPauseLite
	# drives Engine.time_scale to 0.05, this rotation slows to a
	# crawl and the freeze is unmistakable on every cube.
	if _orbit_pivot != null:
		_orbit_pivot.rotation.y += delta * _ORBIT_SPIN_SPEED
		for i in range(_orbit_cubes.size()):
			var cube: MeshInstance3D = _orbit_cubes[i]
			if cube != null:
				cube.rotation.x += delta * (2.0 + 0.5 * float(i))
				cube.rotation.z += delta * (1.3 + 0.3 * float(i))


# --- Scene content ---------------------------------------------------

func _spawn_soldier() -> void:
	var scene: PackedScene = load(_SOLDIER_SCENE) as PackedScene
	if scene == null:
		return
	var soldier: Node3D = scene.instantiate() as Node3D
	soldier.position = Vector3(-1.2, 0.2, 0.8)
	soldier.rotation_degrees = Vector3(0, 25, 0)
	add_child(soldier)
	SparkleLiteDemoWidgets.keep_rifle_only(soldier)
	_anim_player = soldier.find_child(
			"AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player != null and _anim_player.has_animation(&"Idle"):
		_anim_player.play(&"Idle")


func _build_orbit_rig() -> void:
	if _orbit_pivot == null:
		return
	var palette: Array[Color] = [
		SparkleLiteDemoPalette.GRADIENT_YELLOW,
		SparkleLiteDemoPalette.GRADIENT_PINK,
		SparkleLiteDemoPalette.GRADIENT_PURPLE,
		SparkleLiteDemoPalette.GRADIENT_BLUE,
		SparkleLiteDemoPalette.ACCENT_CYAN,
		SparkleLiteDemoPalette.ACCENT_HIT_PAUSE,
	]
	for i in range(_ORBIT_COUNT):
		var cube: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(0.3, 0.3, 0.3)
		cube.mesh = mesh
		var col: Color = palette[i % palette.size()]
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.6
		cube.material_override = mat
		var angle: float = TAU * float(i) / float(_ORBIT_COUNT)
		cube.position = Vector3(
				cos(angle) * _ORBIT_RADIUS,
				sin(angle * 2.0) * 0.25,
				sin(angle) * _ORBIT_RADIUS,
		)
		_orbit_pivot.add_child(cube)
		_orbit_cubes.append(cube)


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
	bg.border_color = SparkleLiteDemoPalette.ACCENT_HIT_PAUSE
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
	title.text = "02 · Hit Pause"
	title.add_theme_font_size_override(&"font_size", 18)
	title.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.ACCENT_HIT_PAUSE)
	col.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = (
			"Camera shake (unscaled) + hit pause. Ring spins on scaled "
			+ "time — freezes when the pause fires."
	)
	subtitle.add_theme_font_size_override(&"font_size", 12)
	subtitle.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	col.add_child(subtitle)


func _build_bottom_bar(root: Control) -> void:
	var wrap: VBoxContainer = VBoxContainer.new()
	wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	wrap.offset_left = 24
	wrap.offset_right = -24
	wrap.offset_top = -100
	wrap.offset_bottom = -24
	wrap.add_theme_constant_override(&"separation", 8)
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(wrap)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(buttons)

	var shoot: Button = SparkleLiteDemoWidgets.make_primary_button(
			"Shoot (Space)", SparkleLiteDemoPalette.ACCENT_HIT_PAUSE)
	shoot.pressed.connect(_on_shoot_pressed)
	buttons.add_child(shoot)

	var heavy: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Heavy Shot (1.6)", SparkleLiteDemoPalette.ACCENT_HIT_PAUSE)
	heavy.pressed.connect(_on_heavy_pressed.bind(1.6))
	buttons.add_child(heavy)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override(&"font_size", 13)
	_status_label.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	_status_label.text = "Ready."
	wrap.add_child(_status_label)


# --- Button handlers -------------------------------------------------

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://addons/sparkle_lite/samples/sparklelite_main.tscn")


func _on_shoot_pressed() -> void:
	_fire(1.0)


func _on_heavy_pressed(intensity: float) -> void:
	_fire(intensity)


func _fire(intensity: float) -> void:
	_play_anim(&"Idle_Shoot")
	_feedback_player.play(intensity)
	if _status_label != null:
		_status_label.text = (
				"play(%.1f) — shake @ 0 ms, hit pause @ 50 ms" % intensity
		)


func _on_sequence_completed() -> void:
	if _status_label != null:
		_status_label.text = _status_label.text + "  (sequence complete)"


# --- Helpers ---------------------------------------------------------

func _play_anim(anim: StringName) -> void:
	if _anim_player == null:
		return
	if not _anim_player.has_animation(anim):
		return
	_anim_player.stop()
	_anim_player.play(anim)
