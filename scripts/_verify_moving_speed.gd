extends SceneTree
## 验：会动的块（升降 / 平移 / 布朗 / 三道渡船 / 移动平台）都提速了，
## 端点停靠时间没被砍掉。  godot --path . --headless --script res://scripts/_verify_moving_speed.gd
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lvl := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(lvl)
	for _i in 30:
		await physics_frame

	var fut := lvl.get_node_or_null("Futures")
	var drifts: Array = fut.get("drifts") if fut != null else []
	print("[speed] 会动的块 %d 台：" % drifts.size())
	for d in drifts:
		var drift := d as ParkourDrift
		print("[speed]   %-12s %.1f m/s　端点停 %.1f s" % [
			drift.name, drift.speed, drift.wait_time])

	var lift := lvl.get_node_or_null("Futures/Drift_K5") as ParkourDrift
	var slide := lvl.get_node_or_null("Futures/Drift_K7") as ParkourDrift
	var brown := lvl.get_node_or_null("Futures/Drift_K9") as ParkourDrift
	var sp := lvl.get_node_or_null("Futures/Ferry_SP2") as ParkourDrift
	var bc := lvl.get_node_or_null("Futures/Ferry_BC2") as ParkourDrift
	var ma := lvl.get_node_or_null("Movers/MoverA") as ParkourMover
	var mb := lvl.get_node_or_null("Movers/MoverB") as ParkourMover
	print("[speed] 升降 %.1f（期望 3.6）/ 平移 %.1f（4.4）/ 布朗 %.1f（2.8）" % [
		lift.speed if lift != null else -1.0, slide.speed if slide != null else -1.0,
		brown.speed if brown != null else -1.0])
	print("[speed] 渡船 现货 %.1f（3.2）/ 币圈 %.1f（4.4，停 %.1f s）" % [
		sp.speed if sp != null else -1.0, bc.speed if bc != null else -1.0,
		bc.wait_time if bc != null else -1.0])
	print("[speed] 移动平台 A %.1f / B %.1f（期望 3.6，停 %.1f s）" % [
		ma.speed if ma != null else -1.0, mb.speed if mb != null else -1.0,
		ma.wait_time if ma != null else -1.0])
	quit(0)
