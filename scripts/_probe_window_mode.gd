extends SceneTree
## 快检：现在的显示设置下，「窗口尺寸 / 模式」到底是什么 —— 用来判断
## `display/window/size/mode` 会不会把自检（它们都靠 `root.size = 1600×900`
## 做像素判据）搞坏。
##
## 用法：
##   godot --path . --script res://scripts/_probe_window_mode.gd

func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	print("[win] 开机时：root.size = %s，DisplayServer.window_get_size() = %s，mode = %d" % [
		str(root.size), str(DisplayServer.window_get_size()), DisplayServer.window_get_mode()])
	print("[win] 屏幕 %s，可用区域 %s" % [
		str(DisplayServer.screen_get_size()), str(DisplayServer.screen_get_usable_rect().size)])

	# 自检们干的事：把窗口设成 1600×900
	root.size = Vector2i(1600, 900)
	await _frames(5)
	print("[win] root.size = 1600×900 之后：root.size = %s，窗口实际 = %s，mode = %d" % [
		str(root.size), str(DisplayServer.window_get_size()), DisplayServer.window_get_mode()])
	print("[win] 视口纹理尺寸 = %s（自检的 get_image() 就是这个尺寸）" % [
		str(root.get_texture().get_image().get_size())])

	# 再来一个小尺寸（_probe_stale_order 用 960×540）
	root.size = Vector2i(960, 540)
	await _frames(5)
	print("[win] root.size = 960×540 之后：窗口实际 = %s，视口纹理 = %s" % [
		str(DisplayServer.window_get_size()), str(root.get_texture().get_image().get_size())])
	quit(0)


func _frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
