## breakthrough_controller.gd — 突破守关者控制器（从 game_manager 剥离，单一职责）。
## 流程：集齐境界 → pending（卡池锁定）→ 波间挑战 → 击杀守关者才真正升境。
## 数值：HP = 当前波怪血 ×16 ×(1+境界×6%)——纯单体系贴线打不完，混修 12-20s 击杀
## （扫参对应 Python strategy.BREAKTHROUGH_DPS_REQ）。
extends RefCounted
class_name BreakthroughController

const HP_PER_WAVE := 16.0
const KILL_REWARD := 60.0
const REALM_HP_STEP := 0.06

var _gm = null   # GameManager 弱引用（避免循环依赖，不标注类型）
var _guard: Enemy = null


func setup(gm) -> void:
	_gm = gm


func is_guard_alive() -> bool:
	return _guard != null and is_instance_valid(_guard)


func on_breakthrough_ready(_path_id: String, _realm_idx: int) -> void:
	SoundManager.play("wave_start", -2.0)
	if _gm._hud:
		_gm._hud.show_toast("⚔ 境界圆满！波间可挑战【突破守关者】— 击杀后才升境")


func challenge() -> void:
	if _gm == null or _gm._build == null or _gm._build.pending_breakthrough.is_empty():
		return
	if is_guard_alive():
		return   # 守关者已在场
	# 波间挑战：关面板、开打（战斗状态注入）
	if _gm._lobby and _gm._lobby.visible:
		_gm._lobby.close()
	_gm.get_tree().paused = false
	var pd: Dictionary = _gm._build.pending_breakthrough
	var realm_idx: int = int(pd.get("realm_idx", 0))
	var hp: float = WaveCurves.enemy_hp(_gm.current_wave) * HP_PER_WAVE * (1.0 + realm_idx * REALM_HP_STEP)
	var guard_enemy := Enemy.new()
	_gm.add_child(guard_enemy)
	guard_enemy.setup(hp, false, true, _gm._hero, Rect2(80, 80, 2840, 1840))
	guard_enemy.global_position = _gm._hero.global_position + Vector2(420, -160)
	guard_enemy.modulate = Color(0.8, 0.55, 1.0)   # 紫色标识
	guard_enemy.kill_reward = KILL_REWARD
	guard_enemy.died.connect(_on_guard_down)
	_gm._spawner._active_enemies.append(guard_enemy)
	_guard = guard_enemy
	if _gm._hud:
		_gm._hud.show_toast("⚔ 突破守关者降临！击杀它完成突破")


func _on_guard_down(_enemy: Node = null) -> void:
	_guard = null
	if _gm == null or _gm._build == null or _gm._build.pending_breakthrough.is_empty():
		return
	_gm._build.apply_breakthrough()   # 真正升境（演出走 realm_devoured → HUD 大字）


## 波结束守关者还活着 → 撤退（pending 保留，波间可再挑战）。
## Enemy 无 deactivate（那是 SummonUnit 的 API）——撤退 = 断信号 + 移出活跃表 + 直接销毁。
func withdraw() -> void:
	if is_guard_alive():
		_guard.died.disconnect(_on_guard_down)
		_gm._spawner._active_enemies.erase(_guard)
		_guard.queue_free()
		_guard = null
		if _gm._hud:
			_gm._hud.show_toast("突破失败…守关者撤退，波间可再次挑战")
