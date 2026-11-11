extends SceneTree
## 出图：校园泼溅在指定「椭球缩放」下长什么样，用来扫描 `--ggs-cov=` 的正确值。
##
## 用户 2026-11-08：「校园泼溅一片白 / 完全糊掉」。数据侧本喵已经排掉
## （opacity / 协方差 / 布局 / `time` 全合规，见 `_tools/diag_splat_records.py`），
## 只剩「椭球的世界单位对不对」——只能靠出图 + 眼睛定。
##
## ⚠️ **必须实例化整个关卡**，不能只挂 `campus_ggs.gd`：
##    `campus_ggs.gd` 的合成 quad 只在 `_active`（= 有 player 且 `player.z < -74`
##    且某层已就绪）时才显示，而且它只认**玩家自己的相机**。
##    本喵第一版只挂了 GGS 节点，出图是一张纯黑 + 加载遮罩（自打脸）。
##
## 用法（**要真窗口**）：
##   & <mono godot> --path . --position -4000,-4000 --resolution 1280x720 --windowed \
##       --audio-driver Dummy --script res://scripts/_probe_campus_cov_shot.gd \
##       -- --ggs-cov=0.3 --ggs-cov-clamp=0.09 --ggs-cov-ref=0.036 --no-capture
##
## ⚠️ 按 AGENTS.md「跑测试 / 弹窗口：绝对不许抢用户前台」：
##    `--position` / `--resolution` / `--audio-driver Dummy` / `--no-capture` 四个都要加，
##    但**光加命令行不够** —— `project.godot` 里 `window/size/mode=2`（最大化）会在启动时
##    把 `--windowed` / `--position` 全顶掉。所以脚本运行时还要自己调
##    `OffscreenWindow.apply(self)`（见 `_run()` 第一行）。
##
## 出图 → `_arisu_learn/_log/_cov_<值>.png`

## 用 preload 而不是全局类名：`--script` 模式下解析不到 `class_name`。
const OffWin := preload("res://scripts/offscreen_window.gd")
const LEVEL := "res://scenes/next_level.tscn"
const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_learn/_log"


func _initialize() -> void:
	_check_window_args()
	_run.call_deferred()


## 硬闸：这条探针必须开真窗口，所以必须守住「不抢前台」。
## ⚠️ **不能**去查命令行里有没有 `--position`：`--position` / `--resolution`
##    是引擎自己的参数，Godot 会从 `OS.get_cmdline_args()` 里**吃掉**，查不到
##    （2026-11-11 实测：本探针因此一律误判「缺参数」直接退出，一张图都没出）。
##    真正该守的是**运行时状态**：`OffWin.apply()` 之后用 `OffWin.is_safe()` 实测。
func _check_window_args() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[cov] 缺 --no-capture（窗口拿到焦点就会抢鼠标），拒绝运行")
		quit(2)


func _cov_tag() -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--ggs-cov="):
			return String(a).substr(10)
	return "default"


func _run() -> void:
	# ⚠️ 第一步就把窗口挪到屏幕外、取消最大化、缩到 960×540。
	#    命令行参数**顶不住** project.godot 里的 window/size/mode=2，必须运行时代码改。
	await OffWin.apply(self)
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[cov] 窗口没挪到屏幕外，拒绝出图：%s" % str(safe0[1]))
		quit(2)
		return
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[cov] 加载不了关卡")
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	for _i in 90:
		await process_frame

	var ggs := level.get_node_or_null("CampusGGS")
	var player := level.get_node_or_null("Player") as Player
	if ggs == null:
		push_error("[cov] 没有 CampusGGS（校园没启用？）")
		quit(1)
		return
	if player == null:
		push_error("[cov] 没有 Player")
		quit(1)
		return
	print("[cov] 椭球缩放 = %.4f" % float(ggs.get("_cov_scale")))

	# 站到楼外高处（z < -74 才会显示校园），用玩家自己的相机
	player.global_position = Vector3(0.0, 14.0, -80.0)
	player.set("velocity", Vector3.ZERO)
	player.call("set_flight_lock", true)
	var aim := Marker3D.new()
	aim.position = Vector3(0.0, 4.0, -140.0)
	level.add_child(aim)
	player.call("look_at_node", aim, 9999.0)

	# 等细层就绪（最多 120 s）
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000:
		var r = ggs.get("rasterizer")
		if r != null and bool(r.is_loaded):
			break
		player.global_position = Vector3(0.0, 14.0, -80.0)
		await process_frame
	var r2 = ggs.get("rasterizer")
	print("[cov] 细层已就绪 = %s" % str(r2 != null and bool(r2.is_loaded)))

	for _i in 60:
		player.global_position = Vector3(0.0, 14.0, -80.0)
		await process_frame
	await RenderingServer.frame_post_draw

	var img := root.get_texture().get_image()
	var path := "%s/_cov_%s.png" % [OUT_DIR, _cov_tag()]
	var err := img.save_png(path)
	print("[cov] 出图 → %s err=%d" % [path, err])

	# 出图完自报「有没有抢前台」，让这件事可核实而不是口头保证。
	var safe: Array = OffWin.is_safe()
	print("[cov] 窗口自检：%s（位置 %s / 尺寸 %s / 焦点 %s / mouse_mode %d）" % [
		"✓ 没抢前台" if bool(safe[0]) else "✗ " + str(safe[1]),
		str(DisplayServer.window_get_position()), str(DisplayServer.window_get_size()),
		str(DisplayServer.window_is_focused()), Input.mouse_mode])
	quit(0)
