extends SceneTree
## 查：两种 transform 下，门朝向分别是世界哪个方向。
##
##   godot --headless --script res://scripts/_probe_orientation.gd -- --no-capture

const ROOM := "res://scenes/esports_room.tscn"

## 两种候选矩阵（列主序，Godot Transform3D 的参数顺序）
const CASES := {
	"A 当前(本喵提交的)": [-1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0],
	"B 原始(你之前摆的)": [-1.1924881e-08, -1.0425061e-15, -1.0,
						8.742278e-08, -1.0, 0.0,
						-1.0, -8.742278e-08, 1.1924881e-08],
}


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await _wait(2)

	for label in CASES.keys():
		var m: Array = CASES[label]
		var basis := Basis(Vector3(m[0], m[1], m[2]),
						   Vector3(m[3], m[4], m[5]),
						   Vector3(m[6], m[7], m[8]))
		var b := basis.orthonormalized()
		var x := b.x
		var y := b.y
		var z := b.z
		print("[ori] ===== %s =====" % label)
		print("[ori]   X 轴 = (%.3f, %.3f, %.3f)" % [x.x, x.y, x.z])
		print("[ori]   Y 轴 = (%.3f, %.3f, %.3f)  ← y分量 %.3f %s"
			% [y.x, y.y, y.z, y.y, "（朝上✓）" if y.y > 0.5 else "（朝下✗ 模型倒立）"])
		print("[ori]   Z 轴 = (%.3f, %.3f, %.3f)  ← 门朝向（本地+Z）" % [z.x, z.y, z.z])
		# 单位性检查
		print("[ori]   行列式 = %.3f %s" % [b.determinant(),
			"（正常）" if b.determinant() > 0 else "（**镜像/翻转**）"])

	# 再实测：把场景按两种矩阵各摆一次，量房子包围盒
	for label in CASES.keys():
		var m: Array = CASES[label]
		var room: Node3D = load(ROOM).instantiate()
		root.add_child(room)
		room.transform = Transform3D(
			Basis(Vector3(m[0], m[1], m[2]), Vector3(m[3], m[4], m[5]), Vector3(m[6], m[7], m[8])),
			Vector3(53.26548, 0.01, 13.256798))
		await _wait(6)
		var box := AABB()
		var first := true
		for n in room.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
		print("[ori] %s → 包围盒 pos=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f)  中心y=%.2f"
			% [label, box.position.x, box.position.y, box.position.z,
			   box.size.x, box.size.y, box.size.z, box.get_center().y])
		room.queue_free()
		await _wait(3)
	quit(0)
