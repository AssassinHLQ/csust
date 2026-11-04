extends SceneTree
## 量「CPU 两级 LOD」有没有生效：相机在一颗 CPU 的正前方，从 4 m 拉到 40 m，
## 每个距离记一次图元数。
##
##   _tools/run_shot.sh res://scripts/_probe_cpu_distance.gd
##
## 预期：
##   ≤10 m  → 高模 12,386 面/颗
##   10~22 m → 低模 3,001 面/颗
##   >22 m  → 整颗不提交
##
## ⚠️ 这个探针**不改** visibility_range —— 改了就把脚本设好的分档覆盖掉了，
##    上一版就是这么量出「图元反而涨到 96 万」的假数据。

const DISTS := [6.0, 15.0, 20.0, 24.0, 40.0]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(40)

	# 找到一颗 CPU 当靶子
	var cpus: Node = null
	for n in game.find_children("*", "Node3D", true, false):
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).ends_with("ryzen_9950x3d.gd"):
			cpus = n
			break
	if cpus == null:
		print("!! 找不到 CPU 节点")
		quit(1)
		return

	var mesh_n := cpus.find_children("*", "MeshInstance3D", true, false).size()
	print("[cpuLOD] 单颗 CPU 下的网格数 = %d（高模 + 低模 + 光环）" % mesh_n)
	print("[cpuLOD] 高模 %s" % ("在" if cpus.get("_model") != null else "不在"))
	print("[cpuLOD] 低模 %s" % ("在" if cpus.get("_model_lod") != null else "不在"))

	var target: Vector3 = (cpus as Node3D).global_position

	var cam := Camera3D.new()
	cam.fov = 55.0
	root.add_child(cam)
	cam.current = true
	await _wait(4)

	for d in DISTS:
		cam.global_position = target + Vector3(0.0, 1.2, float(d))
		cam.look_at(target, Vector3.UP)
		await _wait(14)
		await RenderingServer.frame_post_draw
		print("[cpuLOD] 距离 %5.1f m  →  图元 %7d   draw call %5d" % [
			d,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])

	quit(0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
