extends SceneTree
## 出图：房顶 5090（放大 3 倍）/ 三级台阶 / 更密的牢笼 / 红圈天降 / 压扁。
##
## 用法（**要窗口，不能 --headless**）：
##   godot --path <工程> --script res://scripts/_probe_roof_shots.gd -- --splat=off --bosses=off
## 输出：…/_arisu_captures/_trapshots/*.png

const OUT_SUB := "_trapshots"

var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(40)
	var p := game.get_node_or_null("Player") as Player
	var pk := game.get_node_or_null("Parkour") as Parkour
	pk.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(out)

	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.64, 0.66, 0.78)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(1, 1, 1)
	we.environment.ambient_light_energy = 1.3
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	sun.light_energy = 1.4
	root.add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.05
	_cam.far = 900.0
	root.add_child(_cam)
	_cam.make_current()

	var shed := pk.get_node_or_null("Island/Props/Shed") as Node3D
	var pad := pk.get_node_or_null("Island/Props/ReturnPad") as Node3D
	var island := pk.get_node("Island") as Node3D
	var mid := island.global_position + Vector3(0.0, 0.62, 0.0)
	var c := shed.global_position
	await _shot(out, "1_roof_gpu", c + Vector3(5.0, 3.6, -6.2), c + Vector3(-0.2, 2.7, 0.2))
	await _shot(out, "2_roof_side", c + Vector3(-8.0, 2.2, -4.0), c + Vector3(-0.8, 2.2, 0.4))
	await _shot(out, "3_steps", c + Vector3(-7.4, 2.0, 3.6), c + Vector3(-2.2, 1.0, -0.2))

	# 陷阱：牢笼 + 倭瓜优香
	pk.call("trap_sequence")
	await _wait_ms(1100)
	await _shot(out, "4_cage", pad.global_position + Vector3(7.0, 3.5, -6.0),
		pad.global_position + Vector3(0, 1.5, 0))
	# 把人放到岛中央，让它出招（不然不在攻击范围）
	p.global_position = mid
	p.velocity = Vector3.ZERO
	var boss: Boss = null
	for n in game.get_children():
		if n is Boss and String(n.name).to_lower().contains("squash"):
			boss = n
	if boss == null:
		print("!! 没有倭瓜优香")
		quit(1)
		return
	# 压扁 / 天降：跟着它自己的动作拍（不手动改状态）
	var mo := boss.get_node_or_null("ObjModel") as Node3D
	var base_s := mo.scale.y if mo != null else 1.0
	var shot_squash := false
	var shot_slam := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000 and not (shot_squash and shot_slam):
		await process_frame
		if mo != null and not shot_squash and mo.scale.y < base_s * 0.55:
			shot_squash = true
			await _shot(out, "5_squash", boss.global_position + Vector3(4.6, 1.6, -3.8),
				boss.global_position + Vector3(0, 0.5, 0))
		if not shot_slam and bool(boss.call("mark_visible")):
			shot_slam = true
			var mp := (boss.get_node("SlamMark") as Node3D).global_position
			await _shot(out, "6_slam", mp + Vector3(9.0, 8.0, 9.0), mp + Vector3(0, 3.2, 0))
	quit(0)


func _wait(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _wait_ms(ms: int) -> void:
	await _wait(ms)


func _shot(out: String, name: String, pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("[shots] %s ← %s" % [name, str(pos.snappedf(0.1))])
