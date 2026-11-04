extends SceneTree
## 验「跨格滞回」：站在格子交界处来回走，数窗口切换了几次。
##
##   _tools/run_shot.sh res://scripts/_probe_window_hysteresis.gd
##
## 背景：原来 `_pick_window()` 是「按 XZ 距离取最近 9 块」，站在交界处左右晃，
## 距离序一变窗口就跟着变，每变一次就是一次「重拼 bin + 重传」≈ 0.5~1.2 s 卡顿。
## 2026-11-05 改成「中心格 ±1 + 2 m 滞回」后，理论上来回走**只该切 1 次**。
##
## 判据：来回 10 趟（20 次跨线）切换次数应 ≤ 1。

## 格子约 20×17 m。i=6 的中心 x≈33~41，i=7 的中心 x≈57~61 → 中界线 x≈49。
## z 取 −160（在 j=4 里，远离 z 方向的中线），只让玩家横跨一条中线。
const CX := 49.0
const CZ := -160.0
const AMP := 1.5
const TRIPS := 10


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await _wait(30)

	var ggs := level.get_node_or_null("CampusGGS")
	if ggs == null:
		await _wait(120)
		ggs = level.get_node_or_null("CampusGGS")
	if ggs == null:
		print("!! 没找到 CampusGGS")
		quit(1)
		return
	var p := level.get_node_or_null("Player") as Node3D
	if p == null:
		print("!! 没找到 Player")
		quit(1)
		return
	if not bool(ggs.get("_use_chunks")):
		print("!! 当前不是分块模式（chunks.json 不在？）")
		quit(1)
		return
	p.set_physics_process(false)

	# 先落位，让首个窗口成型并上传完
	p.global_position = Vector3(CX, 1.0, CZ)
	for _i in 600:
		await process_frame
		var r = ggs.get("rasterizer")
		if r != null and bool(r.get("is_loaded")):
			break
	var first: PackedStringArray = ggs.get("_window_names")
	print("[hyst] 起点窗口（%d 块）：%s" % [first.size(), str(first)])
	print("[hyst] 中心格 = %s｜滞回余量 = %.1f m｜窗口 %d×%d" % [
		str(ggs.get("_center_name")), float(ggs.get("hyst_m")),
		int(ggs.get("window_side")), int(ggs.get("window_side"))])

	# 来回走：每次位移后等 0.7 s 让 WINDOW_POLL 有机会评估
	var switches := 0
	var last := first
	var log_lines: Array = []
	for t in TRIPS:
		for dir in [1.0, -1.0]:
			# 只横跨 x 方向的中线，来回 1.5 m（滞回余量 4 m，落在死区里）
			p.global_position = Vector3(CX + dir * AMP, 1.0, CZ)
			for _i in 42:      # ≈0.7 s @60fps
				await process_frame
			var now: PackedStringArray = ggs.get("_window_names")
			if now != last:
				switches += 1
				var c := String(ggs.get("_center_name"))
				log_lines.append("  第 %d 趟 %s → 中心 %s（%d 块）" % [
					t + 1, "+" if dir > 0.0 else "−", c, now.size()])
				last = now
	print("[hyst] 来回 %d 趟（跨线 %d 次）→ 窗口切换 %d 次" % [
		TRIPS, TRIPS * 2, switches])
	for l in log_lines:
		print(String(l))
	print("[hyst] 判据：≤ 1 次算通过（原来按距离取最近 9 块时会反复翻）")
	quit(0)
