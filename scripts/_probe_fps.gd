extends SceneTree
## 量帧率：悬浮平台上跑动时，校园泼溅（615 万点）到底吃掉多少 fps。
## 对比「显示泼溅」与「隐藏泼溅」两组。
##
## 用法：godot --path <工程> --script res://scripts/_probe_fps.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	# 本探针量的是**校园那一份**的 fps：入树前把画室609 摘掉（见 _verify_splat.gd 的注释）。
	# 想量「两份一起」就把这两行删掉 —— 那正是 8 GB 显存最吃紧的情形。
	var room := game.get_node_or_null("Room609")
	if room != null:
		room.free()
	root.add_child(game)
	await process_frame
	await process_frame

	var player: Player = game.get_node("Player")
	var splat: SplatScene = game.get_node("SplatScene")
	var guard := 0
	while guard < 30000 and not splat.is_ready():
		await process_frame
		guard += 1
	print("[fps] 泼溅就绪 = %s，点数 = %d" % [str(splat.is_ready()), splat.point_count])

	# 面向校园、跑到边缘低头 —— 让泼溅真的占满画面
	player.global_position = Vector3(0, 0.05, -16)
	player._yaw = 0.0
	player._pitch = -0.55
	await _wait(60)

	print("[fps] 视口 %s   渲染后端 = %s" % [
		str(root.get_visible_rect().size), RenderingServer.get_video_adapter_name()])
	for label in ["显示泼溅", "隐藏泼溅"]:
		splat.visible = label == "显示泼溅"
		await _wait(60)
		var samples := PackedFloat32Array()
		for _i in 240:
			await process_frame
			samples.append(Engine.get_frames_per_second())
		var sum := 0.0
		var lo := 1e9
		var hi := 0.0
		for v in samples:
			sum += v
			lo = minf(lo, v)
			hi = maxf(hi, v)
		print("[fps] %s：平均 %.1f fps（最低 %.0f，最高 %.0f），%d 帧采样" % [
			label, sum / samples.size(), lo, hi, samples.size()])
	splat.visible = true
	print("[fps] 显存/内存：静态 %.0f MB" % (OS.get_static_memory_usage() / 1048576.0))
	quit(0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
