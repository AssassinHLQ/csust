extends SceneTree
## 验：外汇段七块板的连乘不再狠到「必亏一半」。
##   godot --path . --headless --script res://scripts/_verify_fx_balance.gd
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lvl := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(lvl)
	for _i in 20:
		await physics_frame
	var fut := lvl.get_node_or_null("Futures")
	var quotes: Array = fut.get("quotes")

	var avg := 1.0
	var worst := 1.0
	var best := 1.0
	var n := 0
	for q in quotes:
		if String(q["node"].get_meta("lane", "")) != "FX":
			continue
		var seq: Array = q["seq"]
		var lo := 999.0
		var hi := -999.0
		var sum := 0.0
		for v in seq:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
			sum += 1.0 + float(v) / 100.0
		avg *= sum / float(seq.size())
		worst *= 1.0 + lo / 100.0
		best *= 1.0 + hi / 100.0
		n += 1
		print("[fx] %-4s %s　期望 ×%.4f　最差 ×%.4f　最好 ×%.4f" % [
			String(q["node"].name), str(seq), sum / float(seq.size()),
			1.0 + lo / 100.0, 1.0 + hi / 100.0])
	print("[fx] %d 块连乘：期望 ×%.3f（%+.1f%%）　最惨 ×%.3f（%+.1f%%）　最好 ×%.3f（%+.1f%%）" % [
		n, avg, (avg - 1.0) * 100.0, worst, (worst - 1.0) * 100.0, best, (best - 1.0) * 100.0])
	print("[fx] 结论：%s（期望亏损 ≤ 25%%、最惨不破 −65%%）" % (
		"OK" if avg >= 0.75 and worst >= 0.35 else "FAIL"))
	quit(0)
