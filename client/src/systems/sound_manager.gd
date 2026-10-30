## sound_manager.gd — 音效管理单例（autoload "SoundManager"）。
## Kenney CC0 音效（client/src/assets/audio/）。
## 特性：多变体随机 + 音高抖动（Brotato 式防疲劳）+ 50ms 节流（高攻速不叠噪）
##       + 播放器池复用 + M 键静音（user:// 持久化）。
## 用法：SoundManager.play("kill") / play("fire", -6.0, 0.08)
extends Node

const AUDIO_DIR := "res://src/assets/audio"

## sound_id → 变体文件名列表（播放时随机挑一个）
const _SOUND_TABLE := {
	"fire":         ["fire1", "fire2", "fire3", "fire4"],          # 攻击（激光/剑气）
	"hit":          ["hit1", "hit2", "hit3"],                      # 弹道命中（劈砍）
	"kill":         ["kill0", "kill1", "kill2"],                   # 击杀普通怪
	"boss_kill":    ["boss_kill1", "boss_kill2"],                  # 击杀 Boss
	"hero_hurt":    ["hero_hurt1", "hero_hurt2", "hero_hurt3"],    # 英雄受击（金属闷响）
	"hero_die":     ["hero_die1", "hero_die2"],                    # 英雄死亡（下滑音）
	"wave_start":   ["wave_start1", "wave_start2"],                # 波次开始
	"wave_clear":   ["wave_clear1", "wave_clear2"],                # 波次清空
	"breakthrough": ["breakthrough1", "breakthrough2"],            # 突破境界
	"ui_click":     ["ui_click1", "ui_click2", "ui_click3"],       # 按钮点击
	"card_pick":    ["card_pick1", "card_pick2", "card_pick3"],    # 选卡
	"error":        ["error1", "error2"],                          # 金币不足等
}

const PLAYER_POOL_SIZE := 16        # 复用播放器数量
const THROTTLE_MS := 50             # 同 id 两声之间的最小间隔
const SETTINGS_PATH := "user://settings.cfg"

var _streams: Dictionary = {}       # 文件名 → AudioStream（懒加载缓存）
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _last_play_msec: Dictionary = {}   # sound_id → 上次播放时刻（节流）
var muted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 大厅暂停时 UI 音效照常
	for i in PLAYER_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_load_mute()
	# 订阅 EventBus：这些音效零侵入（不改任何现有代码）
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.wave_started.connect(func(_w): play("wave_start"))
	EventBus.wave_cleared.connect(func(_w): play("wave_clear"))
	EventBus.bond_devoured.connect(func(_p, _r, _n): play("breakthrough"))
	EventBus.run_lost.connect(func(_w): play("hero_die"))
	EventBus.run_won.connect(func(): play("breakthrough", -3.0))


## 播放一个音效。volume_db 衰减（负值更轻）；pitch_jitter 音高随机幅度（防疲劳）。
## 节流：同一 id 在 THROTTLE_MS 内只响一次（连锁弹射/高攻速不会叠成噪音）。
func play(sound_id: String, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	if muted:
		return
	var variants: Array = _SOUND_TABLE.get(sound_id, [])
	if variants.is_empty():
		push_warning("SoundManager: 未知音效 id '%s'" % sound_id)
		return
	# 节流
	var now := Time.get_ticks_msec()
	if now - int(_last_play_msec.get(sound_id, 0)) < THROTTLE_MS:
		return
	_last_play_msec[sound_id] = now
	# 取流（懒加载 + 缓存）
	var fname: String = variants[randi() % variants.size()]
	var stream: AudioStream = _get_stream(fname)
	if stream == null:
		return
	# 池里找空闲播放器（全忙则抢占最旧的 = 轮转）
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _get_stream(fname: String) -> AudioStream:
	if _streams.has(fname):
		return _streams[fname]
	var path := "%s/%s.ogg" % [AUDIO_DIR, fname]
	if not ResourceLoader.exists(path):
		push_warning("SoundManager: 音效文件不存在 %s" % path)
		return null
	var s: AudioStream = load(path)
	_streams[fname] = s
	return s


func _on_enemy_killed(enemy: Node) -> void:
	var e = enemy as Enemy
	if e != null and e.is_boss:
		play("boss_kill", -3.0)
	else:
		play("kill", -6.0)


# ── M 键静音（持久化到 user://settings.cfg）──

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		set_muted(not muted)
		get_viewport().set_input_as_handled()


func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "muted", muted)
	cfg.save(SETTINGS_PATH)


func _load_mute() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		muted = bool(cfg.get_value("audio", "muted", false))
		if muted:
			AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
