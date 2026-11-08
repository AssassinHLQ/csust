extends SceneTree
## 查：电竞房模型到底长什么样 —— 孤零零拉出来，四角度拍 + 打印节点树 / 包围盒 / 网格统计。
## 用来判断「房子变滚木」是模型坏了、还是被压扁了、还是相机视角的问题。
##
## 出图：`_arisu_captures/_esports_shape/`
##   01_front   +Z 正前方（门口那一侧）
##   02_side    +X 侧面
##   03_top     俯视
##   04_iso     斜 45°

const SCENE := "res://scenes/esports_room.tscn"
const OUT := "res://_arisu_captures/_esports_shape"

var _fails := 0


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, p: Vector3, t: Vector3, nm: String) -> void:
	cam.global_position = p
	cam.look_at(t, Vector3.UP)
	await _wait(4)
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	img.save_png("%s/%s.png" % [OUT, nm])
	print("[shape] shot %s" % nm)


func _walk(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		var tris := 0
		if mesh is ArrayMesh:
			var am := mesh as ArrayMesh
			for s in am.get_surface_count():
				var arr := am.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				if idx != null:
					tris += (idx as PackedInt32Array).size() / 3
		extra = "  [Mesh tris=%d aabb=%s]" % [tris, str(mi.get_aabb())]
	print("%s%s (%s)%s" % [pad, n.name, n.get_class(), extra])
	for c in n.get_children():
		_walk(c, depth + 1)


func _run() -> void:
	await _wait(2)
	var room: Node3D = load(SCENE).instantiate()
	root.add_child(room)
	await _wait(6)

	print("======== NODE TREE ========")
	_walk(room, 0)

	var total_tris := 0
	var aabb := AABB()
	var first := true
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D)
		var gw: AABB = m.global_transform * m.get_aabb()
		if first:
			aabb = gw
			first = false
		else:
			aabb = aabb.merge(gw)
		if m.mesh is ArrayMesh:
			var am := m.mesh as ArrayMesh
			for s in am.get_surface_count():
				var arr := am.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				if idx != null:
					total_tris += (idx as PackedInt32Array).size() / 3
	print("======== SUMMARY ========")
	print("[shape] total_tris = %d" % total_tris)
	print("[shape] world_aabb = %s" % str(aabb))
	print("[shape] size = %s" % str(aabb.size))
	print("[shape] root_scale = %s" % str(room.scale))
	print("[shape] root_rot = %s" % str(room.rotation_degrees))

	# 相机
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 500.0
	root.add_child(cam)
	var c := aabb.get_center()
	var r := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	await _shot(cam, c + Vector3(0, r * 0.35, r * 1.25), c, "01_front")
	await _shot(cam, c + Vector3(r * 1.25, r * 0.35, 0), c, "02_side")
	await _shot(cam, c + Vector3(0, r * 1.6, 0.01), c, "03_top")
	await _shot(cam, c + Vector3(r * 0.85, r * 0.7, r * 0.85), c, "04_iso")

	print("[shape] DONE fails=%d" % _fails)
	quit(0 if _fails == 0 else 1)
