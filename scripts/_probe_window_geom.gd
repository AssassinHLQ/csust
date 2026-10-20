extends SceneTree
## 探针：窗口模式的几何（窗口尺寸 / 视口尺寸 / 内容缩放 / 屏幕可用区 / 设置面板占多大）
## 用法（**要窗口**）：
##   godot --script res://scripts/_probe_window_geom.gd -- --splat=off --bosses=off


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(40)
	var menu := game.get_node_or_null("SettingsMenu")
	await _report("启动后", menu)
	for m in ["fullscreen", "windowed", "maximized"]:
		GameSettings.set_value("window_mode", m)
		await _wait(60)
		await _report(m, menu)
	quit(0)


func _report(tag: String, menu: Node) -> void:
	var scr := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(scr)
	print("\n===== %s =====" % tag)
	print("  window mode=%d  size=%s  pos=%s" % [
		DisplayServer.window_get_mode(), str(DisplayServer.window_get_size()),
		str(DisplayServer.window_get_position())])
	print("  screen size=%s usable=%s scale=%.2f dpi=%d" % [
		str(DisplayServer.screen_get_size(scr)), str(usable),
		DisplayServer.screen_get_scale(scr), DisplayServer.screen_get_dpi(scr)])
	print("  root.size=%s  content_scale_size=%s factor=%.2f mode=%d aspect=%d" % [
		str(root.size), str(root.content_scale_size), root.content_scale_factor,
		root.content_scale_mode, root.content_scale_aspect])
	if menu == null:
		return
	menu.call("open")
	await _wait(4)
	var panel := menu.get_node_or_null("Root") as Control
	print("  menu root rect=%s  可见=%s" % [str(panel.get_global_rect()), str(panel.visible)])
	var scroll := menu.get_node_or_null(
		"Root/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsScroll")
	if scroll != null:
		print("  滚动区 rect=%s" % str((scroll as Control).get_global_rect()))
	var close_btn: Button = null
	for n in menu.find_children("*", "Button", true, false):
		if (n as Button).text.begins_with("关闭"):
			close_btn = n
	if close_btn != null:
		var r := close_btn.get_global_rect()
		print("  关闭按钮 rect=%s  在视口内=%s" % [str(r),
			str(r.end.y <= root.size.y and r.end.x <= root.size.x)])
	await _wait(6)
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_wingeom")
	DirAccess.make_dir_recursive_absolute(out)
	root.get_texture().get_image().save_png(out.path_join("%s.png" % tag))
	print("  出图 %s.png  %s" % [tag, str(root.get_texture().get_image().get_size())])
	menu.call("close")


func _wait(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
