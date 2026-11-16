## frame_animator.gd — 帧动画播放器（AI 生成精灵序列 → 状态机播放）。
## 替代"一张贴图 + 代码变换"的僵硬模式。
##
## 用法：
##   var anim = FrameAnimator.new()
##   anim.load_frames("res://src/assets/anim/hero/walk", "walk", 6, 10.0)
##   anim.play("walk")        # 切换到走路动画
##   anim.tick(delta)          # 每帧调用
##   var tex = anim.get_frame() # _draw 里用这个贴图绘制
class_name FrameAnimator
extends RefCounted

var _states: Dictionary = {}    # state_name → {frames: Array[Texture2D], fps: float, loop: bool}
var _current: String = ""
var _frame_idx: float = 0.0
var _playing: bool = false


## 加载一个动画状态（从目录读取 frame_XX.png 序列）
func load_frames(dir_path: String, state_name: String, frame_count: int, fps: float, loop: bool = true) -> void:
	var frames: Array[Texture2D] = []
	for i in range(frame_count):
		var p := "%s/%s_%02d.png" % [dir_path, state_name, i]
		if ResourceLoader.exists(p):
			frames.append(load(p))
	if frames.is_empty():
		return
	_states[state_name] = {"frames": frames, "fps": fps, "loop": loop}


## 是否有可用动画
func has_animation(state: String) -> bool:
	return _states.has(state) and not _states[state]["frames"].is_empty()


## 切换到指定状态（带帧进度重置）
func play(state: String) -> void:
	if state == _current or not has_animation(state):
		return
	_current = state
	_frame_idx = 0.0
	_playing = true


## 停止（回退到第 0 帧）
func stop() -> void:
	_playing = false
	_frame_idx = 0.0


## 每帧调用（推进帧索引）
func tick(delta: float) -> void:
	if not _playing or _current.is_empty():
		return
	var spec: Dictionary = _states[_current]
	var fps: float = spec["fps"]
	var frame_count: int = spec["frames"].size()
	_frame_idx += delta * fps
	if _frame_idx >= frame_count:
		if spec["loop"]:
			_frame_idx = fmod(_frame_idx, frame_count)
		else:
			_frame_idx = frame_count - 1
			_playing = false


## 获取当前帧贴图（_draw 里绘制这个）
func get_frame() -> Texture2D:
	if _current.is_empty() or not _states.has(_current):
		return null
	var frames: Array = _states[_current]["frames"]
	if frames.is_empty():
		return null
	return frames[int(_frame_idx) % frames.size()]


## 当前状态名
func current_state() -> String:
	return _current


## 帧进度（0-1，非循环动画判断是否播完用）
func progress() -> float:
	if _current.is_empty():
		return 0.0
	var count: int = _states[_current]["frames"].size()
	return _frame_idx / maxf(count, 1.0)


## 是否播完（非循环）
func is_finished() -> bool:
	return not _playing and not _current.is_empty()
