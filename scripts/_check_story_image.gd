extends SceneTree
## 确认剧情插图能被对话播放器读到（不渲染，只看纹理尺寸）。
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "res://assets/story/config_sheet.png"
	var tex := load(path) as Texture2D
	if tex == null:
		print("[story-img] 载入失败：%s" % path)
		quit(1)
		return
	print("[story-img] %s → %d × %d" % [path, tex.get_width(), tex.get_height()])
	# 再走一遍播放器的弹图分支，确认路径/缩放都对
	var box := DialogueBox.new()
	root.add_child(box)
	await process_frame
	box.play_steps([{"kind": "image", "path": path}], "check")
	for _i in 6:
		await process_frame
	print("[story-img] 播放器弹图=%s  路径=%s" % [str(box.is_showing_image()), box.current_image_path()])
	quit(0)
