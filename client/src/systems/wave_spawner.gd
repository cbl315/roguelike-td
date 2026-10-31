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
## Boss Debuff 系统（game_manager 注入；急行之令/不灭之躯/回春之核作用于怪）
var boss_debuffs: BossDebuffs = null

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
	var is_boss: bool = WaveCurves.is_boss_wave(_wave)
	var is_elite: bool = WaveCurves.is_elite_wave(_wave)
	enemy.setup(hp, is_boss, is_elite, _hero, _room_rect)
	# Boss Debuff：急行之令（全怪移速）/ 不灭之躯（Boss 血量）/ 回春之核（Boss 回血）
	if boss_debuffs != null:
		boss_debuffs.modify_enemy(enemy, is_boss)
	# 行为分配：普通怪按配比（Boss/精英保持追击强化）
	if not is_boss and not is_elite:
		var kind := _pick_kind()
		if kind != Enemy.Kind.CHASER:
			_apply_kind(enemy, kind, hp)
	# 美术：按类型装载敌人贴图
	var tex: Texture2D = null
	if is_boss:
		tex = SpriteAtlas.get_boss_enemy_tex(_wave)
	elif is_elite:
		tex = SpriteAtlas.get_elite_enemy_tex(_rng)
	elif enemy.kind != Enemy.Kind.CHASER:
		tex = SpriteAtlas.get_enemy_tex_by_kind(enemy.kind)
	else:
		tex = SpriteAtlas.get_normal_enemy_tex(_rng)
	if tex:
		enemy.set_sprite(tex)
	# 在房间边缘随机位置出生（离英雄有一定距离）
	enemy.global_position = _random_edge_pos()
	enemy.reached_core.connect(_on_enemy_reached_core)
	enemy.died.connect(_on_enemy_died)
	_active_enemies.append(enemy)
	enemy_spawned.emit(enemy)


# ── 行为配比（数值轮 2026-10：中等强度，模拟同步见 run_sim ENEMY_BEHAVIOR_*）──
const KIND_MIX := [
	{"kind": Enemy.Kind.RANGED, "from_wave": 5, "ratio": 0.15},
	{"kind": Enemy.Kind.SPLITTER, "from_wave": 8, "ratio": 0.12},
	{"kind": Enemy.Kind.HEALER, "from_wave": 12, "ratio": 0.07},
]


func _pick_kind() -> int:
	for m in KIND_MIX:
		if _wave >= m["from_wave"] and _rng.randf() < m["ratio"]:
			return m["kind"]
	return Enemy.Kind.CHASER


## 行为特化属性（基础 setup 之后的覆盖）
func _apply_kind(enemy: Enemy, kind: int, base_hp: float) -> void:
	enemy.kind = kind
	match kind:
		Enemy.Kind.RANGED:
			enemy.move_speed = 95.0          # 0.8×，风筝
		Enemy.Kind.SPLITTER:
			enemy.max_hp = base_hp * 1.15    # 大只耐打
			enemy.current_hp = enemy.max_hp
			enemy.radius = 22.0
		Enemy.Kind.HEALER:
			enemy.move_speed = 78.0          # 0.65×，慢随


## 分裂怪死亡 → 裂 2 只 mini（30% 血、更快、不再分裂）
func _on_enemy_died(enemy: Enemy) -> void:
	if enemy.kind == Enemy.Kind.SPLITTER and not enemy.is_mini and not enemy.is_boss:
		for i in 2:
			var mini := Enemy.new()
			add_child(mini)
			mini.setup(enemy.max_hp / 1.15 * 0.30, false, false, _hero, _room_rect)
			mini.is_mini = true
			mini.radius = 13.0
			mini.move_speed = enemy.move_speed * 1.35
			mini.kill_reward = enemy.kill_reward * 0.5
			if boss_debuffs != null:
				boss_debuffs.modify_enemy(mini, false)
			mini.global_position = enemy.global_position + Vector2(28 if i == 0 else -28, 12)
			mini.reached_core.connect(_on_enemy_reached_core)
			mini.died.connect(_on_enemy_died)
			_active_enemies.append(mini)
			var tex: Texture2D = SpriteAtlas.get_normal_enemy_tex(_rng)
			if tex:
				mini.set_sprite(tex)
	_remove_enemy(enemy)
	EventBus.enemy_killed.emit(enemy)


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
