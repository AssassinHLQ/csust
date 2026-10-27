extends SceneTree
## 出图：蒙德里安二层的新入口 + 下一场景（门厅）内部。
##   _tools/run_shot.sh res://scripts/_probe_gate_shot.gd
## 输出（工作区 _arisu_captures/）：
##   _gate_2f.png          二层房间里的门（玩家站在跟前，提示牌亮起）
##   _next_level_a.png     门厅：北墙的蒙德里安配色
##   _next_level_b.png     门厅：返回门

func _initialize() -> void:
	_run.call_deferred()


func _shot(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(file_name)
	img.save_png(out)
	print("[截图] %s" % out)


func _run() -> void:
	root.size = Vector2i(1600, 900)

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame
	for c in game.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var gate := game.find_child("MondrianGate", true, false) as Node3D
	var player := game.get_node_or_null("Player") as Node3D
	if gate == null or player == null:
		print("[截图] 缺少 MondrianGate / Player")
		quit(1)
		return
	player.global_position = gate.call("arrival_point")
	for _i in 40:
		await process_frame

	var cam := Camera3D.new()
	cam.fov = 58.0
	game.add_child(cam)
	cam.global_position = Vector3(28.6, 5.55, 11.5)
	cam.look_at(gate.global_position + Vector3(0.0, 0.95, 0.0))
	cam.current = true
	await _shot("_gate_2f.png")

	# 退到楼梯口看整间二层：门在东北角、楼梯在西南角
	cam.global_position = Vector3(22.6, 5.9, 15.4)
	cam.look_at(Vector3(31.2, 5.0, 7.9))
	cam.fov = 72.0
	await _shot("_gate_2f_room.png")

	# 门厅是独立场景：先把主场景收掉，免得两套场景叠在一起
	game.queue_free()
	for _i in 4:
		await process_frame

	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 40:
		await process_frame
	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false

	var cam2 := Camera3D.new()
	cam2.fov = 66.0
	level.add_child(cam2)
	cam2.current = true
	cam2.global_position = Vector3(0.0, 1.65, 3.6)
	cam2.look_at(Vector3(0.0, 1.45, -4.5))
	await _shot("_next_level_a.png")

	cam2.global_position = Vector3(-4.4, 1.8, -3.3)
	cam2.look_at(Vector3(0.6, 1.35, 4.4))
	await _shot("_next_level_b.png")

	quit(0)
