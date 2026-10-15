extends SceneTree
## 一次性探针：确认 `res://icon.png` 导入之后 **alpha 还在**。
##
## 为什么要专门验：Godot 的纹理导入有好几档压缩，其中 VRAM 压缩（S3TC/BPTC）
## 会**丢掉 alpha 精度或整个 alpha 通道**，表现就是任务栏里图标变成一块实心方块
## 或者边缘发黑。这个工程用的是 `compress/mode=0`（无损），本探针就是把这件事钉死。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_icon.gd

const ICON := "res://icon.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ResourceLoader.exists(ICON):
		print("[icon] 找不到 %s" % ICON)
		quit(1)
		return

	var tex := load(ICON) as Texture2D
	if tex == null:
		print("[icon] %s 载入失败" % ICON)
		quit(1)
		return

	var img := tex.get_image()
	if img == null:
		print("[icon] 拿不到 Image")
		quit(1)
		return

	var w := img.get_width()
	var h := img.get_height()
	print("[icon] %s  %d x %d  格式 %d" % [ICON, w, h, img.get_format()])

	var a_min := 256
	var a_max := -1
	var transparent := 0
	var opaque := 0
	var total := 0
	for y in h:
		for x in w:
			var a := int(round(img.get_pixel(x, y).a * 255.0))
			a_min = mini(a_min, a)
			a_max = maxi(a_max, a)
			if a < 8:
				transparent += 1
			elif a > 247:
				opaque += 1
			total += 1

	print("[icon] alpha  最小 %d  最大 %d" % [a_min, a_max])
	print("[icon] 全透明 %.1f%%   全不透明 %.1f%%   半透明(抗锯齿边) %.1f%%" % [
		float(transparent) / total * 100.0,
		float(opaque) / total * 100.0,
		float(total - transparent - opaque) / total * 100.0])
	print("[icon] 四角 alpha = %d, %d, %d, %d" % [
		int(round(img.get_pixel(0, 0).a * 255.0)),
		int(round(img.get_pixel(w - 1, 0).a * 255.0)),
		int(round(img.get_pixel(0, h - 1).a * 255.0)),
		int(round(img.get_pixel(w - 1, h - 1).a * 255.0))])

	var ok: bool = a_min == 0 and a_max == 255 and transparent > total / 10
	print("[icon] %s" % ("PASS 透明通道保住了" if ok else "FAIL alpha 被压坏了"))
	quit(0 if ok else 1)
