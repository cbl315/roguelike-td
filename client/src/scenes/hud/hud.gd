## hud.gd — 战斗 HUD：波次/核心血条/敌人数/结算 + 技能/羁绊触发按钮 + Tab 角色面板
extends Control
class_name HUD

signal skill_picker_requested()
signal bond_picker_requested()
signal char_panel_toggled()   # #6: Tab 角色面板切换（game_manager 处理暂停）

var _char_panel: Control = null   # #6: Tab 角色面板（动态创建）

@onready var _wave_label: Label = $WaveLabel
@onready var _timer_label: Label = $TimerLabel
@onready var _enemy_label: Label = $EnemyLabel
@onready var _gold_label: Label = $GoldLabel
@onready var _hp_bar: ProgressBar = $CoreHPBar
@onready var _hp_label: Label = $CoreHPLabel
@onready var _result_label: Label = $ResultLabel
@onready var _skill_btn: Button = $SideButtons/SkillButton
@onready var _bond_btn: Button = $SideButtons/BondButton
@onready var _skill_count_label: Label = $SideButtons/SkillButton/SkillCount


func _ready() -> void:
	_result_label.visible = false
	_skill_btn.pressed.connect(func(): skill_picker_requested.emit())
	_bond_btn.pressed.connect(func(): bond_picker_requested.emit())


## #6: Tab/ESC 处理角色面板（process_mode=ALWAYS 保证暂停时也能响应）
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB or event.keycode == KEY_ESCAPE:
			if is_char_panel_open():
				char_panel_toggled.emit()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_TAB:
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


func update_gold(g: float) -> void:
	_gold_label.text = "金币: %d" % int(g)


func update_skill_count(banked: int) -> void:
	# 技能按钮显示剩余免费机会；无机会时禁用
	_skill_count_label.text = "(%d)" % banked
	_skill_btn.disabled = banked <= 0


## 更新羁绊按钮：显示当前抽取成本
func update_bond_cost(cost: float) -> void:
	_bond_btn.text = "羁绊 (%d金)" % int(cost)
	_bond_btn.disabled = false


func show_result(won: bool) -> void:
	_result_label.visible = true
	_result_label.text = "🎉 通关！英雄！" if won else "💀 核心被毁，第 %d 波失败"


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
	panel.offset_left = 300; panel.offset_right = 1620
	panel.offset_top = 100; panel.offset_bottom = 980
	panel.z_index = 90
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 2; style.border_width_right = 2
	style.border_width_top = 2; style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.55, 0.7)
	panel.add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 20; scroll.offset_right = -20
	scroll.offset_top = 20; scroll.offset_bottom = -20
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	# 技能列表
	var skill_header := Label.new()
	skill_header.text = "\n=== 已有技能 (%d) ===" % build.owned_skills.size()
	skill_header.add_theme_font_size_override("font_size", 22)
	vbox.add_child(skill_header)
	for sid in build.owned_skills:
		var l := Label.new()
		l.text = "  • " + pools._find_skill_name(String(sid))
		l.add_theme_font_size_override("font_size", 18)
		vbox.add_child(l)
	if build.owned_skills.is_empty():
		var l := Label.new()
		l.text = "  （无）"
		vbox.add_child(l)
	# 羁绊列表
	var bond_header := Label.new()
	bond_header.text = "\n=== 已有羁绊 (%d / %d) ===" % [build.bond_pool.size(), build.bond_pool_capacity]
	bond_header.add_theme_font_size_override("font_size", 22)
	vbox.add_child(bond_header)
	for bid in build.bond_pool:
		var l := Label.new()
		l.text = "  • " + pools._find_bond_name(String(bid))
		l.add_theme_font_size_override("font_size", 18)
		vbox.add_child(l)
	if build.bond_pool.is_empty():
		var l := Label.new()
		l.text = "  （无）"
		vbox.add_child(l)
	# 境界进度
	if not build.path_realm.is_empty():
		var realm_header := Label.new()
		realm_header.text = "\n=== 修炼境界 ==="
		realm_header.add_theme_font_size_override("font_size", 22)
		vbox.add_child(realm_header)
		for pid in build.path_realm.keys():
			var idx: int = build.path_realm[pid]
			var maxr: int = pools.path_max_realm(pid)
			var l := Label.new()
			l.text = "  • %s: 第%d境 %d/%d" % [pools.path_name(pid), idx + 1, idx, maxr]
			l.add_theme_font_size_override("font_size", 18)
			vbox.add_child(l)
