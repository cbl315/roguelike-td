## juice.gd — 程序化动画状态机（Brotato/VS 风格的 game feel）。
## 单张静态贴图 + 代码驱动的变换：idle呼吸、移动挤压、攻击反馈、生成弹出、命中闪白、死亡爆裂。
## 不需要 sprite sheet，不需要帧动画，不需要新美术资源。
##
## 用法：
##   var _juice := Juice.new()
##   _process: _juice.tick(delta, is_moving, speed_ratio)
##   _draw:    draw_set_transform(_juice.offset, _juice.rotation, _juice.scale)
##             draw_texture(tex, -ts/2)
##             draw_set_transform()  # 重置
extends RefCounted
class_name Juice

# ── 当前动画状态（每帧 tick 更新）──
var _time: float = 0.0
var _scale: Vector2 = Vector2.ONE
var _offset: Vector2 = Vector2.ZERO
var _rotation: float = 0.0
var _flash: float = 0.0
var _alpha: float = 1.0

# ── 动画计时器（>= 0 表示正在播放）──
var _attack_t: float = -1.0
var _spawn_t: float = -1.0
var _death_t: float = -1.0

# ── 可配置参数（按实体类型覆盖）──
var idle_bob_amp: float = 2.0          # idle Y 偏移幅度（像素）
var idle_bob_freq: float = 2.5         # idle 呼吸频率（Hz）
var idle_breathe_amp: float = 0.025    # idle 缩放呼吸幅度
var move_stretch: float = 0.10         # 移动挤压拉伸幅度（面积守恒）
var attack_scale := Vector2(1.20, 0.85)  # 攻击瞬间 scale
var attack_time: float = 0.15          # 攻击反馈持续时间
var spawn_time: float = 0.25           # 生成弹出持续时间
var death_time: float = 0.30           # 死亡动画持续时间
var flash_dur: float = 0.12            # 命中闪白持续时间


func _init() -> void:
	# 随机 idle 相位（多实体不会同步呼吸）
	_time = randf() * 10.0


## 每帧调用：更新所有动画状态。
## is_moving: 是否在移动；speed_ratio: 速度比（0=静止, 1=全速）
func tick(delta: float, is_moving: bool = false, speed_ratio: float = 0.0) -> void:
	_time += delta
	# 更新计时器
	if _attack_t >= 0.0:
		_attack_t += delta
		if _attack_t >= attack_time:
			_attack_t = -1.0
	if _spawn_t >= 0.0:
		_spawn_t += delta
		if _spawn_t >= spawn_time:
			_spawn_t = -1.0
	if _death_t >= 0.0:
		_death_t += delta
	# flash 衰减
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / flash_dur)
	# 重算变换
	_compute(is_moving, speed_ratio)


func _compute(is_moving: bool, speed_ratio: float) -> void:
	var sx: float = 1.0
	var sy: float = 1.0
	var oy: float = 0.0
	_rotation = 0.0
	_alpha = 1.0

	# 1. Idle 呼吸（正弦波，非等比缩放 + Y 偏移）
	var wave: float = sin(_time * idle_bob_freq * TAU)
	sx *= 1.0 + wave * idle_breathe_amp
	sy *= 1.0 - wave * idle_breathe_amp
	oy += wave * idle_bob_amp

	# 2. 移动挤压拉伸（沿移动方向拉伸，垂直方向压缩）
	if is_moving and speed_ratio > 0.01:
		sx *= 1.0 + move_stretch * speed_ratio
		sy *= 1.0 - move_stretch * speed_ratio

	# 3. 攻击反馈（elastic 回弹：从 attack_scale 弹回 1.0）
	if _attack_t >= 0.0:
		var t: float = _attack_t / attack_time
		var bounce: float = _ease_out_elastic(t)
		sx *= lerpf(attack_scale.x, 1.0, bounce)
		sy *= lerpf(attack_scale.y, 1.0, bounce)

	# 4. 生成弹出（ease-out-back：从 0 弹到 1，有过冲）
	if _spawn_t >= 0.0:
		var pop: float = _ease_out_back(clampf(_spawn_t / spawn_time, 0.0, 1.0))
		sx *= pop
		sy *= pop

	# 5. 死亡动画（放大 + 旋转 + 淡出）
	if _death_t >= 0.0:
		var t: float = clampf(_death_t / death_time, 0.0, 1.0)
		var ds: float = 1.0 + t * 0.5    # 放大到 1.5×
		sx *= ds
		sy *= ds
		_rotation = t * PI * 0.5         # 旋转 90°
		_alpha = 1.0 - t                 # 淡出

	_scale = Vector2(sx, sy)
	_offset = Vector2(0.0, oy)


# ── 供 _draw() 读取的当前状态 ──

var scale: Vector2:
	get: return _scale

var offset: Vector2:
	get: return _offset

var rotation: float:
	get: return _rotation

## 命中闪白强度（0=无, 1=全白）
func get_flash() -> float:
	return _flash

## 透明度（死亡时递减到 0）
func get_alpha() -> float:
	return _alpha

## 是否正在播放死亡动画
func is_dying() -> bool:
	return _death_t >= 0.0

## 死亡动画进度（0-1），到达 1.0 时应 queue_free
func death_progress() -> float:
	if _death_t < 0.0:
		return 0.0
	return clampf(_death_t / death_time, 0.0, 1.0)


# ── 触发动画 ──

func play_attack() -> void:
	_attack_t = 0.0

func play_spawn() -> void:
	_spawn_t = 0.0

func play_death() -> void:
	_death_t = 0.0

func play_flash() -> void:
	_flash = 1.0


# ── 缓动函数 ──

## ease-out-back：过冲后回弹（生成弹出用）
static func _ease_out_back(t: float, s: float = 1.70158) -> float:
	t -= 1.0
	return 1.0 + (s + 1.0) * t * t * t + s * t * t

## ease-out-elastic：弹性回弹（攻击反馈用）
static func _ease_out_elastic(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	var p: float = 0.35
	return pow(2.0, -10.0 * t) * sin((t - p / 4.0) * (TAU / p)) + 1.0
