extends SceneTree
## 探针：同一个机位、同一帧画面，**只改阳光的阴影参数**，拍两张对比。
## 用户报「感觉阴影非常不自然」——先别猜，把当前参数和调过参数的两张图摆在一起看。
##
## 用法：godot --path <工程> --script res://scripts/_probe_shadow_shot.gd
## 输出：_arisu_captures/_shadow/{before,after}.png

const OUT := "_arisu_captures/_shadow"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1100, 620)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(60)

	var sun := game.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		print("!! 场景里没有 Sun")
		quit(1)
		return
	# 光真正照的方向是 −basis.z
	var dir := -sun.global_transform.basis.z
	print("[shadow] 光方向 %s（y 为负才是从天上往下照）" % str(dir.snappedf(0.01)))
	print("[shadow] 当前：energy=%.2f  max_dist=%.0f  blur=%.2f  normal_bias=%.2f  bias=%.3f  angular=%.2f°" % [
		sun.light_energy, sun.directional_shadow_max_distance, sun.shadow_blur,
		sun.shadow_normal_bias, sun.shadow_bias, sun.light_angular_distance])

	var player := game.get_node_or_null("Player") as Node3D
	var p := player.global_position if player else Vector3.ZERO
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	cam.far = 200.0
	root.add_child(cam)
	cam.make_current()

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out)

	# 侧后方 4 m、高 1.5 m 俯视：阴影落在地面上的范围全在画面里
	var from := p + Vector3(3.0, 1.5, 3.6)
	await _shoot(cam, from, p + Vector3(0, 0.6, 0), out.path_join("before.png"))

	# ── 调参：软的、贴脚的、别拉太远 ──
	sun.light_angular_distance = 1.6           # 1.6° 的角直径 → PCSS 软阴影
	sun.directional_shadow_max_distance = 28.0 # 60 m 太远：同样 4096 张 shadow map 摊到 60 m，
	                                           # 一个 texel 就是 1.5 cm，影子会「飘」离脚
	sun.shadow_normal_bias = 0.9               # 默认 2.0 会把影子推离物体（peter-panning）
	sun.shadow_bias = 0.03
	sun.shadow_blur = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	print("[shadow] 调整后：max_dist=%.0f  normal_bias=%.2f  angular=%.1f°  4 段 PSSM + 混合" % [
		sun.directional_shadow_max_distance, sun.shadow_normal_bias, sun.light_angular_distance])
	await _wait(6)
	await _shoot(cam, from, p + Vector3(0, 0.6, 0), out.path_join("after.png"))
	print("[shadow] 输出 %s" % out)
	quit(0)


func _shoot(cam: Camera3D, from: Vector3, at: Vector3, file: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await _wait(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("  [img] %s" % file)


func _wait(frames: int) -> void:
	for _i in frames:
		await process_frame
