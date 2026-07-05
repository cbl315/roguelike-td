## hud.gd — 战斗 HUD：波次/核心血条/敌人数/结算 + 技能/羁绊触发按钮
extends Control
class_name HUD

signal skill_picker_requested()
signal bond_picker_requested()

@onready var _wave_label: Label = $WaveLabel
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


func update_wave(wave: int) -> void:
	_wave_label.text = "第 %d / %d 波" % [wave, WaveCurves.main_quest_waves()]


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
