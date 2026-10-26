extends SceneTree
## 芹香**动画姿势**到底站在哪 —— 绑姿包围盒会骗人，这里量的是真正渲染出来的那副骨架。
##   godot --path . --script res://scripts/_probe_clerk_anim_ground.gd -- --splat=off
##
## 背景：`_probe_float_lamp_zfight.gd` 量到她的网格世界包围盒底 y = −0.000（**绑姿**），
## 可同一位置渲出来的图里她明显浮在离地 ~0.35 m 的空中。
## 结论：`Cafe_Idle` 这条动画把整条骨架抬起来了，绑姿数据看不出来。
##
## 本探针只回答一个问题：**动画姿势下，鞋底到底在 y 多少**。
##   ① 根骨 / 脚骨的「动画姿势 vs 绑定姿势」世界 y，差值 = 整条骨架被抬了多少
##   ② 逐帧采样根骨 y（2 秒）—— 是静态偏置，还是动画里本来就上下浮
##   ③ 她脚边立一把 5 cm 一格的尺（y = 0.00 ~ 0.45），人眼在图上一格一格数

const GRADE := 0.05
const GRADES := 9


func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_issues1026")
	DirAccess.make_dir_recursive_absolute(out)
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false

	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk == null:
		print("[错误] 没有 Shop/ClerkSerika")
		quit(1)
		return
	var skels := clerk.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		print("[错误] 她身上没有 Skeleton3D")
		quit(1)
		return
	var skel := skels[0] as Skeleton3D
	var base := clerk.global_position
	print("她站在世界 %s；模型根 scale = %.3f" % [str(base.snappedf(0.001)), clerk.scale.y])

	# ── ① 根骨 + 脚骨：动画姿势 vs 绑定姿势 ──
	print("\n① 动画姿势 vs 绑定姿势（世界 y）")
	var root_idx := -1
	for i in skel.get_bone_count():
		var nm := skel.get_bone_name(i)
		var low := nm.to_lower()
		var is_root := (i == 0) or low.contains("root") or low.contains("bip001")
		var is_foot := low.contains("foot") or low.contains("toe")
		if not (is_root or is_foot):
			continue
		var anim_y: float = (skel.global_transform * skel.get_bone_global_pose(i).origin).y
		var rest_y: float = (skel.global_transform * skel.get_bone_global_rest(i).origin).y
		print("  [%2d] %-26s 动画 %+.3f   绑定 %+.3f   差 %+.3f"
			% [i, nm, anim_y, rest_y, anim_y - rest_y])
		if root_idx < 0 and is_root:
			root_idx = i
	if root_idx < 0:
		root_idx = 0
	print("  用来采样的根骨 = [%d] %s" % [root_idx, skel.get_bone_name(root_idx)])

	# ── ② 逐帧采样根骨 y ──
	var lo := 999.0
	var hi := -999.0
	var rest_root: float = (skel.global_transform
		* skel.get_bone_global_rest(root_idx).origin).y
	for _f in 120:
		await process_frame
		var y: float = (skel.global_transform
			* skel.get_bone_global_pose(root_idx).origin).y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	print("\n② 根骨 2 秒采样：y %.3f ~ %.3f（波动 %.3f m，绑定姿势 %.3f）"
		% [lo, hi, hi - lo, rest_root])
	print("  ⇒ 动画把骨架整体抬了 %+.3f m（相对绑定姿势）；波动只有 %.3f m %s"
		% [lo - rest_root, hi - lo,
			"（静态偏置，可以直接减掉）" if hi - lo < 0.03 else "（会上下动，得按最低点对齐）"])

	# ── ③ 逐网格最低点：那个「0.000」到底是不是她的鞋底 ──
	print("\n③ 她身上最低的 8 个网格（绑姿）：如果是鞋，名字里会有 Shoe/Foot/Boot")
	var lows: Array = []
	for mi in clerk.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		lows.append({"n": String(m.name), "lo": a.position.y, "hi": a.end.y})
	lows.sort_custom(func(x, y): return float(x["lo"]) < float(y["lo"]))
	for h in lows.slice(0, 8):
		print("  %-24s y %+.3f ~ %+.3f" % [h["n"], h["lo"], h["hi"]])

	# ── ④ 尺子 ──
	var ruler_x := base.x + 0.34
	var ruler_z := base.z
	for i in GRADES:
		var y := GRADE * float(i)
		var mi2 := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.34, 0.010, 0.26)
		mi2.mesh = bm
		var m2 := StandardMaterial3D.new()
		m2.albedo_color = Color(0.95, 0.20, 0.18) if i % 2 == 0 else Color(0.97, 0.97, 0.97)
		m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi2.material_override = m2
		mi2.position = Vector3(ruler_x, y + 0.005, ruler_z)
		game.add_child(mi2)
	# 立杆：让「一格一格」看得出来
	var post := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.02, GRADE * float(GRADES) + 0.06, 0.02)
	post.mesh = pb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.12, 0.12, 0.14)
	post.material_override = pm
	post.position = Vector3(ruler_x + 0.16, pb.size.y * 0.5 - 0.02, ruler_z)
	game.add_child(post)
	print("\n④ 尺子立在 (%.2f, 0.00~%.2f, %.2f)：每格 %.2f m，红白相间"
		% [ruler_x, GRADE * float(GRADES - 1), ruler_z, GRADE])

	var cam := Camera3D.new()
	cam.near = 0.02
	cam.far = 500.0
	root.add_child(cam)
	# ⚠️ 机位必须站得下：她在柜台（x 31.84~32.56）与东墙内表面（x 33.70）之间的
	#    那条 1.1 m 走道里，所以只能从**北边**顺着走道往南拍。
	cam.fov = 45.0
	cam.global_position = Vector3(base.x + 0.06, 0.45, base.z + 1.90)
	cam.look_at(Vector3(base.x + 0.20, 0.10, base.z), Vector3.UP)
	await _shot(cam, out, "clerk_ruler")
	# 正面全身
	cam.fov = 36.0
	cam.global_position = Vector3(base.x, 0.85, base.z + 2.10)
	cam.look_at(Vector3(base.x, 0.82, base.z), Vector3.UP)
	await _shot(cam, out, "clerk_ruler_full")

	print("\n[截图] %s" % out)
	quit(0)
