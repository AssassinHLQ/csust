extends SceneTree
## 快速加载检查：next_level.tscn 能不能起来、节点数/脚本有没有报错。
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame
	print("[level] 节点 %d 个；靶子 %d；目标监测 %s"
		% [level.get_tree().get_node_count(), 0, str(level.get_node("Goal").monitoring)])
	quit(0)
