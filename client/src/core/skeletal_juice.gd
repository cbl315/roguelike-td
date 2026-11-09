## skeletal_juice.gd — 多部件骨骼动画状态机（Spine 风格，纯代码驱动）。
## 在 Juice 基础上升级：不再把角色当"一张贴图"变换，
## 而是拆为 头/躯干/左臂/右臂/腿部 五个"虚拟骨骼"分层动画。
##
## 每个部件有独立的 offset/rotation/scale，_draw() 按 layer 顺序绘制：
##   腿(后) → 左臂(后) → 躯干 → 头 → 右臂(前)
class_name SkeletalJuice
extends RefCounted

# ── 部件变换（一个"骨骼节点"）──
class Bone:
	var offset: Vector2 = Vector2.ZERO
	var rotation: float = 0.0
	var scale: Vector2 = Vector2.ONE
	var z: int = 0     # 绘制顺序

# ── 动画状态 ──
var _time: float = 0.0
var _move_dir: Vector2 = Vector2.RIGHT
var _move_speed: float = 0.0
var _attack_t: float = -1.0
var _hit_t: float = -1.0
var _death_t: float = -1.0
var _spawn_t: float = -1.0
var _flash: float = 0.0

# ── 可调参数（Brotato 风格默认，按角色覆盖）──
var breathe_amp: float = 0.02
var breathe_freq: float = 2.0
var head_sway_amp: float = 1.5
var walk_bob_freq: float = 8.0
var walk_bob_amp: float = 3.0
var leg_swing_amp: float = 0.25
var arm_swing_amp: float = 0.18
var lean_angle: float = 0.08
var attack_windup: float = 0.06
var attack_lunge: float = 0.10
var attack_recoil: float = 0.12
var attack_total: float = 0.28
var lunge_dist: float = 12.0
var hit_dur: float = 0.15
var hit_stagger: float = 8.0
var hit_tilt: float = 0.15
var death_dur: float = 0.40
var spawn_dur: float = 0.30

var _bones: Dictionary = {}


func _init() -> void:
	_time = randf() * 10.0
	for part in ["legs", "arm_l", "torso", "head", "arm_r"]:
		_bones[part] = Bone.new()
		match part:
			"legs": _bones[part].z = 0
			"arm_l": _bones[part].z = 1
			"torso": _bones[part].z = 2
			"head": _bones[part].z = 3
			"arm_r": _bones[part].z = 4


## 每帧调用
func tick(delta: float, move_dir: Vector2 = Vector2.ZERO, move_speed: float = 0.0) -> void:
	_time += delta
	_move_dir = move_dir.normalized() if move_dir.length() > 0.01 else Vector2.RIGHT
	_move_speed = clampf(move_speed, 0.0, 1.0)
	if _attack_t >= 0.0:
		_attack_t += delta
		if _attack_t >= attack_total:
			_attack_t = -1.0
	if _hit_t >= 0.0:
		_hit_t += delta
		if _hit_t >= hit_dur:
			_hit_t = -1.0
	if _death_t >= 0.0:
		_death_t += delta
	if _spawn_t >= 0.0:
		_spawn_t += delta
		if _spawn_t >= spawn_dur:
			_spawn_t = -1.0
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / 0.12)
	_compute()


func _compute() -> void:
	var t := _time
	var moving := _move_speed > 0.05
	var legs: Bone = _bones["legs"]
	legs.offset = Vector2.ZERO
	legs.rotation = sin(t * walk_bob_freq * TAU) * leg_swing_amp * _move_speed if moving else 0.0
	legs.scale = Vector2.ONE

	var torso: Bone = _bones["torso"]
	var breathe: float = sin(t * breathe_freq * TAU)
	torso.scale = Vector2(1.0 + breathe * breathe_amp, 1.0 - breathe * breathe_amp)
	var bob: float = absf(sin(t * walk_bob_freq * TAU)) * walk_bob_amp * _move_speed if moving else 0.0
	torso.offset = Vector2(0, -bob)
	var lean: float = lean_angle * _move_speed
	torso.rotation = lean if _move_dir.x >= 0 else -lean

	var head: Bone = _bones["head"]
	head.offset = Vector2(sin(t * breathe_freq * TAU * 0.7) * head_sway_amp, torso.offset.y * 0.5)
	head.rotation = -torso.rotation * 0.5
	head.scale = Vector2.ONE

	var swing: float = sin(t * walk_bob_freq * TAU) * arm_swing_amp * _move_speed if moving else 0.0
	var arm_l: Bone = _bones["arm_l"]
	arm_l.rotation = -swing
	arm_l.offset = Vector2.ZERO
	arm_l.scale = Vector2.ONE
	var arm_r: Bone = _bones["arm_r"]
	arm_r.rotation = swing
	arm_r.offset = Vector2.ZERO
	arm_r.scale = Vector2.ONE

	if _attack_t >= 0.0:
		var at: float = _attack_t
		if at < attack_windup:
			var p: float = at / attack_windup
			var pull: float = lunge_dist * 0.4 * p
			_apply_all(Vector2(-pull, 0) * _move_dir, 0.0, Vector2.ONE * (1.0 - 0.05 * p))
		elif at < attack_windup + attack_lunge:
			var p: float = (at - attack_windup) / attack_lunge
			var push: float = lunge_dist * _ease_out_quad(p)
			_apply_all(Vector2(push, 0) * _move_dir, 0.0, Vector2(1.0 + 0.12 * (1.0 - p), 1.0 - 0.08 * (1.0 - p)))
			_bones["arm_r"].offset += _move_dir * push * 0.5
			_bones["arm_r"].rotation += 0.3
		else:
			var p: float = (at - attack_windup - attack_lunge) / attack_recoil
			var rec: float = lunge_dist * 0.3 * (1.0 - _ease_out_elastic(p))
			_apply_all(Vector2(-rec, 0) * _move_dir, 0.0, Vector2.ONE)

	if _hit_t >= 0.0:
		var p: float = _hit_t / hit_dur
		var back: float = hit_stagger * (1.0 - _ease_out_quad(p))
		_apply_all(Vector2(-back, 0) * _move_dir, hit_tilt * (1.0 - p), Vector2.ONE)
		_bones["head"].rotation += hit_tilt * 1.5 * (1.0 - p)

	if _death_t >= 0.0:
		var p: float = clampf(_death_t / death_dur, 0.0, 1.0)
		_apply_all(Vector2(0, p * 20.0), p * PI * 0.4, Vector2.ONE * (1.0 + p * 0.3))
		_bones["head"].offset += Vector2(randf_range(-30, 30), -p * 40)
		_bones["arm_l"].offset += Vector2(-p * 25, p * 15)
		_bones["arm_r"].offset += Vector2(p * 25, p * 15)
		_bones["legs"].offset += Vector2(0, p * 10)

	if _spawn_t >= 0.0:
		var p: float = clampf(_spawn_t / spawn_dur, 0.0, 1.0)
		var pop: float = _ease_out_back(p)
		_apply_all(Vector2.ZERO, 0.0, Vector2(pop, pop))


func _apply_all(off: Vector2, rot: float, scl: Vector2) -> void:
	for part in _bones.keys():
		var b: Bone = _bones[part]
		b.offset += off
		b.rotation += rot
		b.scale *= scl

## 按 z 排序的骨骼层列表（_draw 遍历用）
func get_layers() -> Array:
	return [_bones["legs"], _bones["arm_l"], _bones["torso"], _bones["head"], _bones["arm_r"]]

## 简化接口（兼容单贴图渲染）
func get_root_offset() -> Vector2:
	return _bones["torso"].offset

func get_root_rotation() -> float:
	return _bones["torso"].rotation

func get_root_scale() -> Vector2:
	return _bones["torso"].scale

func get_alpha() -> float:
	if _death_t < 0.0:
		return 1.0
	return 1.0 - clampf(_death_t / death_dur, 0.0, 1.0)

func get_flash() -> float:
	return _flash

func is_dying() -> bool:
	return _death_t >= 0.0

func death_progress() -> float:
	if _death_t < 0.0:
		return 0.0
	return clampf(_death_t / death_dur, 0.0, 1.0)

func play_attack() -> void:
	_attack_t = 0.0

func play_hit() -> void:
	_hit_t = 0.0
	_flash = 1.0

func play_death() -> void:
	_death_t = 0.0

func play_spawn() -> void:
	_spawn_t = 0.0

static func _ease_out_quad(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)

static func _ease_out_back(t: float, s: float = 1.70158) -> float:
	t -= 1.0
	return 1.0 + (s + 1.0) * t * t * t + s * t * t

static func _ease_out_elastic(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	var p: float = 0.35
	return pow(2.0, -10.0 * t) * sin((t - p / 4.0) * (TAU / p)) + 1.0


## ═══ 贴图拆分渲染（剪纸动画模式）═══
## 把单张贴图按水平条带拆为 head/torso/legs 三个区域，
## 各自用对应骨骼的 transform 独立绘制——头会独立摇摆、
## 躯干弹跳时腿留在地面，形成"多部件"视觉。
##
## band 参数：[top_ratio, height_ratio] 占贴图比例
const BAND_HEAD  := Vector2(0.0, 0.30)    # 头部：顶部 30%
const BAND_TORSO := Vector2(0.28, 0.40)   # 躯干：28%-68%（与头/腿各重叠 2%）
const BAND_LEGS  := Vector2(0.66, 0.34)   # 腿部：66%-100%


## 拆分绘制（替代单次 draw_texture 的完整调用序列）
## 在 _draw() 里直接调用此方法代替原来的 draw_set_transform + draw_texture
func draw_split(tex: Texture2D, canvas: CanvasItem) -> void:
	if tex == null:
		return
	var ts: Vector2 = tex.get_size()
	var half: Vector2 = ts / 2.0

	# ── 腿部（最底层）──
	var legs: Bone = _bones["legs"]
	canvas.draw_set_transform(
		legs.offset + Vector2(0, half.y - BAND_LEGS.x * ts.y - BAND_LEGS.y * ts.y * 0.5),
		legs.rotation, legs.scale
	)
	canvas.draw_texture_rect_region(tex,
		Rect2(Vector2(0, BAND_LEGS.x * ts.y), Vector2(ts.x, BAND_LEGS.y * ts.y)),
		Rect2(Vector2(-half.x, -BAND_LEGS.y * ts.y * 0.5), Vector2(ts.x, BAND_LEGS.y * ts.y)),
		Color(0.85, 0.85, 0.85), false, TextureRect.STRETCH_SCALE)

	# ── 左臂（贴在躯干后）──
	var arm_l: Bone = _bones["arm_l"]
	canvas.draw_set_transform(
		arm_l.offset + Vector2(-half.x * 0.3, 0), arm_l.rotation, arm_l.scale
	)
	canvas.draw_texture_rect_region(tex,
		Rect2(Vector2(0, BAND_TORSO.x * ts.y), Vector2(ts.x * 0.25, BAND_TORSO.y * ts.y)),
		Rect2(Vector2(-ts.x * 0.125, -BAND_TORSO.y * ts.y * 0.5), Vector2(ts.x * 0.25, BAND_TORSO.y * ts.y)),
		Color(0.75, 0.75, 0.75), false)

	# ── 躯干 ──
	var torso: Bone = _bones["torso"]
	canvas.draw_set_transform(
		torso.offset + Vector2(0, half.y - BAND_TORSO.x * ts.y - BAND_TORSO.y * ts.y * 0.5),
		torso.rotation, torso.scale
	)
	canvas.draw_texture_rect_region(tex,
		Rect2(Vector2(0, BAND_TORSO.x * ts.y), Vector2(ts.x, BAND_TORSO.y * ts.y)),
		Rect2(Vector2(-half.x, -BAND_TORSO.y * ts.y * 0.5), Vector2(ts.x, BAND_TORSO.y * ts.y)),
		Color.WHITE)

	# ── 头部 ──
	var head: Bone = _bones["head"]
	canvas.draw_set_transform(
		head.offset + Vector2(0, -half.y + BAND_HEAD.x * ts.y + BAND_HEAD.y * ts.y * 0.5),
		head.rotation, head.scale
	)
	canvas.draw_texture_rect_region(tex,
		Rect2(Vector2(0, BAND_HEAD.x * ts.y), Vector2(ts.x, BAND_HEAD.y * ts.y)),
		Rect2(Vector2(-half.x, -BAND_HEAD.y * ts.y * 0.5), Vector2(ts.x, BAND_HEAD.y * ts.y)),
		Color.WHITE)

	# ── 右臂（最前层）──
	var arm_r: Bone = _bones["arm_r"]
	canvas.draw_set_transform(
		arm_r.offset + Vector2(half.x * 0.3, 0), arm_r.rotation, arm_r.scale
	)
	canvas.draw_texture_rect_region(tex,
		Rect2(Vector2(ts.x * 0.75, BAND_TORSO.x * ts.y), Vector2(ts.x * 0.25, BAND_TORSO.y * ts.y)),
		Rect2(Vector2(-ts.x * 0.125, -BAND_TORSO.y * ts.y * 0.5), Vector2(ts.x * 0.25, BAND_TORSO.y * ts.y)),
		Color.WHITE)

	# 重置
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
