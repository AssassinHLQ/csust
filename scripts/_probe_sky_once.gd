extends SceneTree
## 只验证：进关卡时随机天空有没有选上、贴图能不能加载。
##   _tools/run_probe.sh res://scripts/_probe_sky_once.gd [-- --sky=day]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 5:
		await process_frame
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sky := we.environment.sky if we != null else null
	print("[sky] background=%d sky=%s" % [
		int(we.environment.background_mode) if we != null else -1,
		"有" if sky != null else "无"])
	quit(0)
