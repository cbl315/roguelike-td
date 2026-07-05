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
	if not build.path_realm.is_empty():
		var main_path: String = build.path_realm.keys()[0]
		prefer = pools.current_realm_bonds(main_path, build.path_realm[main_path])
	_bond_offers = pools.draw_bond_offers(3, prefer, build.bond_pool)
	_render()


func _render() -> void:
	if build:
		_gold_label.text = "金币: %d" % int(build.gold)
		_build_label.text = build.summary()
		var stats := build.assemble_stats()
		_dps_label.text = "DPS: %.0f" % stats.expected_dps(20.0)
		_realm_label.text = _realm_text()
	var offers: Array = _skill_offers if _current_tab == "skill" else _bond_offers
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
			_cards_container.add_child(_make_card(offer, i))
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
	_add_action("✕ 关闭", "_on_confirm", true)


func _make_card(offer: Dictionary, idx: int) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(280, 360)
	var color := Color(0.2, 0.25, 0.35)
	match offer.get("rarity"):
		"legendary": color = Color(0.5, 0.35, 0.1)
		"epic": color = Color(0.35, 0.2, 0.45)
		"rare": color = Color(0.15, 0.25, 0.45)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = color
	panel_style.border_width_left = 2; panel_style.border_width_right = 2
	panel_style.border_width_top = 2; panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.6, 0.65, 0.8)
	panel.add_theme_stylebox_override("panel", panel_style)
	var vbox := VBoxContainer.new()
	vbox.offset_left = 12; vbox.offset_right = 268
	vbox.offset_top = 12; vbox.offset_bottom = 348
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
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
	_current_tab = "bond" if _current_tab == "skill" else "skill"
	if _current_tab == "skill":
		_refresh_skill_offers()
	else:
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
