extends SceneTree
## EX 轨道炮到底有没有「光柱」？从**侧面**拍，别顺着炮口看。
##
## 用户报：「机甲状态的 ex 技能看起来像给自己加了圆圈光环，都看不见打出去的光柱了」。
##
## 顺着炮口看，一根圆柱必然缩成一个圆 —— 这本身不能证明光柱丢了。
## 所以这里：
##   ① 打印每根炮的 `dir` / 圆柱缩放（`reach` 被近距离物体截断就会变成扁盘）
##   ② 侧向架相机连拍，看它到底是不是一根柱子
##
## ⚠️ 为什么不用 `next_level.tscn`：2026-11-11 另一个会话正在改 `boss.gd`
##    （按骨片受击盒 → 按骨变换），工作区里是半成品、编译不过，连带
##    `trex_yuuka_boss.gd` / `next_level.gd` 全挂。本探针只搭最小场景，不受影响。
##
##   _tools/run_shot.sh res://scripts/_probe_ex_rail.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
## ⚠️ `--script` 模式下解析不到全局类名，必须 preload（AGENTS.md 硬要求）
const MechState := preload("res://scripts/mech_state.gd")
const CostGauge := preload("res://scripts/cost_gauge.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_ex_rail"


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[ex] 缺 --no-capture")
		quit(2)
		return
	_run.call_deferred()


func _dump_beams(ex: Node, tag: String) -> void:
	var fx := ex.get_node_or_null("ExFx")
	if fx == null:
		print("[ex %s] 没有 ExFx" % tag)
		return
	print("[ex %s] ExFx 子节点 %d" % [tag, fx.get_child_count()])
	for c in fx.get_children():
		var holder := c as Node3D
		if holder == null:
			continue
		var aabb := AABB()
		var first := true
		var scale_s := "-"
		for mi in holder.get_children():
			var m := mi as MeshInstance3D
			if m == null:
				continue
			scale_s = str(m.scale)
			var b: AABB = m.global_transform * m.get_aabb()
			if first:
				aabb = b
				first = false
			else:
				aabb = aabb.merge(b)
		print("[ex %s]   「%s」pos=%s child_scale=%s  世界盒 size=%s"
			% [tag, holder.name, str(holder.global_position.round()), scale_s,
			str(aabb.size.snappedf(0.01))])


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[ex] 窗口没挪到屏幕外：%s" % str(safe0[1]))
		quit(2)
		return

	# ── 最小场景：一块 200×200 的地 + 玩家 ──
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.06, 0.07, 0.10)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
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
	(gmesh.material_override as StandardMaterial3D).albedo_color = Color(0.20, 0.22, 0.26)
	ground.add_child(gmesh)
	world.add_child(ground)

	MechState.set_carrier_for_test(true)
	var player := PlayerScene.instantiate() as CharacterBody3D
	world.add_child(player)
	player.global_position = Vector3(0, 0.3, 0)
	for _i in 20:
		await process_frame

	var cf = player.get_node_or_null("Arisu/CarrierForm")
	if cf == null or not cf.call("set_form", true):
		push_error("[ex] 进不了机甲形态")
		quit(1)
		return
	for _i in 40:
		await process_frame
	print("[ex] 机甲形态 = %s" % str(cf.call("is_on")))

	var ex := player.get_node_or_null("ExSystem")
	if ex == null:
		push_error("[ex] Player 下没有 ExSystem")
		quit(1)
		return

	# ── 相机：站在玩家**东侧**、看向 -Z，逼 camera_forward() 指向 -Z ──
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.05
	cam.far = 4000.0
	world.add_child(cam)
	cam.make_current()
	var look_ahead := Vector3(0.0, 1.2, -80.0)
	for _i in 20:
		cam.look_at_from_position(Vector3(0.0, 4.0, 30.0), look_ahead, Vector3.UP)
		await process_frame
	print("[ex] camera_forward = %s" % str(player.call("camera_forward")))

	# 侧向机位（垂直于 -Z，能看见整根柱子）
	var side_pos := Vector3(45.0, 6.0, -18.0)
	var side_look := Vector3(0.0, 1.2, -22.0)

	# ── 触发 EX（E → X）──
	# `feed_key(KEY_E)` 会先查 `can_fire()`，COST 不够就直接返回 false 不进序列，
	# 所以必须先给满 COST（最小场景里是 0）。
	CostGauge.set_cost_for_test(10.0)
	print("[ex] COST = %d" % CostGauge.display())
	ex.call("feed_key", KEY_E)
	var fired := bool(ex.call("feed_key", KEY_X))
	print("[ex] 触发 = %s" % str(fired))

	# 轨道炮只活 0.9 s：前 3 帧抓「刚发射」，再抓两帧
	var t0 := Time.get_ticks_msec()
	var shots := 0
	var marks := [30, 180, 350, 550]
	for mk in marks:
		while Time.get_ticks_msec() - t0 < int(mk):
			cam.look_at_from_position(side_pos, side_look, Vector3.UP)
			await process_frame
		cam.look_at_from_position(side_pos, side_look, Vector3.UP)
		_dump_beams(ex, "t=%dms" % mk)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := "%s/side_%d.png" % [OUT_DIR, shots]
		var err := img.save_png(path)
		var step := 8
		var bright := 0
		var nn := 0
		for y in range(0, img.get_height(), step):
			for x in range(0, img.get_width(), step):
				var c := img.get_pixel(x, y)
				if c.r > 0.85 and c.g > 0.85 and c.b > 0.85:
					bright += 1
				nn += 1
		print("[ex] 侧拍 %d（t≈%dms）err=%d 亮白像素 %.1f%%  %s"
			% [shots, mk, err, 100.0 * float(bright) / maxf(1.0, float(nn)), path])
		shots += 1

	print("[ex] 完")
	quit(0)
