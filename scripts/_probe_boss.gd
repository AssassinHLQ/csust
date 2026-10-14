extends SceneTree
## 探针：看 Godot 导入 FBX 之后到底拿到了什么 —— 节点树 / 骨骼 / 动画 / 尺寸 / 材质。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_boss.gd

const SCENE := "res://models/boss/优香霸王龙.fbx"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ResourceLoader.exists(SCENE):
		push_error("找不到 %s（先跑一次 --import）" % SCENE)
		quit(1)
		return
	var packed: PackedScene = load(SCENE)
	if packed == null:
		push_error("加载失败：%s" % SCENE)
		quit(1)
		return

	var node: Node = packed.instantiate()
	root.add_child(node)
	await process_frame
	await process_frame

	print("================ 1. 节点树（深度 ≤ 4）================")
	_print_tree(node, 0, 4)

	print("\n================ 2. 网格与材质 ================")
	var meshes := _all(node, "MeshInstance3D")
	var tris := 0
	var surfaces := 0
	var mats := {}
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		surfaces += mi.mesh.get_surface_count()
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat:
				mats[mat.resource_name if mat.resource_name != "" else str(mat)] = true
		if mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			for s in am.get_surface_count():
				var arr := am.surface_get_arrays(s)
				if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
					tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("  MeshInstance3D = %d   表面 = %d   三角形 ≈ %d" % [meshes.size(), surfaces, tris])
	print("  材质（去重）= %d" % mats.size())
	for k in mats.keys():
		print("      %s" % k)

	print("\n================ 3. 骨骼 / 蒙皮 ================")
	var skels := _all(node, "Skeleton3D")
	if skels.is_empty():
		print("  ❌ 没有 Skeleton3D —— 没有骨骼")
	else:
		var skel := skels[0] as Skeleton3D
		print("  Skeleton3D 数 = %d   骨骼数 = %d" % [skels.size(), skel.get_bone_count()])
		print("  骨骼名（前 25）：")
		var names: Array[String] = []
		for i in mini(skel.get_bone_count(), 25):
			names.append(skel.get_bone_name(i))
		print("      %s" % ", ".join(names))
		var with_skin := 0
		for m in meshes:
			if (m as MeshInstance3D).skin != null:
				with_skin += 1
		print("  带 skin 的网格 = %d / %d" % [with_skin, meshes.size()])

	print("\n================ 4. 动画 ================")
	var aps := _all(node, "AnimationPlayer")
	if aps.is_empty():
		print("  ❌ 没有 AnimationPlayer —— 没有动画")
	else:
		for a in aps:
			var ap := a as AnimationPlayer
			var list := ap.get_animation_list()
			print("  AnimationPlayer「%s」动作数 = %d" % [ap.name, list.size()])
			for n in list:
				var anim := ap.get_animation(n)
				var tracks := anim.get_track_count()
				print("      %-24s 时长 %.3f s   轨道 %d" % [n, anim.length, tracks])
				if tracks > 0:
					for t in mini(tracks, 2):
						print("          track%d: %s (type=%d)" % [
							t, anim.track_get_path(t), anim.track_get_type(t)])

	print("\n================ 5. 尺寸（判断要不要缩放）================")
	var aabb := _visual_aabb(node)
	print("  视觉包围盒 size = %s" % str(aabb.size.snappedf(0.001)))
	print("  视觉包围盒 范围 = y %.3f … %.3f" % [aabb.position.y, aabb.position.y + aabb.size.y])
	print("  参考：Arisu 约 1.7 m 高；2 m 高的靶子柱直径 0.55")
	var height := aabb.size.y
	if height > 0.0:
		print("  若想做成 6 m 高的 Boss，需要 scale ≈ %.3f" % (6.0 / height))

	quit(0)


func _print_tree(n: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	var extra := ""
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		extra = "  mesh(%d surface)" % (n as MeshInstance3D).mesh.get_surface_count()
	elif n is Skeleton3D:
		extra = "  bones=%d" % (n as Skeleton3D).get_bone_count()
	elif n is AnimationPlayer:
		extra = "  anims=%d" % (n as AnimationPlayer).get_animation_list().size()
	print("  %s%s (%s)%s" % ["    ".repeat(depth), n.name, n.get_class(), extra])
	for c in n.get_children():
		_print_tree(c, depth + 1, max_depth)


func _all(node: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(cls):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _visual_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in _all(node, "VisualInstance3D"):
		var vi := m as VisualInstance3D
		var box := vi.get_aabb()
		if box.size.length() <= 0.0001:
			continue
		var b := vi.global_transform * box
		out = b if first else out.merge(b)
		first = false
	return out
