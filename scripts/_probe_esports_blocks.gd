extends SceneTree
## 列电竞房**低模那一档**（`Room` 节点，59 个网格）每块的面数 + 尺寸，
## 用来看「低面 = 墙体」这条规律在这个模型上成不成立。
##
##   godot --path . --headless --script res://scripts/_probe_esports_blocks.gd

const SCENE := "res://scenes/esports_room.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var room := (load(SCENE) as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	for _i in 5:
		await process_frame

	# ⚠️ 只看 `Room` 那一档 —— 三档 LOD 都实例化着，用 find_children 会拿到 177 个
	var target := room.get_node_or_null("Room")
	if target == null:
		print("[blk] !! 没有 Room 节点")
		quit(1)
		return

	var rows: Array = []
	for n in target.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not (mi.mesh is ArrayMesh):
			continue
		var am := mi.mesh as ArrayMesh
		var tris := 0
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
				tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			elif arr.size() > Mesh.ARRAY_VERTEX:
				tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var b: AABB = mi.global_transform * am.get_aabb()
		rows.append({"name": String(mi.name), "tris": tris, "aabb": b, "size": b.size})

	rows.sort_custom(func(a, b): return a["tris"] < b["tris"])
	print("[blk] 低模档网格总数 = %d" % rows.size())

	print("[blk] ══ 面数 < 50 ══")
	for r in rows:
		if r["tris"] >= 50:
			continue
		var b: AABB = r["aabb"]
		var s: Vector3 = r["size"]
		print("[blk]   %-30s 面 %3d  x %6.2f~%6.2f  y %5.2f~%5.2f  z %6.2f~%6.2f  尺寸 %.2f×%.2f×%.2f" % [
			r["name"], r["tris"], b.position.x, b.position.x + s.x,
			b.position.y, b.position.y + s.y, b.position.z, b.position.z + s.z,
			s.x, s.y, s.z])

	print("[blk] ══ 按**体积**排前 12（大件 = 外壳 / 地板 / 天花板 / 大家具）══")
	var by_vol := rows.duplicate()
	by_vol.sort_custom(func(a, b):
		var va: float = a["size"].x * a["size"].y * a["size"].z
		var vb: float = b["size"].x * b["size"].y * b["size"].z
		return va > vb)
	for i in mini(12, by_vol.size()):
		var r: Dictionary = by_vol[i]
		var b: AABB = r["aabb"]
		var s: Vector3 = r["size"]
		print("[blk]   %-30s 面 %6d  体积 %7.1f  x %6.2f~%6.2f  y %5.2f~%5.2f  z %6.2f~%6.2f  尺寸 %.2f×%.2f×%.2f" % [
			r["name"], r["tris"], s.x * s.y * s.z,
			b.position.x, b.position.x + s.x,
			b.position.y, b.position.y + s.y,
			b.position.z, b.position.z + s.z,
			s.x, s.y, s.z])

	print("[blk] 完成")
	quit(0)
