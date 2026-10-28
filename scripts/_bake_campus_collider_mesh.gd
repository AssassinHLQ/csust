extends SceneTree
## 把 collider-forge / 3dgs_collider.exe 输出的 collider .glb 烘成 Godot 碰撞场景：
##   _tools/run_probe.sh res://scripts/_bake_campus_collider_mesh.gd -- --glb=<绝对路径> --force
## 产物：scenes/campus_collision_mesh.scn（二进制场景，里面一个 StaticBody3D +
## ConcavePolygonShape3D，世界坐标，直接挂进 next_level.tscn）。
##
## 为什么要烘：GLB 里的三角形在**运行时**建 ConcavePolygonShape3D 也行，但 63 万面
## 的 BVH 每次进关都要重建；存成 .scn 后由资源加载器直接读，加载快得多。
## 用 GLTFDocument 读，不依赖编辑器的 .import 流程。

const OUT := "res://scenes/campus_collision_mesh.scn"

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var glb := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/campus_collider_forge.glb"
	var force := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="):
			glb = a.substr(6)
		elif a == "--force":
			force = true
	if FileAccess.file_exists(OUT) and not force:
		print("[mesh] %s 已存在；覆盖请加 -- --force" % OUT)
		quit(0)
		return
	if not FileAccess.file_exists(glb):
		print("[mesh] 找不到 GLB：%s" % glb)
		quit(1)
		return

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var t0 := Time.get_ticks_msec()
	var err := doc.append_from_file(glb, state)
	if err != OK:
		print("[mesh] GLTF 解析失败：%d" % err)
		quit(1)
		return
	var scene := doc.generate_scene(state)
	print("[mesh] GLB 解析 %d ms" % (Time.get_ticks_msec() - t0))
	root.add_child(scene)
	await process_frame

	var faces := PackedVector3Array()
	var meshes := 0
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var xf := mi.global_transform
			var mesh := mi.mesh
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var idx = arrays[Mesh.ARRAY_INDEX]
				meshes += 1
				if idx == null or (idx as PackedInt32Array).is_empty():
					for i in range(0, verts.size() - 2, 3):
						faces.append(xf * verts[i])
						faces.append(xf * verts[i + 1])
						faces.append(xf * verts[i + 2])
				else:
					var ix: PackedInt32Array = idx
					var j := 0
					while j + 2 < ix.size():
						faces.append(xf * verts[ix[j]])
						faces.append(xf * verts[ix[j + 1]])
						faces.append(xf * verts[ix[j + 2]])
						j += 3
		for c in n.get_children():
			stack.append(c)
	print("[mesh] 网格 %d 个，三角形 %d" % [meshes, faces.size() / 3])
	if faces.is_empty():
		print("[mesh] 没读到三角形")
		quit(1)
		return

	var aabb := AABB(faces[0], Vector3.ZERO)
	for v in faces:
		aabb = aabb.expand(v)
	print("[mesh] 包围盒 pos %s size %s" % [
		str(aabb.position.snappedf(0.1)), str(aabb.size.snappedf(0.1))])

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "CampusCollisionMesh"
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	cs.owner = body
	var ps := PackedScene.new()
	err = ps.pack(body)
	if err != OK:
		print("[mesh] pack 失败：%d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT)
	if err != OK:
		print("[mesh] save 失败：%d" % err)
		quit(1)
		return
	print("[mesh] %s ← 三角 %d（%.1f MB）" % [OUT, faces.size() / 3,
		float(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(OUT)).size()) / 1048576.0])
	quit(0)
