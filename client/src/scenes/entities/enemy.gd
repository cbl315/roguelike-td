## enemy.gd — 敌人：房间内自主移动，追击英雄，有 HP。
## 土豆兄弟式：不再沿固定 Path2D，而是直接朝英雄移动 + 房间边界约束。
extends Node2D
class_name Enemy

signal reached_core(enemy, leak_damage: float)
signal died(enemy)

@export var max_hp: float = 100.0
@export var is_boss: bool = false
@export var is_elite: bool = false
@export var radius: float = 18.0
## 击杀奖励金币（数据驱动）
@export var kill_reward: float = 2.0
## 接触英雄造成的伤害（数据驱动）
@export var leak_damage: float = 30.0
## 移动速度（像素/秒）
@export var move_speed: float = 120.0
## 接触英雄的距离（触发 leak_damage）
@export var contact_dist: float = 40.0
## 接触后重新攻击的冷却（秒）
@export var contact_cooldown: float = 1.0

var current_hp: float = 100.0:
	set = set_current_hp
var armor: float = 20.0
var _hero: Node2D = null
var _dead: bool = false
var _contact_cd: float = 0.0   # 接触冷却剩余

## 房间边界（由 spawner 设置）
var _room_rect: Rect2 = Rect2(80, 80, 1760, 920)


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


func setup(hp: float, boss: bool, elite: bool, hero: Node2D, room_rect: Rect2) -> void:
	max_hp = hp
	current_hp = max_hp
	is_boss = boss
	is_elite = elite
	_hero = hero
	_room_rect = room_rect
	armor = 20.0
	radius = 30.0 if boss else (24.0 if elite else 18.0)
	# 移动速度：boss 慢、精英中、普通快（像素/秒）
	move_speed = 60.0 if boss else (90.0 if elite else 120.0)
	# 击杀奖励/接触伤害随类型递增
	kill_reward = 8.0 if boss else (4.0 if elite else 2.0)
	leak_damage = (60.0 + 10.0 * WaveCurves._current_wave) if boss else (40.0 + 5.0 * WaveCurves._current_wave) if elite else (30.0 + 5.0 * WaveCurves._current_wave)
	contact_dist = 36.0 if boss else (32.0 if elite else 28.0)


func _process(delta: float) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	# 朝英雄移动
	var dir: Vector2 = (_hero.global_position - global_position)
	var dist: float = dir.length()
	if dist > contact_dist:
		var step: float = move_speed * delta
		if dist > step:
			global_position += dir.normalized() * step
		else:
			global_position = _hero.global_position
	# 接触英雄：造成伤害 + 进冷却
	_contact_cd -= delta
	if dist <= contact_dist and _contact_cd <= 0.0:
		_contact_cd = contact_cooldown
		reached_core.emit(self, leak_damage)
	# 房间边界约束
	global_position.x = clampf(global_position.x, _room_rect.position.x, _room_rect.position.x + _room_rect.size.x)
	global_position.y = clampf(global_position.y, _room_rect.position.y, _room_rect.position.y + _room_rect.size.y)
	queue_redraw()


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
