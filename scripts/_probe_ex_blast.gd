extends SceneTree
## 出图：机甲 EX 的「蓄力 → 超大光团 → 收细成线」（照碧蓝档案「临战」阿比·埃）。
##
##   godot --path . --script res://scripts/_probe_ex_blast.gd -- --no-capture
##
## 用户 2026-11-11 给了 8 张参考图：
##   图 3/4/5 = EX 蓄力（一圈圈光环涨大）
##   图 6/7/8 = EX 技能（枪口**一开始超大**，然后收细成一条线）
##
## 本探针按时间轴连拍，正好覆盖三个阶段，出图到 `_arisu_captures/_ex_blast/`：
##   charge_a / charge_b      蓄力
##   fire_huge                刚发射（枪口最大那一刻）★ 看的就是这张
##   fire_narrow              收细之后
##   fire_tail                结束前
##
## ⚠️ 侧向机位（垂直炮口）才看得见「柱子」；顺着炮口看必然缩成同心圆。
## ⚠️ 幕外窗口 + --no-capture，不抢用户前台（AGENTS.md 硬要求）。

const OffWin := preload("res://scripts/offscreen_window.gd")
const MechState := preload("res://scripts/mech_state.gd")
const CostGauge := preload("res://scripts/cost_gauge.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_ex_blast"

var _out_abs := ""


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[blast] 缺 --no-capture")
		quit(2)
		return
	_run.call_deferred()


func _dump(ex: Node, tag: String) -> void:
	var fx := ex.get_node_or_null("ExFx")
	if fx == null:
		print("[blast %s] 没有 ExFx" % tag)
		return
	var names: Array[String] = []
	for c in fx.get_children():
		names.append(String(c.name))
	print("[blast %s] ExFx 子节点 = %s" % [tag, ", ".join(names)])
	# 光柱每层枪口端半径（看「收细」有没有真的在动）
	for c in fx.get_children():
		var h := c as Node3D
		if h == null or not String(h.name).begins_with("RailBeam"):
			continue
		var parts: Array[String] = []
		for mi in h.get_children():
			var m := mi as MeshInstance3D
			if m == null:
				continue
			var cm := m.mesh as CylinderMesh
			if cm != null:
				parts.append("%.2f→%.2f" % [cm.bottom_radius, cm.top_radius])
		print("[blast %s]   %s 枪口→远端半径 %s" % [tag, h.name, " / ".join(parts)])


func _run() -> void:
	_out_abs = OUT_DIR
	DirAccess.make_dir_recursive_absolute(_out_abs)
	await OffWin.apply(self, Vector2i(1280, 720))
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[blast] 窗口没挪到屏幕外：%s" % str(safe0[1]))
		quit(2)
		return

	# ── 最小场景 ──
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.47, 0.52)
	# ⚠️ 和**游戏里一致**的 glow：`game.tscn` 的 glow_intensity 只有 0.25
	#    （为了灯管/室内不过曝压低的）。探针第一版完全没开 glow，
	#    所以照片上 FX 一片死平 —— 图的观感骗了本喵，必须按游戏值复现。
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.25
	env.environment.glow_strength = 1.0
	env.environment.glow_bloom = 0.0
	env.environment.glow_hdr_threshold = 1.0
	env.environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	world.add_child(env)

	var ground := StaticBody3D.new()
	ground.position = Vector3(0, -0.5, 0)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	col.shape = box
	ground.add_child(col)
	var gmesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	gmesh.mesh = pm
	gmesh.material_override = StandardMaterial3D.new()
	(gmesh.material_override as StandardMaterial3D).albedo_color = Color(0.18, 0.20, 0.24)
	ground.add_child(gmesh)
	world.add_child(ground)

	MechState.set_carrier_for_test(true)
	var player := PlayerScene.instantiate() as CharacterBody3D
	world.add_child(player)
	player.global_position = Vector3(0, 0.3, 0)
	for _i in 20:
		await process_frame

	# `--form=normal` = 普通爱丽丝（不近机甲形态），用来验激光球那条线
	var want_normal := OS.get_cmdline_user_args().has("--form=normal")
	var cf = player.get_node_or_null("Arisu/CarrierForm")
	if cf == null:
		push_error("[blast] 没有 CarrierForm")
		quit(1)
		return
	if not want_normal:
		if not cf.call("set_form", true):
			push_error("[blast] 进不了机甲形态")
			quit(1)
			return
		for _i in 40:
			await process_frame
	print("[blast] 形态 = %s" % ("机甲" if not want_normal else "普通"))

	var ex := player.get_node_or_null("ExSystem")
	if ex == null:
		push_error("[blast] 没有 ExSystem")
		quit(1)
		return

	# 相机先摆一次，逼 camera_forward() 指向 -Z
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.05
	cam.far = 4000.0
	world.add_child(cam)
	cam.make_current()
	for _i in 20:
		cam.look_at_from_position(Vector3(0.0, 4.0, 30.0), Vector3(0.0, 1.2, -80.0), Vector3.UP)
		await process_frame
	print("[blast] camera_forward = %s" % str(player.call("camera_forward")))

	# 机位：`side` 垂直于炮口、把**爱丽丝和光柱同框**（看向玩家与光柱中点）；
	# `tq` 斜后方，接近参考图视角。
	# ⚠️ 第一版两个机位都只看向远处 z=−24/−40，爱丽丝被枪口那团大光挡住/出画，
	#    看不出比例关系 —— 改成看向 y≈1.6 的腰部高度。
	var aim := Vector3(0.0, 1.8, -3.0)
	var cams := {
		"side": [Vector3(26.0, 5.0, 7.0), aim],
		"tq": [Vector3(-16.0, 8.0, 14.0), aim],
	}

	CostGauge.set_cost_for_test(10.0)
	ex.call("feed_key", KEY_E)
	var fired := bool(ex.call("feed_key", KEY_X))
	print("[blast] 触发 = %s" % fired)
	if not fired:
		quit(1)
		return

	var t0 := Time.get_ticks_msec()
	# 时间轴（ms）
	#   机甲：蓄力 0~550、发射 550~1450（枪口收缩发生在前 450 ms）
	#   普通：蓄力 0~420、光球飞行 ~42 m/s，抓蓄力 + 飞行 + 命中
	var marks := [
		{"t": 300, "name": "1_charge_a"},
		{"t": 500, "name": "2_charge_b"},
		{"t": 600, "name": "3_fire_huge"},
		{"t": 780, "name": "4_fire_narrow"},
		{"t": 1100, "name": "5_fire_steady"},
	]
	if want_normal:
		marks = [
			{"t": 200, "name": "1_charge_a"},
			{"t": 380, "name": "2_charge_b"},
			{"t": 460, "name": "3_orb_out"},
			{"t": 620, "name": "4_orb_fly"},
			{"t": 900, "name": "5_orb_far"},
		]
	for mk in marks:
		while Time.get_ticks_msec() - t0 < int(mk["t"]):
			await process_frame
		_dump(ex, String(mk["name"]))
		for key in cams.keys():
			var pair: Array = cams[key]
			cam.look_at_from_position(pair[0], pair[1], Vector3.UP)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				"%s/%s_%s.png" % [_out_abs, String(mk["name"]), key])
	print("[blast] 出图完成 → %s" % _out_abs)
	quit(0)
