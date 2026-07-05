## wave_spawner.gd — 按 WaveCurves 生成敌人到 Path2D。
## 参考 quiver-td：用 Timer 节点（one_shot + 信号）而非手写 _timer+=delta，
## 暂停/缩放自动正确；支持多个 Marker2D 出生点。
extends Node
class_name WaveSpawner

signal enemy_spawned(enemy)
signal wave_finished()

@export var spawn_interval: float = 0.8   # 每只怪间隔秒数

var _path: Path2D
var _spawn_points: Array = []   # Marker2D 列表（预留多入口；空则用 path 起点）
var _enemies_to_spawn: int = 0
var _wave: int = 1
var _spawning: bool = false
var _active_enemies: Array = []   # 当前波活跃敌人

@onready var _spawn_timer: Timer = $SpawnTimer


func setup(path: Path2D) -> void:
	_path = path


func setup_spawn_points(points: Array) -> void:
	_spawn_points = points


func start_wave(wave: int) -> void:
	_wave = wave
	WaveCurves._current_wave = wave
	_enemies_to_spawn = WaveCurves.enemy_count(wave)
	_spawning = true
	# 第一只立刻刷，后续按间隔（quiver-td 模式）
	_spawn_timer.wait_time = 0.1
	_spawn_timer.start()


func _on_spawn_timer_timeout() -> void:
	if not _spawning:
		return
	if _enemies_to_spawn > 0:
		_spawn_one()
		_enemies_to_spawn -= 1
	if _enemies_to_spawn > 0:
		_spawn_timer.wait_time = spawn_interval
		_spawn_timer.start()
	else:
		_spawning = false


func _spawn_one() -> void:
	var enemy: Enemy = Enemy.new()
	# Enemy 是 Node2D（手动跟随路径），加到 spawner 自身下
	add_child(enemy)
	var hp: float = WaveCurves.enemy_hp(_wave)
	enemy.setup(hp, WaveCurves.is_boss_wave(_wave), WaveCurves.is_elite_wave(_wave), _path)
	# 多出生点：随机选一个偏移起点（暂以 path 起点为基准，预留扩展）
	enemy.reached_core.connect(_on_enemy_reached_core)
	enemy.died.connect(_on_enemy_died)
	_active_enemies.append(enemy)
	enemy_spawned.emit(enemy)


func _on_enemy_reached_core(enemy: Enemy, leak_damage: float) -> void:
	_remove_enemy(enemy)
	# 伤害由 enemy 数据驱动传入（不再 game_manager 硬编码）
	EventBus.enemy_reached_core.emit(enemy, leak_damage)


func _on_enemy_died(enemy: Enemy) -> void:
	_remove_enemy(enemy)
	EventBus.enemy_killed.emit(enemy)


func _remove_enemy(enemy: Enemy) -> void:
	_active_enemies.erase(enemy)
	# 全清且不再生成 → 波结束
	if not _spawning and _active_enemies.is_empty():
		wave_finished.emit()


func active_enemies() -> Array:
	return _active_enemies


func is_active() -> bool:
	return _spawning or not _active_enemies.is_empty()
