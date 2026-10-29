extends SceneTree
## 把碰撞网格的三角形导出成原始 float32（外面用 Python 量 / 改）。
##   _tools/run_probe.sh res://scripts/_export_collision_faces.gd -- --scene=res://scenes/campus_collision_mesh.scn --out=C:/.../faces.f32

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene_path := "res://scenes/campus_collision_mesh.scn"
	var out_path := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/collision_faces.f32"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_path = a.substr(8)
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	var scene := (load(scene_path) as PackedScene).instantiate()
	var cs: CollisionShape3D = null
	for n in scene.find_children("*", "CollisionShape3D", true, false):
		cs = n as CollisionShape3D
		break
	if cs == null or not (cs.shape is ConcavePolygonShape3D):
		print("[faces] 没有 ConcavePolygonShape3D")
		quit(1)
		return
	var faces: PackedVector3Array = (cs.shape as ConcavePolygonShape3D).get_faces()
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		print("[faces] 打不开 %s" % out_path)
		quit(1)
		return
	f.store_buffer(faces.to_byte_array())
	f.close()
	print("[faces] %d 三角 → %s（%.1f MB）"
		% [faces.size() / 3, out_path, float(faces.size() * 12) / 1048576.0])
	quit(0)
