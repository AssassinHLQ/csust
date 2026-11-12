extends SceneTree
## 探针：Godot 的 Theora（.ogv）到底读不读 alpha？
## 读不了就只能退回 PNG 序列，所以这一步必须先量。
const OFF := preload("res://scripts/offscreen_window.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(640, 480))
	for _i in 3:
		await process_frame
	var path := "res://_tmp_plana/test.ogv"
	if not ResourceLoader.exists(path):
		print("❌ 没有 test.ogv")
		quit(1)
		return
	var stream := load(path) as VideoStream
	print("stream = ", stream, "  class=", stream.get_class() if stream else "null")
	var vp := VideoStreamPlayer.new()
	vp.stream = stream
	vp.expand = true
	root.add_child(vp)
	vp.play()
	var got := false
	for _i in 90:
		await process_frame
		var tex: Texture2D = vp.get_video_texture()
		if tex == null:
			continue
		var img: Image = tex.get_image()
		if img == null or img.is_empty():
			continue
		if img.get_width() < 8:
			continue
		var fmt := img.get_format()
		var has_internal_alpha := false
		for f in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_LA8]:
			if fmt == f:
				has_internal_alpha = true
		var a_lo := 255
		var a_count := 0
		if has_internal_alpha:
			for y in range(0, img.get_height(), 7):
				for x in range(0, img.get_width(), 7):
					var a := int(img.get_pixel(x, y).a8)
					if a < a_lo:
						a_lo = a
					if a < 250:
						a_count += 1
		print("帧: %dx%d  format=%d  内建alpha=%s  最小alpha=%d  半透明采样=%d"
			% [img.get_width(), img.get_height(), fmt, str(has_internal_alpha), a_lo, a_count])
		got = true
		break
	if not got:
		print("❌ 90 帧内没拿到有效视频纹理")
	print("★★ 结论：", "ogv 带 alpha 可用" if got else "拿不到帧")
	quit(0)
