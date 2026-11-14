extends SceneTree
## 电竞房**室内**测绘 + 出图。
##
## ── 为什么重测 ──
## `esports_room.tscn` 在 `game.tscn` 里挂着 `Transform3D(1.35375,0,0, 0,-1.5,0, 0,0,-1.35375, …)`，
## **Y 轴是 −1.5**。所以 GLB 里原来的「地板」（局部 y≈0）被翻到**上面**了，
## 原来的「天花板」（局部 y≈3.3~3.6）变成玩家真正踩的**地面**。
## 上一个探针拿局部 y=0 当脚下，于是把相机放到了屋顶外面（拍到了一块天花板）。
##
## 实测换算：world_y = 5.415 − 1.5 × local_y
##   · 局部 y=3.3（天花板面）→ 世界 0.465  ← **玩家站的地面**
##   · 局部 y=0.3（地板面）  → 世界 4.965  ← 头顶
##
## 这一版全部用**世界坐标**干活：在眼睛高度横扫一圈找墙，再把玩家真塞进房间拍图。
##
##   godot --path . --script res://scripts/_probe_esports_interior.gd -- --no-capture --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "res://_tools/_tmp/esports_interior"

## 房间世界 AABB（`_probe_esports_aisle.gd` 实测）：x 46.22~60.31、z 1.86~24.65
const ROOM_CENTER := Vector3(53.27, 0.0, 13.26)
const FLOOR_Y := 0.465
const EYE := 1.62


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
	for c in level.find_children("Companion*", "Node3D", true, false):
		(c as Node3D).visible = false
	await _wait(40)

	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state

	# ── ① 眼睛高度横扫 24 个方向，找墙在哪里 ──
	print("\n======== 眼高 y=%.2f 横扫找墙（中心 %s）========" % [FLOOR_Y + EYE, ROOM_CENTER])
	for i in 24:
		var a := TAU * float(i) / 24.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var from := Vector3(ROOM_CENTER.x, FLOOR_Y + EYE, ROOM_CENTER.z)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 14.0)
		var h := space.intersect_ray(q)
		var deg := rad_to_deg(a) - 90.0        # 换成「相对 +Z 朝向」的罗盘角
		if deg < -180.0:
			deg += 360.0
		if h.is_empty():
			print("  %7.1f°  14 m 内没墙（可能出到室外/门洞）" % deg)
		else:
			var d := from.distance_to(h["position"])
			print("  %7.1f°  墙在 %5.2f m（世界 %s）" % [deg, d, str((h["position"] as Vector3).snappedf(0.05))])

	# ── ② 脚下地面：在 5×5 网格上找可站的高度 ──
	print("\n======== 地面高度抽样（每 2 m 一格，向下 3 m 找第一个碰撞）========")
	var xs := [47.5, 49.5, 51.5, 53.5, 55.5, 57.5, 59.0]
	var zs := [3.5, 6.0, 8.5, 11.0, 13.5, 16.0, 18.5, 21.0, 23.0]
	var head := "   z\\x  "
	for x in xs:
		head += "%6.1f" % float(x)
	print(head)
	for z in zs:
		var line := "  %5.1f " % float(z)
		for x in xs:
			var from := Vector3(float(x), 3.0, float(z))
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -4.0, 0.0))
			var h := space.intersect_ray(q)
			if h.is_empty():
				line += "   -- "
			else:
				line += "%6.2f" % float(h["position"].y)
		print(line)

	# ── ③ 把玩家塞进房间，让物理把他放稳，再从他眼睛里拍 ──
	var player := level.get("_player") as CharacterBody3D
	if player == null:
		print("!! 没有 player")
		quit(1)
		return
	var spots := [
		["from_door", Vector3(53.27, 1.2, 22.0), Vector3(53.27, 1.0, 10.0)],
		["center", Vector3(53.27, 1.2, 13.0), Vector3(53.27, 1.0, 3.0)],
		["toward_door", Vector3(53.27, 1.2, 6.0), Vector3(53.27, 1.0, 22.0)],
		["west_wall", Vector3(48.0, 1.2, 13.0), Vector3(58.0, 1.0, 13.0)],
		["east_wall", Vector3(58.5, 1.2, 13.0), Vector3(48.0, 1.0, 13.0)],
	]
	var out := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	cam.far = 3000.0
	level.add_child(cam)
	cam.make_current()

	for s in spots:
		var tag: String = s[0]
		var at: Vector3 = s[1]
		var look: Vector3 = s[2]
		player.global_position = at
		player.velocity = Vector3.ZERO
		for _f in 45:
			await physics_frame
		var feet := player.global_position.y
		print("[room] %-12s 玩家落稳 脚底 y=%.3f  位置 %s"
			% [tag, feet, str(player.global_position.snappedf(0.01))])
		cam.global_position = Vector3(player.global_position.x, feet + EYE, player.global_position.z)
		await process_frame
		var d := look - cam.global_position
		if Vector2(d.x, d.z).length() < 0.2:
			cam.look_at(cam.global_position + Vector3(0.0, -0.6, -1.0), Vector3.UP)
		else:
			cam.look_at(Vector3(look.x, cam.global_position.y, look.z), Vector3.UP)
		for _f in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		if img != null:
			img.save_png(out.path_join("%s.png" % tag))
			print("[room]   出图 %s.png" % tag)

	print("[room] 输出目录 %s" % out)
	quit(0)
