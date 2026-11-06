## summon_unit.gd — 虚拟召唤单位（莫邪/白魇魔/第三魂宠）
## 跟随英雄移动，自动攻击范围内敌人，不可被选中/受击。
## 有独立 CombatStats（由宠魅羁绊 effect 强化）。
extends Node2D
class_name SummonUnit

signal fired_projectile(target: Node, damage: float, is_crit: bool)

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
var _juice := Juice.new()
var _prev_pos: Vector2 = Vector2.ZERO
var _fire_rng := RandomNumberGenerator.new()

# 占位精灵颜色（彩色圆形，不用美术资源）
const COLOR_MOXIE := Color(0.95, 0.35, 0.15)       # 莫邪：橙红色
const COLOR_BAIYANMENG := Color(0.2, 0.85, 0.9)    # 白魇魔：青色
const COLOR_DEFAULT := Color(0.8, 0.8, 0.8)        # 其它召唤单位：灰
const DRAW_RADIUS := 22.0


func _ready() -> void:
	_fire_rng.randomize()
	if stats == null:
		stats = CombatStats.new()
		stats.apply_atk_bonus()


func setup(p_name: String, p_id: String, hero: Node2D, offset: Vector2) -> void:
	unit_name = p_name
	unit_id = p_id
	var atlas := get_node_or_null("/root/SpriteAtlas")
	if atlas != null:
		_aura_tex = atlas.get_aura_pet(1)
	follow_target = hero
	follow_offset = offset
	stats = CombatStats.new()
	stats.apply_atk_bonus()
	_juice.play_spawn()
	_prev_pos = global_position


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
	# Juice：跟随移动时的挤压
	var moved: float = global_position.distance_to(_prev_pos)
	_juice.tick(delta, moved > 0.5, clampf(moved / (follow_speed * delta + 1.0), 0.0, 1.0))
	_prev_pos = global_position
	queue_redraw()


func _fire(target: Node2D) -> void:
	var enemy: Enemy = target as Enemy
	if enemy == null:
		return
	# 掷骰版（与英雄一致，均值 == expected）
	var rolled: Dictionary = stats.roll_hit_dmg(enemy.armor, _fire_rng)
	var dmg: float = rolled["dmg"]
	if dmg <= 0.0:
		return
	_juice.play_attack()
	fired_projectile.emit(target, dmg, rolled["crit"])


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


## 加载精灵贴图
func set_sprite(tex: Texture2D) -> void:
	_sprite_tex = tex
	queue_redraw()


var _sprite_tex: Texture2D = null
var _aura_tex: Texture2D = null   # 宠物光环 t1（VFX 批次二）


func _draw() -> void:
	# 宠物光环 t1（脚下微呼吸）
	if _aura_tex:
		var bs: float = 1.0 + sin(Time.get_ticks_msec() * 0.004) * 0.05
		draw_set_transform(Vector2.ZERO, 0, Vector2(bs, bs))
		var asz: Vector2 = _aura_tex.get_size()
		draw_texture(_aura_tex, -asz / 2 + Vector2(0, 10))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# 应用 juice 变换（idle呼吸 + 移动挤压 + 攻击反馈）
	draw_set_transform(_juice.offset, _juice.rotation, _juice.scale)
	# 优先贴图，无则色块
	if _sprite_tex:
		var ts: Vector2 = _sprite_tex.get_size()
		draw_texture(_sprite_tex, -ts / 2)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		return
	# 色块 fallback：按 unit_id 画彩色圆形
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
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
