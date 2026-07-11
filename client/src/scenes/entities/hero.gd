## hero.gd — 英雄 = 核心：玩家操控移动（WASD/方向键），自动攻击范围内敌人。
## 房间生存式（土豆兄弟）：英雄可自由移动，怪追击英雄，英雄自动开火。
extends Node2D
class_name Hero

signal target_priority_changed(mode)
signal fired_projectile(target: Node, damage: float)
signal hp_changed(hp: float, max_hp: float)
signal destroyed()

@export var max_hp: float = 1000.0
@export var radius: float = 32.0
## 玩家移动速度（像素/秒）
@export var move_speed: float = 320.0
## 攻击范围（像素半径）
@export var attack_range: float = 450.0

var current_hp: float = 1000.0
var target_priority: int = 0   # TargetPriority.Mode
var _fire_timer: float = 0.0
var _all_enemies: Array = []   # 当前波全部敌人（由 game_manager 每帧推送）
var build: BuildState = null
var _stats: CombatStats = null

## 房间边界（由 game_manager 设置）
var room_rect: Rect2 = Rect2(80, 80, 2840, 1840)

@onready var _priority_label: Label = $PriorityLabel


func _ready() -> void:
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)
	_update_priority_label()


func set_enemies(enemies: Array) -> void:
	_all_enemies = enemies


func take_damage(amount: float) -> void:
	current_hp = maxf(0.0, current_hp - amount)
	hp_changed.emit(current_hp, max_hp)
	queue_redraw()
	if current_hp <= 0.0:
		destroyed.emit()


func refresh_stats() -> void:
	if build != null:
		_stats = build.assemble_stats()
	else:
		_stats = CombatStats.new()
		_stats.apply_atk_bonus()


func _process(delta: float) -> void:
	_handle_movement(delta)
	if _stats == null:
		refresh_stats()
	# 筛选攻击范围内的敌人
	var in_range: Array = []
	for e in _all_enemies:
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= attack_range:
			in_range.append(e)
	if in_range.is_empty():
		return
	var target: Node2D = TargetPriority.pick(in_range, target_priority, global_position)
	if target == null:
		return
	_fire_timer += delta
	var interval: float = 1.0 / _stats.attack_speed
	if _fire_timer >= interval:
		_fire_timer = 0.0
		_fire(target)


## 玩家操控移动：WASD / 方向键，房间边界约束
func _handle_movement(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if dir != Vector2.ZERO:
		global_position += dir.normalized() * move_speed * delta
		# 房间边界约束
		global_position.x = clampf(global_position.x, room_rect.position.x, room_rect.position.x + room_rect.size.x)
		global_position.y = clampf(global_position.y, room_rect.position.y, room_rect.position.y + room_rect.size.y)
		queue_redraw()


func _fire(target: Node2D) -> void:
	var enemy: Enemy = target as Enemy
	if enemy == null:
		return
	var dmg: float = _stats.expected_hit_dmg(enemy.armor)
	# 伤害由弹道到达目标时结算（锁定式，不会误伤途中敌人）
	fired_projectile.emit(target, dmg)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.distance_to(global_position) <= radius + 16:
			cycle_priority()
			get_viewport().set_input_as_handled()


func cycle_priority() -> void:
	target_priority = TargetPriority.next_mode(target_priority)
	_update_priority_label()
	target_priority_changed.emit(target_priority)


func _update_priority_label() -> void:
	if _priority_label:
		_priority_label.text = "目标:" + TargetPriority.label(target_priority)


func _draw() -> void:
	var hp_ratio := clampf(current_hp / max_hp, 1e-05, 1.0)
	# 攻击范围圈（半透明）
	draw_circle(Vector2.ZERO, attack_range, Color(0.3, 0.4, 0.6, 0.06))
	draw_arc(Vector2.ZERO, attack_range, 0, TAU, 64, Color(0.3, 0.4, 0.6, 0.2), 1.5)
	# 外发光
	draw_circle(Vector2.ZERO, radius + 8, Color(0.4, 0.6, 1.0, 0.25))
	# 本体（蓝，hp 越低越偏红）
	var col := Color(0.45, 0.65 * hp_ratio + 0.2, 1.0 * hp_ratio + 0.2)
	draw_circle(Vector2.ZERO, radius, col)
	# HP 环（英雄即核心，显示血量环）
	draw_arc(Vector2.ZERO, radius + 14, -TAU / 2, -TAU / 2 + TAU * hp_ratio, 48, Color(0.4, 1.0, 0.5), 4.0)
