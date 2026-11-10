extends SceneTree
## 单点测试 `HaloFix._average_color()` —— 直接调它，看返回什么。
##
## 说明：`_verify_halo_fix.gd` 里读到的自发光颜色一直是 (0,0,0)，
## 但 `HaloFix` 的日志说图取成功了。所以问题在「取色」这一步本身。
## 这条探针不碰场景，只测一个函数。

const HaloFixScript := preload("res://scripts/halo_fix.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("========== _average_color 单点测试 ==========")
	var path := "res://models/companions/Yuzu_Yuzu_Original_Halo.png"
	var tex := load(path) as Texture2D
	print("贴图 = %s" % str(tex != null))
	if tex == null:
		quit(1)
		return
	print("resource_path = %s" % tex.resource_path)

	# ① 直接调 _average_color
	var c: Color = HaloFixScript._average_color(tex)
	print("_average_color 返回 = (%.3f, %.3f, %.3f, %.3f)" % [c.r, c.g, c.b, c.a])

	# ② 自己再取一次图、自己算一遍（对照）
	var img := tex.get_image()
	print("img = %s" % str(img != null))
	if img != null:
		print("  尺寸 %dx%d 格式 %d" % [img.get_width(), img.get_height(), img.get_format()])
		var w := img.get_width()
		var h := img.get_height()
		var ar := 0.0
		var ag := 0.0
		var ab := 0.0
		var n := 0
		for y in h:
			for x in w:
				var px := img.get_pixel(x, y)
				if px.a < 0.15:
					continue
				ar += px.r
				ag += px.g
				ab += px.b
				n += 1
		print("  手算：n=%d 平均 = (%.3f, %.3f, %.3f)" % [
			n, ar / maxf(float(n), 1.0), ag / maxf(float(n), 1.0), ab / maxf(float(n), 1.0)])
		# 打印几个采样点
		for p in [Vector2i(0, 0), Vector2i(w / 2, h / 2), Vector2i(w - 1, h - 1)]:
			var cc := img.get_pixel(p.x, p.y)
			print("  像素 %s = (%.3f, %.3f, %.3f, %.3f)" % [str(p), cc.r, cc.g, cc.b, cc.a])

	# ③ 兜底
	var f: Color = HaloFixScript._fallback_tint(path)
	print("_fallback_tint 返回 = (%.3f, %.3f, %.3f)" % [f.r, f.g, f.b])
	quit(0)
