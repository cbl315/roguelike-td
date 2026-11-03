## breakthrough_controller.gd — 突破守关者控制器（从 game_manager 剥离，单一职责）。
## 流程：集齐境界 → pending（卡池锁定）→ 波间挑战 → 击杀守关者才真正升境。
## 数值：HP = 当前波怪血 ×16 ×(1+境界×6%)——纯单体系贴线打不完，混修 12-20s 击杀
## （扫参对应 Python strategy.BREAKTHROUGH_DPS_REQ）。
extends RefCounted
class_name BreakthroughController

const HP_PER_WAVE := 11.0   # 波怪血×11（实测 16 偏肉：w10 ~16s 还要兼顾清小怪；11 ≈ 11s）
const KILL_REWARD := 60.0
const SPAWN_OFFSET := Vector2(420, -160)   # 守关者出生点（英雄右上方）
const MILESTONE_HP_STEP := 0.2   # 每档里程碑(5/10/15/20) +20% 守卫血

var _gm = null   # GameManager 弱引用（避免循环依赖，不标注类型）
var _guard: Enemy = null


func setup(gm) -> void:
	_gm = gm


func is_guard_alive() -> bool:
	return _guard != null and is_instance_valid(_guard)


var current_milestone: int = 0   # 当前守卫考核的里程碑级

func on_equip_guard_required(milestone: int) -> void:
	current_milestone = milestone
	SoundManager.play("wave_start", -2.0)
	if _gm._hud:
		_gm._hud.show_toast("⚔ 装备 +%d 词条被【突破守关者】看守——击杀它解锁里程碑！" % milestone)


func challenge() -> void:
	if _gm == null or _gm._build == null or current_milestone <= 0:
		return
	if is_guard_alive():
		return   # 守关者已在场
	# 波间挑战：关面板、开打（战斗状态注入）
	if _gm._lobby and _gm._lobby.visible:
		_gm._lobby.close()
	_gm.get_tree().paused = false
	var step: float = 1.0 + (current_milestone / 5 - 1) * MILESTONE_HP_STEP
	var hp: float = WaveCurves.enemy_hp(_gm.current_wave) * HP_PER_WAVE * step
	var guard_enemy := Enemy.new()
	_gm.add_child(guard_enemy)
	guard_enemy.setup(hp, false, true, _gm._hero, GameConst.ROOM_RECT)
	guard_enemy.global_position = _gm._hero.global_position + SPAWN_OFFSET
	guard_enemy.modulate = Color(0.8, 0.55, 1.0)   # 紫色标识
	guard_enemy.kill_reward = KILL_REWARD
	guard_enemy.is_boss = true   # 大血条/演出按 Boss 待遇
	guard_enemy.died.connect(_on_guard_down)
	_gm._spawner.register_enemy(guard_enemy)
	_guard = guard_enemy
	if _gm._hud:
		_gm._hud.show_toast("⚔ 突破守关者降临！击杀它完成突破")


func _on_guard_down(_enemy: Node = null) -> void:
	_guard = null
	if _gm == null or _gm._build == null or current_milestone <= 0:
		return
	_gm._build.clear_equip_guard(current_milestone)   # 解锁里程碑（下次升级直接通过）
	if _gm._hud:
		_gm._hud.show_toast("⚔ 守关者已诛！装备 +%d 词条解锁，去升级吧" % current_milestone)
	current_milestone = 0


## 波结束守关者还活着 → 撤退（pending 保留，波间可再挑战）。
## Enemy 无 deactivate（那是 SummonUnit 的 API）——撤退 = 断信号 + 移出活跃表 + 直接销毁。
func withdraw() -> void:
	if is_guard_alive():
		_guard.died.disconnect(_on_guard_down)
		_gm._spawner.unregister_enemy(_guard)
		_guard.queue_free()
		_guard = null
		if _gm._hud:
			_gm._hud.show_toast("突破失败…守关者撤退，波间可再次挑战")


## 测试钩子（gmcp regression 用）：立即击杀守关者（走真实死亡→升境流程）
func debug_kill_guard() -> void:
	if is_guard_alive():
		_guard.take_damage(1.0e9)
