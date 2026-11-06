## debug_keys.gd — 调试快捷键 autoload（发布隔离）。
## G=+500金  B=跳到下一个Boss波(10/20/30)  N=秒杀当前波
## 门控：OS.is_debug_build()——导出 release 构建自动全部失效，
## 调试功能不再与发行代码混置（原 game_manager._dbg_* 迁移于此）。
## 测试（gmcp regression 等）可调用公开方法 clear_wave()/jump_to_boss()。
extends Node

const GOLD_GRANT := 500.0


func _ready() -> void:
	# 树暂停（大厅/结算）时也要能响应调试键——否则 N/B 在选卡界面全部失灵
	process_mode = Node.PROCESS_MODE_ALWAYS


# _input 而非 _unhandled_input：大厅开着时 GUI 焦点会拦截 unhandled 层
# （实测最高频'按键没反应'根因）；N/B/G 与 UI 键位无冲突安全
func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	var gm = get_node_or_null("/root/GameRoot/GameManager")
	if gm == null or not ("_build" in gm):
		return
	# 便利：大厅/面板开着时也能跳——自动关面板解锁（波间 state=2 本就合法，
	# 卡的是树暂停+面板焦点；实测最高频的"按键没反应"原因）
	var lobby = get_node_or_null("/root/GameRoot/UILayer/Lobby")
	if lobby != null and lobby.visible:
		match event.keycode:
			KEY_N, KEY_B, KEY_G:
				lobby.close()
				get_tree().paused = false
			_:
				pass
	match event.keycode:
		KEY_G:
			gm._build.add_gold(GOLD_GRANT)
			if "_hud" in gm and gm._hud:
				gm._hud.update_gold(gm._build.gold)
			get_viewport().set_input_as_handled()
		KEY_N:
			clear_wave()
			get_viewport().set_input_as_handled()
		KEY_B:
			jump_to_boss()
			get_viewport().set_input_as_handled()


## 秒杀当前波全部敌人 → 走正常波结束流程（有击杀金币/反馈）
func clear_wave() -> void:
	var gm = _gm()
	if gm == null:
		return
	gm._spawner.stop_spawning()
	for e in gm._spawner.active_enemies().duplicate():
		if is_instance_valid(e):
			e.take_damage(1.0e9)


## 跳到下一个 Boss 波：清场后把波次拨到 next_boss-1，
## 波结束 → 间歇 → 自然进入 Boss 波（完整走预告/横幅/debuff 流程）
func jump_to_boss() -> void:
	var gm = _gm()
	if gm == null:
		return
	var next_boss: int = 0
	for bw in [10, 20, 30]:
		if bw > gm.current_wave:
			next_boss = bw
			break
	if next_boss == 0:
		return
	gm._spawner.stop_spawning()
	for e in gm._spawner.active_enemies().duplicate():
		if is_instance_valid(e):
			e.take_damage(1.0e9)
	gm.current_wave = next_boss - 1


func _gm():
	var gm = get_node_or_null("/root/GameRoot/GameManager")
	if gm == null or not ("_build" in gm):
		return null
	var st := int(gm.state)   # 1=战斗中 2=波间（显式优先级，杜绝 and/or 混写）
	if st == 1 or st == 2:
		return gm
	return null
