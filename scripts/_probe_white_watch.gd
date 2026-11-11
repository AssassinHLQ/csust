extends SceneTree
## 现场取证：玩家正常玩，它在后台盯着画面，一旦「整屏白」就把校园渲染器的完整状态记下来。
##
## 为什么要有它：用户 2026-11-11 报「站在桥上再往前一步就又全白了」，
## 本喵两次自动走位（x=0 / x=10，z 从 −55 走到 −110）都**没复现**（近白只有 4~7%，就是天空）。
## 抓不到的偶发 bug 不该靠猜着改 —— 先把「发生那一刻的状态」变成证据。
##
## ⚠️ 和别的出图探针**故意不同**：这个要**玩家自己操作**，所以
##    · **不**调 `OffWin.apply()`：窗口、鼠标、焦点都要正常，不然没法走位；
##    · 必须显式传 `--play` 才启动 —— 免得本喵或别人误触发一个抢前台的窗口。
##
##   & <godot> --path . --script res://scripts/_probe_white_watch.gd -- --play
##
## 一旦判到整屏白，会：
##   ① 把校园渲染器当时的全部状态打到控制台；
##   ② 追加写 `_log/_white_watch.txt`（含玩家坐标、视口、RID 状态）；
##   ③ 存一张 `_log/_white_watch_<时刻>.png` 作证据。
## 把那个 txt 发给本喵就能继续查。

const LEVEL := "res://scenes/next_level.tscn"
const LOG_PATH := "C:/Users/WY157/Desktop/GODOT/_arisu_learn/_log/_white_watch.txt"
const SHOT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_learn/_log"

const SAMPLE_SEC := 0.4
const WHITE_PIXEL := 0.961      # 三通道都 > 245/255
const WHITE_RATIO := 0.90       # 近白像素占比阈值
const CONFIRM := 3              # 连续几次才算（躲开过曝的天空/闪光）

var _acc := 0.0
var _streak := 0
var _last_state := ""
var _dumps := 0


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--play"):
		print("[watch] 本探针会开一个**正常窗口**（不挪到屏幕外），所以要显式确认：")
		print("[watch]    加 `-- --play` 再跑。")
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[watch] 加载不了关卡")
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	print("[watch] 开跑了。本喵会在后台盯着；出现整屏白就记进 %s" % LOG_PATH)
	print("[watch] 想去哪就去哪，复现了也不用管，本喵自己会记。")
	while true:
		await process_frame
		_acc += get_root().get_process_delta_time() if false else (1.0 / 60.0)
		if _acc < SAMPLE_SEC:
			continue
		_acc = 0.0
		_check(level)


func _check(level: Node) -> void:
	var ggs := level.get_node_or_null("CampusGGS")
	var player := level.get_node_or_null("Player")
	if ggs == null:
		return
	# 状态变化就记一行（便宜，且能和时间线对上）
	var st := _state_line(ggs, player)
	if st != _last_state:
		_last_state = st
		_write("STATE  " + st)
	var img := root.get_texture().get_image()
	if img == null:
		return
	img.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	var w := _white_ratio(img)
	if w > WHITE_RATIO:
		_streak += 1
	else:
		_streak = 0
	if _streak == CONFIRM:
		_dumps += 1
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		var shot := "%s/_white_watch_%s.png" % [SHOT_DIR, stamp]
		root.get_texture().get_image().save_png(shot)
		_write("")
		_write("########## 整屏白 #%d（近白 %.1f%%）##########" % [_dumps, w * 100.0])
		_write("  截图 %s" % shot)
		_write("  " + _state_line(ggs, player))
		_write("  _active=%s _released=%s _ready_done=%s _use_chunks=%s _gave_up=%s"
			% [str(ggs.get("_active")), str(ggs.get("_released")),
				str(ggs.get("_ready_done")), str(ggs.get("_use_chunks")),
				str(ggs.get("_gave_up"))])
		_write("  _bin_path=%s" % str(ggs.get("_bin_path")))
		_write("  _window_names=%s" % ", ".join(ggs.get("_window_names")))
		_write("  _write_thread=%s _pending=%d" % [
			str(ggs.get("_write_thread") != null),
			(ggs.get("_pending_window") as PackedStringArray).size()])
		_write("  _fine_ready=%s _coarse_ready=%s" % [
			str(ggs.get("_fine_ready")), str(ggs.get("_coarse_ready"))])
		_write("  quad=%s visible=%s" % [
			str(ggs.get("quad") != null),
			str((ggs.get("quad") as Node3D).visible) if ggs.get("quad") != null else "-"])
		for rname in ["rasterizer", "coarse_rasterizer"]:
			var r = ggs.get(rname)
			if r == null:
				_write("  %s=null" % rname)
				continue
			_write("  %s: is_loaded=%s render_scale=%s texture_size=%s bin=%s" % [
				rname, str(r.is_loaded), str(r.render_scale), str(r.texture_size),
				str(r.bin_path)])
			var rt = r.render_texture
			_write("      render_texture=%s rid_valid=%s" % [
				str(rt != null), str(rt.texture_rd_rid.is_valid()) if rt != null else "-"])
		for tname in ["tex", "coarse_tex"]:
			var t = ggs.get(tname)
			_write("  %s: %s rid_valid=%s" % [
				tname, str(t != null), str(t.texture_rd_rid.is_valid()) if t != null else "-"])


func _state_line(ggs: Node, player: Node) -> String:
	var p := "?"
	if player != null:
		var q: Vector3 = player.global_position
		p = "(%.1f, %.1f, %.1f)" % [q.x, q.y, q.z]
	return "z=%s active=%s window=%d fine=%s coarse=%s vp=%s" % [
		p, str(ggs.get("_active")),
		(ggs.get("_window_names") as PackedStringArray).size(),
		str(ggs.get("_fine_ready")), str(ggs.get("_coarse_ready")),
		str(DisplayServer.window_get_size())]


func _white_ratio(img: Image) -> float:
	var n := 0
	var w := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			n += 1
			if c.r > WHITE_PIXEL and c.g > WHITE_PIXEL and c.b > WHITE_PIXEL:
				w += 1
	return float(w) / maxf(float(n), 1.0)


func _write(s: String) -> void:
	print(s)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(s)
	f.close()
