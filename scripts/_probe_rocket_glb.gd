extends SceneTree
## 探针：核实 `models/rocket_falcon9/falcon9.glb` 导入后在 Godot 里到底是什么。
##
## 为什么要有这一步：Blender 那边报了「3 个材质槽，其中 [1] 是空槽」，
## 空槽的 surface 在 Godot 里会不会变成无材质白模、会不会整块丢失，
## 必须在引擎里实测，不能凭 Blender 的日志推断。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_rocket_glb.gd

const GLB_PATH := "res://models/rocket_falcon9/falcon9.glb"


func _initialize() -> void:
	print("[rocket] 路径 = %s" % GLB_PATH)
	print("[rocket] 存在 = %s" % str(ResourceLoader.exists(GLB_PATH)))

	if not ResourceLoader.exists(GLB_PATH):
		print("[rocket] ✗ 文件不在（.gitignore 排除的第三方素材）—— 场景必须能降级")
		quit(0)
		return

	var ps := load(GLB_PATH) as PackedScene
	if ps == null:
		print("[rocket] ✗ load() 返回 null（不是 PackedScene）")
		quit(1)
		return
	print("[rocket] PackedScene 载入成功")

	var root_node: Node = ps.instantiate()
	if root_node == null:
		print("[rocket] ✗ 实例化为 null")
		quit(1)
		return
	print("[rocket] 根节点 = %s（%s）" % [root_node.name, root_node.get_class()])

	# ── 遍历，收集所有 MeshInstance3D ──
	var meshes: Array[MeshInstance3D] = []
	_collect(root_node, meshes)
	print("[rocket] MeshInstance3D 节点数 = %d" % meshes.size())

	var total_tris := 0
	var total_surf := 0
	var null_mat_surf := 0
	var mat_names := {}
	var aabb := AABB()
	var first := true

	for mi in meshes:
		var m: Mesh = mi.mesh
		if m == null:
			print("[rocket]   ! %s 的 mesh 是 null" % mi.name)
			continue
		for s in m.get_surface_count():
			total_surf += 1
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var tris := 0
			if idx != null and (idx as PackedInt32Array).size() > 0:
				tris = (idx as PackedInt32Array).size() / 3
			else:
				tris = verts.size() / 3
			total_tris += tris

			var mat := m.surface_get_material(s)
			if mat == null:
				null_mat_surf += 1
				print("[rocket]   ! %s surface %d 无材质，%d 三角面" % [mi.name, s, tris])
			else:
				mat_names[mat.resource_name if mat.resource_name != "" else "(未命名)"] = true

		# AABB 累加。
		# ⚠️ 这里用 `transform` 而不是 `global_transform`：实例还没 add_child 进树，
		#    `global_transform` 会报 "Condition !is_inside_tree()" 并返回单位变换。
		var box := mi.get_aabb()
		var wt := mi.transform
		# 8 个角点变换后重新取包围盒
		for i in 8:
			var p := wt * box.get_endpoint(i)
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)

	print("[rocket] 表面数 = %d（其中无材质 %d）" % [total_surf, null_mat_surf])
	print("[rocket] 合计三角面 = %d" % total_tris)
	print("[rocket] 材质: %s" % ", ".join(mat_names.keys()))

	print("[rocket] ── 包围盒（世界，实例未入树前的局部累积）──")
	print("[rocket]   position = %s" % str(aabb.position.snappedf(0.01)))
	print("[rocket]   size     = %s" % str(aabb.size.snappedf(0.01)))
	print("[rocket]   即 直径 %.2f m（取 x/z 较大者），高 %.2f m" % [
		maxf(aabb.size.x, aabb.size.z), aabb.size.y])

	# ── 材质细节：确认贴图有没有真的内嵌进来 ──
	print("[rocket] ── 材质贴图 ──")
	var seen := {}
	for mi in meshes:
		var m: Mesh = mi.mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat == null or not (mat is BaseMaterial3D):
				continue
			var bm := mat as BaseMaterial3D
			var key := bm.resource_name
			if seen.has(key):
				continue
			seen[key] = true
			var albedo := bm.albedo_texture
			var nrm := bm.normal_texture
			print("[rocket]   %-22s albedo=%s  normal=%s" % [
				key if key != "" else "(未命名)",
				("%dx%d" % [albedo.get_width(), albedo.get_height()]) if albedo != null else "无",
				("%dx%d" % [nrm.get_width(), nrm.get_height()]) if nrm != null else "无"])

	root_node.free()
	print("[rocket] 完成")
	quit(0)


func _collect(n: Node, acc: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		acc.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect(c, acc)
