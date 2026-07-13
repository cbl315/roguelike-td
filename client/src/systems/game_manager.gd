## game_manager.gd — 波次状态机 + 英雄血量/金币管理（M2：英雄=核心）。
## 英雄既是防守目标又是输出。怪到英雄=扣英雄血；英雄血归零=失败。
extends Node2D
class_name GameManager

enum State { READY, WAVE_IN_PROGRESS, WAVE_CLEARED, RUN_WON, RUN_LOST }

@export var hero_hp: float = 1000.0
@export var wave_break: float = 1.5

var state: int = State.READY
var current_wave: int = 0

var _spawner: WaveSpawner
var _hero: Hero
var _hud: HUD
var _lobby: Lobby
var _break_timer: float = 0.0
var _wave_timer: float = 0.0   # #2: 波次倒计时剩余秒
var _gold_tick: float = 0.0   # M3: gold_per_sec 累积器
var _build: BuildState
var _pools: RoguePools
var _started: bool = false


func _ready() -> void:
	_spawner = $WaveSpawner
	_hero = $Hero
	_hud = get_node("../UILayer/HUD")
	_lobby = get_node("../UILayer/Lobby")
	# 房间边界（与 main.tscn RoomBorder 一致：80,80 → 2920,1920）
	var room_rect := Rect2(80, 80, 2840, 1840)
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
	_hud.bond_picker_requested.connect(open_bond_picker)
	_hud.char_panel_toggled.connect(toggle_char_panel)
	_hud.equipment_picker_requested.connect(open_equipment_picker)
	# 开局先弹体系选择面板，选完后再开始第一波
	call_deferred("_show_path_selection")


func _show_path_selection() -> void:
	# 先把 build/pools 传给 lobby（体系选择需要调 build.choose_path）
	_lobby.set_build_ref(_build, _pools)
	# 暂停游戏，弹体系选择面板
	get_tree().paused = true
	_lobby.process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停时 lobby 仍可交互
	_lobby.open_path_selection()


func _process(delta: float) -> void:
	match state:
		State.WAVE_IN_PROGRESS:
			_hero.set_enemies(_spawner.active_enemies())
			_hud.update_enemy_count(_spawner.active_enemies().size())
			# #2: 波次倒计时
			_wave_timer -= delta
			_hud.update_timer(_wave_timer)
			# M3: gold_per_sec 每秒结算
			_gold_tick += delta
			if _gold_tick >= 1.0:
				_gold_tick -= 1.0
				var gps: float = _build.gold_per_sec()
				if gps > 0.0:
					_build.add_gold(gps)
					_hud.update_gold(_build.gold)
			if _wave_timer <= 0.0:
				if _spawner: _spawner.stop_spawning()
				_on_wave_finished()
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
	# #2: 设置波次倒计时
	_wave_timer = WaveCurves.wave_duration(current_wave)
	_lobby.set_build_ref(_build, _pools)
	_hud.update_gold(_build.gold)
	_hud.update_bond_cost(_build.bond_draw_cost())
	_hud.update_equip_state(_build.equip_level, _pools.equip_upgrade_cost(_build.equip_level))
	_hero.refresh_stats()
	if _spawner: _spawner.start_wave(current_wave)


func _on_wave_finished() -> void:
	if state != State.WAVE_IN_PROGRESS:
		return   # 防重复（超时 + 全清可能同时触发）
	state = State.WAVE_CLEARED
	EventBus.wave_cleared.emit(current_wave)
	# #2: 清完怪提前结束 → 剩余时间奖励金币（每秒 2 金）
	var time_bonus: float = 0.0
	if _wave_timer > 0.0:
		time_bonus = ceilf(_wave_timer) * 2.0
	_wave_timer = 0.0
	if _hud: _hud.update_timer(-1.0)   # 隐藏倒计时
	var bonus := 30.0 + 5.0 * current_wave + time_bonus
	_build.add_gold(bonus)
	EventBus.gold_changed.emit(_build.gold)
	if _hud: _hud.update_gold(_build.gold)
	_break_timer = wave_break


func _on_lobby_confirmed() -> void:
	_hud.update_gold(_build.gold)
	_hud.update_bond_cost(_build.bond_draw_cost())
	_hud.update_equip_state(_build.equip_level, _pools.equip_upgrade_cost(_build.equip_level))
	_hero.refresh_stats()
	# 如果是开局选体系后第一次关闭面板 → 开始第一波
	if state == State.READY:
		_start_next_wave()


func open_bond_picker() -> void:
	if _build.gold < _build.bond_draw_cost():
		return
	get_tree().paused = true
	_lobby.set_build_ref(_build, _pools)
	_lobby.open_bond()


## M3: 装备升级入口
func open_equipment_picker() -> void:
	if _build.equip_level >= _pools.equip_max_level():
		return
	var cost: float = _pools.equip_upgrade_cost(_build.equip_level)
	if _build.gold < cost:
		return
	get_tree().paused = true
	_lobby.set_build_ref(_build, _pools)
	_lobby.open_equipment()


func _on_hero_hp_changed(hp: float, max_hp: float) -> void:
	EventBus.core_hp_changed.emit(hp, max_hp)
	_hud.update_core_hp(hp, max_hp)


func _on_hero_destroyed() -> void:
	state = State.RUN_LOST
	get_tree().paused = true   # 暂停游戏，停止所有 _process
	_hud.process_mode = Node.PROCESS_MODE_ALWAYS   # HUD 仍可交互（显示结果）
	EventBus.run_lost.emit(current_wave)
	_hud.show_result(false)


## 怪走到英雄位置 → 扣英雄血（GDD：怪漏到核心）
## 伤害由 enemy.leak_damage 数据驱动传入（随波数/类型递增）
func _on_enemy_reached_hero(enemy: Node, dmg: float) -> void:
	_hero.take_damage(dmg)


## 击杀奖励：金额由 enemy.kill_reward 数据驱动 + 装备经济加成（M3）
func _on_enemy_killed(enemy: Node) -> void:
	var e: Enemy = enemy as Enemy
	var reward: float = e.kill_reward if e != null else 2.0
	# M3: 装备经济效果
	reward += _build.per_kill_bonus()           # per_kill_gold_delta
	reward *= _build.gold_multiplier()          # gold_mult 乘区
	if randf() < _build.double_gold_chance():   # double_gold_chance 概率翻倍
		reward *= 2.0
	_build.add_gold(reward)
	EventBus.gold_changed.emit(_build.gold)
	_hud.update_gold(_build.gold)


func _on_hero_fired(target: Node, dmg: float) -> void:
	var proj := Projectile.new()
	add_child(proj)
	proj.setup(_hero.global_position, target, dmg)
	# 吸血：projectile 命中时按 lifesteal_pct 回血
	proj.hit_target.connect(_on_projectile_hit)


func _on_projectile_hit(target: Node, damage: float) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	if _hero.build == null:
		return
	var stats: CombatStats = _hero.build.assemble_stats()
	var lifesteal: float = stats.lifesteal_pct
	if lifesteal > 0.0:
		_hero.heal(damage * lifesteal)


## #6: 由 HUD 的 Tab 键回调，切换角色面板 + 暂停
func toggle_char_panel() -> void:
	var open: bool = _hud.is_char_panel_open()
	if open:
		_hud.close_character_panel()
		get_tree().paused = false
	else:
		_hud.open_character_panel(_build, _pools)
		get_tree().paused = true


## 按钮点击检测（绕过 GUI 系统：GameManager 是 Node2D，不在 CanvasLayer 下，
## process_mode 默认 INHERIT，_input 正常调用）
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var pos: Vector2 = event.position
	# 左下角固定按钮（SideButtons: offset_top=820, 每个 280×60）
	# 顺序：羁绊(820) / 装备(880) / 角色面板(940)
	if Rect2(40, 820, 280, 60).has_point(pos):
		open_bond_picker()
		get_viewport().set_input_as_handled()
		return
	if Rect2(40, 880, 280, 60).has_point(pos):
		open_equipment_picker()
		get_viewport().set_input_as_handled()
		return
	if Rect2(40, 940, 280, 60).has_point(pos):
		toggle_char_panel()
		get_viewport().set_input_as_handled()
		return
	# lobby 卡片"选择"按钮（CanvasLayer GUI 不工作，手动检测卡片区域）
	if _lobby and _lobby.visible:
		for card in _lobby.card_click_rects:
			if card["rect"].has_point(pos):
				_lobby._on_pick(card["idx"])
				get_viewport().set_input_as_handled()
				return


## Tab/C 键 → 角色面板
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB or event.keycode == KEY_C:
			if _lobby and not _lobby.visible:
				toggle_char_panel()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _hud and _hud.is_char_panel_open():
				toggle_char_panel()
				get_viewport().set_input_as_handled()
