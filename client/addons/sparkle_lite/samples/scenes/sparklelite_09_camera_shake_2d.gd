# 09_camera_shake_2d.gd
# Demo 09 — Camera Shake 2D.
#
# Scene shape:
#   • Root is a Node2D. The Camera2D sits directly under the root
#     and is the single active 2D camera for the viewport.
#   • A Playfield Node2D holds the candy sprites (built in code so
#     we can tune counts and colours without editing the scene).
#   • FeedbackPlayer carries a single FeedbackCameraShake2DLite
#     authored in the inspector.
#   • HUD lives on a CanvasLayer so the top bar and buttons are not
#     dragged around by the shake — only the playfield moves.
#
# Why AUTO camera selection works:
#   FeedbackCameraShake2DLite calls viewport.get_camera_2d() on play,
#   which returns the enabled Camera2D under the same viewport. Since
#   Demo is the current_scene root and Camera is its direct child,
#   that lookup succeeds without any BY_PATH wiring.
#
# What to touch:
#   • Pick the FeedbackPlayer in the scene dock, open the Feedbacks
#     array in the inspector, tweak position_amplitude (pixels),
#     rotation_amplitude (degrees), duration_ms, and the noise
#     randomness values.

extends Node2D

const _CANDY_PATHS: Array[String] = [
	"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_1.png",
	"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_2.png",
	"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_upgrade_3.png",
	"res://addons/sparkle_lite/samples/assets/sprites/sparklelite_candy_special_rain.png",
]

const _BG_COLOR: Color = Color("#140A1F")
const _GRID_COLOR: Color = Color("#271838")
const _GRID_STEP: float = 64.0

@onready var _feedback_player: FeedbackPlayerLite = $FeedbackPlayer
@onready var _camera: Camera2D = $Camera
@onready var _playfield: Node2D = $Playfield

var _status_label: Label


func _ready() -> void:
	_camera.make_current()
	_build_playfield()
	_build_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event
		if key.keycode == KEY_SPACE:
			_on_shoot_pressed()
		elif key.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://addons/sparkle_lite/samples/sparklelite_main.tscn")


func _draw() -> void:
	# Full-viewport backdrop + grid so the shake is unmistakable.
	# Draw in local space; Camera2D takes care of the rest.
	var size: Vector2 = get_viewport_rect().size
	var half: Vector2 = size * 0.5
	draw_rect(Rect2(-half, size), _BG_COLOR)
	var x: float = -half.x
	while x <= half.x:
		draw_line(Vector2(x, -half.y), Vector2(x, half.y),
				_GRID_COLOR, 1.0)
		x += _GRID_STEP
	var y: float = -half.y
	while y <= half.y:
		draw_line(Vector2(-half.x, y), Vector2(half.x, y),
				_GRID_COLOR, 1.0)
		y += _GRID_STEP


# --- Scene content ---------------------------------------------------

func _build_playfield() -> void:
	# Lay the candies out in a loose ring so the rotational shake
	# reads on anything the camera frames — not just one object.
	var count: int = 8
	var radius: float = 220.0
	for i in range(count):
		var sprite: Sprite2D = Sprite2D.new()
		var tex_path: String = _CANDY_PATHS[i % _CANDY_PATHS.size()]
		sprite.texture = load(tex_path) as Texture2D
		var angle: float = TAU * float(i) / float(count)
		sprite.position = Vector2(cos(angle), sin(angle)) * radius
		sprite.scale = Vector2(0.6, 0.6)
		sprite.rotation = angle + PI * 0.5
		_playfield.add_child(sprite)

	# Centre candy — the anchor the camera is trained on.
	var centre: Sprite2D = Sprite2D.new()
	centre.texture = load(_CANDY_PATHS[3]) as Texture2D
	centre.scale = Vector2(0.85, 0.85)
	_playfield.add_child(centre)


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
			SparkleLiteDemoPalette.CARD_BG.b, 0.82)
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
	title.text = "09 · Camera Shake 2D"
	title.add_theme_font_size_override(&"font_size", 18)
	title.add_theme_color_override(
			&"font_color", SparkleLiteDemoPalette.ACCENT_CAMERA_SHAKE)
	col.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = (
			"FeedbackCameraShake2DLite on a Camera2D — position "
			+ "amplitude in pixels, rotation in degrees."
	)
	subtitle.add_theme_font_size_override(&"font_size", 12)
	subtitle.add_theme_color_override(&"font_color", SparkleLiteDemoPalette.TEXT_MUTED)
	col.add_child(subtitle)


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
			"Pop (Space)", SparkleLiteDemoPalette.ACCENT_CAMERA_SHAKE)
	shoot.pressed.connect(_on_shoot_pressed)
	buttons.add_child(shoot)

	var soft: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Soft (0.4)", SparkleLiteDemoPalette.ACCENT_CAMERA_SHAKE)
	soft.pressed.connect(_on_soft_pressed)
	buttons.add_child(soft)

	var heavy: Button = SparkleLiteDemoWidgets.make_secondary_button(
			"Heavy (1.8)", SparkleLiteDemoPalette.ACCENT_CAMERA_SHAKE)
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
	_status_label.text = "Ready. Click Pop or press Space."
	wrap.add_child(_status_label)


# --- Button handlers -------------------------------------------------

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://addons/sparkle_lite/samples/sparklelite_main.tscn")


func _on_shoot_pressed() -> void:
	_feedback_player.play()
	_update_status("play() — intensity 1.0")


func _on_soft_pressed() -> void:
	_feedback_player.play(0.4)
	_update_status("play(0.4) — soft")


func _on_heavy_pressed() -> void:
	_feedback_player.play(1.8)
	_update_status("play(1.8) — heavy")


func _on_rebuild_pressed() -> void:
	# Full runtime API: build a new FeedbackCameraShake2DLite in code
	# and swap the player's feedbacks array out for it.
	var shake: FeedbackCameraShake2DLite = FeedbackCameraShake2DLite.new()
	shake.label = "Rebuilt From Code"
	shake.duration_ms = 600.0
	shake.position_amplitude = Vector2(22.0, 22.0)
	shake.rotation_amplitude = 3.5
	shake.rotation_randomness = 0.7
	_feedback_player.clear_feedbacks()
	_feedback_player.add_feedback(shake)
	_feedback_player.play(1.2)
	_update_status("Rebuilt feedback list via add_feedback() + play(1.2)")


func _update_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
