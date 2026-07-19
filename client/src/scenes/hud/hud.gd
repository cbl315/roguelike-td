## hud.gd — 战斗 HUD：波次/核心血条/敌人数/结算 + 羁绊/装备触发按钮 + Tab 角色面板
extends Control
class_name HUD

signal bond_picker_requested()
signal char_panel_toggled()
signal equipment_picker_requested()   # M3: 装备升级

var _char_panel: Control = null   # #6: Tab 角色面板（动态创建）
var _toast_label: Label = null    # 居中临时提示（突破境界）
var _toast_timer: float = 0.0     # Toast 剩余显示时间

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


func _process(delta: float) -> void:
	# Toast 倒计时 + 淡出（process_mode=ALWAYS 保证暂停时也运行）
	if _toast_timer > 0:
		_toast_timer -= delta
		if _toast_timer <= 0:
			_toast_label.visible = false
		elif _toast_timer < 0.5:
			_toast_label.modulate.a = _toast_timer / 0.5


func _show_toast(text: String, color: Color, duration: float = 3.0) -> void:
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", color)
	_toast_label.modulate.a = 1.0
	_toast_label.visible = true
	_toast_timer = duration


func _on_bond_devoured(path_id: String, realm_idx: int, realm_name: String) -> void:
	# 突破境界提示：realm_name 是刚完成的境界（如轮海），idx 是已完成数
	var name_map := {"zhutian": "遮天"}
	var pname: String = name_map.get(path_id, path_id)
	_show_toast("⚡ 突破！%s·%s 圆满（%d境）" % [pname, realm_name, realm_idx], Color(1.0, 0.85, 0.3))


func _on_bond_btn() -> void:
	bond_picker_requested.emit()


func _on_equip_btn() -> void:
	equipment_picker_requested.emit()


func _on_char_btn() -> void:
	char_panel_toggled.emit()


## 角色面板：Tab/C 键 或 ESC 关闭（也通过按钮触发，移动端友好）
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
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


func update_gold(g: float) -> void:
	_gold_label.text = "金币: %d" % int(g)


## 更新羁绊按钮：显示当前抽取成本
func update_bond_cost(cost: float) -> void:
	_bond_btn.text = "羁绊 (%d金)" % int(cost)
	_bond_btn.disabled = false


## M3: 更新装备按钮：显示等级 + 升级成本
func update_equip_state(level: int, cost: float) -> void:
	_equip_btn.text = "装备 (+%d, %d金)" % [level, int(cost)]
	_equip_btn.disabled = false


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
	# 已吞噬羁绊
	if build.devoured_bonds.size() > 0:
		var dev_header := Label.new()
		dev_header.text = "\n=== 已吞噬 (%d) ===" % build.devoured_bonds.size()
		dev_header.add_theme_font_size_override("font_size", 22)
		vbox.add_child(dev_header)
		for bid in build.devoured_bonds:
			var l := Label.new()
			l.text = "  ◆ " + pools._find_bond_name(String(bid))
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
			var prog: Dictionary = pools.cultivation_progress(build.bond_pool, build.path_realm)
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
