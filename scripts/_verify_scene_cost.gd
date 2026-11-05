extends SceneTree
## headless 清点一个场景的「渲染成本」：**不渲染、不开窗口**。
##
##   _tools/run_probe.sh res://scripts/_verify_scene_cost.gd
##   _tools/run_probe.sh res://scripts/_verify_scene_cost.gd -- res://scenes/next_level.tscn
##
## 回答三个问题：
##   1. 「物体 4322 / draw call 2912」是谁贡献的 —— 按节点名前缀分组统计；
##   2. 贴图显存大概多少 —— 数**唯一**贴图，按尺寸估（宽×高×4 B×1.33 mipmap）；
##   3. 有没有明显浪费：同一个网格被实例化很多次（本该 MultiMesh）、
##      或者大量 1×1 / 极小贴图。
##
## ⚠️ 这里的显存是**估算**（按格式算字节），不等于 `RENDER_VIDEO_MEM_USED`；
##    真要量那个必须开窗口，本探针只负责把「谁占了多少」列清楚。

const DEFAULT_SCENE := "res://scenes/game.tscn"


func _initialize() -> void:
	var path := DEFAULT_SCENE
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0:
		path = String(ua[0])
	_run(path)


func _run(path: String) -> void:
	if not ResourceLoader.exists(path):
		print("[cost] !! 找不到场景 %s" % path)
		quit(1)
		return
	var inst := (load(path) as PackedScene).instantiate()
	root.add_child(inst)

	var nodes := 0
	var meshes: Array[MeshInstance3D] = []
	var lights := 0
	var labels := 0
	_walk(inst, func(n: Node):
		nodes += 1
		if n is MeshInstance3D:
			meshes.append(n)
		elif n is Light3D:
			lights += 1
		elif n is Label3D:
			labels += 1)

	# ── 按「节点名前缀」分组（`Foo_001` / `Foo2` 归到 `Foo`）──
	var groups := {}
	var mesh_by_res := {}
	var surf_total := 0
	for m in meshes:
		var nm := String(m.name)
		var key := _prefix(nm)
		groups[key] = int(groups.get(key, 0)) + 1
		var mesh := m.mesh
		if mesh == null:
			continue
		var rid := mesh.get_rid()
		mesh_by_res[rid] = int(mesh_by_res.get(rid, 0)) + 1
		surf_total += mesh.get_surface_count()

	print("[cost] 场景 %s" % path)
	print("[cost] 节点 %d｜网格实例 %d（唯一网格 %d）｜表面合计 %d｜灯光 %d｜Label3D %d" % [
		nodes, meshes.size(), mesh_by_res.size(), surf_total, lights, labels])

	var keys := groups.keys()
	keys.sort_custom(func(a, b): return int(groups[a]) > int(groups[b]))
	print("[cost] 数量最多的 12 组（按节点名前缀）：")
	for i in mini(12, keys.size()):
		print("[cost]   %-24s %5d" % [String(keys[i]), int(groups[keys[i]])])

	# ── 贴图 ──
	var texs := {}
	for m in meshes:
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			_collect_textures(mat, texs)
	var bytes := 0
	var big: Array = []
	for t in texs.keys():
		var tex := t as Texture2D
		if tex == null:
			continue
		var w := tex.get_width()
		var h := tex.get_height()
		var b := int(float(w * h) * 4.0 * 1.34)
		bytes += b
		big.append({"n": tex.resource_path.get_file(), "w": w, "h": h, "b": b})
	big.sort_custom(func(a, b): return int(a["b"]) > int(b["b"]))
	print("[cost] 唯一贴图 %d 张｜估算显存 %.0f MiB（宽×高×4B×1.34 mipmap）" % [
		texs.size(), float(bytes) / 1048576.0])
	for i in mini(10, big.size()):
		var e: Dictionary = big[i]
		print("[cost]   %-42s %5d×%-5d %6.1f MiB" % [
			String(e["n"]), int(e["w"]), int(e["h"]), float(e["b"]) / 1048576.0])

	print("[cost] 提示：GDGS 泼溅的显存不在这里（它走 RenderingDevice，按点数算），")
	print("[cost]       277 万点约 1.3 GB（splats 665 MB + 排序键值 443 MB + 其它）。")

	# ── 几何体：顶点/索引，估显存（顶点 ~32 B、索引 4 B）──
	var geo := {}
	var vtx_total := 0
	var idx_total := 0
	var prim_count := 0
	for m in meshes:
		# ⚠️ 内置图元（BoxMesh / QuadMesh / PlaneMesh…）没有 `surface_get_array_len`，
		#    第一版直接调它就 SCRIPT ERROR 了。它们由引擎按参数生成、不进显存大头，跳过。
		if not (m.mesh is ArrayMesh):
			prim_count += 1
			continue
		var am := m.mesh as ArrayMesh
		var v := 0
		var ix := 0
		for s in am.get_surface_count():
			v += am.surface_get_array_len(s)
			ix += am.surface_get_array_index_len(s)
		vtx_total += v
		idx_total += ix
		var key := am.resource_path
		if key.is_empty():
			key = "<内嵌网格>"
		var e: Dictionary = geo.get(key, {"v": 0, "i": 0, "n": 0})
		e["v"] = int(e["v"]) + v
		e["i"] = int(e["i"]) + ix
		e["n"] = int(e["n"]) + 1
		geo[key] = e
	var geo_bytes := int(float(vtx_total) * 32.0 + float(idx_total) * 4.0)
	print("[cost] 几何：顶点 %d（%.0f 万）｜索引 %d｜估显存 %.0f MiB｜内置图元 %d 个（不计）" % [
		vtx_total, float(vtx_total) / 10000.0, idx_total,
		float(geo_bytes) / 1048576.0, prim_count])
	var gk := geo.keys()
	gk.sort_custom(func(a, b): return int(geo[a]["v"]) > int(geo[b]["v"]))
	print("[cost] 顶点最多的 12 个网格：")
	for i in mini(12, gk.size()):
		var e: Dictionary = geo[gk[i]]
		print("[cost]   %-40s 顶点 %8d（×%d 份）估 %.1f MiB" % [
			String(gk[i]).get_file() if not String(gk[i]).begins_with("<") else String(gk[i]),
			int(e["v"]), int(e["n"]),
			float(float(e["v"]) * 32.0 + float(e["i"]) * 4.0) / 1048576.0])
	quit(0)


## `Foo_001` → `Foo`；`Chunk_1_2` → `Chunk`；数字结尾也砍掉
func _prefix(nm: String) -> String:
	var s := nm
	while s.length() > 0 and (s[s.length() - 1].is_valid_int() or s[s.length() - 1] == "_"):
		s = s.substr(0, s.length() - 1)
	if s.is_empty():
		s = nm
	return s


func _walk(n: Node, fn: Callable) -> void:
	fn.call(n)
	for c in n.get_children():
		_walk(c, fn)


func _collect_textures(mat: Material, out: Dictionary) -> void:
	if mat == null:
		return
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		for t in [bm.albedo_texture, bm.normal_texture, bm.orm_texture,
				bm.emission_texture, bm.metallic_texture, bm.roughness_texture]:
			if t != null:
				out[t] = true
	elif mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		for p in sm.get_shader_parameter_list():
			var v = sm.get_shader_parameter(p)
			if v is Texture2D:
				out[v] = true
