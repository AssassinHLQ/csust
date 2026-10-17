extends SceneTree
## 探针：老师模型里**每个 surface 到底是身体哪一块、现在什么颜色**。
## 文件里没有贴图、顶点色又是纯白，颜色全靠 `baseColorFactor`
## （被 toon 节点树吃掉了，只剩橄榄绿 / 黑）。要把它改成「白皮肤 + 棕头发」，
## 先得知道哪个材质管皮肤、哪个管头发 —— 用 surface 的包围盒判断。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_sensei_mats.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node = (load("res://models/npc/sensei.glb") as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var total := AABB()
	var first := true
	for mi in _all_meshes(inst):
		if mi.name.begins_with("cs_"):
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var box := AABB(verts[0], Vector3.ZERO)
			for v in verts:
				box = box.expand(v)
			total = box if first else total.merge(box)
			first = false
			var base := "-"
			var vcol := "-"
			var emis := "-"
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				base = str(bm.albedo_color)
				vcol = str(bm.vertex_color_use_as_albedo)
				emis = str(bm.emission_enabled) + " / " + str(bm.emission)
			print("[mat] surf %d  %-14s 顶点 %6d  颜色 %s  vcol=%s  emis=%s" % [
				s, "<无>" if mat == null else mat.resource_name, verts.size(), base, vcol, emis])
			print("      局部包围盒 y=[%.3f, %.3f]  x=[%.3f, %.3f]  z=[%.3f, %.3f]" % [
				box.position.y, box.end.y, box.position.x, box.end.x,
				box.position.z, box.end.z])
	print("[mat] 整体包围盒 %s" % str(total))
	quit(0)


func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D and (x as MeshInstance3D).mesh != null:
			out.append(x as MeshInstance3D)
		for c in x.get_children():
			stack.append(c)
	return out
