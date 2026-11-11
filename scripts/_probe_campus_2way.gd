extends SceneTree
## 同一份校园数据，**两个渲染器**同一机位对比：GGS（`addons/ggs_campus`）vs
## GDGS（`addons/gdgs`，Compute 那套，原版）。
##
## 为什么要有它：用户 2026-11-11「全量这么稀疏」，本喵已经量到
## σ/点距 = 0.064（每颗泼渍只盖点间距的 6%）—— 但那是"数据侧"的解释。
## 到底是**数据本来就稀**，还是 **GGS 把协方差算小了**，只能拿同一份数据
## 换渲染器画一遍来判断：
##   · GDGS 稠密 → GGS 的协方差/投影有问题（去修 GGS）
##   · 两者一样稀 → 数据本身如此（要么放大泼渍、要么接受）
##
## 用法（要真窗口）：
##   GGS：  … --script res://scripts/_probe_campus_2way.gd -- --no-capture --out=x.png
##   GDGS： … --script res://scripts/_probe_campus_2way.gd -- --no-capture --gdgs --out=y.png
##
## ⚠️ `--position` 是引擎参数，Godot 会从 `OS.get_cmdline_args()` 吃掉，
##    不能拿它做参数闸（踩过）。窗口安全靠 `OffWin.is_safe()` 实测。

const OffWin := preload("res://scripts/offscreen_window.gd")
const LEVEL := "res://scenes/next_level.tscn"

var _out := "C:/Users/WY157/Desktop/GODOT/_arisu_learn/_log/_2way.png"
var _gdgs := false
var _y := 150.0
var _back := 260.0
## 覆盖率统计的区域：整帧
var _tag := "ggs"


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[2way] 缺 --no-capture，拒绝运行")
		quit(2)
		return
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s == "--gdgs":
			_gdgs = true
		elif s.begins_with("--y="):
			_y = float(s.substr(4))
		elif s.begins_with("--back="):
			_back = float(s.substr(7))
		elif s.begins_with("--tag="):
			_tag = s.substr(6)
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self)
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[2way] 窗口没挪到屏幕外，拒绝出图：%s" % str(safe0[1]))
		quit(2)
		return
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[2way] 加载不了关卡")
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	await OffWin.apply(self)
	for _i in 120:
		await process_frame

	var player := level.get_node_or_null("Player")
	var ggs := level.get_node_or_null("CampusGGS")
	var campus := level.get_node_or_null("Campus")
	print("[2way] %s｜CampusGGS=%s  Campus(GDGS)=%s" % [
		"GDGS" if _gdgs else "GGS",
		"有" if ggs != null else "无", "有" if campus != null else "无"])
	if player == null:
		push_error("[2way] 没有 Player")
		quit(1)
		return
	player.set("velocity", Vector3.ZERO)
	player.call("set_flight_lock", true)
	player.global_position = Vector3(0.0, 30.0, -140.0)

	# 自己架相机（俯瞰）：两个渲染器都认这一台
	var cam := Camera3D.new()
	level.add_child(cam)
	cam.fov = 55.0
	var target := Vector3(0.0, 0.0, -300.0)
	cam.global_position = target + Vector3(0.0, _y, _back)
	cam.look_at(target, Vector3.UP)
	cam.make_current()

	if _gdgs:
		# GDGS 那条路：等 `Campus`（SplatScene）自己解码完（6.15M 点，约 20~40 s）
		if campus == null:
			push_error("[2way] 没有 Campus（GDGS 未启用？要加 --no-ggs-campus）")
			quit(1)
			return
		campus.call("force_start")
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 240000:
			var ready := false
			if campus.has_method("is_ready"):
				ready = bool(campus.call("is_ready"))
			if ready:
				break
			cam.global_position = target + Vector3(0.0, _y, _back)
			cam.look_at(target, Vector3.UP)
			player.global_position = Vector3(0.0, 30.0, -140.0)
			await process_frame
		print("[2way] GDGS 就绪 = %s（等了 %d ms）" % [
			str(campus.call("is_ready")), Time.get_ticks_msec() - t0])
	else:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 240000:
			var r = ggs.get("rasterizer") if ggs != null else null
			if r != null and bool(r.is_loaded):
				break
			cam.global_position = target + Vector3(0.0, _y, _back)
			cam.look_at(target, Vector3.UP)
			player.global_position = Vector3(0.0, 30.0, -140.0)
			await process_frame
		print("[2way] GGS 细层就绪 = %s（等了 %d ms）" % [
			str(ggs.get("rasterizer") != null and bool(ggs.get("rasterizer").is_loaded)),
			Time.get_ticks_msec() - t0])

	for _i in 40:
		cam.global_position = target + Vector3(0.0, _y, _back)
		cam.look_at(target, Vector3.UP)
		player.global_position = Vector3(0.0, 30.0, -140.0)
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(_out)
	# 覆盖率：把「天空色」排除，剩下的算"被泼渍画到的像素"
	print("[2way] 出图 → %s err=%d size=%s" % [_out, err, str(img.get_size())])
	print("[2way] %s 覆盖率统计：" % _tag)
	_report(img)
	quit(0 if err == OK else 1)


## 分区域统计「非天空」像素占比 + 亮度方差（糊掉的话方差会低）
func _report(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var step := maxi(1, w / 400)
	for band in [["天空(上 1/3)", 0, h / 3], ["校园(中 1/3)", h / 3, h * 2 / 3], ["地面(下 1/3)", h * 2 / 3, h]]:
		var y0: int = band[1]
		var y1: int = band[2]
		var n := 0
		var non_sky := 0
		var sum := 0.0
		var sumsq := 0.0
		var y := y0
		while y < y1:
			var x := 0
			while x < w:
				var c := img.get_pixel(x, y)
				var lum := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
				n += 1
				sum += lum
				sumsq += lum * lum
				# 天空是粉紫色且很亮；泼渍/建筑通常更暗或更绿
				if not (c.r > 0.55 and c.b > 0.55 and c.g > 0.5 and lum > 0.62):
					non_sky += 1
				x += step
			y += step
		var mean := sum / maxf(float(n), 1.0)
		var var_ := maxf(sumsq / maxf(float(n), 1.0) - mean * mean, 0.0)
		print("   %-14s 非天空 %5.1f%%   平均亮度 %.3f   方差 %.5f" % [
			band[0], 100.0 * float(non_sky) / maxf(float(n), 1.0), mean, var_])
