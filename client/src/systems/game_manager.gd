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
var _rng := RandomNumberGenerator.new()

# 召唤单位（宠魅体系）
var _summon_units: Array = []   # Array[SummonUnit]

# Sparkle Lite game feel：场景级反馈（震动/顿帧/闪屏）
var _fb_kill: FeedbackPlayerLite = null       # 击杀普通怪
var _fb_kill_boss: FeedbackPlayerLite = null  # 击杀 Boss（更强）
var _fb_hit: FeedbackPlayerLite = null        # 英雄受击

# Boss Debuff 系统（GDD §12）
var _boss_debuffs := BossDebuffs.new()
var _lobby_reroll_delta: int = 0   # 封印之手：Boss 波后大厅刷新次数增减

# 大招系统（GDD §11）—— 数值定稿（2026-10 数值轮，模拟胜率 ~54%）
const ULT_DMG_MULT := 8.0          # 倍率：expected_hit_dmg × 8（继承 build 乘区，前期全额生效）
const ULT_PER_ENEMY_CAP := 0.22    # 每怪伤害上限 = 该怪当前血 ×22%（数值轮定稿）
var _ult_energy: float = 0.0       # 0..1
var _fb_ult: FeedbackPlayerLite = null

# 局内统计（结算画面用）
var _stats_damage: float = 0.0
var _stats_kills: int = 0
var _stats_boss_kills: int = 0
var _stats_breakthroughs: int = 0
var _stats_gold_earned: float = 0.0


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
	# 美术：英雄贴图（SpriteAtlas 集中预加载）
	if SpriteAtlas.hero_tex:
		_hero.set_sprite(SpriteAtlas.hero_tex)
	_rng.randomize()
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
	# 召唤单位（宠魅体系）：build_state 通过信号通知生成/吞噬
	_build.summon_unit_requested.connect(_on_summon_requested)
	_build.summon_unit_devoured.connect(_on_summon_devoured)
	# 境界吞噬桥接（build_state 不引 EventBus autoload，保持 headless -s 可测）
	_build.realm_devoured.connect(func(p: String, r: int, n: String): EventBus.bond_devoured.emit(p, r, n))
	_lobby.confirmed.connect(_on_lobby_confirmed)
	_hud.bond_picker_requested.connect(open_bond_picker)
	_hud.char_panel_toggled.connect(toggle_char_panel)
	_hud.equipment_picker_requested.connect(open_equipment_picker)
	_hud.restart_requested.connect(_on_restart_requested)
	_hud.ult_requested.connect(_try_release_ult)
	_hud.boss_debuff_reroll_requested.connect(_on_reroll_debuff)
	_hud.boss_debuff_remove_requested.connect(_on_remove_debuff)
	EventBus.bond_devoured.connect(func(_p, _r, _n): _stats_breakthroughs += 1)   # 局内统计
	# 种子机制：开局直接开始第一波（体系种子在羁绊池里选）
	_lobby.set_build_ref(_build, _pools)
	# Boss Debuff：每局抽 3 个绑定 Boss 波
	_boss_debuffs.setup(_rng)
	_spawner.boss_debuffs = _boss_debuffs
	# Sparkle Lite：创建场景级反馈播放器
	_setup_feedbacks()
	call_deferred("_start_next_wave")


## Sparkle Lite 反馈配置：3种预设（击杀普通/Boss/英雄受击）
func _setup_feedbacks() -> void:
	# 击杀普通怪：轻微震动 + 顿帧
	_fb_kill = FeedbackPlayerLite.new()
	_fb_kill.name = "FBKill"
	var kill_shake := FeedbackCameraShake2DLite.new()
	kill_shake.position_amplitude = Vector2(4, 4)
	kill_shake.rotation_amplitude = 1.0
	kill_shake.duration_ms = 120.0
	var kill_pause := FeedbackHitPauseLite.new()
	kill_pause.duration_ms = 40.0
	kill_pause.time_scale_during_pause = 0.1
	_fb_kill.feedbacks = [kill_shake, kill_pause]
	add_child(_fb_kill)

	# 击杀 Boss：强震动 + 顿帧 + 白闪
	_fb_kill_boss = FeedbackPlayerLite.new()
	_fb_kill_boss.name = "FBKillBoss"
	var boss_shake := FeedbackCameraShake2DLite.new()
	boss_shake.position_amplitude = Vector2(16, 16)
	boss_shake.rotation_amplitude = 4.0
	boss_shake.duration_ms = 400.0
	var boss_pause := FeedbackHitPauseLite.new()
	boss_pause.duration_ms = 120.0
	boss_pause.time_scale_during_pause = 0.03
	var boss_flash := FeedbackScreenFlash2DLite.new()
	boss_flash.flash_color = Color.WHITE
	boss_flash.flash_intensity = 0.5
	boss_flash.fade_out_duration_ms = 300.0
	_fb_kill_boss.feedbacks = [boss_shake, boss_pause, boss_flash]
	add_child(_fb_kill_boss)

	# 英雄受击：红色闪屏 + 微震动
	_fb_hit = FeedbackPlayerLite.new()
	_fb_hit.name = "FBHit"
	var hit_shake := FeedbackCameraShake2DLite.new()
	hit_shake.position_amplitude = Vector2(6, 6)
	hit_shake.duration_ms = 150.0
	var hit_flash := FeedbackScreenFlash2DLite.new()
	hit_flash.flash_color = Color(1.0, 0.2, 0.2)
	hit_flash.flash_intensity = 0.3
	hit_flash.fade_out_duration_ms = 200.0
	_fb_hit.feedbacks = [hit_shake, hit_flash]
	add_child(_fb_hit)

	# 大招释放：金色强闪 + 强震动 + 顿帧
	_fb_ult = FeedbackPlayerLite.new()
	_fb_ult.name = "FBUlt"
	var ult_shake := FeedbackCameraShake2DLite.new()
	ult_shake.position_amplitude = Vector2(20, 20)
	ult_shake.rotation_amplitude = 5.0
	ult_shake.duration_ms = 450.0
	var ult_pause := FeedbackHitPauseLite.new()
	ult_pause.duration_ms = 150.0
	ult_pause.time_scale_during_pause = 0.05
	var ult_flash := FeedbackScreenFlash2DLite.new()
	ult_flash.flash_color = Color(1.0, 0.9, 0.55)
	ult_flash.flash_intensity = 0.55
	ult_flash.fade_out_duration_ms = 350.0
	_fb_ult.feedbacks = [ult_shake, ult_pause, ult_flash]
	add_child(_fb_ult)


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
			# 大招蓄能：基础时间充能（满槽 20s→35s 随波次；击杀/受击另加速）
			_charge_ult(delta)
			_hero.set_enemies(_spawner.active_enemies())
			# 每帧给所有召唤单位推送敌人列表（和给 hero 推送一样）
			var _active_enemies: Array = _spawner.active_enemies()
			for su in _summon_units:
				if is_instance_valid(su):
					su.set_enemies(_active_enemies)
			_hud.update_enemy_count(_active_enemies.size())
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
		if _hud: _hud.show_result(true, current_wave - 1, _stats_snapshot())
		return
	state = State.WAVE_IN_PROGRESS
	EventBus.wave_started.emit(current_wave)
	if _hud: _hud.update_wave(current_wave)
	# Boss Debuff：激活本波 debuff（若有）+ 横幅预告
	var deb: Dictionary = _boss_debuffs.on_wave_started(current_wave)
	if not deb.is_empty():
		EventBus.boss_debuff_revealed.emit(deb.get("id", ""), current_wave)
		if _hud: _hud.show_boss_debuff_banner(deb.get("name", ""), current_wave)
	_refresh_boss_forecast()
	# #2: 设置波次倒计时
	_wave_timer = WaveCurves.wave_duration(current_wave)
	_lobby.set_build_ref(_build, _pools)
	_hud.update_gold(_build.gold)
	_hud.update_bond_cost(_build.bond_draw_cost())
	_hud.update_equip_state(_build.equip_level, _pools.equip_upgrade_cost(_build.equip_level))
	_hero.refresh_stats()   # debuff 属性类效果在此生效
	_boss_debuffs.modify_stats(_hero._stats)
	_refresh_summon_stats()
	if _spawner: _spawner.start_wave(current_wave)


func _on_wave_finished() -> void:
	if state != State.WAVE_IN_PROGRESS:
		return   # 防重复（超时 + 全清可能同时触发）
	state = State.WAVE_CLEARED
	EventBus.wave_cleared.emit(current_wave)
	# Boss Debuff：波结束 → 停用效果；封印之手作用于之后的大厅
	var was_debuff_wave: bool = _boss_debuffs.is_active()
	_lobby_reroll_delta = _boss_debuffs.reroll_cap_delta() if was_debuff_wave else 0
	_boss_debuffs.on_wave_finished()
	_hero.refresh_stats()   # 恢复无 debuff 属性
	# #2: 清完怪提前结束 → 剩余时间奖励金币（每秒 2 金）
	var time_bonus: float = 0.0
	if _wave_timer > 0.0:
		time_bonus = ceilf(_wave_timer) * 2.0
	_wave_timer = 0.0
	if _hud: _hud.update_timer(-1.0)   # 隐藏倒计时
	var bonus := 30.0 + 5.0 * current_wave + time_bonus
	_stats_gold_earned += bonus
	_build.add_gold(bonus)
	_refresh_boss_forecast()   # 波间：更新下一个 Boss 预告（换/删道具入口）
	EventBus.gold_changed.emit(_build.gold)
	if _hud: _hud.update_gold(_build.gold)
	_break_timer = wave_break


func _on_lobby_confirmed() -> void:
	_lobby_reroll_delta = 0   # 封印之手只作用于 Boss 波后的一次大厅会话
	_hud.update_gold(_build.gold)
	_hud.update_bond_cost(_build.bond_draw_cost())
	_hud.update_equip_state(_build.equip_level, _pools.equip_upgrade_cost(_build.equip_level))
	_hero.refresh_stats()
	_boss_debuffs.modify_stats(_hero._stats)   # Boss 波内开大厅重选羁绊后仍保持 debuff
	_refresh_summon_stats()


func open_bond_picker() -> void:
	if _build.gold < _build.bond_draw_cost():
		SoundManager.play("error")
		return
	get_tree().paused = true
	_lobby.set_build_ref(_build, _pools)
	_lobby.reroll_delta = _lobby_reroll_delta   # 封印之手：Boss 波后大厅刷新 -1
	_lobby.open_bond()


## M3: 装备升级入口
func open_equipment_picker() -> void:
	if _build.equip_level >= _pools.equip_max_level():
		return
	var cost: float = _pools.equip_upgrade_cost(_build.equip_level)
	if _build.gold < cost:
		SoundManager.play("error")
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
	_hud.process_mode = Node.PROCESS_MODE_ALWAYS   # HUD 仍可交互（显示结果/重开）
	EventBus.run_lost.emit(current_wave)
	_hud.show_result(false, current_wave, _stats_snapshot())


## 结算画面按 R → 重载场景开新局（HUD 发信号，GameManager 执行）
func _on_restart_requested() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _stats_snapshot() -> Dictionary:
	var bonds: int = _build.bond_pool.size() + _build.devoured_bonds.size()
	return {
		"damage": _stats_damage, "kills": _stats_kills, "boss_kills": _stats_boss_kills,
		"breakthroughs": _stats_breakthroughs, "gold": _stats_gold_earned, "bonds": bonds,
	}


# ── 应对道具（GDD §13：换 40 金 / 删 120 金，作用于下一个 Boss 波）──

const DEBUFF_REROLL_COST := 40.0
const DEBUFF_REMOVE_COST := 120.0


func _on_reroll_debuff() -> void:
	var nb: Dictionary = _boss_debuffs.next_boss(current_wave)
	if nb.is_empty() or nb.get("removed", false):
		return
	if _build.gold < DEBUFF_REROLL_COST:
		SoundManager.play("error")
		return
	_build.spend(DEBUFF_REROLL_COST)
	_boss_debuffs.reroll_slot(int(nb["idx"]), _rng)
	SoundManager.play("card_pick")
	_hud.update_gold(_build.gold)
	_refresh_boss_forecast()


func _on_remove_debuff() -> void:
	var nb: Dictionary = _boss_debuffs.next_boss(current_wave)
	if nb.is_empty() or nb.get("removed", false):
		return
	if _build.gold < DEBUFF_REMOVE_COST:
		SoundManager.play("error")
		return
	_build.spend(DEBUFF_REMOVE_COST)
	_boss_debuffs.remove_slot(int(nb["idx"]))
	SoundManager.play("breakthrough", -3.0)
	_hud.update_gold(_build.gold)
	_refresh_boss_forecast()


## 波间 Boss 预告条（HUD）：下一个 Boss 的 debuff + 换/删按钮状态
func _refresh_boss_forecast() -> void:
	if _hud == null:
		return
	var nb: Dictionary = _boss_debuffs.next_boss(current_wave)
	_hud.update_boss_forecast(nb, _build.gold)


## 怪走到英雄位置 → 扣英雄血（GDD：怪漏到核心）
## 伤害由 enemy.leak_damage 数据驱动传入（随波数/类型递增）
func _on_enemy_reached_hero(enemy: Node, dmg: float) -> void:
	# 受击音效只在实际掉血时响（无敌帧内不响）
	if _hero._dmg_cooldown <= 0.0:
		SoundManager.play("hero_hurt", -4.0)
		_gain_ult(0.03)   # 受击加速充能 +3%
	_hero.take_damage(dmg)
	# Boss Debuff：反噬之力（受击额外掉核心血，绕过无敌帧）
	var extra: float = _boss_debuffs.extra_core_loss(_hero.max_hp)
	if extra > 0.0:
		_hero.apply_raw_damage(extra)
	# Sparkle Lite：英雄受击反馈（红闪 + 微震动）
	if _fb_hit != null:
		_fb_hit.play()


## 击杀奖励：金额由 enemy.kill_reward 数据驱动 + 装备经济加成（M3）
func _on_enemy_killed(enemy: Node) -> void:
	var e: Enemy = enemy as Enemy
	var reward: float = e.kill_reward if e != null else 2.0
	# M3: 装备经济效果
	reward += _build.per_kill_bonus()           # per_kill_gold_delta
	reward *= _build.gold_multiplier()          # gold_mult 乘区
	reward = _boss_debuffs.modify_gold(reward)  # Boss Debuff：贪婪之噬（Boss 波内金币减半）
	if randf() < _build.double_gold_chance():   # double_gold_chance 概率翻倍
		reward *= 2.0
	_build.add_gold(reward)
	EventBus.gold_changed.emit(_build.gold)
	_hud.update_gold(_build.gold)
	# Sparkle Lite：击杀反馈（Boss 强震动+顿帧+闪屏，普通怪轻震动）
	if _fb_kill_boss != null and e != null and e.is_boss:
		_fb_kill_boss.play()
		_stats_boss_kills += 1
	elif _fb_kill != null:
		_fb_kill.play()
	_stats_kills += 1
	_stats_gold_earned += reward
	_gain_ult(0.015)   # 击杀加速充能 +1.5%


# ── 大招系统（GDD §11）──

## 满槽所需基础时间：30s → 80s 随波次（后期约 1.1-1.5 波一发）；击杀/受击另加速
func _ult_full_time() -> float:
	return 30.0 + 50.0 * clampf(current_wave / 30.0, 0.0, 1.0)


func _charge_ult(delta: float) -> void:
	if _ult_energy >= 1.0:
		return
	_gain_ult(delta / _ult_full_time())


func _gain_ult(amount: float) -> void:
	if _ult_energy >= 1.0:
		return   # 满了就停（不溢出，也不重复发信号）
	_ult_energy = minf(1.0, _ult_energy + amount)
	EventBus.ult_energy_changed.emit(_ult_energy)
	if _ult_energy >= 1.0:
		_hud.on_ult_ready()   # 就绪提示（音效+按钮点亮）


## 释放大招：清屏 AOE（继承 build 乘区 expected×8）+ 冲击波演出
func _try_release_ult() -> void:
	if _ult_energy < 1.0 or state != State.WAVE_IN_PROGRESS:
		return
	if not is_instance_valid(_hero) or _hero._stats == null:
		return
	_ult_energy = 0.0
	EventBus.ult_energy_changed.emit(0.0)
	EventBus.ult_activated.emit()
	# 演出：冲击波 + 金闪/强震/顿帧 + 音效
	var sw := Shockwave.new()
	sw.global_position = _hero.global_position
	sw.z_index = 55
	add_child(sw)
	if _fb_ult != null:
		_fb_ult.play()
	SoundManager.play("boss_kill", -3.0)
	_hero._juice.play_attack()
	# 结算：全屏敌人受 min(expected×8, 单怪当前血×20%)——前期全额爽，中后期每发恒清 20% 波血
	var killed := 0
	for e in _spawner.active_enemies().duplicate():
		if not is_instance_valid(e):
			continue
		var enemy: Enemy = e as Enemy
		var dmg: float = minf(_hero._stats.expected_hit_dmg(enemy.armor) * ULT_DMG_MULT,
			enemy.max_hp * ULT_PER_ENEMY_CAP)
		_stats_damage += dmg
		FloatingText.spawn(self, enemy.global_position, "%d" % int(round(dmg)), false, true)
		enemy.take_damage(dmg)
		killed += 1


func _on_hero_fired(target: Node, dmg: float, is_crit: bool) -> void:
	SoundManager.play("fire", -10.0)
	var proj := Projectile.new()
	add_child(proj)
	proj.setup(_hero.global_position, target, dmg, is_crit)
	# 美术：弹道贴图（随机元素特效）
	var ptex: Texture2D = SpriteAtlas.get_projectile_tex(_rng)
	if ptex:
		proj.set_sprite(ptex)
	# 吸血：projectile 命中时按 lifesteal_pct 回血
	proj.hit_target.connect(_on_projectile_hit)


func _on_projectile_hit(target: Node, damage: float, is_crit: bool) -> void:
	SoundManager.play("hit", -9.0)
	_stats_damage += damage
	# 伤害数字（普通白 / 暴击金大字）
	if is_instance_valid(target):
		FloatingText.spawn(self, (target as Node2D).global_position,
			"%d" % int(round(damage)), is_crit)
	if _hero == null or not is_instance_valid(_hero):
		return
	if _hero.build == null:
		return
	var stats: CombatStats = _hero.build.assemble_stats()
	var lifesteal: float = stats.lifesteal_pct
	if lifesteal > 0.0:
		_hero.heal(damage * lifesteal * _boss_debuffs.healing_mult())   # 禁疗之印
	# Boss Debuff：镜面之甲（命中反弹，绕过无敌帧直接扣血）
	var reflect: float = _boss_debuffs.reflect_dmg(damage)
	if reflect > 0.0:
		_hero.apply_raw_damage(reflect)


# ── 召唤单位（宠魅体系）──

## 创建并挂载一个召唤单位到 self（和 hero 同层）。
func spawn_summon_unit(unit_id: String, unit_name: String, offset: Vector2) -> void:
	if not is_instance_valid(_hero):
		return
	# 已存在同 id 的召唤单位则不重复创建
	for su in _summon_units:
		if is_instance_valid(su) and su.unit_id == unit_id:
			return
	var summon := SummonUnit.new()
	add_child(summon)
	summon.setup(unit_name, unit_id, _hero, offset)
	# 美术：按 unit_id 装载贴图
	match unit_id:
		"moxie":
			if SpriteAtlas.summon_moxie_tex:
				summon.set_sprite(SpriteAtlas.summon_moxie_tex)
		"baiyanmeng":
			if SpriteAtlas.summon_baiyanmeng_tex:
				summon.set_sprite(SpriteAtlas.summon_baiyanmeng_tex)
	# 初始位置 = 英雄位置 + 偏移（避免从原点飞过来）
	summon.global_position = _hero.global_position + offset
	# 绑定 source：信号自带 (target, dmg)，bind 把召唤单位追加在末尾 → (target, dmg, source)
	summon.fired_projectile.connect(_on_summon_fired.bind(summon))
	_summon_units.append(summon)


## build_state 请求生成召唤单位（unit_id 决定跟随偏移）。
func _on_summon_requested(unit_id: String, unit_name: String) -> void:
	# 莫邪在英雄右上方，白魇魔在英雄左上方
	var offset: Vector2
	match unit_id:
		"moxie":
			offset = Vector2(70, -70)
		"baiyanmeng":
			offset = Vector2(-70, -70)
		_:
			offset = Vector2(0, -100)
	spawn_summon_unit(unit_id, unit_name, offset)


## 白魇魔被吞噬 → 停用对应召唤单位。
func _on_summon_devoured(unit_id: String) -> void:
	for su in _summon_units:
		if is_instance_valid(su) and su.unit_id == unit_id:
			su.deactivate()


## 刷新所有召唤单位的属性（用和英雄一样的 build stats）
func _refresh_summon_stats() -> void:
	if _build == null:
		return
	# 宠魅三区：召唤单位吃自己的 pet_scope 池（莫邪/白魇魔独立数值，
	# 基础 × SUMMON_BASE_ATK_RATIO），不再复用本体全套 stats
	var pet_stats: Dictionary = {}
	for su in _summon_units:
		if not is_instance_valid(su) or not su.active:
			continue
		var uid: String = su.unit_id
		if not pet_stats.has(uid):
			var ps: CombatStats = _build.assemble_pet_stats(uid)
			_boss_debuffs.modify_stats(ps)
			pet_stats[uid] = ps
		su.refresh_stats(pet_stats[uid])


## 召唤单位发射弹道（复用 _on_hero_fired 的逻辑，吸血也走 hero.heal）。
## 信号 fired_projectile 自带 (target, dmg, is_crit)；bind 追加 source → (target, dmg, is_crit, source)。
func _on_summon_fired(target: Node, dmg: float, is_crit: bool, source: Node) -> void:
	if not is_instance_valid(source):
		return
	var proj := Projectile.new()
	add_child(proj)
	proj.setup(source.global_position, target, dmg, is_crit)
	# 美术：弹道贴图
	var ptex: Texture2D = SpriteAtlas.get_projectile_tex(_rng)
	if ptex:
		proj.set_sprite(ptex)
	# 吸血：projectile 命中时按 lifesteal_pct 回血（命中 hero.heal）
	proj.hit_target.connect(_on_projectile_hit)


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


## Tab/C 键 → 角色面板；Q → 大招
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			_try_release_ult()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB or event.keycode == KEY_C:
			if _lobby and not _lobby.visible:
				toggle_char_panel()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _hud and _hud.is_char_panel_open():
				toggle_char_panel()
				get_viewport().set_input_as_handled()
		elif _handle_debug_keys(event.keycode):
			get_viewport().set_input_as_handled()


# ── 调试快捷键（发布前移除）──

## N=跳过当前波  B=跳到下一个Boss波(10/20/30)  G=+500金
func _handle_debug_keys(keycode: int) -> bool:
	if state != State.WAVE_IN_PROGRESS and state != State.WAVE_CLEARED:
		return false
	match keycode:
		KEY_N:
			_dbg_clear_current_wave()
			return true
		KEY_B:
			_dbg_jump_to_next_boss()
			return true
		KEY_G:
			_build.add_gold(500.0)
			_hud.update_gold(_build.gold)
			return true
	return false


## 秒杀当前波全部敌人 → 走正常波结束流程（有击杀金币/反馈）
func _dbg_clear_current_wave() -> void:
	if _spawner:
		_spawner.stop_spawning()
	for e in _spawner.active_enemies().duplicate():
		if is_instance_valid(e):
			e.take_damage(1.0e9)


## 跳到下一个 Boss 波：清场后把波次拨到 next_boss-1，
## 波结束 → 1.5s 间歇 → _start_next_wave 自然进入 Boss 波（完整走预告/横幅/debuff 流程）
func _dbg_jump_to_next_boss() -> void:
	var next_boss: int = 0
	for bw in [10, 20, 30]:
		if bw > current_wave:
			next_boss = bw
			break
	if next_boss == 0:
		return   # 三个 Boss 波都打完了
	if _spawner:
		_spawner.stop_spawning()
	for e in _spawner.active_enemies().duplicate():
		if is_instance_valid(e):
			e.take_damage(1.0e9)
	current_wave = next_boss - 1
