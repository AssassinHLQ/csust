extends SceneTree
## 只做加载检查：第二关能不能装起来（不开窗口、不渲染）。
##   godot --path . --headless --script res://scripts/_check_level2.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://scenes/next_level.tscn") as PackedScene
	if packed == null:
		print("[check] next_level.tscn 载入失败")
		quit(1)
		return
	var level := packed.instantiate()
	root.add_child(level)
	for _i in 5:
		await process_frame
	var hall := level.get_node_or_null("Hall")
	print("[check] Hall=%s  子节点=%d  CampusDeconstruct=%s" % [
		"OK" if hall != null else "缺失",
		level.get_child_count(),
		"仍在" if level.get_node_or_null("CampusDeconstruct") != null else "已撤掉"])
	if hall != null:
		var interior := hall.get_node_or_null("Interior")
		print("[check] Interior=%s  节点数=%d" % [
			"OK" if interior != null else "缺失",
			interior.get_child_count() if interior != null else 0])
	var bosses := 0
	for c in level.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("trex_yuuka_boss.gd"):
			bosses += 1
			print("[check] %s 位置=%s 身高=%s" % [c.name, str(c.get("position").snappedf(0.1)),
				str(c.get("height"))])
	print("[check] 霸王龙优香 %d 只" % bosses)
	quit(0)
