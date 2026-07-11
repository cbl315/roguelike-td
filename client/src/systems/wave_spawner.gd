## wave_spawner.gd — 按 WaveCurves 生成敌人（房间生存式）。
## 敌人在房间边缘随机位置出生，追击英雄。参考 quiver-td Timer 节点驱动。
extends Node
class_name WaveSpawner

signal enemy_spawned(enemy)
signal wave_finished()

@export var spawn_interval: float = 0.8   # 每只怪间隔秒数

var _hero: Node2D = null
var _room_rect: Rect2 = Rect2(80, 80, 2840, 1840)
var _enemies_to_spawn: int = 0
var _wave: int = 1
var _spawning: bool = false
var _active_enemies: Array = []   # 当前波活跃敌人
var _rng := RandomNumberGenerator.new()

@onready var _spawn_timer: Timer = $SpawnTimer


func setup(hero: Node2D, room_rect: Rect2) -> void:
	_hero = hero
	_room_rect = room_rect
	_rng.randomize()


func start_wave(wave: int) -> void:
	_wave = wave
	WaveCurves._current_wave = wave
	var count: int = WaveCurves.enemy_count(wave)
	_enemies_to_spawn = count
	_spawning = true
	# #7: 渐进式刷怪 — 间隔 = 波次时长 / 敌人数量（均匀铺满整波，波越大刷越快）
	var dur: float = WaveCurves.wave_duration(wave)
	spawn_interval = maxf(0.3, dur / float(count))
	# 首只延迟 1 秒（给"波次开始了"的缓冲）
	_spawn_timer.wait_time = 1.0
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
	add_child(enemy)
	var hp: float = WaveCurves.enemy_hp(_wave)
	enemy.setup(hp, WaveCurves.is_boss_wave(_wave), WaveCurves.is_elite_wave(_wave), _hero, _room_rect)
	# 在房间边缘随机位置出生（离英雄有一定距离）
	enemy.global_position = _random_edge_pos()
	enemy.reached_core.connect(_on_enemy_reached_core)
	enemy.died.connect(_on_enemy_died)
	_active_enemies.append(enemy)
	enemy_spawned.emit(enemy)


## 在房间边缘随机选一个出生点（离英雄至少 300px，避免贴脸刷）
func _random_edge_pos() -> Vector2:
	var margin: float = 60.0
	var hero_pos: Vector2 = _hero.global_position if _hero != null else _room_rect.get_center()
	for _attempt in 10:
		var side: int = _rng.randi() % 4
		var pos: Vector2 = Vector2.ZERO
		match side:
			0: # 上边
				pos = Vector2(_rng.randf_range(_room_rect.position.x + margin, _room_rect.position.x + _room_rect.size.x - margin), _room_rect.position.y + margin)
			1: # 下边
				pos = Vector2(_rng.randf_range(_room_rect.position.x + margin, _room_rect.position.x + _room_rect.size.x - margin), _room_rect.position.y + _room_rect.size.y - margin)
			2: # 左边
				pos = Vector2(_room_rect.position.x + margin, _rng.randf_range(_room_rect.position.y + margin, _room_rect.position.y + _room_rect.size.y - margin))
			3: # 右边
				pos = Vector2(_room_rect.position.x + _room_rect.size.x - margin, _rng.randf_range(_room_rect.position.y + margin, _room_rect.position.y + _room_rect.size.y - margin))
		if pos.distance_to(hero_pos) >= 300.0:
			return pos
	return Vector2(_room_rect.position.x + margin, _room_rect.position.y + margin)


func _on_enemy_reached_core(enemy: Enemy, leak_damage: float) -> void:
	# 敌人接触英雄造成伤害，但不移除敌人（持续追击）
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


## 强制停止刷怪（波次超时时调用，剩余待刷的不刷了）
func stop_spawning() -> void:
	_spawning = false
	_enemies_to_spawn = 0
	_spawn_timer.stop()


func is_active() -> bool:
	return _spawning or not _active_enemies.is_empty()
