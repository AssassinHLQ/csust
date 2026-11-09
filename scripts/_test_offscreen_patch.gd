extends SceneTree
## 补丁验证脚本：确认「三行保护」在 window/size/mode=2（最大化）的项目设置下真的生效。
##
## 背景（2026-11-09）：命令行 --position/--resolution/--windowed 会被 project.godot 的
## 最大化设置顶掉，所以必须在脚本运行时自己改窗口状态。
##
## 本脚本验证的三行保护：
##   DisplayServer.window_set_mode(WINDOW_MODE_WINDOWED)   取消最大化
##   DisplayServer.window_set_flag(WINDOW_FLAG_NO_FOCUS)   禁止抢焦点
##   DisplayServer.window_set_position(Vector2i(-4000,-4000))  挪出屏幕
##
## 与 OffWin.apply() 的区别：不设置窗口尺寸，避免破坏各探针自己的出图分辨率。
##
## 用法：Godot --path <工程> --script res://scripts/_test_offscreen_patch.gd -- --no-capture


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	for _i in 400:
		await process_frame

	var pos := DisplayServer.window_get_position()
	var size := DisplayServer.window_get_size()
	var focused := DisplayServer.window_is_focused()
	var mm := Input.mouse_mode

	print("================ 补丁验证 ================")
	print("  窗口位置   : %s" % str(pos))
	print("  窗口尺寸   : %s" % str(size))
	print("  是否抢焦点 : %s" % str(focused))
	print("  mouse_mode : %d" % mm)
	print("  窗口模式   : %d  (0=窗口化 2=最大化)" % DisplayServer.window_get_mode())

	var ok := true
	if pos.x > -1000 and pos.y > -1000:
		print("  ✗ 窗口还在屏幕内 —— 保护无效")
		ok = false
	else:
		print("  ✓ 窗口在屏幕外")

	if focused:
		print("  ✗ 窗口抢到了焦点 —— 保护无效")
		ok = false
	else:
		print("  ✓ 没有抢焦点")

	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED:
		print("  ✗ 仍是最大化模式")
		ok = false
	else:
		print("  ✓ 已取消最大化")

	# 出图探针依赖的能力：渲染纹理可读
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("  ✗ 无法取到渲染纹理（出图探针不可用）")
		ok = false
	else:
		print("  ✓ 渲染纹理可读 %s" % str(img.get_size()))

	print("")
	print("  %s" % ("★ 补丁有效：可以批量应用" if ok else "✗ 补丁无效：不要批量应用"))
	quit(0 if ok else 1)
