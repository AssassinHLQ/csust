extends SceneTree
## 查：电竞房三档 LOD 模型（low/mid/high）的**内部朝向是否一致**。
##
## 使用者 2026-11-10：「远看是对的，走进就变错了，又反了」
## 表现是「走近之后模型翻了一面」——最可能是三档 glb 的轴向/朝向不同。
##
##   godot --headless --script res://scripts/_probe_lod_orient.gd -- --no-capture

const LOW := "res://models/esports_room/esports_room.glb"
const MID := "res://models/esports_room/esports_room_mid.glb"
const HIGH := "res://models/esports_room/esports_room_high.glb"


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await _wait(2)
	print("[lo] ============ 三档 LOD 轴向对比 ============")

	for item in [[LOW, "low "], [MID, "mid "], [HIGH, "high"]]:
		var path: String = item[0]
		var tag: String = item[1]
		if not ResourceLoader.exists(path):
			print("[lo] %s  不存在" % tag)
			continue
		var ps: PackedScene = load(path)
		if ps == null:
			print("[lo] %s  load 失败" % tag)
			continue
		var inst: Node3D = ps.instantiate()
		root.add_child(inst)
		await _wait(5)

		# 整个实例的包围盒（本地坐标，不带任何外部 transform）
		var box := AABB()
		var first := true
		var tris := 0
		for n in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
			var mesh := mi.mesh
			if mesh is ArrayMesh:
				var am := mesh as ArrayMesh
				for s in am.get_surface_count():
					var arr := am.surface_get_arrays(s)
					var idx = arr[Mesh.ARRAY_INDEX]
					if idx != null:
						tris += (idx as PackedInt32Array).size() / 3

		print("[lo] %s  size=(%.2f, %.2f, %.2f)  pos=(%.2f, %.2f, %.2f)  三角面 %d"
			% [tag, box.size.x, box.size.y, box.size.z,
			   box.position.x, box.position.y, box.position.z, tris])

		# 关键：找出「门」在哪一侧。门 = 某面墙上 y 0.3~2.4 高度有凹陷。
		# 用更稳的判据：看 +X / -X / +Z / -Z 四个方向，哪一侧的「竖直墙面面积」最小
		var wall := {"+X": 0.0, "-X": 0.0, "+Z": 0.0, "-Z": 0.0}
		var lo := box.position
		var hi := box.position + box.size
		var eps := 0.35
		for n in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			var c := a.get_center()
			var y_ok := c.y > lo.y + 0.3 and c.y < lo.y + 2.4
			if not y_ok:
				continue
			# 靠近某个面 & 该面很薄 = 贴在那面墙上的东西
			if absf(c.x - hi.x) < eps and a.size.x < eps * 2:
				wall["+X"] += 1
			if absf(c.x - lo.x) < eps and a.size.x < eps * 2:
				wall["-X"] += 1
			if absf(c.z - hi.z) < eps and a.size.z < eps * 2:
				wall["+Z"] += 1
			if absf(c.z - lo.z) < eps and a.size.z < eps * 2:
				wall["-Z"] += 1
		print("[lo]    四面墙贴附件计数：+X=%d -X=%d +Z=%d -Z=%d （门那侧通常最少）"
			% [wall["+X"], wall["-X"], wall["+Z"], wall["-Z"]])

		inst.queue_free()
		await _wait(4)
	quit(0)
