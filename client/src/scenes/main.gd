## main.gd — M0 主场景：显示项目就绪 + debug 面板
extends Node2D


func _ready() -> void:
	# 数据加载校验（EventBus 已 autoload）
	if OS.is_debug_build():
		print("[main] Roguelike-TD 启动 | EventBus: ", EventBus != null)
