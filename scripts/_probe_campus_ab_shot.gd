extends SceneTree
## A/B 出图：校园在**同一机位**下，新「分块 SOG」与旧「raw bin」两条路画出来一样吗。
##
## 这是分块 SOG 改造的**回归证据**：数据层的等价已经有
## `_verify_campus_sog.gd`（13/13，点集与旧 bin 排序后最大差 78 µm）撑着，
## 但「渲染出来是不是同一张图」只能出图比。
##
## 用哪套分块由**命令行**决定 —— `campus_ggs.gd::_ready()` 读
## `OS.get_cmdline_user_args()`，所以必须在启动时给，不能在脚本里改：
##   新：  …… -- --out=<png>
##   旧：  …… -- --ggs-chunks=res://splatdata/campus_chunks10w/chunks.json --out=<png>
##
## ⚠️ 按 AGENTS.md「跑测试 / 弹窗口：绝对不许抢用户前台」：
##    必须带 `--position -4000,-4000` + `--no-capture`，并且**第一件事**就调
##    `OffWin.apply(self)`（命令行顶不住 project.godot 的 `window/size/mode=2`）。
##    漏参数直接退出，不出图。

const OffWin := preload("res://scripts/offscreen_window.gd")
const LEVEL := "res://scenes/next_level.tscn"

var _out := "C:/Users/WY157/Desktop/GODOT/_arisu_learn/_log/_ab_shot.png"


func _initialize() -> void:
	if not _check_args():
		return
	_run.call_deferred()


## ⚠️ 这里**不能**去查 `--position` 在不在命令行里：`--position` / `--resolution`
##    是引擎自己的参数，Godot 会把它们从 `OS.get_cmdline_args()` 里吃掉，
##    查不到（第一版就是这么误判、直接退出的）。
##    真正该守的不变量是「窗口确实在屏幕外、且没抢鼠标」—— 那是**运行时状态**，
##    下面 `_run()` 里 `OffWin.apply()` 之后用 `OffWin.is_safe()` 实测，比查命令行强。
func _check_args() -> bool:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[ab] 缺 --no-capture（窗口拿到焦点就会抢鼠标），拒绝运行")
		quit(2)
		return false
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			_out = String(a).substr(6)
	return true


func _run() -> void:
	await OffWin.apply(self)
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[ab] 窗口没挪到屏幕外，拒绝出图：%s" % str(safe0[1]))
		quit(2)
		return
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[ab] 加载不了关卡")
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	# ⚠️ 关卡加载完要把窗口**再**挪一次：实测加载过程会把窗口顶回 (0,34)/2560×1334
	#    （项目设置 mode=2 在加载阶段又生效了一次，第一版出图就是这样被拍在屏幕内的）。
	await OffWin.apply(self)
	for _i in 60:
		await process_frame
	await OffWin.apply(self)

	var ggs := level.get_node_or_null("CampusGGS")
	var player := level.get_node_or_null("Player")
	if ggs == null or player == null:
		push_error("[ab] 缺 CampusGGS 或 Player")
		quit(1)
		return
	print("[ab] 分块清单 = %s" % str(ggs.get("chunks_json")))
	print("[ab] 源 = %s｜粗层 = %s" % [
		"SOG 块" if not (ggs.get("_palette") as PackedByteArray).is_empty() else "raw bin",
		str(ggs.get("_coarse_path"))])

	# 站在楼外（z < -74 才显示校园），固定机位
	player.global_position = Vector3(0.0, 14.0, -80.0)
	player.set("velocity", Vector3.ZERO)
	player.call("set_flight_lock", true)
	var aim := Marker3D.new()
	aim.position = Vector3(0.0, 4.0, -140.0)
	level.add_child(aim)
	player.call("look_at_node", aim, 9999.0)

	# 等细层就绪（最坏要等后台解码 + 上传；SOG 那条路首次约 3 s）
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:
		var r = ggs.get("rasterizer")
		if r != null and bool(r.is_loaded):
			break
		player.global_position = Vector3(0.0, 14.0, -80.0)
		await process_frame
	var r2 = ggs.get("rasterizer")
	var fine_ok: bool = r2 != null and bool(r2.is_loaded)
	print("[ab] 细层就绪 = %s（等了 %d ms）" % [str(fine_ok), Time.get_ticks_msec() - t0])

	# 再多跑几十帧：让相机/合成 quad/粗层都稳定下来
	for _i in 60:
		player.global_position = Vector3(0.0, 14.0, -80.0)
		await process_frame
	await RenderingServer.frame_post_draw

	var img := root.get_texture().get_image()
	var err := img.save_png(_out)
	print("[ab] 出图 → %s err=%d  size=%s" % [_out, err, str(img.get_size())])
	var safe: Array = OffWin.is_safe()
	print("[ab] 窗口自检：%s（位置 %s / 尺寸 %s / 焦点 %s / mouse_mode %d）" % [
		"OK 没抢前台" if bool(safe[0]) else "NG " + str(safe[1]),
		str(DisplayServer.window_get_position()), str(DisplayServer.window_get_size()),
		str(DisplayServer.window_is_focused()), Input.mouse_mode])
	quit(0 if fine_ok and err == OK else 1)
