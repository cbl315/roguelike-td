## lobby.gd — 按需触发的选择器面板（M2 重构：不自动弹，玩家点 HUD 按钮打开）
## 羁绊选择器（需 build.bond_draw_cost() 金，递增 30→60）/ 装备升级。
## （技能选择器已移除：技能改为每体系 1 个起点技能。）
extends Control
class_name Lobby

signal confirmed()

const REROLL_CAP := 3

var build: BuildState
var pools: RoguePools

var _bond_offers: Array = []
var _rerolls_this_wave: int = 0
var _current_tab: String = "bond"   # "bond" or "equipment"
var _replace_mode: bool = false       # 池满替换模式：显示池子让玩家选扔哪个
var _pending_offer: Dictionary = {}   # 替换模式下待入池的新羁绊

@onready var _gold_label: Label = $TopBar/GoldLabel
@onready var _info_label: Label = $TopBar/InfoLabel
@onready var _dps_label: Label = $TopBar/DPSLabel
@onready var _build_label: Label = $TopBar/BuildLabel
@onready var _cards_container: HBoxContainer = $CardsContainer
@onready var _actions: VBoxContainer = $Actions
@onready var _realm_label: Label = $SidePanel/RealmLabel


func setup(p_build: BuildState, p_pools: RoguePools) -> void:
	# 兼容旧调用（game_manager 现在用 set_build_ref）
	set_build_ref(p_build, p_pools)


func set_build_ref(p_build: BuildState, p_pools: RoguePools) -> void:
	build = p_build
	pools = p_pools
	if build and not build.changed.is_connected(_render):
		build.changed.connect(_render)


## HUD 按钮"羁绊"触发：打开即扣 bond_draw_cost() 金，之后 3 选 1 和刷新都免费。
func open_bond() -> void:
	if build == null or not build.spend(build.bond_draw_cost()):
		return   # 金币不足
	build.bonds_drawn += 1   # 递增下一次抽羁绊成本
	_current_tab = "bond"
	_rerolls_this_wave = 0
	_refresh_bond_offers()
	visible = true


## M3: HUD 按钮"装备"触发：装备升级界面
func open_equipment() -> void:
	_current_tab = "equipment"
	_render()
	visible = true


func close() -> void:
	_replace_mode = false
	_pending_offer = {}
	visible = false
	get_tree().paused = false
	confirmed.emit()


func _refresh_bond_offers() -> void:
	# 阶梯抽取：引擎只给当前境界的羁绊 + generic（硬限制，不会越级出 EX）
	# prefer：当前境界还缺的羁绊（加权，加快凑齐突破）
	var prefer: Array = []
	var prog: Dictionary = pools.cultivation_progress(build.bond_pool, build.path_realm)
	if not prog.is_empty():
		prefer = prog.get("needed", [])
	# 排除：已拥有 + 已吞噬（引擎内部也排已拥有，这里补已吞噬）
	var excluded: Array = build.bond_pool.duplicate()
	for b in build.devoured_bonds:
		if not excluded.has(b):
			excluded.append(b)
	_bond_offers = pools.draw_bond_offers(3, prefer, excluded, build.path_realm)
	_render()


## 存储当前卡片的屏幕区域 + idx（供 GameManager._input 手动点击检测）
var card_click_rects: Array = []


func _render() -> void:
	card_click_rects.clear()
	if build:
		_gold_label.text = "金币: %d" % int(build.gold)
		_build_label.text = build.summary()
		var stats := build.assemble_stats()
		_dps_label.text = "DPS: %.0f" % stats.expected_dps(20.0)
		_realm_label.text = _realm_text()
	# 替换模式：池满了，让玩家选一个羁绊扔掉换新的
	if _replace_mode:
		_render_replace_mode()
		return
	if _current_tab == "equipment":
		_render_equipment_tab()
		return
	# 默认/羁绊 tab
	var offers: Array = _bond_offers
	var prog: Dictionary = pools.cultivation_progress(build.bond_pool, build.path_realm)
	if not prog.is_empty():
		_info_label.text = "【%s·%s】境界进度: %d/%d  缺: %s" % [
			prog.get("path_name", ""), prog.get("realm_name", ""),
			prog.get("owned_count", 0), prog.get("total_count", 0),
			", ".join(prog.get("missing_names", []))
		]
	else:
		_info_label.text = "[羁绊] 未修炼任何体系（凑齐同体系羁绊自动吞噬升境）"
	# 清空卡片
	for c in _cards_container.get_children():
		c.queue_free()
	# 渲染卡片：羁绊模式在有钱抽时显示
	var show_cards := true
	if offers.is_empty():
		var empty := Label.new()
		empty.text = "当前可抽羁绊已全拥有\n请先突破境界解锁更多，或关闭继续战斗"
		empty.horizontal_alignment = 1   # CENTER
		_cards_container.add_child(empty)
		show_cards = false
	if show_cards:
		for i in offers.size():
			var offer: Dictionary = offers[i]
			var card: Control = _make_card(offer, i)
			_cards_container.add_child(card)
			# 记录卡片屏幕区域供手动点击检测（延迟一帧等布局完成）
			call_deferred("_record_card_rect", card, i)


## 替换模式渲染：羁绊池满了，显示当前池中所有羁绊，玩家点一个 = 扔掉它换 pending_offer。
## pending_offer 显示在最右侧（不可点，只展示将要获得的）。
func _render_replace_mode() -> void:
	card_click_rects.clear()
	# 新羁绊名
	var new_name: String = _pending_offer.get("name", "?")
	_info_label.text = "⚠️ 羁绊池已满！选一个【丢弃】来换取【%s】" % new_name
	# 清空卡片容器
	for c in _cards_container.get_children():
		c.queue_free()
	# 渲染池中现有羁绊（可点 = 丢弃它）
	for i in build.bond_pool.size():
		var bid: String = build.bond_pool[i]
		var b: Dictionary = pools._find_bond(bid)
		var fake_offer: Dictionary = {
			"id": bid, "name": b.get("name", bid), "rarity": b.get("rarity", "N"),
			"effect": b.get("effect", {})
		}
		var card: Control = _make_card(fake_offer, i)
		# 标记为丢弃卡片（红框）
		card.modulate = Color(1.0, 0.7, 0.7)
		_cards_container.add_child(card)
		call_deferred("_record_card_rect", card, i)
	# 最右侧显示将要获得的新羁绊（不可点，展示用）
	var new_card: Control = _make_card(_pending_offer, -1)
	new_card.modulate = Color(0.7, 1.0, 0.7)
	_cards_container.add_child(new_card)
	# actions 区只留"取消"
	for c in _actions.get_children():
		c.queue_free()
	var cancel_btn := Button.new()
	cancel_btn.text = "取消（不替换）"
	cancel_btn.pressed.connect(_on_replace_cancel)
	_actions.add_child(cancel_btn)


## 替换模式：点了某张池中羁绊卡片 = 丢弃它换 pending_offer。
func _on_replace_pick(idx: int) -> void:
	if idx < 0 or idx >= build.bond_pool.size():
		return
	var discard_id: String = build.bond_pool[idx]
	build.replace_bond(discard_id, _pending_offer)
	# 退出替换模式
	_replace_mode = false
	_pending_offer = {}
	close()


## 替换模式：取消（退回 open 时扣的钱，因为没真正获得羁绊）。
func _on_replace_cancel() -> void:
	_replace_mode = false
	_pending_offer = {}
	build.refund_bond_draw()
	_refresh_bond_offers()


## M3: 装备 tab 渲染（升级界面，非 3 选 1）
func _render_equipment_tab() -> void:
	card_click_rects.clear()
	var next_level: int = build.equip_level + 1
	var cost: float = pools.equip_upgrade_cost(build.equip_level)
	var maxed: bool = build.equip_level >= pools.equip_max_level()
	_info_label.text = "[装备] 当前 +%d / +%d" % [build.equip_level, pools.equip_max_level()]
	# 清空卡片容器
	for c in _cards_container.get_children():
		c.queue_free()
	# 构造装备升级卡片
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(400, 360)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.2, 0.3)
	style.border_width_left = 3; style.border_width_right = 3
	style.border_width_top = 3; style.border_width_bottom = 3
	style.border_color = Color(0.4, 0.7, 1.0) if not maxed else Color(0.3, 0.3, 0.3)
	panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.offset_left = 16; vbox.offset_right = 384
	vbox.offset_top = 16; vbox.offset_bottom = 344
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	# 当前等级
	var lv_label := Label.new()
	lv_label.text = "当前等级: +%d" % build.equip_level
	lv_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(lv_label)
	if maxed:
		var maxed_label := Label.new()
		maxed_label.text = "已达最高等级！"
		maxed_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.3))
		maxed_label.add_theme_font_size_override("font_size", 22)
		vbox.add_child(maxed_label)
	else:
		# 下级奖励
		var reward: Dictionary = pools.equip_level_reward(next_level)
		var is_milestone: bool = pools.is_milestone_level(next_level)
		var next_label := Label.new()
		var reward_desc: String = pools._effect_to_text(_clean_reward(reward))
		next_label.text = "升级到 +%d:\n  %s%s" % [next_level, reward_desc, "\n  ⚡ 里程碑！抽词条" if is_milestone else ""]
		next_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if not is_milestone else Color(1.0, 0.85, 0.2))
		next_label.add_theme_font_size_override("font_size", 20)
		vbox.add_child(next_label)
		# 成本
		var cost_label := Label.new()
		cost_label.text = "成本: %d 金（你有 %d 金）" % [int(cost), int(build.gold)]
		cost_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3) if build.gold < cost else Color(0.5, 1.0, 0.5))
		cost_label.add_theme_font_size_override("font_size", 20)
		vbox.add_child(cost_label)
		# 升级按钮
		var btn := Button.new()
		btn.text = "升级到 +%d (%d金)" % [next_level, int(cost)]
		btn.disabled = build.gold < cost
		btn.custom_minimum_size = Vector2(300, 60)
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_equip_upgrade)
		vbox.add_child(btn)
	# 已有词条
	if build.equip_affixes.size() > 0:
		var affix_header := Label.new()
		affix_header.text = "\n已有词条 (%d):" % build.equip_affixes.size()
		affix_header.add_theme_font_size_override("font_size", 20)
		vbox.add_child(affix_header)
		for affix in build.equip_affixes:
			var tag: String = "🔴" if affix.get("polarity") == "curse" else "🟢"
			var al := Label.new()
			al.text = "  %s %s" % [tag, affix.get("name", "")]
			al.add_theme_font_size_override("font_size", 18)
			vbox.add_child(al)
	_cards_container.add_child(panel)
	call_deferred("_record_card_rect", panel, 0)
	# 动作按钮
	_clear_actions()
	_add_action("切换 羁绊/装备 (Tab)", "_on_toggle_tab", true)
	_add_action("稍后再选", "_on_confirm", true)


## 过滤 reward dict 中的非 effect 字段
func _clean_reward(reward: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in reward:
		if k != "level" and k != "milestone" and k != "milestone_guaranteed_positive":
			out[k] = reward[k]
	return out


## M3: 装备升级
func _on_equip_upgrade() -> void:
	var result: Dictionary = build.equip_upgrade()
	if result.is_empty():
		return
	# 如果触发了里程碑，显示词条结果
	var milestone: Dictionary = result.get("milestone", {})
	if not milestone.is_empty():
		# 里程碑抽到了词条，留在面板让玩家看结果
		_render()
	else:
		close()   # 普通升级，关闭面板


func _record_card_rect(card: Control, idx: int) -> void:
	if is_instance_valid(card):
		card_click_rects.append({"rect": card.get_global_rect(), "idx": idx})
	# 动作按钮
	_clear_actions()
	if _current_tab == "bond":
		var reroll_lbl := "刷新羁绊 (免费 %d/%d)" % [_rerolls_this_wave, REROLL_CAP]
		_add_action(reroll_lbl, "_on_reroll_bond",
			_rerolls_this_wave < REROLL_CAP)
	_add_action("切换 羁绊/装备 (Tab)", "_on_toggle_tab", true)
	_add_action("稍后再选", "_on_confirm", true)


func _make_card(offer: Dictionary, idx: int) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(280, 360)
	var color := Color(0.2, 0.25, 0.35)
	match offer.get("rarity"):
		"EX": color = Color(0.6, 0.4, 0.1)
		"UR": color = Color(0.5, 0.35, 0.1)
		"SSR": color = Color(0.35, 0.2, 0.45)
		"SR": color = Color(0.15, 0.25, 0.45)
		"N": color = Color(0.2, 0.25, 0.35)
	# #2: 高亮——三层：当前境界需求（金）> 同体系（青）> 无关
	var highlight_level := 0   # 0=普通, 1=同体系, 2=当前境界
	var will_trigger_devour := false
	if _current_tab == "bond":
		var prog: Dictionary = pools.cultivation_progress(build.bond_pool, build.path_realm)
		if not prog.is_empty():
			var pid: String = prog.get("path_id", "")
			var bid: String = offer.get("id", "")
			var needed: Array = prog.get("needed", [])
			if needed.has(bid):
				highlight_level = 2
				# 判断选了这个后是否凑齐 → 触发吞噬
				var sim_pool: Array = build.bond_pool.duplicate()
				sim_pool.append(bid)
				var dev: Variant = pools.find_devourable(sim_pool, build.path_realm)
				will_trigger_devour = dev != null
			elif pools.bond_in_path(bid, pid):
				highlight_level = 1
	var border_col := Color(0.6, 0.65, 0.8)
	var border_w := 2
	if highlight_level == 2:
		border_col = Color(1.0, 0.85, 0.2)   # 金色：当前境界
		border_w = 4
	elif highlight_level == 1:
		border_col = Color(0.3, 0.8, 1.0)   # 青色：同体系
		border_w = 3
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = color
	panel_style.border_width_left = border_w; panel_style.border_width_right = border_w
	panel_style.border_width_top = border_w; panel_style.border_width_bottom = border_w
	panel_style.border_color = border_col
	panel.add_theme_stylebox_override("panel", panel_style)
	var vbox := VBoxContainer.new()
	vbox.offset_left = 12; vbox.offset_right = 268
	vbox.offset_top = 12; vbox.offset_bottom = 348
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	# 境界/体系标记
	if highlight_level == 2:
		var realm_tag := Label.new()
		realm_tag.text = "⚡ 选此触发吞噬升境！" if will_trigger_devour else "⚡ 当前境界"
		realm_tag.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		realm_tag.add_theme_font_size_override("font_size", 18)
		vbox.add_child(realm_tag)
	elif highlight_level == 1:
		var path_tag := Label.new()
		path_tag.text = "◆ 同体系羁绊"
		path_tag.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		path_tag.add_theme_font_size_override("font_size", 18)
		vbox.add_child(path_tag)
	var rarity_label := Label.new()
	rarity_label.text = "[%s]" % offer.get("rarity", "")
	rarity_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	vbox.add_child(rarity_label)
	var name_label := Label.new()
	name_label.text = offer.get("name", "")
	name_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(name_label)
	var kind_label := Label.new()
	kind_label.text = offer.get("kind", "")
	kind_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	vbox.add_child(kind_label)
	# 加成数值（核心：让玩家看到选什么有用）
	var desc: String = offer.get("desc", "")
	if desc == "":
		# 兜底：从 effect 字典现算
		desc = pools._effect_to_text(offer.get("effect", {}))
	if desc != "":
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
		desc_label.add_theme_font_size_override("font_size", 18)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size = Vector2(240, 0)
		vbox.add_child(desc_label)
	var btn := Button.new()
	if idx < 0:
		btn.text = "（待获得）"
		btn.disabled = true
	elif _replace_mode:
		btn.text = "丢弃换新"
	else:
		btn.text = "选择"
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if idx >= 0:
		btn.pressed.connect(_on_pick.bind(idx))
	vbox.add_child(btn)
	return panel


func _clear_actions() -> void:
	for c in _actions.get_children():
		c.queue_free()


func _add_action(text: String, method: String, enabled: bool) -> void:
	var btn := Button.new()
	btn.text = text
	btn.disabled = not enabled
	btn.pressed.connect(Callable(self, method))
	_actions.add_child(btn)


func _realm_text() -> String:
	if build.path_realm.is_empty():
		return "未修炼任何体系"
	var lines: Array = []
	for pid in build.path_realm.keys():
		var idx: int = build.path_realm[pid]
		var maxr: int = pools.path_max_realm(pid)
		var rname := pools.realm_name(pid, mini(idx, maxr - 1)) if idx < maxr else "圆满"
		lines.append("%s: 第%d境(%s) %d/%d" % [pools.path_name(pid), idx + 1, rname, idx, maxr])
	return "\n".join(lines)


# ── 动作 ──
func _on_pick(idx: int) -> void:
	# 替换模式：点击池中卡片 = 丢弃它换 pending_offer
	if _replace_mode:
		_on_replace_pick(idx)
		return
	# 羁绊：open_bond 时已扣钱，这里直接选（免费）
	var offers: Array = _bond_offers
	if idx >= offers.size():
		return
	var offer: Dictionary = offers[idx]
	var ok: bool = build.take_bond_offer(offer)
	if not ok:
		# 池满 → 进替换模式：让玩家选一个扔掉换新的
		_pending_offer = offer
		_replace_mode = true
		_render()
		return
	# 选一次即关闭面板
	close()


func _on_reroll_bond() -> void:
	# 刷新免费（open_bond 时已付 bond_draw_cost）
	if _rerolls_this_wave < REROLL_CAP:
		_rerolls_this_wave += 1
		_refresh_bond_offers()


func _on_toggle_tab() -> void:
	# 两路循环: bond ↔ equipment
	match _current_tab:
		"bond":
			_current_tab = "equipment"
			_render()
		_:
			_current_tab = "bond"
			_refresh_bond_offers()


func _on_confirm() -> void:
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_on_toggle_tab()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
