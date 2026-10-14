extends SceneTree
## 探针：「飞猪优香」FBX 经 Godot(ufbx) 导入后到底拿到了什么。
## 重点回答三件事：
##   1. 有没有骨骼 / 动画（Python 侧扫二进制说没有 Deformer，这里复核）
##   2. 材质名 → Godot 有没有自动绑上 uv/ 下的贴图（没绑就得像霸王龙那样手工绑）
##   3. 真实尺寸多大（决定要不要归一化）
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_boss_pig.gd

const SCENE := "res://models/boss_pig/猪猪优香.fbx"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ResourceLoader.exists(SCENE):
		push_error("找不到 %s（先跑一次 --import）" % SCENE)
		quit(1)
		return
	var packed: PackedScene = load(SCENE)
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
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		surfaces += mi.mesh.get_surface_count()
		if mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			for s in am.get_surface_count():
				var arr := am.surface_get_arrays(s)
				if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
					tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("  MeshInstance3D = %d   表面 = %d   三角形 ≈ %d" % [meshes.size(), surfaces, tris])
	print("  逐表面明细（★ = 已自动绑上贴图）：")
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		print("    「%s」 skin=%s" % [mi.name, "有" if mi.skin != null else "无"])
		var am2 := mi.mesh as ArrayMesh
		for s in am2.get_surface_count():
			var mat := am2.surface_get_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				var tex := "（无贴图）"
				if sm.albedo_texture != null:
					tex = "★ " + sm.albedo_texture.resource_path.get_file()
				print("        surface %d  材质名「%s」  %s  base_color=%s" % [
					s, sm.resource_name, tex, str(sm.albedo_color)])
			elif mat != null:
				print("        surface %d  材质「%s」 class=%s（不是 StandardMaterial3D）" % [
					s, mat.resource_name, mat.get_class()])
			else:
				print("        surface %d  没有材质" % s)

	print("\n================ 2b. 逐网格位置（判本体朝向用）================")
	print("  猪鼻子一定在最前面：比较「立方体_001(鼻子)」与「立方体(身体)」的 Z 中心即可。")
	for m in meshes:
		var mi2 := m as MeshInstance3D
		if mi2.mesh == null:
			continue
		var b2 := mi2.global_transform * mi2.get_aabb()
		print("    「%s」中心 %s  size %s" % [
			mi2.name, str(b2.get_center().snappedf(0.01)), str(b2.size.snappedf(0.01))])

	print("\n================ 3. 骨骼 / 蒙皮 ================")
	var skels := _all(node, "Skeleton3D")
	if skels.is_empty():
		print("  ❌ 没有 Skeleton3D —— 纯静态网格（要靠网格包围盒定尺寸）")
	else:
		for sk in skels:
			var skel := sk as Skeleton3D
			print("  Skeleton3D「%s」骨骼数 = %d" % [skel.name, skel.get_bone_count()])

	print("\n================ 4. 动画 ================")
	var aps := _all(node, "AnimationPlayer")
	if aps.is_empty():
		print("  ❌ 没有 AnimationPlayer —— 没有动画（当木桩正合适）")
	else:
		for a in aps:
			var ap := a as AnimationPlayer
			print("  AnimationPlayer「%s」动作数 = %d：%s" % [
				ap.name, ap.get_animation_list().size(), str(ap.get_animation_list())])

	print("\n================ 5. 尺寸 ================")
	var aabb := _visual_aabb(node)
	print("  视觉包围盒 size = %s" % str(aabb.size.snappedf(0.001)))
	print("  视觉包围盒 范围 = y %.3f … %.3f" % [aabb.position.y, aabb.position.y + aabb.size.y])
	print("  参考：Arisu 约 1.7 m；霸王龙优香 4.5 m 高、12.6 m 长")
	if aabb.size.y > 0.0:
		print("  若想做成 2.5 m 高，scale ≈ %.4f" % (2.5 / aabb.size.y))

	print("\n================ 6. 细看三张贴图（人眼核对用）================")
	for n in ["pig_tex1.png", "pig_tex2.png", "pig_untitled1.png", "pig_nose.png",
			"pig_tail.png", "pig_halo.png"]:
		var p := "res://models/boss_pig/tex/%s" % n
		var tex: Texture2D = load(p) if ResourceLoader.exists(p) else null
		if tex == null:
			print("  %-18s 读不到" % n)
		else:
			print("  %-18s %d × %d" % [n, tex.get_width(), tex.get_height()])

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
		if n == null:
			continue
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
