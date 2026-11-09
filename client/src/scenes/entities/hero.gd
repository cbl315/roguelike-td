## hero.gd — 英雄 = 核心：玩家操控移动（WASD/方向键），自动攻击范围内敌人。
## 房间生存式（土豆兄弟）：英雄可自由移动，怪追击英雄，英雄自动开火。
extends Node2D
class_name Hero

signal target_priority_changed(mode)
signal fired_projectile(target: Node, damage: float, is_crit: bool)
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
var _juice := Juice.new()
var _prev_pos: Vector2 = Vector2.ZERO   # 上一帧位置（计算移动速度比）
var _fire_rng := RandomNumberGenerator.new()   # 暴击掷骰专用（_ready 里 randomize）

## 房间边界（由 game_manager 设置）
var room_rect: Rect2 = GameConst.ROOM_RECT

@onready var _priority_label: Label = $PriorityLabel


func _ready() -> void:
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)
	_update_priority_label()
	_prev_pos = global_position
	_fire_rng.randomize()


func set_enemies(enemies: Array) -> void:
	_all_enemies = enemies


var _dmg_cooldown: float = 0.0   # 全局受伤间隔（0.3s 内只受一次伤）
const DMG_INTERVAL := 0.3


## ── 公开访问（game_manager 编排用；原 _stats/_dmg_cooldown/_juice 跨对象私有访问修复）──
func get_stats() -> CombatStats:
	return _stats


func is_vulnerable() -> bool:
	return _dmg_cooldown <= 0.0


func play_attack_fx() -> void:
	_juice.play_attack()


func take_damage(amount: float) -> void:
	if _dmg_cooldown > 0.0:
		return   # 全局无敌帧内，不受伤
	current_hp = maxf(0.0, current_hp - amount)
	hp_changed.emit(current_hp, max_hp)
	_juice.play_flash()
	queue_redraw()
	_dmg_cooldown = DMG_INTERVAL   # 进入 0.3s 无敌
	if current_hp <= 0.0:
		destroyed.emit()


func refresh_stats() -> void:
	if build != null:
		_stats = build.assemble_stats()
	else:
		_stats = CombatStats.new()
		_stats.apply_atk_bonus()
	# VFX 批次二：主体系光环（体系色圈 t1；高境界升级 t2/t3——按已修体系数）
	if build != null:
		var main_pid := ""
		var realms_done := 0
		for pid in build.path_realm.keys():
			if not pid.begins_with("generic_") and pid != "seed":
				main_pid = pid
				realms_done = maxi(realms_done, int(build.path_realm.get(pid, 0)))
		var atlas := get_node_or_null("/root/SpriteAtlas")
		if atlas != null:
			var tier: int = 1 if realms_done < 3 else (2 if realms_done < 6 else 3)
			_aura_tex = atlas.get_aura_hero(tier)
			if _aura_tex == null:
				_aura_tex = atlas.get_aura_circle(main_pid)
	# 三伤害类型：主体系决定弹道类型（星辰变/斗破=法术，遮天/宠魅=物理）
	if _stats != null and build != null:
		for pid in build.path_realm.keys():
			if pid != "generic_fusion":
				_stats.damage_type = "magic" if pid in ["xingchenbian", "doupo"] else "physical"
				break
	# 从 CombatStats 更新 max_hp（hp_pct_delta 生效）
	var new_max: float = _stats.effective_max_hp() if _stats != null else 1000.0
	if new_max != max_hp:
		# 保持当前血量比例（升 max_hp 时不掉血）
		var ratio: float = current_hp / maxf(max_hp, 1.0)
		max_hp = new_max
		current_hp = minf(max_hp, current_hp + (new_max - max_hp))   # max_hp 增加时，补满差值
		if current_hp > max_hp:
			current_hp = max_hp
		hp_changed.emit(current_hp, max_hp)


## 直接扣血（绕过无敌帧；Boss Debuff 反弹伤害用）。仍触发信号与死亡判定。
func apply_raw_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	hp_changed.emit(current_hp, max_hp)
	queue_redraw()
	if current_hp <= 0.0:
		destroyed.emit()


## 吸血回血（projectile 命中时调用）
func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	current_hp = minf(max_hp, current_hp + amount)
	hp_changed.emit(current_hp, max_hp)


func _process(delta: float) -> void:
	if _dmg_cooldown > 0.0:
		_dmg_cooldown -= delta
	_handle_movement(delta)
	if _stats == null:
		refresh_stats()
	# Juice：计算移动速度比并更新动画状态
	var moved: float = global_position.distance_to(_prev_pos)
	var speed_ratio: float = clampf(moved / (move_speed * delta + 1.0), 0.0, 1.0)
	_juice.tick(delta, moved > 1.0, speed_ratio)
	var vel: Vector2 = global_position - _prev_pos
	_skel.tick(delta, vel, speed_ratio)
	_prev_pos = global_position
	queue_redraw()
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
	var interval: float = 1.0 / maxf(_stats.attack_speed, 0.1)   # 除零防御（与 summon_unit 一致）
	if _fire_timer >= interval:
		_fire_timer = 0.0
		_fire(target)


## 玩家操控移动：WASD / 方向键 / 移动端虚拟摇杆，房间边界约束
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
	# 移动端：键盘无输入时读虚拟摇杆方向
	if dir == Vector2.ZERO:
		dir = VirtualJoystick.dir
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
	# 掷骰版伤害（暴击真实判定，均值 == expected；伤害数字需要区分暴击）
	var rolled: Dictionary = _stats.roll_hit_dmg(enemy.armor, _fire_rng)
	var dmg: float = rolled["dmg"]
	var is_crit: bool = rolled["crit"]
	_juice.play_attack()
	# 伤害由弹道到达目标时结算（锁定式，不会误伤途中敌人）
	fired_projectile.emit(target, dmg, is_crit)
	# 连锁弹射（联动 chain_extra_bounces）：命中后弹射到附近敌人
	if _stats.chain_extra_bounces > 0:
		_do_chain_bounce(target, dmg)


## 连锁弹射：从初始目标开始，找最近未命中敌人弹射，递减 0.7×/次
func _do_chain_bounce(initial_target: Node2D, base_dmg: float) -> void:
	var bounces: int = _stats.chain_extra_bounces
	var hit: Dictionary = {initial_target: true}
	var current_pos: Vector2 = initial_target.global_position
	var current_dmg: float = base_dmg * 0.7   # 第一弹射 0.7×
	for _i in bounces:
		# 找最近的未命中敌人
		var nearest: Enemy = null
		var nearest_dist: float = 400.0   # 弹射最大距离
		for e in _all_enemies:
			if is_instance_valid(e) and not hit.has(e):
				var d: float = current_pos.distance_to(e.global_position)
				if d < nearest_dist:
					nearest_dist = d
					nearest = e
		if nearest == null:
			break
		hit[nearest] = true
		_skel.play_attack()
		fired_projectile.emit(nearest, current_dmg, false)
		current_pos = nearest.global_position
		current_dmg *= 0.7   # 每次递减


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
	# 主体系光环（脚下，呼吸微缩放；VFX 批次二）
	if _aura_tex:
		var bs: float = 1.0 + sin(Time.get_ticks_msec() * 0.003) * 0.04
		draw_set_transform(Vector2.ZERO, 0, Vector2(bs, bs))
		var as_: Vector2 = _aura_tex.get_size()
		draw_texture(_aura_tex, -as_ / 2 + Vector2(0, 18), Color(1, 1, 1, 0.35))   # 光环限透明度 35%（防过亮）
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# 攻击范围圈（半透明，不参与 juice 变换）
	draw_circle(Vector2.ZERO, attack_range, Color(0.3, 0.4, 0.6, 0.02))   # 极淡填充（0.06→0.02 消除'白色一坨'感）
	draw_arc(Vector2.ZERO, attack_range, 0, TAU, 64, Color(0.3, 0.4, 0.6, 0.2), 1.5)
	# 本体：应用 juice 变换（idle呼吸 + 移动挤压 + 攻击反馈）
	# 骨骼动画：单贴图 + root transform（拆分渲染回退——几何验证通过后恢复）
	# 骨骼拆分渲染（头/躯干/腿独立动画——剪纸模式）
	if _sprite_tex and _skel != null:
		_skel.draw_split(_sprite_tex, self)
		if _juice.get_flash() > 0.0:
			var tsf: Vector2 = _sprite_tex.get_size()
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			draw_rect(Rect2(-tsf / 2, tsf), Color(1, 1, 1, _juice.get_flash() * 0.7), true)
	else:
		# 外发光
		draw_circle(Vector2.ZERO, radius + 8, Color(0.4, 0.6, 1.0, 0.25))
		# 色块本体（蓝，hp 越低越偏红）
		var col := Color(0.45, 0.65 * hp_ratio + 0.2, 1.0 * hp_ratio + 0.2)
		if _juice.get_flash() > 0.0:
			col = col.lerp(Color.WHITE, _juice.get_flash())
		draw_circle(Vector2.ZERO, radius, col)
	# 重置变换（HP环不受 juice 影响）
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# HP 环（始终叠加在贴图/色块上方）
	draw_arc(Vector2.ZERO, radius + 14, -TAU / 2, -TAU / 2 + TAU * hp_ratio, 48, Color(0.4, 1.0, 0.5), 4.0)


## 加载精灵贴图（有贴图时替换色块）
func set_sprite(tex: Texture2D) -> void:
	_sprite_tex = tex
	queue_redraw()


var _sprite_tex: Texture2D = null
var _aura_tex: Texture2D = null   # 主体系光环（VFX 批次二：体系色圈+英雄t1-3）
var _skel = preload("res://src/core/skeletal_juice.gd").new()   # 骨骼动画（VFX 批次五）
