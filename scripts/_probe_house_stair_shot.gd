extends SceneTree
## 出图：商店边那栋蒙德里安小屋（game.tscn 里的 MondrianHouse）楼梯。
##   _tools/run_shot.sh res://scripts/_probe_house_stair_shot.gd -- --splat=off --story=off
## 用玩家自己的第三人称相机，复现「楼梯被堵」时的视角。

func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(player: CharacterBody3D, pos: Vector3, yaw: float, pitch: float, name: String) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.set("_yaw", yaw)
	player.set("_pitch", pitch)
	await _wait(24)
	root.get_texture().get_image().save_png("res://_arisu_captures/_stairs/%s.png" % name)
	var cam := player.get_node("CameraRig/SpringArm3D/Camera3D") as Camera3D
	print("[stair] %s player=%s cam=%s" % [name, str(player.global_position.snappedf(0.01)),
		str(cam.global_position.snappedf(0.01)) if cam != null else "-"])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_arisu_captures/_stairs"))
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(60)
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var player := game.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		print("[stair] 没找到 Player")
		quit(1)
		return

	# 小屋根节点 transform = (27.3, 0, 13.5)；下面都是世界坐标
	const O := Vector3(27.3, 0.0, 13.5)
	# 楼梯在西侧 local x=-6.95，local z 从 -4.30 爬到 +2.70
	await _shot(player, O + Vector3(-6.95, 0.25, -5.35), PI, -0.12, "01_bottom")
	await _shot(player, O + Vector3(-6.95, 2.20, -0.80), PI, -0.10, "02_mid")
	await _shot(player, O + Vector3(-6.95, 4.25, 2.45), PI, -0.12, "03_top")
	await _shot(player, O + Vector3(-6.95, 4.25, 3.40), 0.0, -0.05, "04_top_look_north")
	await _shot(player, O + Vector3(-6.95, 0.25, 1.20), 0.0, 1.05, "05_under_ramp_up")
	await _shot(player, O + Vector3(-2.00, 0.25, 0.80), PI * 0.5, 0.55, "06_l1_look_west_up")
	await _shot(player, O + Vector3(-6.95, 4.30, 2.20), PI, -0.25, "07_top_look_south_slab")
	await _shot(player, O + Vector3(-5.00, 0.25, 1.00), PI * 0.5, 0.20, "08_side_from_east")
	await _shot(player, O + Vector3(-6.95, 0.25, 3.90), 0.0, 0.25, "09_south_end_wall")
	await _shot(player, O + Vector3(-6.50, 0.25, -5.10), PI, -0.10, "10_entrance_east_lane")

	# 实际爬一遍：从楼梯底按前，看能不能到二层
	player.global_position = O + Vector3(-6.95, 0.25, -5.35)
	player.velocity = Vector3.ZERO
	player.set("_yaw", PI)
	player.set("_pitch", -0.1)
	await _wait(24)
	Input.action_press("move_forward")
	var top := 0.0
	for _f in 420:
		await process_frame
		top = maxf(top, player.global_position.y)
	Input.action_release("move_forward")
	await _wait(20)
	print("[stair] 爬坡 end=(%.2f, %.2f, %.2f) 最高 y=%.2f（二层 4.20）" % [
		player.global_position.x, player.global_position.y, player.global_position.z, top])
	quit(0)
