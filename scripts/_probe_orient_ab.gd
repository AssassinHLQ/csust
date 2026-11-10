extends SceneTree
## 用**编辑器视角**（带坐标轴、线框）拍电竞房的两个朝向，让你直接指出哪个对。
##
## 使用者 2026-11-10：「大的有台阶，是地板，天花板小」
## 本喵之前一直把「上面那块板」当屋顶，看错了。这次拍带线框的对照图。
##
##   godot --script res://scripts/_probe_orient_ab.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const ROOM := "res://scenes/esports_room.tscn"
const OUT := "res://_arisu_captures/_orient_ab"


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, nm: String) -> void:
	await _wait(5)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, nm])
	print("[ab] 图 %s" % nm)


func _run() -> void:
	await OffWin.apply(self, Vector2i(960, 540))
	await _wait(2)

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 400.0
	root.add_child(cam)
	cam.current = true

	# 两个候选：A = Y翻(-1)  B = Y正(+1)
	var cases := {
		"A_Y翻(y=-1)": Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)),
		"B_Y正(y=+1)": Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)),
	}
	for label in cases.keys():
		var b: Basis = cases[label]
		var room: Node3D = load(ROOM).instantiate()
		root.add_child(room)
		room.transform = Transform3D(b, Vector3(53.26548, 0.01, 13.256798))
		await _wait(10)

		# 量：网格的 y 范围（判断哪块板在上、哪块在下）
		var low := room.get_node_or_null("Room") as Node3D
		var target: Node3D = low if low != null else room
		var box := AABB()
		var first := true
		for n in target.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
		print("[ab] %-14s 包围盒 y[%.2f, %.2f]  size=(%.2f,%.2f,%.2f)  Y轴y分量=%.1f"
			% [label, box.position.y, box.position.y + box.size.y,
			   box.size.x, box.size.y, box.size.z, b.y.y])

		var c := box.get_center()
		cam.global_position = Vector3(c.x - 14.0, c.y + 4.0, c.z - 20.0)
		cam.look_at(Vector3(c.x, c.y, c.z), Vector3.UP)
		await _shot(cam, label)

		# 用「地板」的判据再量一次：水平面积最大的那块薄板在哪
		var best_area := 0.0
		var best_y := 0.0
		var best_name := ""
		for n in target.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			var area := a.size.x * a.size.z
			if area > best_area and a.size.y < 2.5:
				best_area = area
				best_y = a.position.y
				best_name = mi.name
		print("[ab]   最大水平薄板：%s  面积%.0f m²  y=%.2f（相对包围盒底 %.2f）"
			% [best_name, best_area, best_y, best_y - box.position.y])

		room.queue_free()
		await _wait(5)
	quit(0)
