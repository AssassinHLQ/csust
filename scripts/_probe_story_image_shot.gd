extends SceneTree
## 出图：买完电脑后「确认收货地址」那张活动室图，检查放大后有没有压到对话框。
##   _tools/run_shot.sh res://scripts/_probe_story_image_shot.gd
const OUT := "res://_arisu_captures/_sheets"


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var box := DialogueBox.new()
	root.add_child(box)
	await _wait(4)
	box.set_cps(100000.0)
	box.play_steps([
		{"kind": "image", "path": "res://assets/story/gamedev_room.jpg",
			"caption": "千禧年学院一年级游戏开发部活动室"},
	], "probe_image")
	await _wait(12)
	var panel := box.get("_image_panel") as Control
	var rect := panel.get_global_rect()
	var vp := root.get_visible_rect()
	var rootc := box.get("_root") as Control
	var img := box.get("_image_rect") as Control
	var cap := box.get("_image_caption") as Control
	print("[image-shot] panel local size=%s pos=%s global=%s offsets L%.1f R%.1f T%.1f B%.1f min=%s" % [
		str(panel.size), str(panel.position), str(rect),
		panel.offset_left, panel.offset_right, panel.offset_top, panel.offset_bottom,
		str(panel.get_combined_minimum_size())])
	print("[image-shot] img size=%s pos=%s global=%s" % [str(img.size), str(img.position), str(img.get_global_rect())])
	print("[image-shot] cap size=%s pos=%s global=%s" % [str(cap.size), str(cap.position), str(cap.get_global_rect())])
	print("[image-shot] root size=%s scale=%s viewport=%s" % [str(rootc.size), str(rootc.scale), str(vp)])
	print("[image-shot] 对话框顶 %.0f" % (900.0 - 30.0 - 136.0))
	root.get_texture().get_image().save_png(OUT + "/03_story_image_big.png")
	print("[image-shot] 存图")
	box.finish()
	quit(0)
