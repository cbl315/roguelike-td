## wave_curves.gd — 敌人曲线（移植自 balance/td_balance/curves.py）
## 从 data/waves.json 读曲线参数，算每波的 hp/count/duration。
## SSOT 是 balance/data/waves.yaml（Python），这里只读导出的 JSON。
extends RefCounted
class_name WaveCurves

const _DATA_PATH := "res://data/waves.json"

# 缓存曲线参数（懒加载）
static var _params: Dictionary = {}

## 当前波数（由 spawner/game_manager 写入，供 enemy 等 setData 驱动用）
static var _current_wave: int = 1


static func _ensure_loaded() -> void:
	if not _params.is_empty():
		return
	var f := FileAccess.open(_DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("wave_curves: 无法读取 %s" % _DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_params = parsed


## 单怪血量 = base × growth^(wave-1)
static func enemy_hp(wave: int) -> float:
	_ensure_loaded()
	var hp: Dictionary = _params.get("enemy_hp", {})
	return float(hp.get("base", 100.0)) * pow(float(hp.get("growth", 1.05)), wave - 1)


## 怪物数量 = round(base + per_wave × wave)
static func enemy_count(wave: int) -> int:
	_ensure_loaded()
	var c: Dictionary = _params.get("enemy_count", {})
	return roundi(float(c.get("base", 8)) + float(c.get("per_wave", 1.5)) * wave)


## 该波时长（秒）= base + per_wave × wave
static func wave_duration(wave: int) -> float:
	_ensure_loaded()
	var d: Dictionary = _params.get("wave_duration", {})
	return float(d.get("base_seconds", 25)) + float(d.get("per_wave_seconds", 1)) * wave


## 该波总血量 = enemy_hp × enemy_count
static func wave_total_hp(wave: int) -> float:
	return enemy_hp(wave) * enemy_count(wave)


## 是否 Boss 波
static func is_boss_wave(wave: int) -> bool:
	_ensure_loaded()
	var n: int = int(_params.get("boss", {}).get("every_n_waves", 10))
	return n > 0 and wave % n == 0


## 是否精英波（非 Boss）
static func is_elite_wave(wave: int) -> bool:
	_ensure_loaded()
	var n: int = int(_params.get("elite", {}).get("every_n_waves", 5))
	return n > 0 and wave % n == 0 and not is_boss_wave(wave)


## 主线波数（30）
static func main_quest_waves() -> int:
	_ensure_loaded()
	return int(_params.get("main_quest", {}).get("waves", 30))


## Boss 在该波总血量中的占比（仅 UI 血条分配用）
static func boss_share() -> float:
	_ensure_loaded()
	return float(_params.get("boss", {}).get("total_hp_share", 0.4))
