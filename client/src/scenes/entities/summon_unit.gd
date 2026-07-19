## summon_unit.gd — 虚拟召唤单位（莫邪/白魇魔/第三魂宠）
## 跟随英雄移动，自动攻击范围内敌人，不可被选中/受击。
## 有独立 CombatStats（由宠魅羁绊 effect 强化）。
extends Node2D
class_name SummonUnit

signal fired_projectile(target: Node, damage: float)

## 跟随的目标（英雄）
var follow_target: Node2D = null
## 跟随偏移（相对英雄的位置，多只召唤兽不重叠）
var follow_offset: Vector2 = Vector2.ZERO
## 召唤单位标识
var unit_name: String = ""
var unit_id: String = ""    # moxie / baiyanmeng / third_pet
## 独立战斗属性
var stats: CombatStats = null
## 攻击范围
var attack_range: float = 350.0
## 攻击间隔计时
var _fire_timer: float = 0.0
## 当前波全部敌人（由 game_manager 推送）
var all_enemies: Array = []
## 跟随速度
var follow_speed: float = 400.0
## 是否激活（白魇魔被吞噬后 deactivate）
var active: bool = true

# 占位精灵颜色（彩色圆形，不用美术资源）
const COLOR_MOXIE := Color(0.95, 0.35, 0.15)       # 莫邪：橙红色
const COLOR_BAIYANMENG := Color(0.2, 0.85, 0.9)    # 白魇魔：青色
const COLOR_DEFAULT := Color(0.8, 0.8, 0.8)        # 其它召唤单位：灰
const DRAW_RADIUS := 22.0


func _ready() -> void:
	if stats == null:
		stats = CombatStats.new()
		stats.apply_atk_bonus()


func setup(p_name: String, p_id: String, hero: Node2D, offset: Vector2) -> void:
	unit_name = p_name
	unit_id = p_id
	follow_target = hero
	follow_offset = offset
	stats = CombatStats.new()
	stats.apply_atk_bonus()


func set_enemies(enemies: Array) -> void:
	all_enemies = enemies


func _process(delta: float) -> void:
	if not active or follow_target == null or not is_instance_valid(follow_target):
		return
	# 跟随英雄（平滑移动到 follow_target + offset）
	var target_pos: Vector2 = follow_target.global_position + follow_offset
	var dist: float = global_position.distance_to(target_pos)
	if dist > 5.0:
		var step: float = minf(follow_speed * delta, dist)
		global_position = global_position.move_toward(target_pos, step)
	# 攻击逻辑
	if stats == null:
		return
	var in_range: Array = []
	for e in all_enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= attack_range:
			in_range.append(e)
	if in_range.is_empty():
		return
	# 选最近敌人
	var nearest: Node2D = null
	var nearest_dist: float = 999999.0
	for e in in_range:
		var d: float = global_position.distance_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	if nearest == null:
		return
	_fire_timer += delta
	var interval: float = 1.0 / maxf(stats.attack_speed, 0.1)
	if _fire_timer >= interval:
		_fire_timer = 0.0
		_fire(nearest)


func _fire(target: Node2D) -> void:
	var enemy: Enemy = target as Enemy
	if enemy == null:
		return
	var dmg: float = stats.expected_hit_dmg(enemy.armor)
	if dmg <= 0.0:
		return
	fired_projectile.emit(target, dmg)


## 更新属性（羁绊变化时调用）
func refresh_stats(new_stats: CombatStats) -> void:
	stats = new_stats


## 停用（白魇魔被吞噬后调用）
func deactivate() -> void:
	active = false
	visible = false


## 重新激活
func activate() -> void:
	active = true
	visible = true


## 占位精灵：按 unit_id 画彩色圆形（莫邪=橙红，白魇魔=青色，其它=灰）
func _draw() -> void:
	var col: Color = COLOR_DEFAULT
	match unit_id:
		"moxie":
			col = COLOR_MOXIE
		"baiyanmeng":
			col = COLOR_BAIYANMENG
	# 外发光
	draw_circle(Vector2.ZERO, DRAW_RADIUS + 6, Color(col.r, col.g, col.b, 0.22))
	# 本体
	draw_circle(Vector2.ZERO, DRAW_RADIUS, col)
	# 描边
	draw_arc(Vector2.ZERO, DRAW_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.5), 1.5)
