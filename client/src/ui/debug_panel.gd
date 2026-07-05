## debug_panel.gd — M0 调试面板：显示已加载的数据条数 + 版本
## 验证数据从 JSON 正确加载（数字对得上 balance/data）。
extends Control
class_name DebugPanel

var _data: Dictionary = {}

@onready var _label: RichTextLabel = $RichTextLabel


func _ready() -> void:
	_load_and_show()


func _load_and_show() -> void:
	_data = DataLoader.load_all()
	var s := "[b]Roguelike-TD · M0 就绪[/b]\n\n"
	s += "[color=#9ece6a]数据加载验证（源: balance/data/*.yaml → JSON）[/color]\n\n"
	s += "技能: [color=#7aa2f7]%d[/color] 个\n" % _data.get("skills", []).size()
	s += "词条: [color=#7aa2f7]%d[/color] 个\n" % _data.get("affixes", []).size()
	s += "羁绊: [color=#7aa2f7]%d[/color] 个\n" % _data.get("bonds", []).size()
	s += "修炼路径: [color=#7aa2f7]%d[/color] 条\n" % _data.get("paths", []).size()
	s += "联动规则: [color=#7aa2f7]%d[/color] 条\n" % _data.get("synergies", []).size()
	s += "\n原始数据（waves/economy/equipment/boss_debuffs/consumables）: "
	s += "[color=#9ece6a]已加载[/color]\n" if _data.has("waves") else "[color=#f7768e]缺失[/color]\n"
	s += "\n[color=#9aa5ce]按 M1 进入战斗（待实装）[/color]"
	_label.text = s


func reload() -> void:
	_load_and_show()
