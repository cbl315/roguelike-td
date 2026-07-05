## hero.gd — 英雄 = 核心（M2 改：英雄就是防守目标，怪朝英雄走，打英雄=扣血）。
## 自动攻击全屏范围内的敌人。点击切换目标优先级。
extends Node2D
class_name Hero

signal target_priority_changed(mode)
signal fired_projectile(target: Node, damage: float)
signal hp_changed(hp: float, max_hp: float)
signal destroyed()

@export var max_hp: float = 1000.0
@export var radius: float = 32.0

var current_hp: float = 1000.0
var target_priority: int = 0   # TargetPriority.Mode
var _fire_timer: float = 0.0
var _enemies_in_range: Array = []
var build: BuildState = null
var _stats: CombatStats = null

@onready var _priority_label: Label = $PriorityLabel


func _ready() -> void:
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)
	_update_priority_label()


func set_enemies(enemies: Array) -> void:
	_enemies_in_range = enemies


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
	if _stats == null:
		refresh_stats()
	# 全屏范围：所有有效敌人都在射程内
	var in_range: Array = []
	for e in _enemies_in_range:
		if is_instance_valid(e):
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


func _fire(target: Node2D) -> void:
	var enemy: Enemy = target as Enemy
	if enemy == null:
		return
	var dmg: float = _stats.expected_hit_dmg(enemy.armor)
	# 伤害改由弹道到达目标时结算（锁定式，不会误伤途中敌人）
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
	# 外发光
	draw_circle(Vector2.ZERO, radius + 8, Color(0.4, 0.6, 1.0, 0.25))
	# 本体（蓝，hp 越低越偏红）
	var col := Color(0.45, 0.65 * hp_ratio + 0.2, 1.0 * hp_ratio + 0.2)
	draw_circle(Vector2.ZERO, radius, col)
	# HP 环（英雄即核心，显示血量环）
	draw_arc(Vector2.ZERO, radius + 14, -TAU / 2, -TAU / 2 + TAU * hp_ratio, 48, Color(0.4, 1.0, 0.5), 4.0)
