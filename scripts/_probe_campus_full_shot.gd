extends SceneTree
## 出图：**全量校园**（不做 3×3 窗口）在指定机位/俯瞰角下的样子。
##
##   & <godot> --path . --position -4000,-4000 --resolution 1280x720 --windowed \
##       --audio-driver Dummy --script res://scripts/_probe_campus_full_shot.gd -- \
##       --no-capture --out=C:/.../_log/_full.png [--y=120] [--back=200] [--cov=0.1]
##
## 为什么单独写一条：`_probe_campus_ab_shot.gd` 的机位是贴地第三人称（看得清近景、
## 看不出整体），而「全量校园」想知道的是**整份重建铺成什么样**。
##
## ⚠️ `--position` 是引擎参数，Godot 会从 `OS.get_cmdline_args()` 吃掉，
##    **不能**拿它做参数闸（本喵在 `_probe_campus_cov_shot.gd` 上就踩过：
##    那条检查永远为假、探针从来没真出过图）。窗口安全靠 `OffWin.is_safe()` 实测。

const OffWin := preload("res://scripts/offscreen_window.gd")
const LEVEL := "res://scenes/next_level.tscn"
const FULL := "res://splatdata/campus_sog/chunks_full.json"

var _out := "C:/Users/WY157/Desktop/GODOT/_arisu_learn/_log/_full_campus.png"
var _y := 120.0
var _back := 200.0


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[full] 缺 --no-capture，拒绝运行")
		quit(2)
		return
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--y="):
			_y = float(s.substr(4))
		elif s.begins_with("--back="):
			_back = float(s.substr(7))
	# 先自己把分块清单换成「全量单块」，再实例化关卡 —— `_ready()` 只读一次
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self)
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[full] 窗口没挪到屏幕外，拒绝出图：%s" % str(safe0[1]))
		quit(2)
		return
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[full] 加载不了关卡")
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	await OffWin.apply(self)
	for _i in 90:
		await process_frame

	var ggs := level.get_node_or_null("CampusGGS")
	var player := level.get_node_or_null("Player")
	if ggs == null or player == null:
		push_error("[full] 缺 CampusGGS 或 Player")
		quit(1)
		return
	# 换成全量单块（614 万点），关掉粗层：要看的就是「整份重建」
	ggs.set("chunks_json", FULL)
	print("[full] 清单切成全量：%s" % str(ggs.call("_resolve_chunks_json")))
	ggs.set("_bin_override", "res://campus_ggs.bin")
	ggs.set("_bin_override", "")
	# 重新走一遍清单 + 重建
	ggs.set("_palette", PackedByteArray())
	ggs.set("_chunk_list", [])
	var ok: bool = ggs.call("_load_manifest")
	print("[full] 全量清单加载 = %s，块数 %d" % [str(ok), (ggs.get("_chunk_list") as Array).size()])
	ggs.set("_coarse_off", true)
	ggs.set("_ready_done", false)
	ggs.set("_window_names", PackedStringArray())

	# 俯瞰机位：站在玩家外面，自己架相机
	player.global_position = Vector3(0.0, 30.0, -140.0)
	player.set("velocity", Vector3.ZERO)
	player.call("set_flight_lock", true)
	var cam := Camera3D.new()
	level.add_child(cam)
	cam.fov = 55.0
	cam.make_current()
	var target := Vector3(0.0, 0.0, -300.0)
	cam.global_position = target + Vector3(0.0, _y, _back)
	cam.look_at(target, Vector3.UP)

	# 等细层就绪（全量 1406 MB，实测约 11 s）
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000:
		var r = ggs.get("rasterizer")
		if r != null and bool(r.is_loaded):
			break
		await process_frame
	var r2 = ggs.get("rasterizer")
	print("[full] 细层就绪 = %s（等了 %d ms）" % [
		str(r2 != null and bool(r2.is_loaded)), Time.get_ticks_msec() - t0])
	# 再跑几十帧让合成稳定
	for _i in 40:
		cam.global_position = target + Vector3(0.0, _y, _back)
		cam.look_at(target, Vector3.UP)
		player.global_position = Vector3(0.0, 30.0, -140.0)
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(_out)
	print("[full] 出图 → %s err=%d size=%s" % [_out, err, str(img.get_size())])
	quit(0 if err == OK else 1)
