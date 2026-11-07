extends SceneTree
## 量：新电竞房 GLB 里**哪个方向是「上」**、门在哪一头。
##   _tools/run_probe.sh res://scripts/_probe_esports_axes.gd -- --splat=off --story=off
##
## 依据：房间是个 10.4 × 16.84 × 3.6 的长方体，两头短墙上有门洞。
## 所以「上」= 尺寸最小的那一维（3.6）；「门」= 长边方向上、**竖直面被掏空**的那一头。
## 做法：把它当成方盒子，沿 6 个方向各量「从中心打到盒子表面的距离」和
## 「该方向上有没有实体网格」—— 门洞那一头的水平射线会穿过去很远。

const GLB := "res://models/esports_room/esports_room.glb"

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	var room := (load(GLB) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	await _wait(10)

	var meshes := room.find_children("*", "MeshInstance3D", true, false)
	var box := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	print("[axes] 世界包围盒 pos=%s size=%s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])
	var c := box.get_center()
	var s := box.size

	# ① 尺寸排序：最小那维 = 房间高度（除非空心）
	var dims := [["x", s.x], ["y", s.y], ["z", s.z]]
	dims.sort_custom(func(a, b): return a[1] < b[1])
	print("[axes] 三围从小到大：%s（最小那维 = 房间高度 3.6）" % str(dims))
	var up: String = "y"
	if absf(s.y - 3.6) > 0.3:
		up = String(dims[0][0])
		print("[axes] ⚠️ Y 不是最小维 → 真正的「上」是 %s 轴" % up)
	else:
		print("[axes] Y 就是「上」")

	# ② 长方体六个面的中心点，沿法线打射线，看打出去多远（从外面往里打）
	var space := root.world_3d.direct_space_state
	var dirs := {
		"+X": Vector3(1, 0, 0), "-X": Vector3(-1, 0, 0),
		"+Y": Vector3(0, 1, 0), "-Y": Vector3(0, -1, 0),
		"+Z": Vector3(0, 0, 1), "-Z": Vector3(0, 0, -1),
	}
	for nm in dirs.keys():
		var d: Vector3 = dirs[nm]
		var half := Vector3(s.x * 0.5, s.y * 0.5, s.z * 0.5)
		var extent := absf(d.x) * half.x + absf(d.y) * half.y + absf(d.z) * half.z
		var start: Vector3 = c + d * (extent + 6.0)
		var q := PhysicsRayQueryParameters3D.create(start, c, 0xFFFFFFFF)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			print("[axes] %s 方向：射线没打到东西（这个方向可能是门洞开口）" % nm)
		else:
			var dist: float = start.distance_to(hit["position"])
			print("[axes] %s 方向：打到实体，距墙面 %.2f m" % [nm, dist])

	# ③ 直接看网格顶点在哪个轴向上「薄」：取最大那件的地板件
	print("[axes] ── 关键物体的世界 AABB（判断墙/地板/天花板）──")
	var rows := []
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		rows.append([String(mi.name), a.position, a.size])
	rows.sort_custom(func(a, b): return (b[2] as Vector3).length() > (a[2] as Vector3).length())
	for i in mini(8, rows.size()):
		var r: Array = rows[i]
		var nm2 := String(r[0])
		nm2 = nm2.substr(0, 34)
		var p2 := (r[1] as Vector3).snappedf(0.01)
		var s2 := (r[2] as Vector3).snappedf(0.01)
		print("[axes]   %-34s pos=%s size=%s" % [nm2, str(p2), str(s2)])
	quit(0)
