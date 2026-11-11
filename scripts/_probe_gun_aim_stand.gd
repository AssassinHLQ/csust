extends SceneTree
## 出图：站定开火时，**把枪掰向准星**之后两只手会不会离开枪？
##
## 背景：用户 2026-11-11 报「子弹锐角拐弯」。根因是站桩开火动作把枪抱在胸前
## （枪管与准星差 70~98°），子弹从枪口飞到准星就得拐弯。
## 把枪掰直能消掉拐弯，但 `_aim_gun()` 里 2026-10 的注释说那样「两只手会离开枪」。
## 这个探针就是去**看一眼到底离不离**，用第三人称相机拍左右两版对比。
##
##   _tools/run_shot.sh res://scripts/_probe_gun_aim_stand.gd -- --no-capture --splat=off
## 输出：
##   _arisu_captures/_gun_aim_off.png   不掰（现状）
##   _arisu_captures/_gun_aim_on.png    掰向准星

const OffWin := preload("res://scripts/offscreen_window.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	for _i in 3:
		await process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	for _i in 40:
		await process_frame

	var player := game.get_node_or_null("Player") as Node3D
	var weapon := game.get_node_or_null("Player/Weapon")
	var drv: Node = game.find_child("AnimDriver", true, false)
	if player == null or weapon == null or drv == null:
		print("❌ 缺 Player / Weapon / AnimDriver")
		quit()
		return

	# 侧前方相机：按**角色朝向**算，别用世界轴硬编码（角色初始朝向不是 +Z）
	var cam := Camera3D.new()
	cam.fov = 45.0
	game.add_child(cam)
	var chest: Vector3 = player.global_position + Vector3(0, 1.05, 0)
	var f: Vector3 = player.call("camera_forward")
	f.y = 0.0
	if f.length_squared() < 0.001:
		f = Vector3.FORWARD
	f = f.normalized()
	var right := f.cross(Vector3.UP).normalized()
	var eye := chest + right * 1.7 + f * 1.1 + Vector3.UP * 0.15
	cam.look_at_from_position(eye, chest + f * 0.25, Vector3.UP)
	cam.make_current()
	for _i in 5:
		await process_frame

	await _one_round(drv, weapon, false, "_gun_aim_off.png")
	await _one_round(drv, weapon, true, "_gun_aim_on.png")

	game.queue_free()
	await process_frame
	quit()


func _one_round(drv: Node, weapon: Node, aim_on: bool, file_name: String) -> void:
	drv.set("aim_while_standing", aim_on)
	# 连打几发让 FIRE 状态维持住（单发 0.4 s，会自己回 LOCOMOTION）
	for _i in 30:
		weapon.call("shoot")
		await process_frame
	print("[探针] aim_while_standing=%s  枪管偏离准星 %.1f°，实际掰了 %.1f°"
		% [str(aim_on), float(drv.get("gun_aim_deg")), float(drv.get("gun_aim_applied_deg"))])
	await _save(file_name)


func _save(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("⚠️ headless 拿不到渲染纹理，跳过出图")
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(file_name)
	img.save_png(out)
	print("[截图] %s" % out)
