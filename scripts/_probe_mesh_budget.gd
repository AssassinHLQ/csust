extends SceneTree
## 「高面数场景该怎么优化」的**能力盘点 + 现状测量**。
##
## 分两半：
##   ① 问引擎：Godot 4.7.1 到底给了哪些和「面数 / draw call / 遮挡」有关的开关
##      （`GeometryInstance3D` 的 visibility_range / lod_bias 在不在、occlusion 怎么挂）。
##      不靠记忆，直接 `ClassDB` 查，查完才算数。
##   ② 量现状：电竞房放进来之后到底几个网格、多少顶点、多少 draw call、多少显存，
##      以及**按材质合并**能省多少（这是 archviz 模型最值钱的一刀）。
##
## 用法（headless 就够，不用开窗口）：
##   _tools/run_probe.sh res://scripts/_probe_mesh_budget.gd
##   _tools/run_probe.sh res://scripts/_probe_mesh_budget.gd -- --scene=esports_room

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene_name := "esports_room"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_name = a.substr(8)

	_log("=== ① 引擎能力盘点（Godot %s）===" % Engine.get_version_info()["string"])
	_dump_class("GeometryInstance3D", [
		"visibility_range_begin", "visibility_range_begin_margin",
		"visibility_range_end", "visibility_range_end_margin",
		"visibility_range_fade_mode", "lod_bias", "gi_mode",
		"cast_shadow", "extra_cull_margin", "ignore_occlusion_culling",
	])
	_dump_class("MeshInstance3D", ["mesh", "skeleton", "skin"])
	_dump_class("OccluderInstance3D", ["bake_simplification_distance", "occluder"])
	_dump_enum("GeometryInstance3D", "VisibilityRangeFadeMode")
	_dump_enum("GeometryInstance3D", "GIMode")
	_dump_methods_containing("Mesh", ["create_trimesh", "merge", "surface_get", "get_aabb"])
	_dump_methods_containing("ArrayMesh", ["add_surface", "surface_set", "clear_surfaces"])
	_dump_singletons()

	_log("")
	_log("=== ② 现有场景成本（%s）===" % scene_name)
	var path := "res://scenes/%s.tscn" % scene_name
	if not FileAccess.file_exists(path):
		_log("找不到 %s" % path)
		quit(1)
		return
	var packed: PackedScene = load(path)
	var inst := packed.instantiate()
	root.add_child(inst)
	await process_frame

	var meshes: Array[MeshInstance3D] = []
	_collect(inst, meshes)
	_log("网格节点：%d" % meshes.size())

	var verts := 0
	var prims := 0
	var surfaces := 0
	var mats := {}
	var by_mesh_rid := {}
	var biggest: Array = []
	for m in meshes:
		var mesh: Mesh = m.mesh
		if mesh == null:
			continue
		var mv := 0
		var mp := 0
		by_mesh_rid[mesh] = int(by_mesh_rid.get(mesh, 0)) + 1
		for s in mesh.get_surface_count():
			surfaces += 1
			var mat := mesh.surface_get_material(s)
			var key := "<null>"
			if mat != null:
				key = mat.resource_name + "|" + str(mat.get_instance_id())
			mats[key] = int(mats.get(key, 0)) + 1
			if mesh is ArrayMesh:
				var am := mesh as ArrayMesh
				var a: Array = am.surface_get_arrays(s)
				if a.size() > Mesh.ARRAY_VERTEX and a[Mesh.ARRAY_VERTEX] != null:
					mv += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				if a.size() > Mesh.ARRAY_INDEX and a[Mesh.ARRAY_INDEX] != null:
					mp += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		verts += mv
		prims += mp
		if mp >= 2000:
			biggest.append({"name": String(m.name), "prim": mp, "vert": mv})

	_log("总顶点：%d   总三角形：%d   表面（≈draw call 下限）：%d" % [verts, prims, surfaces])
	_log("唯一 Mesh 资源：%d   唯一材质：%d" % [by_mesh_rid.size(), mats.size()])
	_log("→ 按材质合并的**上限**：draw call 从 %d 降到 ≤ %d" % [surfaces, mats.size()])

	biggest.sort_custom(func(a, b): return int(a["prim"]) > int(b["prim"]))
	_log("")
	_log("最重的 %d 个网格：" % mini(biggest.size(), 12))
	for i in mini(biggest.size(), 12):
		_log("  %-34s %8d 三角  %8d 顶点" % [
			String(biggest[i]["name"]).substr(0, 34),
			int(biggest[i]["prim"]), int(biggest[i]["vert"])])

	_write_out()
	quit(0)


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	var mi := node as MeshInstance3D
	if mi != null:
		out.append(mi)
	for c in node.get_children():
		_collect(c, out)


## 打印某个类上这些属性是否存在、默认值多少 —— 「文档说有」不如「引擎里有」。
## ⚠️ `ClassDB` 在 4.7 里**没有** `class_has_property`；用 `class_get_property_list`
##    自己翻。也没有 `class_get_property_default_value`，默认值只能实例化之后读。
func _dump_class(cls: String, props: Array) -> void:
	_log("  [%s]" % cls)
	var have := {}
	for p in ClassDB.class_get_property_list(cls, true):
		have[String(p["name"])] = true
	var probe: Object = null
	if ClassDB.can_instantiate(cls):
		probe = ClassDB.instantiate(cls)
	for p in props:
		var nm := String(p)
		if have.has(nm):
			var dv := "<只能实例化后读>"
			if probe != null:
				dv = str(probe.get(nm))
			_log("    ✓ %-30s 默认 %s" % [nm, dv])
		else:
			_log("    ✗ %-30s （这个版本没有）" % nm)
	if probe != null:
		probe.free()


func _dump_enum(cls: String, name: String) -> void:
	var out: Array = []
	for c in ClassDB.class_get_enum_list(cls, true):
		if String(c) == name:
			for e in ClassDB.class_get_enum_constants(cls, name, true):
				out.append("%s=%d" % [String(e), ClassDB.class_get_integer_constant(cls, String(e))])
	_log("  [%s.%s] %s" % [cls, name, ", ".join(out) if out.size() else "（无）"])


func _dump_methods_containing(cls: String, needles: Array) -> void:
	var found: Array = []
	for m in ClassDB.class_get_method_list(cls, true):
		var nm := String(m["name"])
		for n in needles:
			if nm.begins_with(String(n)):
				found.append(nm)
				break
	found.sort()
	_log("  [%s] 相关方法：%s" % [cls, ", ".join(found) if found.size() else "（无）"])


func _dump_singletons() -> void:
	_log("  [关键全局]")
	for p in ["rendering/limits/opengl/max_lights_per_object",
			"rendering/anti_aliasing/quality/msaa_3d",
			"rendering/occlusion_culling/use_occlusion_culling",
			"rendering/mesh_lod/lod_change/threshold_pixels",
			"debug/settings/stdout/verbose_stdout"]:
		_log("    %-58s = %s" % [p, str(ProjectSettings.get_setting(p, "<未设置>"))])


func _write_out() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_log")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("mesh_budget.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()


var _lines: PackedStringArray = PackedStringArray()


func _log(s: String) -> void:
	print("[budget] " + s)
	_lines.append(s)
