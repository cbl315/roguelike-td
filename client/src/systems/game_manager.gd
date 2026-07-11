## game_manager.gd — 波次状态机 + 英雄血量/金币管理（M2：英雄=核心）。
## 英雄既是防守目标又是输出。怪到英雄=扣英雄血；英雄血归零=失败。
extends Node2D
class_name GameManager

enum State { READY, WAVE_IN_PROGRESS, WAVE_CLEARED, RUN_WON, RUN_LOST }

@export var hero_hp: float = 1000.0
@export var wave_break: float = 1.5

var state: int = State.READY
var current_wave: int = 0
var skill_upgrades_banked: int = 0

var _spawner: WaveSpawner
var _hero: Hero
var _hud: HUD
var _lobby: Lobby
var _break_timer: float = 0.0
var _build: BuildState
var _pools: RoguePools
var _started: bool = false


func _ready() -> void:
	_spawner = $WaveSpawner
	_hero = $Hero
	_hud = get_node("../HUD")
	_lobby = get_node("../Lobby")
	# 房间边界（与 main.tscn RoomBorder 一致）
	var room_rect := Rect2(80, 80, 1760, 920)
	_spawner.setup(_hero, room_rect)
	_hero.room_rect = room_rect
	_hero.max_hp = hero_hp
	_hero.current_hp = hero_hp
	# M2: build 系统
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_pools = RoguePools.new(rng)
	_build = BuildState.new()
	_build.setup(_pools, rng)
	_hero.build = _build
	_hero.refresh_stats()
	# 信号
	_spawner.wave_finished.connect(_on_wave_finished)
	_hero.hp_changed.connect(_on_hero_hp_changed)
	_hero.destroyed.connect(_on_hero_destroyed)
	EventBus.enemy_reached_core.connect(_on_enemy_reached_hero)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	_hero.fired_projectile.connect(_on_hero_fired)
	_lobby.confirmed.connect(_on_lobby_confirmed)
	_hud.skill_picker_requested.connect(open_skill_picker)
	_hud.bond_picker_requested.connect(open_bond_picker)
	call_deferred("_start_next_wave")


func _process(delta: float) -> void:
	match state:
		State.WAVE_IN_PROGRESS:
			_hero.set_enemies(_spawner.active_enemies())
			_hud.update_enemy_count(_spawner.active_enemies().size())
		State.WAVE_CLEARED:
			_break_timer -= delta
			if _break_timer <= 0.0:
				_start_next_wave()


func _start_next_wave() -> void:
	_started = true
	current_wave += 1
	if current_wave > WaveCurves.main_quest_waves():
		state = State.RUN_WON
		EventBus.run_won.emit()
		if _hud: _hud.show_result(true)
		return
	state = State.WAVE_IN_PROGRESS
	EventBus.wave_started.emit(current_wave)
	if _hud: _hud.update_wave(current_wave)
	skill_upgrades_banked += 2 if WaveCurves.is_boss_wave(current_wave) else 1
	EventBus.skill_upgrade_available = skill_upgrades_banked
	_lobby.set_build_ref(_build, _pools)
	_lobby.update_banked(skill_upgrades_banked)
	_hud.update_skill_count(skill_upgrades_banked)
	_hud.update_gold(_build.gold)
	_hud.update_bond_cost(_build.bond_draw_cost())
	_hero.refresh_stats()
	if _spawner: _spawner.start_wave(current_wave)


func _on_wave_finished() -> void:
	state = State.WAVE_CLEARED
	EventBus.wave_cleared.emit(current_wave)
	var bonus := 30.0 + 5.0 * current_wave
	_build.add_gold(bonus)
	EventBus.gold_changed.emit(_build.gold)
	if _hud: _hud.update_gold(_build.gold)
	_break_timer = wave_break


func _on_lobby_confirmed() -> void:
	skill_upgrades_banked = _lobby._banked
	EventBus.skill_upgrade_available = skill_upgrades_banked
	_hud.update_skill_count(skill_upgrades_banked)
	_hud.update_gold(_build.gold)
	_hero.refresh_stats()


func open_skill_picker() -> void:
	if skill_upgrades_banked <= 0:
		return
	get_tree().paused = true
	_lobby.set_build_ref(_build, _pools)
	_lobby.open_skill(skill_upgrades_banked)


func open_bond_picker() -> void:
	if _build.gold < _build.bond_draw_cost():
		return
	get_tree().paused = true
	_lobby.set_build_ref(_build, _pools)
	_lobby.open_bond()


func _on_hero_hp_changed(hp: float, max_hp: float) -> void:
	EventBus.core_hp_changed.emit(hp, max_hp)
	_hud.update_core_hp(hp, max_hp)


func _on_hero_destroyed() -> void:
	state = State.RUN_LOST
	EventBus.run_lost.emit(current_wave)
	_hud.show_result(false)


## 怪走到英雄位置 → 扣英雄血（GDD：怪漏到核心）
## 伤害由 enemy.leak_damage 数据驱动传入（随波数/类型递增）
func _on_enemy_reached_hero(enemy: Node, dmg: float) -> void:
	_hero.take_damage(dmg)


## 击杀奖励：金额由 enemy.kill_reward 数据驱动（GDD §3.4 per_kill）
func _on_enemy_killed(enemy: Node) -> void:
	var e: Enemy = enemy as Enemy
	var reward: float = e.kill_reward if e != null else 2.0
	_build.add_gold(reward)
	EventBus.gold_changed.emit(_build.gold)
	_hud.update_gold(_build.gold)


func _on_hero_fired(target: Node, dmg: float) -> void:
	var proj := Projectile.new()
	add_child(proj)
	proj.setup(_hero.global_position, target, dmg)
