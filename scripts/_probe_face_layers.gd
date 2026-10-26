extends SceneTree
## 把「脸上那几层」拆开量：每个 surface 的顶点包围盒 + 四个方向的头部特写。
##   godot --path . --script res://scripts/_probe_face_layers.gd -- --splat=off
##
## 用户 2026-10-26：「角色眉毛部分多重表情叠加了，应该是所有角色都有这个问题」。
## 已知：身体网格上挂着 5 个 surface（Body / Face / EyeMouth / Eyebrow / Hair），
## 而 `FaceFix.separate_face_layers()`（把 EyeMouth/Eyebrow 沿法线推开，治「双眼皮打架」）
## **只在 `anim_driver.gd`（玩家）里调过** —— 同伴和店员都没调。
## 本探针要分清两件事：
##   ① 是**共面 z-fighting**（两层贴在同一深度，花的是同一套几何）→ 推开就好；
##   ② 还是**两套眉毛几何真的叠在一起**（顶点包围盒会明显更高）→ 得藏掉一套。
## 所以这里把每个 surface 的**顶点**自己算一遍包围盒，再出四张头部特写。

const OUT := "_arisu_captures/_fix1026"
var _out_abs := ""


func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out_abs, nm])


## 逐 surface 算顶点世界包围盒（比 `mesh.get_aabb()` 细，能看出「一套还是两套几何」）
func _dump_surfaces(tag: String, node: Node3D) -> void:
	print("\n── %s ──" % tag)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not (m.mesh is ArrayMesh):
			continue
		var am := m.mesh as ArrayMesh
		var has_face := false
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			var nm := "" if mat == null else String(mat.resource_name)
			if nm.contains("Face") or nm.contains("Eye") or nm.contains("Brow"):
				has_face = true
		if not has_face:
			continue
		var xf := m.global_transform
		for s in am.get_surface_count():
			var mat2 := am.surface_get_material(s)
			var sn := "" if mat2 == null else String(mat2.resource_name)
			var arr := am.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if vs.is_empty():
				continue
			var lo := Vector3(1e9, 1e9, 1e9)
			var hi := Vector3(-1e9, -1e9, -1e9)
			for v in vs:
				var w: Vector3 = xf * v
				lo = Vector3(minf(lo.x, w.x), minf(lo.y, w.y), minf(lo.z, w.z))
				hi = Vector3(maxf(hi.x, w.x), maxf(hi.y, w.y), maxf(hi.z, w.z))
			print("  %-34s 顶点 %5d  世界 y %+.3f ~ %+.3f（高 %.3f）  z %+.3f ~ %+.3f"
				% [sn.get_slice("_", 2) if sn.count("_") >= 2 else sn, vs.size(),
					lo.y, hi.y, hi.y - lo.y, lo.z, hi.z])
		# 同一网格里 Face 与 Eyebrow 的顶点深度差（z 越大越靠前 = 面朝方向未知，取绝对值）
		print("    （%s：surface %d 个）" % [String(m.name), am.get_surface_count()])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out)
	_out_abs = out
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false

	var targets: Array = []
	for nm in ["CompanionMidori", "CompanionMomoi", "Shop/ClerkSerika"]:
		var nd := game.get_node_or_null(nm) as Node3D
		if nd != null:
			targets.append([nm.replace("/", "_"), nd])
	var cam := Camera3D.new()
	cam.near = 0.01
	cam.far = 400.0
	root.add_child(cam)
	for t in targets:
		var nd := t[1] as Node3D
		_dump_surfaces(String(t[0]), nd)
		var skels := nd.find_children("*", "Skeleton3D", true, false)
		if skels.is_empty():
			continue
		var skel := skels[0] as Skeleton3D
		var head := Vector3.ZERO
		var found := false
		for i in skel.get_bone_count():
			var bn := skel.get_bone_name(i)
			if bn == "Bip001 Head" or bn.to_lower().ends_with("head"):
				head = skel.global_transform * skel.get_bone_global_pose(i).origin
				found = true
				break
		if not found:
			continue
		# 四个方位各拍一张 —— 不假设模型朝哪边（上一版就是猜错方向拍到后脑勺）
		var dirs := [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]
		var tags := ["S", "E", "N", "W"]
		for i in 4:
			cam.fov = 26.0
			cam.global_position = head + dirs[i] * 0.62 + Vector3(0, 0.03, 0)
			cam.look_at(head + Vector3(0, -0.02, 0), Vector3.UP)
			await _shot(cam, "face_%s_%s" % [String(t[0]), tags[i]])
	print("\n[截图] %s" % out)
	quit(0)
