## projectile.gd — 追踪式投射物（锁定目标，飞行到达才结算伤害）。
## 参考 quiver-td projectile/missile：持有 target 引用，每帧追向 target 当前位置，
## 到达时对原目标造成伤害（不会误伤途中经过的其他敌人）。
## #3: 带拖尾特效（程序化绘制，零美术依赖）。
extends Node2D
class_name Projectile

signal hit_target(target: Node, damage: float)

@export var speed: float = 1200.0
@export var radius: float = 6.0
@export var arrive_dist: float = 14.0   # 距目标多近视为"到达"

var _target: Node2D = null
var _damage: float = 0.0
var _life: float = 0.0
const MAX_LIFE := 2.0

## #3: 拖尾历史位置（最近 6 帧）
var _trail: Array = []
const TRAIL_LEN := 6


func _ready() -> void:
	z_index = 50   # 置于顶层，不被路径/敌人体遮挡


## from=发射点, target=锁定目标, damage=到达时结算的伤害
func setup(from: Vector2, target: Node2D, damage: float) -> void:
	global_position = from
	_target = target
	_damage = damage


func _process(delta: float) -> void:
	# 目标已失效（死亡/释放）→ 弹道直接消失（伤害不结算）
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return
	var dir: Vector2 = _target.global_position - global_position
	var dist: float = dir.length()
	if dist < arrive_dist:
		# 到达：对锁定的原目标结算伤害（不会误伤途中敌人）
		_target.take_damage(_damage)
		hit_target.emit(_target, _damage)
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


func _draw() -> void:
	# #3: 拖尾（从旧到新，逐渐变亮变大）
	for i in range(_trail.size()):
		var t: float = 1.0 - float(i) / float(TRAIL_LEN)   # 0=最旧, 1=最新
		var alpha: float = t * 0.5
		var r: float = radius * (0.3 + t * 0.7)
		draw_circle(_trail[i], r, Color(1.0, 0.9, 0.3, alpha))
	# 发光 + 本体
	draw_circle(Vector2.ZERO, radius + 3, Color(1.0, 0.9, 0.3, 0.4))
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.95, 0.4))
