extends SceneTree
## 把游戏开发部模型的可见三角形烘成一块 ConcavePolygonShape3D。
## 照着 UE「Complex Collision As Simple」的做法：碰撞跟着模型走，不再是 27 个方盒子。
##   _tools/run_probe.sh res://scripts/_bake_gamedev_trimesh.gd
## 产物：assets/collision/gamedev_room_trimesh.res（在 Model 局部坐标里）

const GLB := "res://models/gamedev_room/gamedev_room.glb"
const OUT := "res://assets/collision/gamedev_room_trimesh.res"


func _initialize() -> void:
	var ps := load(GLB) as PackedScene
	if ps == null:
		print("[bake] 载入 GLB 失败")
		quit(1)
		return
	var holder := ps.instantiate()
	var mis := holder.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty() and holder is MeshInstance3D:
		mis = [holder]
	var faces := PackedVector3Array()
	var tris := 0
	for node in mis:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.transform
		var mesh := mi.mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var raw = arr[Mesh.ARRAY_INDEX]
			var idx: PackedInt32Array
			if raw == null or (raw as PackedInt32Array).is_empty():
				idx = PackedInt32Array()
				for i in verts.size():
					idx.append(i)
			else:
				idx = raw
			var n := (idx.size() / 3) * 3
			for i in range(0, n, 3):
				faces.append(xf * verts[idx[i]])
				faces.append(xf * verts[idx[i + 1]])
				faces.append(xf * verts[idx[i + 2]])
			tris += n / 3
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/collision"))
	var err := ResourceSaver.save(shape, OUT)
	print("[bake] tris=", tris, " faces=", faces.size(), " err=", err,
		" bytes=", FileAccess.get_file_as_bytes(OUT).size() if FileAccess.file_exists(OUT) else -1)
	quit(0)
