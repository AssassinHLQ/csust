extends SceneTree
## 验「10×10 分块 + 3×3 窗口」：进第二关、把玩家挪到几个位置，看窗口换没换、显存多少。
##
##   _tools/run_shot.sh res://scripts/_probe_campus_window.gd
##
## 判据：
##   1. 启动后窗口拼出来（`_window_names` 非空、bin 大小合理）
##   2. 玩家换个区域 → 窗口内容变了、bin 重写
##   3. 显存远低于全量那份（全量约 2.9 GiB 口径，进程内实测约 4975 MiB）

const SPOTS := [
	{"n": "出生点/广场", "p": Vector3(0.0, 1.0, -80.0)},
	{"n": "校园东侧", "p": Vector3(60.0, 1.0, -150.0)},
	{"n": "校园深处", "p": Vector3(-40.0, 1.0, -200.0)},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await _wait(30)

	var ggs := level.get_node_or_null("CampusGGS")
	if ggs == null:
		# 有的版本是延迟挂的
		await _wait(120)
		ggs = level.get_node_or_null("CampusGGS")
	if ggs == null:
		print("!! 没找到 CampusGGS")
		quit(1)
		return
	print("[win] CampusGGS 就位")

	var p := level.get_node_or_null("Player") as Node3D
	if p == null:
		print("!! 没找到 Player")
		quit(1)
		return

	for s in SPOTS:
		var spot: Dictionary = s
		p.global_position = spot["p"]
		await _wait(40)          # 给窗口评估 + 重拼 + 重传时间
		var names: PackedStringArray = ggs.get("_window_names")
		var binp := String(ggs.get("_bin_path"))
		var sz := 0
		if FileAccess.file_exists(binp):
			sz = int(FileAccess.get_file_as_bytes(binp).size())
		print("[win] %-10s → 窗口 %d 块 | bin %s | %.1f MB | VRAM %.0f MiB" % [
			String(spot["n"]), names.size(),
			binp.get_file(), float(sz) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
		if names.size() > 0:
			var head: Array = []
			for i in mini(9, names.size()):
				head.append(names[i])
			print("[win]            %s" % str(head))

	quit(0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
