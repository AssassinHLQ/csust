extends SceneTree
## 两件事一次量清（用户 2026-10-26）：
##   A. 画室里**老师左边那张桌子**到底在世界坐标哪儿（要给它加碰撞体）
##   B. 角色的**眉毛/眼睛表情零件**为什么「多重叠加」—— 哪些网格、哪些骨、怎么藏的
##   godot --path . --script res://scripts/_probe_desk_and_brows.gd -- --splat=off
##
## 出图：_arisu_captures/_fix1026/{art_desk_grid,art_desk_top,
##       face_<名字>.png}

const OUT := "_arisu_captures/_fix1026"
## ⚠️ 出图必须用**绝对路径**：`save_png()` 收相对路径时是相对**可执行文件**（Godot 目录），
##    不是相对项目 —— 第一版就栽在这（`Can't save PNG at path`）。
var _out_abs := ""


func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out_abs, nm])


func _face_parts(tag: String, node: Node3D) -> Dictionary:
	print("\n── %s ──" % tag)
	var out := {"head": Vector3.ZERO, "has_head": false}
	var skel: Skeleton3D = null
	var skels := node.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		skel = skels[0] as Skeleton3D
	# ① 脸相关网格
	print("  脸相关网格（名字里带 brow/eye/mouth 的）：")
	var n := 0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var low := String(m.name).to_lower()
		if not (low.contains("brow") or low.contains("eye") or low.contains("mouth")):
			continue
		var mats: Array[String] = []
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			mats.append("—" if mat == null else String(mat.resource_name))
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		print("    %-26s 可见 %-5s 形态键 %d  材质 %s  y %+.3f~%+.3f"
			% [String(m.name), str(m.is_visible_in_tree()),
				m.mesh.get_blend_shape_count(), ", ".join(mats),
				a.position.y, a.end.y])
		n += 1
	print("    共 %d 个" % n)
	# ② 眉/眼相关骨：当前 pose 的缩放（≈0 = 被藏起来了）
	# ①b **每个网格的每个 surface**（表情变体常常是「同一个身体网格上的一堆 surface」，
	#    名字里带 EyeMouth / Eyebrow，靠形态键或骨缩放切换 —— 不看 surface 找不到）
	print("  每个网格的 surface 与形态键：")
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var sc := m.mesh.get_surface_count()
		var bs: int = m.mesh.get_blend_shape_count()
		var names: Array[String] = []
		for s in sc:
			var mat := m.mesh.surface_get_material(s)
			names.append("—" if mat == null else String(mat.resource_name))
		print("    %-28s surface %d、形态键 %d → %s"
			% [String(m.name), sc, bs, ", ".join(names)])
		if bs > 0:
			var vals: Array[String] = []
			for b in bs:
				vals.append("%s=%.2f" % [m.mesh.get_blend_shape_name(b),
					m.get_blend_shape_value(b)])
			print("        形态键值：%s" % ", ".join(vals))
	if skel != null:
		print("  眉/眼相关骨（pose 缩放 ≈ 0 的就是「被藏起来的表情变体」）：")
		var k := 0
		for i in skel.get_bone_count():
			var bn := skel.get_bone_name(i)
			var low := bn.to_lower()
			if not (low.contains("brow") or low.contains("eye") or low.contains("eyering")):
				continue
			var sc := skel.get_bone_pose(i).basis.get_scale()
			var rc := skel.get_bone_rest(i).basis.get_scale()
			print("    [%2d] %-26s pose 缩放 (%.3f, %.3f, %.3f)   rest (%.3f, %.3f, %.3f)"
				% [i, bn, sc.x, sc.y, sc.z, rc.x, rc.y, rc.z])
			k += 1
		print("    共 %d 根" % k)
		# 头骨世界位置（用来摆相机）
		for i in skel.get_bone_count():
			if skel.get_bone_name(i).to_lower().contains("head"):
				out["head"] = skel.global_transform * skel.get_bone_global_pose(i).origin
				out["has_head"] = true
				break
	return out


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

	# ══════════ A. 画室：老师 + 桌子 ══════════
	print("══════ A. 画室老师与那张桌子 ══════")
	var sensei := game.get_node_or_null("Sensei") as Node3D
	var cam := Camera3D.new()
	cam.near = 0.02
	cam.far = 500.0
	root.add_child(cam)
	if sensei == null:
		print("  [错误] 场景里没有 Sensei")
	else:
		var sp := sensei.global_position
		print("Sensei 世界坐标 %s，朝向 y = %.1f°"
			% [str(sp.snappedf(0.01)), rad_to_deg(sensei.rotation.y)])
		var bb := AABB()
		var first := true
		var nmesh := 0
		for mi in sensei.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var a: AABB = m.global_transform * m.mesh.get_aabb()
			bb = a if first else bb.merge(a)
			first = false
			nmesh += 1
		print("  网格 %d 个，世界包围盒 x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f"
			% [nmesh, bb.position.x, bb.end.x, bb.position.y, bb.end.y,
				bb.position.z, bb.end.z])
		# 1 m 一格的参考格（在地面上）：红 = x 方向、蓝 = z 方向
		for i in range(-4, 5):
			var mx := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(0.06, 0.01, 0.06)
			mx.mesh = bx
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color(0.95, 0.15, 0.15) if i % 5 == 0 else Color(0.85, 0.75, 0.2)
			mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mx.material_override = mm
			mx.position = Vector3(sp.x + float(i), 0.02, sp.z)
			game.add_child(mx)
			var mz := MeshInstance3D.new()
			var bz := BoxMesh.new()
			bz.size = Vector3(0.06, 0.01, 0.06)
			mz.mesh = bz
			var mm2 := StandardMaterial3D.new()
			mm2.albedo_color = Color(0.25, 0.55, 0.95) if i % 5 == 0 else Color(0.85, 0.75, 0.2)
			mm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mz.material_override = mm2
			mz.position = Vector3(sp.x, 0.02, sp.z + float(i))
			game.add_child(mz)
		print("  已在地面摆 1 m 一格的标记（红点 = 老师的正前/后方向上的整米，蓝点 = 左右）")
		# 从老师正上方俯视：桌子在哪一目了然
		cam.fov = 60.0
		cam.global_position = Vector3(sp.x, 6.5, sp.z + 0.01)
		cam.look_at(Vector3(sp.x, 0.2, sp.z), Vector3.UP)
		await _shot(cam, "art_desk_top")
		# 平视：站在老师南侧往北看
		cam.fov = 70.0
		cam.global_position = Vector3(sp.x, 1.55, sp.z + 2.60)
		cam.look_at(Vector3(sp.x, 1.10, sp.z), Vector3.UP)
		await _shot(cam, "art_desk_grid")

	# ══════════ B. 眉毛/眼睛表情零件 ══════════
	print("\n══════ B. 三个角色的脸零件 ══════")
	var targets: Array = [["爱丽丝（玩家）", game.get_node_or_null("Player") as Node3D]]
	for nm in ["CompanionMomoi", "CompanionMidori", "Shop/ClerkSerika"]:
		var nd := game.get_node_or_null(nm) as Node3D
		if nd != null:
			targets.append([nm, nd])
	for t in targets:
		var info := _face_parts(String(t[0]), t[1] as Node3D)
		if bool(info["has_head"]):
			var h: Vector3 = info["head"]
			# 正脸特写：相机摆在头骨正前方 0.45 m、齐眉高
			var nod := t[1] as Node3D
			var fwd := -nod.global_transform.basis.z
			cam.fov = 32.0
			cam.global_position = h + fwd * 0.55 + Vector3(0, 0.02, 0)
			cam.look_at(h, Vector3.UP)
			await _shot(cam, "face_%s" % String(t[0]).replace("/", "_").replace("（", "").replace("）", ""))

	print("\n[截图] %s" % out)
	quit(0)
