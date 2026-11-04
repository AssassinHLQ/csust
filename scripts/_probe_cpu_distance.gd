extends SceneTree
## A/B：609 屋顶 149 颗 9950X3D 的可见距离 **22 m vs 10 m**，量图元 / draw call。
##
##   _tools/run_shot.sh res://scripts/_probe_cpu_distance.gd
##
## 运行时直接改 `visibility_range_end`，不用重新编译，两种距离同一机位交替测。
## 机位放在离屋顶 15~20 m 的地方 —— 那一段正是 22 m 能画、10 m 画不到的距离带。

const EYE := Vector3(0.0, 8.0, 19.0)
const LOOK := Vector3(0.0, 4.0, 0.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(40)

	var cpus := game.get_node_or_null("Room609/RoomCpus")
	if cpus == null:
		# 名字可能不同，退一步按脚本找
		for n in game.find_children("*", "Node3D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("ryzen_9950x3d.gd"):
				cpus = n
				break
	if cpus == null:
		print("!! 找不到 CPU 节点")
		quit(1)
		return

	var meshes := cpus.find_children("*", "MeshInstance3D", true, false)
	print("[cpudist] CPU 网格 %d 个" % meshes.size())

	var cam := Camera3D.new()
	cam.fov = 55.0
	root.add_child(cam)
	cam.global_position = EYE
	cam.look_at(LOOK, Vector3.UP)
	cam.current = true
	await _wait(4)

	for d in [22.0, 10.0, 22.0, 10.0]:
		for n in meshes:
			(n as MeshInstance3D).visibility_range_end = d
		await _wait(12)
		await RenderingServer.frame_post_draw
		print("[cpudist] range=%5.1f m  →  图元 %7d   draw call %5d" % [
			d,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])

	quit(0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
