extends SceneTree
## 探针：新 Boss「倭瓜优香」（OBJ）导进来之后长什么样。
##
## 要回答两件事：
##   1. **`texture_map` 的键该写什么** —— Godot 的 OBJ 导入会给材质改名，
##      得先把它实际用的名字打出来（当年飞猪优香那份表就是照着这个写的）。
##   2. **原始包围盒** —— 决定 `height`（归一化目标身高）与 `collision_factors`。
##
## 用法：godot --path <工程> --script res://scripts/_probe_boss_squash.gd -- --splat=off

const MODEL := "res://models/boss_squash/倭瓜优香.obj"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var res := load(MODEL)
	if res == null:
		print("!! 载入失败 %s" % MODEL)
		quit(1)
		return
	# ⚠️ OBJ 在 Godot 里导入成 **`Mesh`**（`type="Mesh"`），不是 `PackedScene`；
	#    FBX 才是场景。所以这里两种都接。
	var n: Node3D
	if res is PackedScene:
		n = (res as PackedScene).instantiate() as Node3D
	elif res is Mesh:
		n = Node3D.new()
		n.name = "ObjRoot"
		var mi := MeshInstance3D.new()
		mi.name = "倭瓜优香"
		mi.mesh = res as Mesh
		n.add_child(mi)
	else:
		print("!! 认不出的资源类型：%s" % res.get_class())
		quit(1)
		return
	root.add_child(n)
	await process_frame
	await process_frame

	var meshes := _all(n, "MeshInstance3D")
	print("[probe] 节点 %d 个、MeshInstance3D %d 个" % [_count(n), meshes.size()])
	var aabb := AABB()
	var first := true
	var i := 0
	for mi in meshes:
		var m := mi as MeshInstance3D
		var am := m.mesh as ArrayMesh
		if am == null:
			continue
		print("  [mesh %d] %s  表面 %d 个" % [i, m.name, am.get_surface_count()])
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			var rname := "（无材质）"
			var tex := ""
			var blend := ""
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				rname = sm.resource_name
				if sm.albedo_texture != null:
					tex = sm.albedo_texture.resource_path.get_file()
				blend = "alpha=%s" % str(sm.transparency)
			elif mat is BaseMaterial3D:
				rname = (mat as BaseMaterial3D).resource_name
			print("      surface %d  材质名「%s」  贴图 %s  %s"
				% [s, rname, tex if tex != "" else "（MTL 里没写）", blend])
		var bb: AABB = m.global_transform * m.get_aabb()
		aabb = bb if first else aabb.merge(bb)
		first = false
		i += 1
	print("[probe] 原始包围盒 %s" % str(aabb))
	print("[probe] 尺寸 %s   最低点 y = %.3f   最高点 y = %.3f"
		% [str(aabb.size.snappedf(0.001)), aabb.position.y, aabb.end.y])
	quit(0)


func _all(node: Node, cls: String) -> Array:
	var out: Array = []
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out


func _count(node: Node) -> int:
	var k := 1
	for c in node.get_children():
		k += _count(c)
	return k
