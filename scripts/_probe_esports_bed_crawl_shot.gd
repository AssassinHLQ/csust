extends SceneTree
## 出图：电竞房双层床下铺睡龛 · 蹲伏钻入（用户 2026-11-13「床为什么不能钻进去?要能进去的」）。
## 蹲伏（Ctrl）把胶囊缩到 0.8 m；床垫实测面 y=0.556、睡龛净高 0.875 m。
## 把玩家以蹲姿放进睡龛，拍两个机位：过道平视龛口、沿床列看一排龛口。
##   _tools/run_shot.sh res://scripts/_probe_esports_bed_crawl_shot.gd --splat=off --story=off

const OFFWIN := preload("res://scripts/offscreen_window.gd")
const OUT := "_arisu_captures/_esports_bed_crawl"
const MOUTH := Vector3(54.0, 0.7, 10.78)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFFWIN.apply(self)
	root.size = Vector2i(1280, 720)
	var level := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _f in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame
	var room := level.get_node_or_null("EsportsRoom") as Node3D
	var player := level.get("_player") as CharacterBody3D
	if room == null or player == null:
		print("!! 缺房间或玩家")
		quit(1)
		return
	room.visible = true
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	for c in level.find_children("Companion*", "Node3D", true, false):
		(c as Node3D).visible = false

	# 蹲姿放进第一个睡龛，等物理停靠
	Input.action_press("crouch")
	player.global_position = MOUTH
	player.velocity = Vector3.ZERO
	for _f in 60:
		await physics_frame
	var cap := (player.get_node("Collision") as CollisionShape3D).shape as CapsuleShape3D
	print("[probe] 蹲伏就位  脚底 y=%.3f  胶囊高 %.2f" % [player.global_position.y, cap.height])
	var lod := room.get_node_or_null("Lod")
	if lod != null:
		for c in lod.get_children():
			print("[probe] LOD %s visible=%s" % [c.name, str((c as Node3D).visible)])
	print("[probe] Low(Room) visible=%s" % str((room.get_node("Room") as Node3D).visible))
	var bedn := room.get_node_or_null("Room")
	if bedn != null:
		var n := 0
		for mi in bedn.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var bb: AABB = m.global_transform * m.mesh.get_aabb()
			if bb.has_point(Vector3(54.276, 1.476, 10.786)):
				n += 1
				print("[probe] 床网格 %s visible=%s aabb=%s" % [m.name, str(m.visible), str(bb)])
		print("[probe] 含床板中心的网格 %d 个" % n)

	var out := ProjectSettings.globalize_path("res://").path_join("..").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 3000.0
	root.add_child(cam)
	cam.make_current()
	await process_frame

	var shots := [
		# 过道内斜视龛口：低于端板底 0.981，从 -Z 侧看蹲在床垫上的人
		["niche", Vector3(53.78, 0.95, 10.2), Vector3(54.05, 0.9, 10.78)],
		# 外部机位：从房间 -X/-Z 角看整列床与蹲在第一个龛里的人
		["wide", Vector3(50.0, 1.6, 9.6), Vector3(54.3, 1.0, 12.5)],
		# 顶视调试：天花板下看人与床的相对位置（直下视 up 用 +Z，避免退化）
		["top", Vector3(54.0, 3.2, 10.78), Vector3(54.0, 0.5, 10.78), Vector3(0, 0, 1)],
	]
	for s in shots:
		var name: String = s[0]
		var eye: Vector3 = s[1]
		var look: Vector3 = s[2]
		var up := Vector3.UP
		if s.size() > 3:
			up = s[3]
		print("[probe] 拍 %s 前  玩家 %s  crouch=%s  scale.y=%.2f"
			% [name, str(player.global_position.snappedf(0.01)),
				str(player.crouching), player.get_node("Arisu").scale.y])
		cam.global_position = eye
		await process_frame
		cam.look_at(look, up)
		for _i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		if img != null:
			img.save_png(out.path_join("%s.png" % name))
		print("  %s 相机 %s" % [name, str(cam.global_position.snappedf(0.1))])

	print("[probe] 输出 %s" % out)
	quit(0)