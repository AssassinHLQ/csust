extends SceneTree
## 逐个量 `game.tscn` 里每个 `ext_resource` 子场景的 load 耗时，
## 找出开局 1.6 s 的 `load(game.tscn)` 到底被谁吃掉。
##
##   godot --headless --script res://scripts/_probe_subscene_cost.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await OffWin.apply(self)
	await _wait(2)
	print("[sub] ============ game.tscn 各子场景 load 耗时 ============")

	var txt := FileAccess.get_file_as_string(GAME)
	if txt.is_empty():
		print("[sub] !! 读不到 %s" % GAME)
		quit(1)
		return

	# 抓出所有 path="res://..." 的 ext_resource
	var paths: Array[String] = []
	for line in txt.split("\n"):
		var l := line.strip_edges()
		if not l.begins_with("[ext_resource"):
			continue
		var i := l.find("path=\"")
		if i < 0:
			continue
		var j := l.find("\"", i + 6)
		if j < 0:
			continue
		var p := l.substr(i + 6, j - i - 6)
		if not paths.has(p):
			paths.append(p)

	print("[sub] 共 %d 个子场景/资源" % paths.size())

	var rows := []
	var total := 0.0
	for p in paths:
		var t0 := Time.get_ticks_usec()
		var r = load(p)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		rows.append([ms, p, r != null])

	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("[sub] ---- 按耗时降序（只列 > 5 ms 的）----")
	for r in rows:
		if r[0] < 5.0:
			continue
		print("[sub] %8.1f ms  %s%s" % [r[0], r[1], "" if r[2] else "   !! 加载失败"])
	print("[sub] ---- 合计 %.1f ms（逐个 load，可能有缓存影响）----" % total)

	# 再看几个已知的大文件单独 load 的耗时
	print("[sub] ---- 几个大件单独量 ----")
	for p in [
		"res://models/esports_room/esports_room.glb",
		"res://scenes/esports_collision_baked.tscn",
		"res://scenes/mondrian_house_baked.tscn",
	]:
		if not ResourceLoader.exists(p):
			print("[sub] %-52s （不存在）" % p)
			continue
		var t0 := Time.get_ticks_usec()
		load(p)
		print("[sub] %8.1f ms  %s" % [(Time.get_ticks_usec() - t0) / 1000.0, p])

	quit(0)
