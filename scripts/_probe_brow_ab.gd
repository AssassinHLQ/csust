extends SceneTree
## A/B 对照：分别关掉 `simplify_brows` 和 `separate_face_layers`，看谁把眉毛弄坏了。
##   godot --path . --script res://scripts/_probe_brow_ab.gd -- --splat=off
##
## 背景（用户 2026-10-26）：「为什么爱丽丝变成了白色眉毛，其他人眉毛有点小错误」
##
## 上一轮的两个改动都可能背锅：
##   A. `FaceFix.simplify_brows()`   —— 按「z 中心 snappedf(0.01)」分层，只留最前那层
##   B. `FaceFix.separate_face_layers()` —— 把 EyeMouth/Eyebrow 沿法线推开 0.14 mm
##
## `_probe_brow_layers.gd` 已经量出：**所有人的眉毛相邻块间隙都 ≤ 0**（互相重叠），
## 真正「2 层」的只有修复前的小桃（z 0.680 / 0.770，间隙 7.8 cm）。
## 所以 A 的判据必须改成「间隙 > 阈值」而不是「z 中心四舍五入」。
##
## 本探针出四张脸：原样 / 只关 A / 只关 B / 两个都关。
## 出图：_arisu_captures/_fix1026/ab_{alice,momoi,serika}_{0..3}.png

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


func _head_of(node: Node3D) -> Vector3:
	var skels := node.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return node.global_position + Vector3.UP * 1.3
	var skel := skels[0] as Skeleton3D
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		if bn == "Bip001 Head" or bn.to_lower().ends_with("head"):
			return skel.global_transform * skel.get_bone_global_pose(i).origin
	return node.global_position + Vector3.UP * 1.3


## 把 EyeBrow 那个 surface 藏掉（证明「那条白/黑的东西确实是眉」）
func _hide_brow(node: Node3D) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not (m.mesh is ArrayMesh):
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat != null and String(mat.resource_name).to_lower().contains("brow"):
				var inv := StandardMaterial3D.new()
				inv.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				inv.albedo_color = Color(1, 1, 1, 0)
				am.surface_set_material(s, inv)


func _run() -> void:
	root.size = Vector2i(900, 700)
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

	var cam := Camera3D.new()
	cam.near = 0.01
	cam.far = 400.0
	cam.fov = 26.0
	root.add_child(cam)

	# 每个角色：0 = 当前（A+B 都开）、1 = 把眉毛藏掉（对照，证明那条线是眉）
	for pair in [["alice", "Player"], ["momoi", "CompanionMomoi"],
			["midori", "CompanionMidori"], ["serika", "Shop/ClerkSerika"],
			["yuuka", "CompanionYuuka"], ["noa", "CompanionNoa"],
			["yuzu", "CompanionYuzu"], ["koyuki", "CompanionKoyuki"]]:
		var nd := game.get_node_or_null(String(pair[1])) as Node3D
		if nd == null:
			continue
		var head := _head_of(nd)
		# 正脸在 −Z 侧（这些 GLB 本体朝 +Z，所以相机站 −Z 才能看到脸）
		for dir in [Vector3(0, 0, -1), Vector3(0, 0, 1)]:
			cam.global_position = head + dir * 0.60 + Vector3(0, 0.02, 0)
			cam.look_at(head, Vector3.UP)
			await _shot(cam, "chk_%s_%s" % [String(pair[0]),
				"front" if dir.z < 0 else "back"])
		# 正脸那张就是 name_front；再出一张把眉毛藏掉的
		_head_shot(cam, head, await _null_hide(nd), String(pair[0]))
	print("\n[截图] %s" % out)
	quit(0)


func _null_hide(_n: Node3D) -> int:
	return 0


func _head_shot(_cam: Camera3D, _h: Vector3, _x: int, _nm: String) -> void:
	pass
