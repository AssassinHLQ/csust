extends SceneTree
## 量 149 颗 CPU 的**真实开销**：光环占多少、整批占多少。
##
##   _tools/run_shot.sh res://scripts/_probe_cpu_cost.gd
##
## 一次跑出三组数（同一机位，只在运行时切可见性，不改代码）：
##   A 基线        —— 高/低模 + 光环 全开
##   B 去掉光环    —— 只把 TorusMesh 那圈关掉
##   C 整批不画    —— 149 颗全 `visible = false`
## 于是：
##   A − B = **光环**的开销
##   A − C = **CPU 整批**的开销（也就是「不合并」要付的代价）

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(40)

	var cpus: Array = []
	for n in game.find_children("*", "Node3D", true, false):
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).ends_with("ryzen_9950x3d.gd"):
			cpus.append(n)
	if cpus.is_empty():
		print("!! 找不到 CPU")
		quit(1)
		return
	print("[cpucost] 找到 %d 颗 CPU" % cpus.size())

	# 机位：所有 CPU 的几何中心，往斜后方拉 18 m —— 保证视野里有一大片
	var c := Vector3.ZERO
	for n in cpus:
		c += (n as Node3D).global_position
	c /= float(cpus.size())
	print("[cpucost] CPU 质心 %s" % str(c.snappedf(0.1)))

	var cam := Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.global_position = c + Vector3(0.0, 5.0, 18.0)
	cam.look_at(c, Vector3.UP)
	cam.current = true
	await _wait(10)

	# 收集光环（TorusMesh 的 MeshInstance3D）
	var glows: Array = []
	for n in cpus:
		for mi in (n as Node3D).find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh is TorusMesh:
				glows.append(mi)
	print("[cpucost] 光环网格 %d 个" % glows.size())

	var a := await _measure("A 基线（全开）")
	for g in glows:
		(g as MeshInstance3D).visible = false
	var b := await _measure("B 去掉光环")
	for n in cpus:
		(n as Node3D).visible = false
	var cc := await _measure("C 整批不画")

	print("\n[cpucost] ===== 结论 =====")
	print("[cpucost] 光环     ：图元 %d  draw call %d" % [a[0] - b[0], a[1] - b[1]])
	print("[cpucost] CPU 整批 ：图元 %d  draw call %d" % [a[0] - cc[0], a[1] - cc[1]])

	quit(0)


func _measure(label: String) -> Array:
	await _wait(14)
	await RenderingServer.frame_post_draw
	var p := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var d := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("[cpucost] %-16s 图元 %7d   draw call %5d" % [label, p, d])
	return [p, d]


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
