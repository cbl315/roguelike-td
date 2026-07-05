## enemy.gd — 敌人：沿路径移动，有 HP，到终点扣核心血。
## 用 progress_ratio (0..1) 移动，避免 bake 长度异常导致瞬间到终点。
extends Node2D
class_name Enemy

signal reached_core(enemy, leak_damage: float)
signal died(enemy)

@export var max_hp: float = 100.0
@export var progress_per_sec: float = 0.06   # 每秒沿路径前进的比例（0.06 = ~17秒走完）
@export var is_boss: bool = false
@export var is_elite: bool = false
@export var radius: float = 18.0
## 击杀奖励金币（数据驱动，参考 quiver-td enemy.kill_reward）
@export var kill_reward: float = 2.0
## 漏到核心造成的伤害（数据驱动）
@export var leak_damage: float = 30.0

var current_hp: float = 100.0:
	set = set_current_hp
var armor: float = 20.0
var _path: Path2D
var _progress: float = 0.0    # 0..1 沿路径进度
var _dead: bool = false


func _ready() -> void:
	current_hp = max_hp
	z_index = 20


## 血量 setter：归零自动触发死亡（参考 quiver-td set_health 模式）
func set_current_hp(value: float) -> void:
	current_hp = maxf(0.0, value)
	queue_redraw()
	if current_hp <= 0.0 and not _dead:
		_dead = true
		died.emit(self)
		queue_free()


func setup(hp: float, boss: bool, elite: bool, path: Path2D) -> void:
	# 直接用 B 路线校准曲线（base 100, growth 1.05），不再 ×4。
	# 早先 ×4 是 M1 band-aid，反而让前波怪太耐打、手感发滞。
	max_hp = hp
	current_hp = max_hp
	is_boss = boss
	is_elite = elite
	_path = path
	armor = 20.0
	radius = 30.0 if boss else (24.0 if elite else 18.0)
	# 移动速度：progress/sec。baked_length≈3236，0.10 ≈ 10 秒走完全程（~324px/s）。
	progress_per_sec = 0.05 if boss else (0.07 if elite else 0.10)
	# 击杀奖励/漏怪伤害随类型递增（数据驱动，避免 game_manager 硬编码）
	kill_reward = 8.0 if boss else (4.0 if elite else 2.0)
	leak_damage = (60.0 + 10.0 * WaveCurves._current_wave) if boss else (40.0 + 5.0 * WaveCurves._current_wave) if elite else (30.0 + 5.0 * WaveCurves._current_wave)
	_progress = 0.0
	_update_pos()


func _process(delta: float) -> void:
	if _path == null:
		return
	_progress += progress_per_sec * delta
	if _progress >= 1.0:
		reached_core.emit(self, leak_damage)
		queue_free()
		return
	_update_pos()
	queue_redraw()


func _update_pos() -> void:
	if _path == null or _path.curve == null:
		return
	# 用 progress(0..1) 映射到曲线长度
	var baked_len: float = _path.curve.get_baked_length()
	if baked_len <= 0.1:
		return   # 曲线异常，不动（避免位置错乱）
	var dist: float = _progress * baked_len
	var local: Vector2 = _path.curve.sample_baked(dist)
	global_position = _path.to_global(local)


func take_damage(amount: float) -> void:
	current_hp -= amount   # 走 setter，归零自动触发 died


func _draw() -> void:
	var hp_ratio := clampf(current_hp / max_hp, 0.0, 1.0)
	var col := Color(1.0, 0.25 + 0.4 * (1.0 - hp_ratio), 0.3 + 0.3 * (1.0 - hp_ratio))
	if is_boss:
		col = Color(1.0, 0.4, 0.8)
	elif is_elite:
		col = Color(1.0, 0.6, 0.3)
	draw_circle(Vector2.ZERO, radius + 6, Color(col.r, col.g, col.b, 0.25))
	draw_circle(Vector2.ZERO, radius, col)
	var bar_w := radius * 1.6
	draw_rect(Rect2(-bar_w / 2, -radius - 12, bar_w, 4), Color(0.2, 0.2, 0.25), true)
	draw_rect(Rect2(-bar_w / 2, -radius - 12, bar_w * hp_ratio, 4), Color(0.9, 0.2, 0.3), true)
