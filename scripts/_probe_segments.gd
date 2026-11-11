extends SceneTree
## 打印跑酷的段划分：每段起点站号、站名、以及 Futures 里被判成 fund/lottery 的板。
##
##   godot --headless --path <工程> --script res://scripts/_probe_segments.gd -- --no-capture --splat=off --story=off

const DEADLINE_S := 60.0
var _t0 := 0


func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	_watchdog()
	_run.call_deferred()


func _watchdog() -> void:
	while true:
		await create_timer(1.0).timeout
		if (Time.get_ticks_msec() - _t0) / 1000.0 > DEADLINE_S:
			printerr("[seg] 超时")
			quit(2)
			return


func _run() -> void:
	root.size = Vector2i(640, 360)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 40:
		await process_frame

	var pk := game.get_node_or_null("Parkour") as Parkour
	if pk == null:
		print("[seg] 没有 Parkour")
		quit(1)
		return
	print("[seg] segments = %s" % str(pk.segments))
	print("[seg] seg_names = %s" % str(pk.seg_names))
	print("[seg] 站数 = %d" % pk.node_count())
	for k in pk.segments.size():
		var start := pk.segment_start(k)
		print("[seg] 第 %d 段（seg=%d）：起点站 %d「%s」 → 终点站 %d" % [
			k + 1, k, start, pk.label_at(start),
			(pk.segment_start(k + 1) - 1) if k + 1 < pk.segments.size() else pk.node_count() - 1])

	# 看看 Futures 把哪些板判成了 fund / lottery
	var fut := game.get_node_or_null("Parkour/Futures")
	if fut == null:
		for n in game.find_children("*", "Node", true, false):
			if String(n.name).contains("Futures"):
				fut = n
				break
	if fut != null and fut.has_method("_collect_plates"):
		var plates: Array = fut.get("plates") if fut.get("plates") != null else []
		var fund := 0
		var lot := 0
		for pl in plates:
			var k := String(pl.get("kind", ""))
			if k == "fund":
				fund += 1
			elif k == "lottery":
				lot += 1
		print("[seg] Futures 结算板：fund=%d  lottery=%d  合计=%d" % [fund, lot, plates.size()])

	# 规则牌
	for n in game.find_children("RuleSign*", "Label3D", true, false):
		print("[seg] 规则牌 %s → 「%s」" % [String(n.name), String((n as Label3D).text).replace("\n", " / ")])
	# 关键：P1 / T1 各自属于哪一段（自检用这两个站名验证 fund / lottery）
	for want_name in ["P1", "T1", "B1", "K1"]:
		for i in pk.node_count():
			if pk.label_at(i) == want_name:
				var sg := pk.segment_of(i)
				print("[seg] 站「%s」= 第 %d 站，属于 seg=%d（%s）" % [
					want_name, i, sg,
					pk.seg_names[sg] if sg >= 0 and sg < pk.seg_names.size() else "?"])
				break

	quit(0)
