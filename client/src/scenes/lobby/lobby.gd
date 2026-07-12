## lobby.gd — 按需触发的选择器面板（M2 重构：不自动弹，玩家点 HUD 按钮打开）
## 技能选择器（需免费机会）/ 羁绊选择器（需 build.bond_draw_cost() 金，递增 30→60）。
extends Control
class_name Lobby

signal confirmed()

const REROLL_BASE := 20.0
const REROLL_INC := 5.0
const REROLL_CAP := 3

var build: BuildState
var pools: RoguePools

var _skill_offers: Array = []
var _bond_offers: Array = []
var _skill_upgrades_left: int = 0
var _banked: int = 0
var _rerolls_this_wave: int = 0
var _current_tab: String = "skill"   # "skill" or "bond"

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


func update_banked(n: int) -> void:
	_banked = n


## HUD 按钮"技能"触发：需有免费机会
func open_skill(banked: int) -> void:
	_banked = banked
	if _banked <= 0:
		return
	_current_tab = "skill"
	_skill_upgrades_left = _banked
	_rerolls_this_wave = 0
	_refresh_skill_offers()
	visible = true


## HUD 按钮"羁绊"触发：需 build.bond_draw_cost() 金
func open_bond() -> void:
	if build == null or build.gold < build.bond_draw_cost():
		return
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
	visible = false
	get_tree().paused = false
	confirmed.emit()


func _refresh_skill_offers() -> void:
	_skill_offers = pools.draw_skill_offers(build.owned_skills)
	_render()


func _refresh_bond_offers() -> void:
	# 优先抽主修炼路径当前境界的羁绊（50% 概率），其余全池
	var prefer: Array = []
	var prog: Dictionary = pools.cultivation_progress(build.bond_pool, build.path_realm)
	if not prog.is_empty():
		prefer = prog.get("needed", [])
	# 排除：已拥有 + 已吞噬 + 已修满路径的全部羁绊
	var excluded: Array = build.bond_pool.duplicate()
	for b in build.devoured_bonds:
		if not excluded.has(b):
			excluded.append(b)
	# 已修满的路径：整个路径的羁绊都不再出现
	for pid in build.path_realm.keys():
		if pools.path_max_realm(pid) > 0 and build.path_realm[pid] >= pools.path_max_realm(pid) - 1:
			for b in pools.all_bonds_in_path(pid):
				if not excluded.has(b):
					excluded.append(b)
	_bond_offers = pools.draw_bond_offers(3, prefer, excluded)
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
	var offers: Array = _skill_offers if _current_tab == "skill" else _bond_offers
	if _current_tab == "equipment":
		_render_equipment_tab()
		return
	if _current_tab == "bond":
		var prog: Dictionary = pools.cultivation_progress(build.bond_pool, build.path_realm)
		if not prog.is_empty():
			_info_label.text = "【%s·%s】境界进度: %d/%d  缺: %s" % [
				prog.get("path_name", ""), prog.get("realm_name", ""),
				prog.get("owned_count", 0), prog.get("total_count", 0),
				", ".join(prog.get("missing_names", []))
			]
		else:
			_info_label.text = "[羁绊] 未修炼任何体系（凑齐同体系羁绊自动吞噬升境）"
	else:
		_info_label.text = "[%s] 剩余机会:%d  (Tab切换)" % [_current_tab, _skill_upgrades_left]
	# 清空卡片
	for c in _cards_container.get_children():
		c.queue_free()
	# 渲染卡片：技能模式只在有剩余机会时显示卡片；羁绊模式在有钱抽时显示
	var show_cards := true
	if _current_tab == "skill" and _skill_upgrades_left <= 0:
		var empty := Label.new()
		empty.text = "技能机会已用完（每波清完自动+1）\n可切到羁绊页，或关闭继续战斗"
		empty.horizontal_alignment = 1   # CENTER
		_cards_container.add_child(empty)
		show_cards = false
	elif _current_tab == "bond" and build.gold < build.bond_draw_cost() and offers.is_empty():
		var empty := Label.new()
		empty.text = "金币不足 %d 抽羁绊\n关闭继续战斗攒钱" % int(build.bond_draw_cost())
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
	_add_action("切换 技能/羁绊/装备 (Tab)", "_on_toggle_tab", true)
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
	if _current_tab == "skill":
		_add_action("刷新技能 (扣%d金)" % _reroll_cost(), "_on_reroll",
			_skill_upgrades_left > 0 and _rerolls_this_wave < REROLL_CAP and build.gold >= _reroll_cost())
		_add_action("跳过得 %d金" % 20, "_on_skip", _skill_upgrades_left > 0)
	else:
		_add_action("刷新羁绊 (扣%d金)" % _reroll_cost(), "_on_reroll_bond",
			_rerolls_this_wave < REROLL_CAP and build.gold >= _reroll_cost())
	_add_action("切换 技能/羁绊 (Tab)", "_on_toggle_tab", true)
	_add_action("稍后再选", "_on_confirm", true)


func _make_card(offer: Dictionary, idx: int) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(280, 360)
	var color := Color(0.2, 0.25, 0.35)
	match offer.get("rarity"):
		"legendary": color = Color(0.5, 0.35, 0.1)
		"epic": color = Color(0.35, 0.2, 0.45)
		"rare": color = Color(0.15, 0.25, 0.45)
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
	btn.text = "选择"
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
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


func _reroll_cost() -> float:
	return REROLL_BASE + REROLL_INC * _rerolls_this_wave


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
	var offers: Array = _skill_offers if _current_tab == "skill" else _bond_offers
	if idx >= offers.size():
		return
	var offer: Dictionary = offers[idx]
	if _current_tab == "skill":
		if _skill_upgrades_left <= 0:
			return
		build.take_skill_offer(offer)
		_skill_upgrades_left -= 1
		_banked = _skill_upgrades_left   # 同步回 game_manager 的 banked
		# 选一次即关闭面板（点击一次选一次）。下次想选再点 HUD 按钮。
		close()
	else:
		# 羁绊：扣 build.bond_draw_cost() 金，不够则不选
		if not build.spend(build.bond_draw_cost()):
			return
		build.take_bond_offer(offer)
		# 选一次即关闭面板
		close()


func _on_reroll() -> void:
	if build.spend(_reroll_cost()):
		_rerolls_this_wave += 1
		_refresh_skill_offers()


func _on_reroll_bond() -> void:
	if build.spend(_reroll_cost()):
		_rerolls_this_wave += 1
		_refresh_bond_offers()


func _on_skip() -> void:
	if _skill_upgrades_left > 0:
		build.add_gold(20.0)
		_skill_upgrades_left -= 1
		_banked = _skill_upgrades_left
		close()   # 跳过也算一次操作，关闭面板


func _on_toggle_tab() -> void:
	# 三路循环: skill → bond → equipment → skill
	match _current_tab:
		"skill":
			_current_tab = "bond"
			_refresh_bond_offers()
		"bond":
			_current_tab = "equipment"
			_render()
		_:
			_current_tab = "skill"
			_refresh_skill_offers()


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
