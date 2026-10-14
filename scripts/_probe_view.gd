extends SceneTree
## 视角诊断工具：
##   1) 打印相机视线、角色朝向、靶子方位的真实数值；
##   2) 从角色四周各渲一张图，用来**肉眼**确定「model_root.rotation.y = 0 时脸朝哪」。
##
## §1.4.1 那张「相机视线 = -(sin(_yaw), cos(_yaw))」的结论就是这个工具量出来的。
##
## 用法（必须真实渲染，不能 --headless）：
##   godot --path <工程> --script res://scripts/_probe_view.gd
## 输出：…/_arisu_captures/_view/*.png

const OUT_SUB := "_view"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await _wait(30)

	var player: Player = game.get_node("Player")
	var cam: Camera3D = player.cam
	var hud: Node = game.get_node_or_null("HUD")

	var out := ProjectSettings.globalize_path("res://") \
		.path_join("..").simplify_path().path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(out)

	# ---------- A. 出生画面（用游戏自己的相机）----------
	print("========== A. 出生状态 ==========")
	print("  player.global_position = %s" % str(player.global_position.snappedf(0.01)))
	print("  _yaw = %.4f   rig.rotation.y = %.4f" % [player._yaw, player.rig.rotation.y])
	print("  _facing_yaw = %.4f   model_root.rotation.y = %.4f" % [
		player._facing_yaw, player.model_root.rotation.y])
	print("  cam.global_position = %s" % str(cam.global_position.snappedf(0.01)))
	print("  cam 在 rig 本地坐标 = %s" % str(player.rig.to_local(cam.global_position).snappedf(0.01)))
	print("  camera_forward()  = %s" % str(player.camera_forward().snappedf(0.01)))
	print("  cam.basis.z       = %s" % str(cam.global_transform.basis.z.snappedf(0.01)))
	print("  (sin(_yaw),cos(_yaw))   = %s" % str(_yawvec(player._yaw).snappedf(0.01)))
	print("  -(sin(_yaw),cos(_yaw))  = %s   ← 应等于 camera_forward()" % str((-_yawvec(player._yaw)).snappedf(0.01)))
	print("  (sin(f),cos(f)) [脸朝向] = %s" % str(_yawvec(player._facing_yaw).snappedf(0.01)))
	print("  角色→相机 = %s" % str(_flat(cam.global_position - player.global_position).normalized().snappedf(0.01)))

	print("  --- 靶子/柱子相对角色的方位（-Z 是场地深处）---")
	for t in game.get_children():
		if t is Target:
			var d := _flat(t.global_position - player.global_position)
			var front := d.normalized().dot(player.camera_forward())
			var sp := cam.unproject_position(t.global_position + Vector3.UP * 0.5)
			var vp := root.get_visible_rect().size
			var on := sp.x >= 0.0 and sp.x <= vp.x and sp.y >= 0.0 and sp.y <= vp.y
			print("    %-8s 世界 %s  距离 %.1f  与视线点积 %+.2f  屏幕 %s  在画面内 %s" % [
				t.name, str(t.global_position.snappedf(0.1)), d.length(), front,
				str(sp.snappedf(1.0)), str(on)])
	print("  ⚠️ 「在画面内」这一列对相机背后的点是**假**的：unproject_position 会回绕，")
	print("     只有「与视线点积」> 0 才真的在前方。")

	await _save(out.path_join("00_spawn.png"))

	# ---------- B. 冻结角色，从四个方位看图 ----------
	hud.visible = false
	player.set_physics_process(false)
	player.model_root.rotation.y = 0.0
	await _wait(4)

	var eye := Camera3D.new()
	eye.fov = 50.0
	root.add_child(eye)
	eye.make_current()

	var center := player.global_position + Vector3.UP * 1.05
	var d := 2.4
	var spots := {
		"10_from_pZ": Vector3(0, 0.45, d),
		"11_from_nZ": Vector3(0, 0.45, -d),
		"12_from_pX": Vector3(d, 0.45, 0),
		"13_from_nX": Vector3(-d, 0.45, 0),
	}
	print("\n========== B. model_root.rotation.y = 0 时，四方位渲图 ==========")
	for key in spots:
		eye.global_position = center + (spots[key] as Vector3)
		eye.look_at(center, Vector3.UP)
		await _wait(3)
		await _save(out.path_join("%s.png" % key))
		print("  %s  相机位于 %s" % [key, str((spots[key] as Vector3).snappedf(0.01))])

	# ---------- C. 角色转 180° 再看一遍 ----------
	player.model_root.rotation.y = PI
	await _wait(4)
	print("\n========== C. model_root.rotation.y = PI 时，正反两张 ==========")
	for key in ["20_rotPI_pZ", "21_rotPI_nZ"]:
		eye.global_position = center + (spots["10_from_pZ"] if key.ends_with("pZ") else spots["11_from_nZ"])
		eye.look_at(center, Vector3.UP)
		await _wait(3)
		await _save(out.path_join("%s.png" % key))
		print("  %s" % key)

	print("\n[probe] 图片输出目录：%s" % out)
	quit(0)


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var err := img.save_png(path)
	print("  [img] %s  err=%d" % [path, err])


func _yawvec(y: float) -> Vector3:
	return Vector3(sin(y), 0.0, cos(y))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
