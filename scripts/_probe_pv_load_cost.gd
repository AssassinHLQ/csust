extends SceneTree
## 量「开场 PV 每张图在**主线程**上到底要花多少 ms」。
##
##   bash _tools/run_probe.sh res://scripts/_probe_pv_load_cost.gd
##
## ── 为什么单独量这个 ──
## 开场 PV 在 `--script` 模式下被 `game.gd:883` 主动跳过，所以带 `--script` 的
## 真窗口探针**永远看不到 PV**（这就是前两版探针等 150 s 也等不到 TitleIntro 的原因）。
## 但「图加载要多久」是纯 CPU 的事，不需要窗口 —— headless 就能量：
##   · `load()` 一张 pv_hd 的 CompressedTexture2D 要多久（读 .ctex + 解压）；
##   · 现场解 JPEG 字节（没导入缓存时的退化路径）要多久；
##   · `ImageTexture.create_from_image()` 上传要多久。
## 这些数就是「第一张图卡几下」的直接来源：`_loop_slides()` 是在主线程上
## 同步做这些的。

## 判断标准：单次超过这个就算「能看出来的卡」（60 fps 一帧 16.7 ms）
const NOTE_MS := 16.0

var _pv: Array[String] = []
var _hd: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_pv = _list("res://assets/cg/pv")
	_hd = _list("res://assets/cg/pv_hd")
	print("开头 PV：pv %d 张 / pv_hd %d 张（优先用 pv_hd）" % [_pv.size(), _hd.size()])
	print("显示尺寸约 1600×900 时每张要「等比盖满屏幕」再平移，行程取决于图宽。\n")

	# ① 走导入缓存 load()（正常路径）
	print("── ① load() 走 .ctex 导入缓存（`_load_texture` 的主路径）──")
	var total := 0.0
	for p in _hd:
		var t := Time.get_ticks_usec()
		var tex := load(p) as Texture2D
		var ms := float(Time.get_ticks_usec() - t) / 1000.0
		total += ms
		var sz := tex.get_size() if tex != null else Vector2.ZERO
		print("  %-46s %6.1f ms  %s%s" % [
			p.get_file(), ms, str(sz),
			"  ← 超过一帧，会卡" if ms >= NOTE_MS else ""])
	print("  合计 %.1f ms（8 张；全在主线程上就是开头那几下卡）\n" % total)

	# ② 现场解 JPEG 字节（没有 .import 时的退化路径）
	print("── ② 现场解 JPEG 字节（退化路径，`load()` 失败时走）──")
	var total2 := 0.0
	for p in _hd:
		var t := Time.get_ticks_usec()
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			print("  %s 读不出来" % p.get_file())
			continue
		var bytes := f.get_buffer(f.get_length())
		f.close()
		var img := Image.new()
		var ok := img.load_jpg_from_buffer(bytes) == OK
		var decode_ms := float(Time.get_ticks_usec() - t) / 1000.0
		total2 += decode_ms
		print("  %-46s %6.1f ms  解码%s  %s" % [
			p.get_file(), decode_ms, "成功" if ok else "失败",
			"（仅解码，上传另算）"])
	print("  合计 %.1f ms（只有解码；`ImageTexture.create_from_image` 还要再花时间）\n" % total2)

	# ③ ImageTexture 上传（GPU 侧，headless 下量的是驱动调用开销）
	print("── ③ ImageTexture.create_from_image() 上传 ──")
	var f2 := FileAccess.open(_hd[0], FileAccess.READ)
	if f2 != null:
		var bytes2 := f2.get_buffer(f2.get_length())
		f2.close()
		var img2 := Image.new()
		if img2.load_jpg_from_buffer(bytes2) == OK:
			var t3 := Time.get_ticks_usec()
			var it := ImageTexture.create_from_image(img2)
			print("  %-46s %6.1f ms  → %s" % [
				_hd[0].get_file(), float(Time.get_ticks_usec() - t3) / 1000.0, str(it.get_size())])
		else:
			print("  解码失败，跳过")

	# ④ 着色器编译：PV_SLIDE_SHADER 首次用要编译（headless 下只能看能不能建起来）
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ COLOR = texture(TEXTURE, UV); }"
	print("\n── ④ 着色器 ──")
	print("  headless 没有渲染后端，编译耗时测不了；真机首次绘制那次编译")
	print("  通常 100~500 ms（驱动侧 pipeline 创建），是本喵最怀疑的「卡几下」来源。")

	print("\n结论：单张图在主线程上 %.0f~%.0f ms ⇒ 一次「卡」≈ 一次换图。" % [
		total / maxf(float(_hd.size()), 1.0), total2 / maxf(float(_hd.size()), 1.0)])
	quit(0)


func _list(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	var names := da.get_files()
	names.sort()
	for f in names:
		var low := f.to_lower()
		if low.ends_with(".jpg") or low.ends_with(".png") or low.ends_with(".webp") \
				or low.ends_with(".jpeg"):
			out.append(dir_path.path_join(f))
	return out
