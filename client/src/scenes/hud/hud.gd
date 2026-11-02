## hud.gd — 战斗 HUD：波次/核心血条/敌人数/结算 + 羁绊/装备触发按钮 + Tab 角色面板
extends Control
class_name HUD

signal bond_picker_requested()
signal char_panel_toggled()
signal equipment_picker_requested()   # M3: 装备升级
signal restart_requested()            # 结算画面按 R 重开
signal ult_requested()                # 大招按钮（Q 键等价，移动端入口）
signal boss_debuff_reroll_requested() # 应对道具：换（GDD §13）
signal boss_debuff_remove_requested() # 应对道具：删

var _char_panel: Control = null   # #6: Tab 角色面板（动态创建）

# ── 布局常量区（UI 场景化前的集中管理；P2-⑥ 债务缓解）──
const POS_TOP_RIGHT := Vector2(1500, 0)      # 右上信息区原点（核心血条/能量条/预告条）
const POS_FORECAST_BTNS := Vector2(1500, 128)  # Boss 预告换/删按钮
const POS_RESULT := Vector2(560, 400)        # 结算面板文字区
var _toast_label: Label = null    # 居中临时提示（突破境界）
var _toast_timer: float = 0.0     # Toast 剩余显示时间
var _result_shown: bool = false   # 结算画面显示中（R 键重开用）
var _ult_bar: ProgressBar = null  # 大招能量条
var _forecast_label: Label = null # 下一个 Boss debuff 预告
var _forecast_reroll: Button = null
var _forecast_remove: Button = null
var _forecast_cache: Dictionary = {}   # 最近一次预告数据（金币变化时刷新按钮态）
var _breakthrough_layer: CanvasLayer = null   # 突破演出层（大厅遮罩之上）
var _breakthrough_label: Label = null
var _breakthrough_timer: float = 0.0
var _fb_breakthrough: FeedbackPlayerLite = null   # 金闪+顿帧

@onready var _wave_label: Label = $WaveLabel
@onready var _timer_label: Label = $TimerLabel
@onready var _enemy_label: Label = $EnemyLabel
@onready var _gold_label: Label = $GoldLabel
@onready var _hp_bar: ProgressBar = $CoreHPBar
@onready var _hp_label: Label = $CoreHPLabel
@onready var _result_label: Label = $ResultLabel
@onready var _bond_btn: Button = $SideButtons/BondButton
@onready var _equip_btn: Button = $SideButtons/EquipButton
@onready var _char_btn: Button = $SideButtons/CharButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停（大厅）时 _process 也跑，Toast 能淡出
	_result_label.visible = false
	_bond_btn.pressed.connect(_on_bond_btn)
	_equip_btn.pressed.connect(_on_equip_btn)
	_char_btn.pressed.connect(_on_char_btn)
	# 创建 Toast 提示（突破境界）
	_toast_label = Label.new()
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.offset_top = 120
	_toast_label.add_theme_font_size_override("font_size", 32)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.visible = false
	add_child(_toast_label)
	# 连接信号
	EventBus.bond_devoured.connect(_on_bond_devoured)
	EventBus.ult_energy_changed.connect(update_ult_energy)
	_setup_ult_ui()
	_setup_breakthrough_ui()
	_setup_forecast_ui()


func _process(delta: float) -> void:
	# Toast 倒计时 + 淡出（process_mode=ALWAYS 保证暂停时也运行）
	if _toast_timer > 0:
		_toast_timer -= delta
		if _toast_timer <= 0:
			_toast_label.visible = false
		elif _toast_timer < 0.5:
			_toast_label.modulate.a = _toast_timer / 0.5
	# 突破演出：大字弹入（1.6→1.0）+ 尾段淡出
	if _breakthrough_timer > 0:
		_breakthrough_timer -= delta
		if _breakthrough_timer <= 0:
			_breakthrough_label.visible = false
		else:
			var s: float = maxf(1.0, 1.0 + 0.6 * _breakthrough_timer / 2.2)   # 前 ~0.8s 从 1.6 收到 1.0
			_breakthrough_label.scale = Vector2(s, s)
			if _breakthrough_timer < 0.5:
				_breakthrough_label.modulate.a = _breakthrough_timer / 0.5


## 公开 toast（game_manager 突破怪等流程用）
func show_toast(text: String, color: Color = Color(0.95, 0.85, 0.55), duration: float = 3.0) -> void:
	_show_toast(text, color, duration)


func _show_toast(text: String, color: Color, duration: float = 3.0) -> void:
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", color)
	_toast_label.modulate.a = 1.0
	_toast_label.visible = true
	_toast_timer = duration


## Boss Debuff 横幅预告（Boss 波开始时，比普通 Toast 更醒目）
func show_boss_debuff_banner(debuff_name: String, wave: int) -> void:
	SoundManager.play("wave_start", -3.0)
	_show_toast("⚠ 第 %d 波 BOSS · %s" % [wave, debuff_name], Color(1.0, 0.45, 0.35), 4.0)


## 吞噬召唤单位演出（白魇魔→半魔）：暗紫大字 + 顿帧（复用突破层）
func show_summon_devoured(unit_name: String) -> void:
	_breakthrough_label.text = "🌑 %s 被吞噬 · 半魔觉醒 🌑\n（加成并入本体）" % unit_name
	_breakthrough_label.modulate.a = 1.0
	_breakthrough_label.visible = true
	_breakthrough_label.scale = Vector2(1.6, 1.6)
	_breakthrough_label.add_theme_color_override("font_color", Color(0.75, 0.5, 0.95))
	_breakthrough_timer = 2.2
	if _fb_breakthrough != null:
		_fb_breakthrough.play()


func _on_bond_devoured(path_id: String, realm_idx: int, realm_name: String) -> void:
	# 突破演出（GDD 情感爽点）：金光闪屏 + 境界大字 + 顿帧（音效 SoundManager 已接）
	var name_map := {"zhutian": "遮天", "xingchenbian": "星辰变", "chongmei": "宠魅", "doupo": "斗破"}
	var pname: String = name_map.get(path_id, path_id)
	_breakthrough_label.text = "⚡ %s · %s 圆满 ⚡\n（%d 境）" % [pname, realm_name, realm_idx]
	_breakthrough_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))   # 金色（吞噬演出可能改过）
	_breakthrough_label.modulate.a = 1.0
	_breakthrough_label.visible = true
	_breakthrough_label.scale = Vector2(1.6, 1.6)   # 大字从 1.6 弹到 1.0
	_breakthrough_timer = 2.2
	if _fb_breakthrough != null:
		_fb_breakthrough.play()


func _setup_ult_ui() -> void:
	# 能量条（核心血条正下方，金色）
	_ult_bar = ProgressBar.new()
	_ult_bar.position = POS_TOP_RIGHT + Vector2(0, 68)
	_ult_bar.size = Vector2(390, 14)
	_ult_bar.min_value = 0.0
	_ult_bar.max_value = 1.0
	_ult_bar.value = 0.0
	_ult_bar.show_percentage = false
	_ult_bar.modulate = Color(1.0, 0.85, 0.45)
	add_child(_ult_bar)
	# 能量条本身可点击释放（与 Q 键等价；原左下大招按钮与右上条重复，已删——
	# 移动端入口也由本条承担）
	_ult_bar.custom_minimum_size = Vector2(390, 18)   # 加高命中区
	_ult_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_ult_bar.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and _ult_bar.value >= 1.0:
			ult_requested.emit())
	_ult_bar.tooltip_text = "大招能量（满后点击或按 Q 释放）"


func _setup_breakthrough_ui() -> void:
	# 演出层在大厅遮罩之上（UILayer=10 → 15）
	_breakthrough_layer = CanvasLayer.new()
	_breakthrough_layer.layer = 15
	add_child(_breakthrough_layer)
	_breakthrough_label = Label.new()
	# 固定居中区域（anchors CENTER 会得 0 尺寸 Label）
	_breakthrough_label.position = Vector2(360, 380)
	_breakthrough_label.size = Vector2(1200, 200)
	_breakthrough_label.pivot_offset = Vector2(600, 100)   # 中心为缩放轴
	_breakthrough_label.add_theme_font_size_override("font_size", 52)
	_breakthrough_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
	_breakthrough_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_breakthrough_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_breakthrough_label.visible = false
	_breakthrough_layer.add_child(_breakthrough_label)
	# 突破反馈：金光闪屏 + 顿帧
	_fb_breakthrough = FeedbackPlayerLite.new()
	var flash := FeedbackScreenFlash2DLite.new()
	flash.flash_color = Color(1.0, 0.92, 0.6)
	flash.flash_intensity = 0.5
	flash.fade_out_duration_ms = 400.0
	var pause := FeedbackHitPauseLite.new()
	pause.duration_ms = 150.0
	pause.time_scale_during_pause = 0.05
	_fb_breakthrough.feedbacks = [flash, pause]
	add_child(_fb_breakthrough)


func update_ult_energy(ratio: float) -> void:
	if _ult_bar != null:
		_ult_bar.value = ratio
		# 满能量视觉：金条变亮 + tooltip 提示（点击/Q 释放）
		_ult_bar.modulate = Color(1.0, 0.95, 0.55) if ratio >= 1.0 else Color(1.0, 0.85, 0.45)
		_ult_bar.tooltip_text = "⚡ 大招就绪！点击或按 Q 释放" if ratio >= 1.0 else "大招能量（满后点击或按 Q 释放）"


## 下一个 Boss debuff 预告 + 换/删道具（GDD §13，game_manager 波间刷新）
func _setup_forecast_ui() -> void:
	_forecast_label = Label.new()
	_forecast_label.position = POS_TOP_RIGHT + Vector2(0, 100)
	_forecast_label.size = Vector2(390, 26)
	_forecast_label.add_theme_font_size_override("font_size", 17)
	_forecast_label.add_theme_color_override("font_color", Color(0.95, 0.7, 0.55))
	add_child(_forecast_label)
	_forecast_reroll = Button.new()
	_forecast_reroll.position = POS_FORECAST_BTNS
	_forecast_reroll.size = Vector2(130, 34)
	_forecast_reroll.add_theme_font_size_override("font_size", 15)
	_forecast_reroll.focus_mode = Control.FOCUS_NONE
	_forecast_reroll.pressed.connect(func(): boss_debuff_reroll_requested.emit())
	add_child(_forecast_reroll)
	_forecast_remove = Button.new()
	_forecast_remove.position = POS_FORECAST_BTNS + Vector2(140, 0)
	_forecast_remove.size = Vector2(130, 34)
	_forecast_remove.add_theme_font_size_override("font_size", 15)
	_forecast_remove.focus_mode = Control.FOCUS_NONE
	_forecast_remove.pressed.connect(func(): boss_debuff_remove_requested.emit())
	add_child(_forecast_remove)
	_forecast_label.visible = false
	_forecast_reroll.visible = false
	_forecast_remove.visible = false


func update_boss_forecast(nb: Dictionary, gold: float) -> void:
	_forecast_cache = {"nb": nb, "gold": gold}
	var show: bool = not nb.is_empty()
	_forecast_label.visible = show
	_forecast_reroll.visible = show
	_forecast_remove.visible = show
	if not show:
		return
	var removed: bool = nb.get("removed", false)
	if removed:
		_forecast_label.text = "下一 BOSS（第 %d 波）：✅ debuff 已消除" % int(nb["wave"])
	else:
		_forecast_label.text = "下一 BOSS（第 %d 波）：%s" % [int(nb["wave"]), nb.get("name", "?")]
	_forecast_reroll.text = "换 40金"
	_forecast_remove.text = "删 120金"
	_forecast_reroll.disabled = removed or gold < 40.0
	_forecast_remove.disabled = removed or gold < 120.0


func update_gold(g: float) -> void:
	_gold_label.text = "金币: %d" % int(g)
	# 金币变化联动预告按钮禁用态（缓存数据重算）
	if not _forecast_cache.is_empty():
		update_boss_forecast(_forecast_cache.get("nb", {}), g)


func on_ult_ready() -> void:
	SoundManager.play("wave_clear", -4.0)   # 就绪提示音


func _on_bond_btn() -> void:
	SoundManager.play("ui_click", -6.0)
	bond_picker_requested.emit()


func _on_equip_btn() -> void:
	SoundManager.play("ui_click", -6.0)
	equipment_picker_requested.emit()


func _on_char_btn() -> void:
	SoundManager.play("ui_click", -6.0)
	char_panel_toggled.emit()


## 角色面板：Tab/C 键 或 ESC 关闭（也通过按钮触发，移动端友好）
## 结算画面：R 键重开（HUD 是 ALWAYS，暂停时也能收到）
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R and _result_shown:
			# 顺序关键：先标记已处理再 emit——emit 同步触发 reload_current_scene，
			# HUD 出树后 get_viewport() 会返回 null
			get_viewport().set_input_as_handled()
			restart_requested.emit()
			return
		if event.keycode == KEY_TAB or event.keycode == KEY_C:
			char_panel_toggled.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if is_char_panel_open():
				char_panel_toggled.emit()
				get_viewport().set_input_as_handled()


func update_wave(wave: int) -> void:
	_wave_label.text = "第 %d / %d 波" % [wave, WaveCurves.main_quest_waves()]


## 更新波次倒计时（秒）
func update_timer(seconds: float) -> void:
	if seconds < 0.0:
		_timer_label.text = ""
		return
	_timer_label.text = "⏱ %ds" % maxi(0, int(ceil(seconds)))


func update_enemy_count(n: int) -> void:
	_enemy_label.text = "敌人: %d" % n


func update_core_hp(hp: float, max_hp: float) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_hp_label.text = "核心 %d / %d" % [int(hp), int(max_hp)]


## 更新羁绊按钮：显示当前抽取成本
func update_bond_cost(cost: float) -> void:
	_bond_btn.text = "羁绊 (%d金)" % int(cost)
	_bond_btn.disabled = false


## M3: 更新装备按钮：显示等级 + 升级成本
func update_equip_state(level: int, cost: float) -> void:
	_equip_btn.text = "装备 (+%d, %d金)" % [level, int(cost)]
	_equip_btn.disabled = false


func show_result(won: bool, wave: int = 1, stats: Dictionary = {}) -> void:
	_result_shown = true
	_result_label.visible = true
	# 加高结算区域容纳统计块（原 120 高只够两行）
	_result_label.position = POS_RESULT
	_result_label.size = Vector2(800, 280)
	_result_label.add_theme_font_size_override("font_size", 30)
	var title := ""
	if won:
		title = "🎉 通关！英雄！守住全部 %d 波" % wave
	else:
		title = "💀 核心被毁，第 %d 波失败" % wave
	var body := ""
	if not stats.is_empty():
		body = "\n\n总伤害 %s   击杀 %d（Boss %d）\n突破 %d 境   羁绊 %d 张   获取金币 %s" % [
			_fmt_num(stats.get("damage", 0.0)), stats.get("kills", 0), stats.get("boss_kills", 0),
			stats.get("breakthroughs", 0), stats.get("bonds", 0), _fmt_num(stats.get("gold", 0.0))]
	_result_label.text = title + body + "\n\n按 R 重新开始"


func _fmt_num(v: float) -> String:
	if v >= 1000000.0:
		return "%.1fM" % (v / 1000000.0)
	if v >= 1000.0:
		return "%.1fK" % (v / 1000.0)
	return "%d" % int(v)


# ── #6: Tab 角色面板 ──

## 切换角色面板（由 game_manager 的 Tab 键调用）
func toggle_character_panel(build: BuildState, pools: RoguePools) -> void:
	if _char_panel != null and is_instance_valid(_char_panel) and _char_panel.visible:
		close_character_panel()
	else:
		open_character_panel(build, pools)


func open_character_panel(build: BuildState, pools: RoguePools) -> void:
	if _char_panel == null or not is_instance_valid(_char_panel):
		_char_panel = _build_char_panel()
		add_child(_char_panel)
	_render_char_panel(build, pools)
	_char_panel.visible = true


func close_character_panel() -> void:
	if _char_panel != null and is_instance_valid(_char_panel):
		_char_panel.visible = false


func is_char_panel_open() -> bool:
	return _char_panel != null and is_instance_valid(_char_panel) and _char_panel.visible


func _build_char_panel() -> Control:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 100; panel.offset_right = 1820
	panel.offset_top = 60; panel.offset_bottom = 1020
	panel.z_index = 90
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 2; style.border_width_right = 2
	style.border_width_top = 2; style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.55, 0.7)
	panel.add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 20)
	scroll.size = Vector2(1700 - 40, 960 - 40)   # 固定大小（panel 区域 100-1820 × 60-1020）
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(1700 - 60, 0)   # 固定宽度，让内容撑高度
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)
	vbox.set_meta("vbox", true)   # 标记，方便后续 find
	return panel


func _render_char_panel(build: BuildState, pools: RoguePools) -> void:
	if _char_panel == null:
		return
	var scroll: ScrollContainer = _char_panel.get_child(0)
	var vbox: VBoxContainer = scroll.get_child(0)
	# 清空旧内容
	for c in vbox.get_children():
		c.queue_free()
	# 标题
	var title := Label.new()
	title.text = "=== 角色面板 (Tab 关闭) ==="
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)
	# 属性
	var stats: CombatStats = build.assemble_stats()
	var dps: float = stats.expected_dps(20.0)
	var stat_lines: Array = [
		"生命: %.0f" % stats.effective_max_hp(),
		"吸血: %.0f%%" % (stats.lifesteal_pct * 100.0),
		"减伤: %.0f%%" % (stats.damage_reduction * 100.0),
		"攻击力: %.0f" % stats.atk,
		"技能倍率: ×%.2f" % stats.atk_ratio,
		"暴击率: %.0f%%" % (stats.crit_rate * 100.0),
		"暴击伤害: ×%.2f" % stats.crit_dmg,
		"攻速: %.1f/s" % stats.attack_speed,
		"弹数: %d" % stats.projectile_count,
		"物理伤害: +%.0f%%" % (stats.physical_dmg_pct * 100.0),
		"法术伤害: +%.0f%%" % (stats.magic_dmg_pct * 100.0),
		"元素伤害: +%.0f%%" % (stats.elemental_pct * 100.0),
		"最终伤害: +%.0f%%" % ((CombatStats.final_mult(stats.final_dmg_mults) - 1.0) * 100.0),
		"护甲穿透: %.0f%%" % (stats.armor_pen * 100.0),
		"真伤占比: %.0f%%" % (stats.true_dmg_pct * 100.0),
		"--- 预期 DPS(20甲): %.0f ---" % dps,
	]
	for line in stat_lines:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 20)
		vbox.add_child(l)
	# 宠物属性：只在实际有宠物时显示（非宠魅局/白魇魔已吞噬并入本体 → 整段隐藏）
	var pet_lines: Array = []
	if build.path_realm.has("chongmei"):
		# 莫邪：选宠魅种子即常驻
		var mx: CombatStats = build.assemble_pet_stats("moxie")
		pet_lines.append("莫邪：攻击 %.0f | 攻速 %.1f/s | 弹数 %d | DPS(20甲) %.0f" % [
			mx.atk, mx.attack_speed, mx.projectile_count, mx.expected_dps(20.0)])
		# 白魇魔：魂士境(1)降生 ~ 魂朽境(6)被吞噬；吞噬后并入本体不再单列
		var cmr := int(build.path_realm.get("chongmei", 0))
		if cmr >= 1 and not build.baiyanmeng_devoured():
			var bym: CombatStats = build.assemble_pet_stats("baiyanmeng")
			pet_lines.append("白魇魔：攻击 %.0f | 攻速 %.1f/s | 弹数 %d | DPS(20甲) %.0f" % [
				bym.atk, bym.attack_speed, bym.projectile_count, bym.expected_dps(20.0)])
	if not pet_lines.is_empty():
		var pet_header := Label.new()
		pet_header.text = "\n=== 宠物属性 ==="
		pet_header.add_theme_font_size_override("font_size", 22)
		pet_header.add_theme_color_override("font_color", Color(0.8, 0.55, 1.0))
		vbox.add_child(pet_header)
		for line in pet_lines:
			var l2 := Label.new()
			l2.text = line
			l2.add_theme_font_size_override("font_size", 20)
			l2.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
			vbox.add_child(l2)
	# 羁绊列表
	var bond_header := Label.new()
	bond_header.text = "\n=== 已有羁绊 (%d / %d) ===" % [build.bond_pool.size(), build.bond_pool_capacity]
	bond_header.add_theme_font_size_override("font_size", 22)
	vbox.add_child(bond_header)
	for bid in build.bond_pool:
		var l := Label.new()
		l.text = "  • " + pools.find_bond_name(String(bid))
		l.add_theme_font_size_override("font_size", 18)
		vbox.add_child(l)
	if build.bond_pool.is_empty():
		var l := Label.new()
		l.text = "  （无）"
		vbox.add_child(l)
	# 已吞噬羁绊
	if build.devoured_bonds.size() > 0:
		var dev_header := Label.new()
		dev_header.text = "\n=== 已吞噬 (%d) ===" % build.devoured_bonds.size()
		dev_header.add_theme_font_size_override("font_size", 22)
		vbox.add_child(dev_header)
		for bid in build.devoured_bonds:
			var l := Label.new()
			l.text = "  ◆ " + pools.find_bond_name(String(bid))
			l.add_theme_font_size_override("font_size", 16)
			l.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
			vbox.add_child(l)
	# 境界进度（显示境界名 + 当前境界羁绊进度）
	if not build.path_realm.is_empty():
		var realm_header := Label.new()
		realm_header.text = "\n=== ⚡ 修炼境界 ==="
		realm_header.add_theme_font_size_override("font_size", 22)
		vbox.add_child(realm_header)
		for pid in build.path_realm.keys():
			var idx: int = build.path_realm[pid]
			var maxr: int = pools.path_max_realm(pid)
			# 跳过 generic_fusion（不是修炼体系，不显示境界进度）
			if pid == "generic_fusion":
				continue
			var prog: Dictionary = pools.cultivation_progress_for(build.bond_pool, pid, idx)
			# 境界名（轮海/道宫/四极…），修满显示"圆满"
			var cur_name := pools.realm_name(pid, mini(idx, maxr - 1)) if idx < maxr else "圆满"
			var l := Label.new()
			if idx >= maxr:
				l.text = "  ★ %s: %s 圆满 (%d/%d)" % [pools.path_name(pid), cur_name, idx, maxr]
				l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			else:
				var owned_n: int = int(prog.get("owned_count", 0))
				var total_n: int = int(prog.get("total_count", 0))
				l.text = "  ◆ %s · %s  羁绊 %d/%d  (%d/%d境)" % [
					pools.path_name(pid), cur_name, owned_n, total_n, idx, maxr]
			l.add_theme_font_size_override("font_size", 20)
			vbox.add_child(l)
			# 当前境界还缺哪些羁绊
			if idx < maxr:
				var missing_names: Array = prog.get("missing_names", [])
				if not missing_names.is_empty():
					var ml := Label.new()
					ml.text = "      缺: " + ", ".join(missing_names)
					ml.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
					ml.add_theme_font_size_override("font_size", 16)
					vbox.add_child(ml)
	# M3: 装备信息
	var eq_header := Label.new()
	eq_header.text = "\n=== 装备 +%d / +%d ===" % [build.equip_level, pools.equip_max_level()]
	eq_header.add_theme_font_size_override("font_size", 22)
	vbox.add_child(eq_header)
	var eq_gps: float = build.gold_per_sec()
	var eq_pkb: float = build.per_kill_bonus()
	var eq_gm: float = build.gold_multiplier()
	var eq_info := Label.new()
	eq_info.text = "  每秒金币: +%.1f  击杀金币: +%.1f  金币倍率: ×%.2f" % [eq_gps, eq_pkb, eq_gm]
	eq_info.add_theme_font_size_override("font_size", 18)
	vbox.add_child(eq_info)
	if build.equip_affixes.size() > 0:
		for affix in build.equip_affixes:
			var polarity_tag := "🔴" if affix.get("polarity") == "curse" else "🟢"
			var al := Label.new()
			var affix_desc: String = pools._effect_to_text(affix.get("effect", {}))
			al.text = "  %s %s %s" % [polarity_tag, affix.get("name", ""), affix_desc]
			al.add_theme_font_size_override("font_size", 18)
			vbox.add_child(al)
	# 已触发联动
	if build.active_synergies.size() > 0:
		var syn_header := Label.new()
		syn_header.text = "\n=== ⚡ 已触发联动 (%d) ===" % build.active_synergies.size()
		syn_header.add_theme_font_size_override("font_size", 22)
		syn_header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		vbox.add_child(syn_header)
		for syn in build.active_synergies:
			var rarity: String = syn.get("rarity", "")
			var tier_prefix := "★ " if rarity == "EX" else ""
			var l := Label.new()
			l.text = "  ⚡ %s%s" % [tier_prefix, syn.get("name", syn.get("id", ""))]
			l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			l.add_theme_font_size_override("font_size", 18)
			vbox.add_child(l)
	else:
		var syn_empty := Label.new()
		syn_empty.text = "\n=== 联动 ===\n  （未触发——修满体系 + 搭配技能/装备可触发联动）"
		syn_empty.add_theme_font_size_override("font_size", 18)
		syn_empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		vbox.add_child(syn_empty)
