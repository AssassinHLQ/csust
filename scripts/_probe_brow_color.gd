extends SceneTree
## 量「眉毛那一层到底是哪一层、什么颜色」—— 用户 2026-10-26：
## 「为什么爱丽丝变成了白色眉毛，其他人眉毛有点小错误」
##   godot --path . --script res://scripts/_probe_brow_color.gd -- --splat=off
##
## 怀疑两件事，本探针分别给证据：
##   ① `simplify_brows()` 给爱丽丝**选错了层**（留了白色那一层）；
##   ② 其他人「细线残留」是因为把多余顶点**压到同一点**，而每个顶点的**骨骼权重不同**
##      —— 蒙皮一动又把它们拉开了，压平不等于消失。
##
## 所以逐角色报：
##   ① Eyebrow surface 的材质名 + albedo 贴图 + 贴图尺寸；
##   ② 每个连通块的 **UV 中心** 和从贴图上**采到的颜色**（白/黑一眼可辨）；
##   ③ 每个连通块的**骨骼索引 + 权重**是否一致（不一致 = 压平会被蒙皮拉开）。

const OUT := "_arisu_captures/_fix1026"
var _out_abs := ""


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _find_brow(node: Node3D) -> Array:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not (m.mesh is ArrayMesh):
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat != null and String(mat.resource_name).to_lower().contains("brow"):
				return [m, am, s, mat]
	return []


func _islands(arr: Array) -> Array:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] \
		if arr.has(Mesh.ARRAY_TEX_UV) else PackedVector2Array()
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] \
		if arr.has(Mesh.ARRAY_BONES) else PackedInt32Array()
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] \
		if arr.has(Mesh.ARRAY_WEIGHTS) else PackedFloat32Array()
	var parent := PackedInt32Array()
	parent.resize(vs.size())
	for i in vs.size():
		parent[i] = i
	var t := 0
	while t + 2 < idx.size():
		var a := idx[t]
		var b2 := idx[t + 1]
		var c := idx[t + 2]
		var ra := a
		while parent[ra] != ra:
			ra = parent[ra]
		var rb := b2
		while parent[rb] != rb:
			rb = parent[rb]
		var rc := c
		while parent[rc] != rc:
			rc = parent[rc]
		var mn := mini(ra, mini(rb, rc))
		parent[ra] = mn
		parent[rb] = mn
		parent[rc] = mn
		t += 3
	var groups := {}
	for i in vs.size():
		var r := i
		while parent[r] != r:
			r = parent[r]
		if not groups.has(r):
			groups[r] = PackedInt32Array()
		var g: PackedInt32Array = groups[r]
		g.append(i)
		groups[r] = g
	var out: Array = []
	for k in groups:
		var g2: PackedInt32Array = groups[k]
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		var uv := Vector2.ZERO
		var nb := 0
		for i in g2:
			var v := vs[i]
			lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
			hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
			if i < uvs.size():
				uv += uvs[i]
				nb += 1
		if nb > 0:
			uv /= float(nb)
		# 骨骼 / 权重是否一致（前 4 个权重的组合）
		var sig := ""
		for i in g2:
			if i * 4 + 3 < bones.size():
				sig += "%d/%d/%d/%d;" % [bones[i * 4], bones[i * 4 + 1],
					bones[i * 4 + 2], bones[i * 4 + 3]]
		out.append({"verts": g2, "lo": lo, "hi": hi, "uv": uv, "sig": sig})
	return out


func _report(tag: String, node: Node3D) -> void:
	print("\n──────── %s ────────" % tag)
	var hit := _find_brow(node)
	if hit.is_empty():
		print("  （没有 Eyebrow surface）")
		return
	var m := hit[0] as MeshInstance3D
	var am := hit[1] as ArrayMesh
	var surf := int(hit[2])
	var mat := hit[3] as StandardMaterial3D
	print("  网格 %s / surface %d / 材质 %s" % [String(m.name), surf, String(mat.resource_name)])
	var tex := mat.albedo_texture
	if tex == null:
		print("  **没有 albedo 贴图** → 颜色全靠 albedo_color = %s" % str(mat.albedo_color))
	else:
		print("  albedo 贴图 %s（%d × %d）albedo_color = %s"
			% [tex.resource_path.get_file(), tex.get_width(), tex.get_height(),
				str(mat.albedo_color)])
	var arr := am.surface_get_arrays(surf)
	var isl := _islands(arr)
	print("  连通块 %d 个：" % isl.size())
	for i in isl.size():
		var lo: Vector3 = isl[i]["lo"]
		var hi: Vector3 = isl[i]["hi"]
		var uv: Vector2 = isl[i]["uv"]
		var col := mat.albedo_color
		if tex != null:
			var img := tex.get_image()
			if img != null and img.get_width() > 0:
				var px := clampi(int(uv.x * float(img.get_width())),
					0, img.get_width() - 1)
				var py := clampi(int(uv.y * float(img.get_height())),
					0, img.get_height() - 1)
				col = img.get_pixel(px, py)
		var sig: String = isl[i]["sig"]
		var parts := sig.split(";", false)
		var uniq := {}
		for p in parts:
			uniq[p] = true
		print("    块 %d: 顶点 %2d  z %+.3f~%+.3f  UV(%.3f, %.3f) → 色 %s  骨骼组合 %d 种%s"
			% [i, (isl[i]["verts"] as PackedInt32Array).size(),
				lo.z, hi.z, uv.x, uv.y,
				"#%02x%02x%02x" % [int(col.r * 255), int(col.g * 255), int(col.b * 255)],
				uniq.size(), "  ← 压平会被蒙皮拉开" if uniq.size() > 1 else ""])


func _run() -> void:
	root.size = Vector2i(800, 600)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out)
	_out_abs = out

	for pair in [["爱丽丝（玩家）", "Player"], ["小雪", "CompanionKoyuki"],
			["优香", "CompanionYuuka"], ["诺亚", "CompanionNoa"],
			["小桃", "CompanionMomoi"], ["小绿", "CompanionMidori"],
			["柚子", "CompanionYuzu"], ["凯伊", "CompanionKei"],
			["芹香", "Shop/ClerkSerika"]]:
		var nd := game.get_node_or_null(String(pair[1])) as Node3D
		if nd == null:
			print("\n──────── %s：**节点不存在** ────────" % String(pair[0]))
			continue
		_report(String(pair[0]), nd)
	quit(0)
