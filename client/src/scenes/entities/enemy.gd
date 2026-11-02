## enemy.gd — 敌人：房间内自主移动，追击英雄，有 HP。
## 土豆兄弟式：直接朝英雄移动 + 房间边界约束。
## 4 种行为（Kind）：CHASER 追击 / RANGED 风筝吐弹 / SPLITTER 死亡分裂 / HEALER 治疗光环。
extends Node2D
class_name Enemy

signal reached_core(enemy, leak_damage: float)
signal died(enemy)

enum Kind { CHASER, RANGED, SPLITTER, HEALER }

@export var max_hp: float = 100.0
@export var is_boss: bool = false
@export var is_elite: bool = false
@export var radius: float = 18.0
## 行为类型（决定移动/攻击模式，血条颜色区分）
var kind: int = Kind.CHASER
## 分裂怪的小体（不再分裂、更小更快）
var is_mini: bool = false
## 击杀奖励金币（数据驱动）
@export var kill_reward: float = 2.0
## 接触英雄造成的伤害（数据驱动）
@export var leak_damage: float = 30.0
## 移动速度（像素/秒）
@export var move_speed: float = 120.0
## 接触英雄的距离（触发 leak_damage）
@export var contact_dist: float = 40.0
## 接触后重新攻击的冷却（秒）
@export var contact_cooldown: float = 1.0
## Boss 回春之核：每 5s 回血比例（% max hp，0 = 无回血）
var regen_pct_per_5s: float = 0.0
var _regen_timer: float = 0.0

# RANGED：风筝距离区间 + 吐弹
const RANGED_KEEP_MIN := 220.0    # 近于此距离后撤
const RANGED_KEEP_MAX := 330.0    # 远于此距离靠近
const RANGED_FIRE_CD := 2.8       # 吐弹间隔（秒）
const RANGED_PROJ_SPEED := 480.0
var _ranged_cd: float = 1.2       # 首发延迟
# HEALER：治疗光环
const HEAL_RADIUS := 220.0
const HEAL_CD := 3.0
const HEAL_PCT := 0.08            # 每次治疗量（% 目标 max hp）
var _heal_cd: float = 1.5
var _heal_pulse: float = -1.0     # 治疗脉冲视觉计时（>=0 播放）

var current_hp: float = 100.0:
	set = set_current_hp
var armor: float = 20.0
var _hero: Node2D = null
var _dead: bool = false
var _contact_cd: float = 0.0   # 接触冷却剩余
var _flash_timer: float = 0.0   # #3: 受击闪白剩余（fallback 色块用）
var _burst_timer: float = -1.0  # #3: 死亡爆裂动画（>=0 时播放，0.2s 后 queue_free）
var _juice := Juice.new()
var _prev_pos: Vector2 = Vector2.ZERO

## 房间边界（由 spawner 设置）
var _room_rect: Rect2 = GameConst.ROOM_RECT


func _ready() -> void:
	current_hp = max_hp
	z_index = 20
	_fire_rng.randomize()
	add_to_group("enemies")   # healer 光环检索 / 后续 AOE 查询用


## 血量 setter：归零自动触发死亡 + 爆裂动画（参考 quiver-td set_health 模式）
func set_current_hp(value: float) -> void:
	current_hp = maxf(0.0, value)
	# #3: 受击闪白（非致命伤害）
	if current_hp > 0.0:
		_flash_timer = 0.08
		_juice.play_flash()
	queue_redraw()
	if current_hp <= 0.0 and not _dead:
		_dead = true
		died.emit(self)
		# #3: 不立即 queue_free，播放死亡动画
		_burst_timer = 0.0
		_juice.play_death()


func setup(hp: float, boss: bool, elite: bool, hero: Node2D, room_rect: Rect2) -> void:
	max_hp = hp
	current_hp = max_hp
	is_boss = boss
	is_elite = elite
	_hero = hero
	_room_rect = room_rect
	armor = 20.0
	radius = 30.0 if boss else (24.0 if elite else 18.0)
	# 移动速度：boss 慢、精英中、普通快（像素/秒）
	move_speed = 60.0 if boss else (90.0 if elite else 120.0)
	# 击杀奖励/接触伤害随类型递增
	kill_reward = 8.0 if boss else (4.0 if elite else 2.0)
	leak_damage = (60.0 + 10.0 * WaveCurves._current_wave) if boss else (40.0 + 5.0 * WaveCurves._current_wave) if elite else (30.0 + 5.0 * WaveCurves._current_wave)
	contact_dist = 36.0 if boss else (32.0 if elite else 28.0)
	_juice.play_spawn()   # 生成弹出动画
	_prev_pos = global_position


func _process(delta: float) -> void:
	# #3: 死亡动画播放中 → 不再移动，只播动画
	if _burst_timer >= 0.0:
		_burst_timer += delta
		_juice.tick(delta, false, 0.0)
		queue_redraw()
		if _burst_timer > 0.2:
			queue_free()
		return
	if _hero == null or not is_instance_valid(_hero):
		return
	# Boss 回春之核：每 5s 回血
	if regen_pct_per_5s > 0.0:
		_regen_timer += delta
		if _regen_timer >= 5.0:
			_regen_timer = 0.0
			current_hp = minf(max_hp, current_hp + max_hp * regen_pct_per_5s)
	# #3: 受击闪白计时
	if _flash_timer > 0.0:
		_flash_timer -= delta
	# 治疗脉冲视觉计时
	if _heal_pulse >= 0.0:
		_heal_pulse += delta
		if _heal_pulse > 0.5:
			_heal_pulse = -1.0
	# 朝英雄移动（按行为分派）
	var dir: Vector2 = (_hero.global_position - global_position)
	var dist: float = dir.length()
	match kind:
		Kind.RANGED:
			_move_ranged(delta, dir, dist)
		Kind.HEALER:
			_move_healer(delta, dir, dist)
		_:
			_move_chaser(delta, dir, dist)
	# 接触英雄：造成伤害 + 进冷却（HEALER 不近身输出，半径外游走）
	_contact_cd -= delta
	if kind != Kind.HEALER and dist <= contact_dist and _contact_cd <= 0.0:
		_contact_cd = contact_cooldown
		reached_core.emit(self, leak_damage)
	# 房间边界约束
	global_position.x = clampf(global_position.x, _room_rect.position.x, _room_rect.position.x + _room_rect.size.x)
	global_position.y = clampf(global_position.y, _room_rect.position.y, _room_rect.position.y + _room_rect.size.y)
	# Juice：移动挤压
	var moved: float = global_position.distance_to(_prev_pos)
	var speed_ratio: float = clampf(moved / (move_speed * delta + 1.0), 0.0, 1.0)
	_juice.tick(delta, moved > 0.5, speed_ratio)
	_prev_pos = global_position
	queue_redraw()


func take_damage(amount: float) -> void:
	current_hp -= amount   # 走 setter，归零自动触发 died


# ── 行为实现 ──

## 默认：直追英雄
func _move_chaser(delta: float, dir: Vector2, dist: float) -> void:
	if dist > contact_dist:
		var step: float = move_speed * delta
		if dist > step:
			global_position += dir.normalized() * step
		else:
			global_position = _hero.global_position


## 远程怪：保持 [220, 330] 风筝区间 + 周期吐弹（弹道复用 Projectile，红 tint，不挂玩家钩子）
func _move_ranged(delta: float, dir: Vector2, dist: float) -> void:
	if dist > RANGED_KEEP_MAX:
		global_position += dir.normalized() * move_speed * 0.8 * delta
	elif dist < RANGED_KEEP_MIN:
		global_position -= dir.normalized() * move_speed * 0.7 * delta   # 后撤
	_ranged_cd -= delta
	if _ranged_cd <= 0.0 and dist <= RANGED_KEEP_MAX + 60.0:
		_ranged_cd = RANGED_FIRE_CD
		_spit_projectile()


func _spit_projectile() -> void:
	if get_parent() == null:
		return
	var proj := Projectile.new()
	get_parent().add_child(proj)
	# 敌方弹道 = 直线飞行 + 碰撞命中（可躲避）：方向在吐弹瞬间锁定，
	# 英雄走位可躲开（原来复用 setup 追踪弹道导致必中，难度过高）。
	proj.setup_enemy(global_position, _hero, leak_damage * 0.8, RANGED_PROJ_SPEED)
	proj.modulate = Color(1.0, 0.5, 0.45)   # 红色 tint 区分敌方弹
	# 运行时取 SpriteAtlas（--script 独立测试模式无 autoload，跳过贴图）
	var atlas := get_node_or_null("/root/SpriteAtlas")
	if atlas != null:
		var tex: Texture2D = atlas.get_projectile_tex(_fire_rng)
		if tex:
			proj.set_sprite(tex)


## 奶妈：慢速追随 + 每 3s 治疗半径内其他怪（8% max hp）+ 绿色脉冲
func _move_healer(delta: float, dir: Vector2, dist: float) -> void:
	if dist > contact_dist * 2.5:
		global_position += dir.normalized() * move_speed * 0.65 * delta
	_heal_cd -= delta
	if _heal_cd <= 0.0:
		_heal_cd = HEAL_CD
		var healed := 0
		for node in get_tree().get_nodes_in_group("enemies"):
			var other := node as Enemy
			if other == null or other == self or not is_instance_valid(other):
				continue
			if other.global_position.distance_to(global_position) <= HEAL_RADIUS:
				other.current_hp = minf(other.max_hp, other.current_hp + other.max_hp * HEAL_PCT)
				healed += 1
		if healed > 0:
			_heal_pulse = 0.0


var _fire_rng := RandomNumberGenerator.new()


var _sprite_tex: Texture2D = null


## 加载精灵贴图
func set_sprite(tex: Texture2D) -> void:
	_sprite_tex = tex
	queue_redraw()


func _draw() -> void:
	# 死亡爆裂动画（贴图/色块通用）
	if _burst_timer >= 0.0:
		var t: float = _burst_timer / 0.2
		var burst_r: float = radius + t * 40.0
		var burst_a: float = 1.0 - t
		# 先画本体（带 juice 死亡变换：放大+旋转+淡出）
		draw_set_transform(_juice.offset, _juice.rotation, _juice.scale)
		if _sprite_tex:
			var ts: Vector2 = _sprite_tex.get_size()
			draw_texture(_sprite_tex, -ts / 2)
			if burst_a < 1.0:
				draw_rect(Rect2(-ts / 2, ts), Color(0, 0, 0, (1.0 - burst_a) * 0.5), true)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		# 爆裂环
		draw_circle(Vector2.ZERO, burst_r, Color(1.0, 0.8, 0.3, burst_a * 0.6))
		draw_arc(Vector2.ZERO, burst_r, 0, TAU, 32, Color(1.0, 0.9, 0.4, burst_a), 3.0)
		return
	var hp_ratio := clampf(current_hp / max_hp, 0.0, 1.0)
	# 本体：应用 juice 变换（idle呼吸 + 移动挤压 + 攻击/受击反馈）
	draw_set_transform(_juice.offset, _juice.rotation, _juice.scale)
	if _sprite_tex:
		var ts: Vector2 = _sprite_tex.get_size()
		draw_texture(_sprite_tex, -ts / 2)
		# 命中闪白：贴图上叠加白色半透明
		if _juice.get_flash() > 0.0:
			draw_rect(Rect2(-ts / 2, ts), Color(1, 1, 1, _juice.get_flash() * 0.7), true)
	else:
		var col := Color(1.0, 0.25 + 0.4 * (1.0 - hp_ratio), 0.3 + 0.3 * (1.0 - hp_ratio))
		if is_boss:
			col = Color(1.0, 0.4, 0.8)
		elif is_elite:
			col = Color(1.0, 0.6, 0.3)
		if _juice.get_flash() > 0.0:
			col = col.lerp(Color.WHITE, _juice.get_flash())
		draw_circle(Vector2.ZERO, radius + 6, Color(col.r, col.g, col.b, 0.25))
		draw_circle(Vector2.ZERO, radius, col)
	# 重置变换
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# 治疗脉冲（healer 施法时绿色扩散环）
	if _heal_pulse >= 0.0:
		var t: float = _heal_pulse / 0.5
		draw_arc(Vector2.ZERO, radius + t * HEAL_RADIUS * 0.4, 0, TAU, 40,
			Color(0.4, 1.0, 0.5, (1.0 - t) * 0.7), 3.0)
	# 血条（贴图/色块通用，叠加在上方；颜色按行为区分）
	var bar_col := Color(0.9, 0.2, 0.3)          # chaser 红
	if kind == Kind.RANGED:
		bar_col = Color(0.75, 0.4, 1.0)          # 远程紫
	elif kind == Kind.SPLITTER:
		bar_col = Color(0.3, 0.85, 0.9)          # 分裂青
	elif kind == Kind.HEALER:
		bar_col = Color(0.4, 0.95, 0.5)          # 奶妈绿
	var bar_w := radius * 1.6
	draw_rect(Rect2(-bar_w / 2, -radius - 12, bar_w, 4), Color(0.2, 0.2, 0.25), true)
	draw_rect(Rect2(-bar_w / 2, -radius - 12, bar_w * hp_ratio, 4), bar_col, true)
