## projectile.gd — 追踪式投射物（锁定目标，飞行到达才结算伤害）。
## 参考 quiver-td projectile/missile：持有 target 引用，每帧追向 target 当前位置，
## 到达时对原目标造成伤害（不会误伤途中经过的其他敌人）。
## #3: 带拖尾特效（程序化绘制，零美术依赖）。
extends Node2D
class_name Projectile

signal hit_target(target: Node, damage: float, is_crit: bool)

@export var speed: float = 1200.0
@export var radius: float = 6.0
@export var arrive_dist: float = 14.0   # 距目标多近视为"到达"

var _target: Node2D = null
var _damage: float = 0.0
var _crit: bool = false
var _life: float = 0.0
const MAX_LIFE := 2.0

# ── 敌方直线弹道（可躲避）：发射瞬间锁定方向，飞行中不再追踪英雄 ──
var _enemy_linear := false
var _hero: Node2D = null
var _vel_dir: Vector2 = Vector2.ZERO
const ENEMY_MAX_LIFE := 3.0      # 超时消失（飞出有效范围）
const HERO_HIT_DIST := 40.0      # 弹心-英雄中心命中判定（radius 32 + 弹体余量）

## #3: 拖尾历史位置（最近 6 帧）
var _trail: Array = []
const TRAIL_LEN := 6


func _ready() -> void:
	z_index = 50   # 置于顶层，不被路径/敌人体遮挡
	# Additive 混合：黑色=透明、亮色=发光，天然消除特效贴图的抠图残留背景
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_juice.play_spawn()
	_juice.spawn_time = 0.08   # 弹道弹出比角色快


## from=发射点, target=锁定目标, damage=到达时结算的伤害, crit=是否暴击（伤害数字用）
func setup(from: Vector2, target: Node2D, damage: float, crit: bool = false) -> void:
	global_position = from
	_target = target
	_damage = damage
	_crit = crit


## 敌方弹道（可躲避）：直线飞行 + 碰撞命中。方向在发射瞬间锁定，
## 英雄走位可躲开（飞过头即落空）；命中才结算伤害。
func setup_enemy(from: Vector2, hero: Node2D, damage: float, spd: float) -> void:
	global_position = from
	_hero = hero
	_damage = damage
	speed = spd
	_enemy_linear = true
	_vel_dir = (hero.global_position - from).normalized()   # 只取发射瞬间的方向


func _process(delta: float) -> void:
	if _enemy_linear:
		_process_enemy_linear(delta)
		return
	# 目标已失效（死亡/释放）→ 弹道直接消失（伤害不结算）
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return
	var dir: Vector2 = _target.global_position - global_position
	var dist: float = dir.length()
	if dist < arrive_dist:
		# 到达：对锁定的原目标结算伤害（不会误伤途中敌人）
		_target.take_damage(_damage)
		hit_target.emit(_target, _damage, _crit)
		queue_free()
		return
	global_position += dir.normalized() * speed * delta
	# #3: 记录拖尾位置（local 坐标，相对于 projectile 自身）
	_trail.push_front(Vector2.ZERO)   # 当前位置就是局部原点
	if _trail.size() > TRAIL_LEN:
		_trail.pop_back()
	_life += delta
	if _life > MAX_LIFE:
		queue_free()
	_juice.tick(delta, true, 1.0)   # 飞行中持续拉伸
	queue_redraw()                  # juice 变换需要每帧重绘


## 敌方直线弹道：直线飞行 → 碰撞命中 / 超时消失（可躲避的核心）
func _process_enemy_linear(delta: float) -> void:
	if _hero == null or not is_instance_valid(_hero):
		queue_free()   # 英雄失效（重开等）→ 弹道清场
		return
	global_position += _vel_dir * speed * delta
	_life += delta
	# 命中判定：弹心与英雄中心足够近才结算（走位躲开 = 落空）
	if global_position.distance_to(_hero.global_position) <= HERO_HIT_DIST:
		_hero.take_damage(_damage)
		queue_free()
		return
	if _life > ENEMY_MAX_LIFE:
		queue_free()
		return
	_trail.push_front(Vector2.ZERO)
	if _trail.size() > TRAIL_LEN:
		_trail.pop_back()
	_juice.tick(delta, true, 1.0)
	queue_redraw()


var _sprite_tex: Texture2D = null
var _juice := Juice.new()


## 加载弹道贴图
func set_sprite(tex: Texture2D) -> void:
	_sprite_tex = tex


func _draw() -> void:
	# 拖尾（贴图/色块通用）
	for i in range(_trail.size()):
		var t: float = 1.0 - float(i) / float(TRAIL_LEN)
		var alpha: float = t * 0.5
		var r: float = radius * (0.3 + t * 0.7)
		draw_circle(_trail[i], r, Color(1.0, 0.9, 0.3, alpha))
	# 本体：应用 juice 变换（生成弹出）
	draw_set_transform(_juice.offset, _juice.rotation, _juice.scale)
	if _sprite_tex:
		var ts: Vector2 = _sprite_tex.get_size()
		draw_texture(_sprite_tex, -ts / 2)
	else:
		# 发光 + 色块本体
		draw_circle(Vector2.ZERO, radius + 3, Color(1.0, 0.9, 0.3, 0.4))
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.95, 0.4))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
