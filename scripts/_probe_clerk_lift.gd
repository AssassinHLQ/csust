extends SceneTree
## 判图：芹香的脚到底该抬多少 —— 侧视 + 地面标线，五个候选高度各拍一张。
##   godot --path . --script res://scripts/_probe_clerk_lift.gd -- --splat=off
## 输出：_arisu_captures/_lift/lift_<值>.png（拼成 _sheet.png 看）
##
## 为什么不用「骨骼高度」判定：她的骨架里**没有 toe 骨**，`Bip001 L/R Foot` 到底
## 是踝关节还是脚掌前部、离鞋底多少，不同角色的绑定不一样。上一次拿玩家的
## Foot 骨高度（+0.006）当尺子给她定到 +0.007，结果脚陷进地里 —— 说明两套骨架
## 的「Foot 到鞋底」距离并不相等。所以这次不推、直接拍：
##   地上摆一条**品红色标线**（y ≈ 0），相机侧视，看图里鞋底和标线谁高谁低。
const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_lift"
## 候选抬脚值（模型根节点的 y）
const LIFTS := [-0.043, 0.000, 0.060, 0.120, 0.180, 0.240]


func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, path: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_ABS)
	root.size = Vector2i(480, 480)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false

	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk == null:
		print("[错误] 没有 ClerkSerika")
		quit(1)
		return
	# 她的模型是第一个子节点（`_build_model()` 里 add_child(model)）
	var model: Node3D = null
	for c in clerk.get_children():
		if c is Node3D and not (c is CollisionObject3D):
			model = c as Node3D
			break
	if model == null:
		print("[错误] 找不到模型节点")
		quit(1)
		return
	# ⚠️ 必须先把人挪到**空地**再拍：
	#    她本来站在柜台（x 31.84~32.56）和东墙内表面（x 33.75）之间，只有 1.19 m 空当，
	#    相机根本塞不进去。第一版把相机放在 x = 33.16 + 2.30 = 35.46 ——
	#    那已经在商店东墙（33.90）外面了，六张图全是「商店外墙 + 地面」，一个人都看不见。
	#    抬脚值是模型自己的属性，在哪儿量都一样。
	clerk.global_position = Vector3(28.0, 0.0, 6.0)
	for _f in 10:
		await process_frame
	var base := clerk.global_position
	print("把芹香挪到空地 %s；模型当前 y = %.3f" % [str(base), model.position.y])

	# 地面标线：品红薄板，顶面在 y = 0.000 / 0.002，放在她脚前 0.30 m
	var mark := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 0.004, 0.06)
	mark.mesh = bm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1.0, 0.0, 0.85)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.0, 0.85)
	mm.emission_energy_multiplier = 1.2
	mark.material_override = mm
	mark.position = Vector3(base.x, 0.002, base.z + 0.30)
	game.add_child(mark)

	# 侧视相机：低机位、贴地平视，能看到鞋底和标线的关系
	var cam := Camera3D.new()
	cam.fov = 26.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)
	# 侧视：从 +X 侧 2.6 m、y=0.30 平视脚部；fov 收窄减小透视畸变
	cam.fov = 22.0
	cam.global_position = Vector3(base.x + 2.60, 0.30, base.z + 0.05)
	cam.look_at(Vector3(base.x, 0.14, base.z + 0.05), Vector3.UP)

	for lift in LIFTS:
		var lf: float = lift
		model.position.y = lf
		await process_frame
		await process_frame
		var nm := "lift_%+.3f" % lf
		await _shot(cam, "%s/%s.png" % [OUT_ABS, nm])
		print("  拍好 %s" % nm)

	print("[截图] %s" % OUT_ABS)
	quit(0)
