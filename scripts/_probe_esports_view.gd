extends SceneTree
## 电竞房**室内取景**：定街机柜摆哪儿。
##
## ── 上一版的教训 ──
## ① `Camera3D` 在 Godot 4 **没有 `up` 属性**（只有 `look_at(target, up)` 的第二个参数）。
##    写 `cam.up = …` 会脚本报错、协程中断、`quit()` 再也不执行 ⇒ 进程永远挂着。
## ② 屋顶是**合并进 `M_材质_3` 的**（一个网格横跨 y 0.01~4.97），没法按网格藏掉；
##    所以俯视图改成「贴着天花板下方 + fov 120」硬拍。
##
## ── 已经量到的事实 ──
##   · 地面 y≈0.51（网格与碰撞一致）
##   · 房间世界范围 x 47.3~60.3、z 1.86~23.55
##   · 电竞桌一条长排：x 52.9~54.6、z 10.2~17.0，紧贴 x≈54.8 的隔断
##   · 上下铺 / 衣柜：x 47.2~50.0
##   · ⇒ 中间 **x 50~52.9** 是一条约 3 m 宽的走道
##
##   godot --path . --script res://scripts/_probe_esports_view.gd -- --no-capture --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "res://_tools/_tmp/esports_view"
const FLOOR_Y := 0.51
const EYE := 1.62
## 走道中线（上下铺与电竞桌之间）
const AISLE_X := 51.35


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await OFF.apply(self, Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var level := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _f in 140:
		await process_frame
	paused = false
	await _wait(20)
	var room := level.get_node_or_null("EsportsRoom") as Node3D
	if room == null:
		print("!! 无 EsportsRoom")
		quit(1)
		return
	room.visible = true
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	await _wait(50)

	var out := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 3000.0
	level.add_child(cam)
	cam.make_current()

	# ── ① 俯视平面图：贴着天花板下沿，fov 120 硬吃整间屋 ──
	cam.fov = 120.0
	cam.global_position = Vector3(53.27, 4.30, 13.26)
	await process_frame
	cam.look_at(Vector3(53.27, FLOOR_Y, 13.26), Vector3(0.0, 0.0, -1.0))
	for _f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(out.path_join("plan.png"))
		print("[view] plan.png（俯视，上=+Z 右=+X）")

	# ── ② 室内平视：走道前后、左右各一张 ──
	cam.fov = 78.0
	var shots: Array = [
		["aisle_n", Vector3(AISLE_X, FLOOR_Y + EYE, 21.0), Vector3(AISLE_X, FLOOR_Y + 1.2, 8.0)],
		["aisle_s", Vector3(AISLE_X, FLOOR_Y + EYE, 8.0), Vector3(AISLE_X, FLOOR_Y + 1.2, 21.0)],
		["to_desks", Vector3(AISLE_X, FLOOR_Y + EYE, 14.0), Vector3(56.5, FLOOR_Y + 1.0, 14.0)],
		["to_beds", Vector3(AISLE_X, FLOOR_Y + EYE, 14.0), Vector3(46.0, FLOOR_Y + 1.0, 14.0)],
		["end_north", Vector3(AISLE_X, FLOOR_Y + EYE, 4.0), Vector3(AISLE_X, FLOOR_Y + 1.2, 14.0)],
		["end_south", Vector3(AISLE_X, FLOOR_Y + EYE, 19.5), Vector3(AISLE_X, FLOOR_Y + 1.2, 9.0)],
	]
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	for s in shots:
		var tag: String = s[0]
		var eye: Vector3 = s[1]
		var look: Vector3 = s[2]
		cam.global_position = eye
		await process_frame
		cam.look_at(look, Vector3.UP)
		for _f in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var im := root.get_texture().get_image()
		if im != null:
			im.save_png(out.path_join("%s.png" % tag))
		# 同时把「正前方 4 m 内有没有东西」打出来，光看图不好估距离
		var q := PhysicsRayQueryParameters3D.create(eye, eye + (look - eye).normalized() * 4.0)
		var h := space.intersect_ray(q)
		print("[view] %-10s 眼睛 %s  前方 %s" % [tag, str(eye.snappedf(0.01)),
			"4 m 内无碰撞" if h.is_empty() else "%.2f m 处撞 %s" % [eye.distance_to(h["position"]), str(h.get("collider"))]])

	# ── ③ 走道地面净空扫描：给街机柜找一段前后左右都空的地方 ──
	print("\n======== 走道净空扫描（x=%.2f，z 每 1 m 一格，测四周 0.9 m 内有没有东西）========" % AISLE_X)
	var z := 3.0
	while z <= 22.0:
		var foot := Vector3(AISLE_X, FLOOR_Y + 0.9, z)
		var clear := true
		var worst := 99.0
		for i in 8:
			var a := TAU * float(i) / 8.0
			var d := Vector3(cos(a), 0.0, sin(a))
			var q := PhysicsRayQueryParameters3D.create(foot, foot + d * 0.9)
			var h := space.intersect_ray(q)
			if not h.is_empty():
				clear = false
				worst = minf(worst, foot.distance_to(h["position"]))
		print("  z %5.1f  %s%s" % [z, "✔ 四周 0.9 m 全空" if clear else "✘ 最近障碍 %.2f m" % worst, ""])
		z += 1.0

	print("[view] 输出目录 %s" % out)
	quit(0)
