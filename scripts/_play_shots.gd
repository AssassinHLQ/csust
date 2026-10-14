extends Node
## 玩法截图工具：程序化地让角色待机 / 走动 / 跑动 / 开镜 / 开火 / 换弹 / 蹲行 / 打靶，
## 每个状态渲一张图，顺便把关键数据打印出来。
##
## 用法：set ARISU_PLAY=1 运行 res://scenes/game.tscn
## 输出：…/_arisu_captures/_play/*.png

const OUT_SUB := "_play"


func _ready() -> void:
	if OS.get_environment("ARISU_PLAY") != "1":
		return
	_run.call_deferred()


func _run() -> void:
	var dir := _out_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var game := get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame

	var player: Player = game.get_node("Player")
	var weapon: Weapon = game.get_node("Player/Weapon")
	var driver: AnimDriver = game.get_node("Player/Arisu/Model/AnimDriver")

	player.aiming = false
	await _shot(dir, "01_idle", 20)

	Input.action_press("move_forward")
	await _shot(dir, "02_walk", 45)
	print("[play] 走动：速度 %.2f m/s  当前动画 %s" % [_hspeed(player), driver.current_clip()])

	Input.action_press("sprint")
	await _shot(dir, "03_run", 55)
	print("[play] 跑动：速度 %.2f m/s  当前动画 %s" % [_hspeed(player), driver.current_clip()])
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _wait(40)

	player._set_aiming(true)
	await _shot(dir, "04_aim", 35)
	print("[play] 开镜：FOV %.1f  距离 %.2f" % [player.cam.fov, player.spring.spring_length])

	var before := weapon.current_ammo
	weapon.shoot()
	await _shot(dir, "05_fire", 6)
	print("[play] 开火：弹药 %d 到 %d  状态 %s" % [before, weapon.current_ammo, driver.current_state_name()])

	for _i in 5:
		weapon._cooldown = 0.0
		weapon.shoot()
		await _wait(3)
	await _shot(dir, "06_burst", 1)
	print("[play] 连发后弹药 = %d" % weapon.current_ammo)

	player._set_aiming(false)
	weapon.try_reload()
	await _shot(dir, "07_reload", 12)

	await _wait(70)
	Input.action_press("crouch")
	Input.action_press("move_forward")
	await _shot(dir, "08_crouch", 40)
	print("[play] 蹲行：速度 %.2f m/s" % _hspeed(player))
	Input.action_release("crouch")
	Input.action_release("move_forward")
	await _wait(30)

	player.global_position = Vector3(6, 0.05, -4)
	player._yaw = 0.0
	player.rig.rotation.y = 0.0
	player._facing_yaw = player._yaw + PI
	player.model_root.rotation.y = player._yaw + PI
	player._pitch = -0.02
	await _wait(15)
	var target: Target = game.get_node("Target1")
	var hp0 := target.health
	weapon.current_ammo = weapon.magazine_size
	weapon.fire_interval = 0.0
	weapon.spread_hip = 0.0
	for _i in 4:
		weapon._cooldown = 0.0
		weapon.shoot()
		await _wait(4)
	await _shot(dir, "09_hit_target", 1)
	print("[play] 打靶：Target1 血量 %.0f 到 %.0f" % [hp0, target.health])

	print("[play] 完成")
	get_tree().quit(0)


func _hspeed(player: Player) -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _shot(dir: String, shot_name: String, settle_frames: int) -> void:
	await _wait(maxi(settle_frames, 1))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, shot_name])
	print("  [shot] ", shot_name)


func _wait(frames: int) -> void:
	for _i in maxi(frames, 1):
		await get_tree().process_frame


func _out_dir() -> String:
	var project_dir := ProjectSettings.globalize_path("res://")
	return project_dir.path_join("..").simplify_path().path_join("_arisu_captures").path_join(OUT_SUB)
