extends SceneTree
## 探针：同一个机位、同一帧，只改「阴影质量」三档（低 / 中 / 高），各拍一张。
##
## 用户 2026-10-21：「阴影怎么感觉高质量比低质量还难看一点点」——
## 先前的实现只改 `directional_shadow_max_distance`（低 40 / 中 60 / 高 120），
## 阴影图固定 4096²，于是越高档 texel 越粗。改完之后用这三张图验收：
## **「高」的边必须是柔和的半影（PCSS），而不是更粗的锯齿。**
##
## 机位选在**商店地板上**（平台外面、头顶没有 609 的代理天花板），
## 阳光能直接打到地面，影子最干净。
##
## 用法：godot --path <工程> --script res://scripts/_probe_shadow_levels.gd -- --splat=off
## 输出：`_arisu_captures/_shadow/level1_low.png` / level2_mid / level3_high

const OUT := "_shadow"
const LEVELS := [[1, "level1_low.png"], [2, "level2_mid.png"], [3, "level3_high.png"]]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 30:
		await process_frame
	paused = false
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")
	var hud := game.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false

	# 玩家挪到商店地板上，朝东站着（他的影子会落在地砖上）
	var player := game.get_node_or_null("Player") as Node3D
	if player != null:
		player.global_position = Vector3(24.0, 0.15, -14.0)
		player.rotation.y = -PI * 0.5

	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 300.0
	root.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(28.0, 2.2, -10.6)
	cam.look_at(Vector3(23.5, 0.15, -14.6), Vector3.UP)

	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)

	var sun: DirectionalLight3D = null
	for n in game.find_children("*", "DirectionalLight3D", true, false):
		sun = n as DirectionalLight3D
		break

	for lv in LEVELS:
		GameSettings.set_value("shadow_quality", float(lv[0]))
		for _i in 14:
			await process_frame
		if sun != null:
			print("[阴影] %-5s 远裁 %5.0f m  angular %.2f°  blur %.2f  normal_bias %.2f  bias %.3f  %s" % [
				GameSettings.value_text("shadow_quality", float(lv[0])),
				sun.directional_shadow_max_distance, sun.light_angular_distance,
				sun.shadow_blur, sun.shadow_normal_bias, sun.shadow_bias,
				"4 段混合" if sun.directional_shadow_blend_splits else "无混合"])
		await _shot(out_dir.path_join(lv[1]))

	print("\n出图：%s" % out_dir)
	quit(0)


func _shot(path: String) -> void:
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	for _i in 6:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("[shot] %s" % path.get_file())
