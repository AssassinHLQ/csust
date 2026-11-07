extends SceneTree
## 临时：验证 GGS 室内释放 / 出门重建。
##   _tools/run_shot.sh res://scripts/_probe_ggs_inside.gd -- --splat=off

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _vram() -> float:
	return float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0


func _fps() -> float:
	return float(Performance.get_monitor(Performance.TIME_FPS))


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _wait(120)
	var ggs := scene.get_node_or_null("CampusGGS") as Node
	var player := scene.get_node_or_null("Player") as Node3D
	if ggs == null or player == null:
		print("[ggsprobe] 缺 CampusGGS 或 Player")
		quit(1)
		return
	print("[ggsprobe] 初始 VRAM=%.1f MiB  hide=%s" % [_vram(), str(ggs.hide_inside_aabb)])
	player.global_position = Vector3(0, 1.6, 0)
	await _wait(40)
	print("[ggsprobe] 室内 释放后 rasterizer=%s quad=%s VRAM=%.1f MiB" % [
		str(ggs.rasterizer), str(ggs.quad), _vram()])
	await _wait(90)
	print("[ggsprobe] 室内 FPS=%.1f VRAM=%.1f MiB" % [_fps(), _vram()])
	player.global_position = Vector3(0, 1.6, 16)
	await _wait(40)
	print("[ggsprobe] 门外 rasterizer=%s quad=%s VRAM=%.1f MiB" % [
		str(ggs.rasterizer), str(ggs.quad), _vram()])
	await _wait(240)
	print("[ggsprobe] 重建后 FPS=%.1f rasterizer=%s quad=%s VRAM=%.1f MiB" % [
		_fps(), str(ggs.rasterizer), str(ggs.quad), _vram()])
	quit(0)
