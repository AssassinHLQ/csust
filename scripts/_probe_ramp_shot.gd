extends SceneTree
## 出图：蒙德里安楼梯改成斜坡之后的样子。
##   _tools/run_shot.sh res://scripts/_probe_ramp_shot.gd -- --splat=off --no-capture
## 输出：
##   _ramp_side.png   一层站位看整条斜坡
##   _ramp_walk.png   玩家站在坡中间的第一人称视角（看相机还卡不卡栏板）

func _initialize() -> void:
	_run.call_deferred()


func _shot(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(file_name)
	root.get_texture().get_image().save_png(out)
	print("[截图] %s" % out)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false

	var house := game.get_node_or_null("MondrianHouse") as Node3D
	var hp := house.global_position
	for c in game.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false

	# 侧视图：站在一层大厅里往西看斜坡
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.fov = 62.0
	cam.global_position = Vector3(hp.x + 2.6, 1.9, hp.z + 3.4)
	cam.look_at(Vector3(hp.x - 6.9, 2.2, hp.z - 0.8))
	cam.current = true
	await _shot("_ramp_side.png")

	# 玩家视角：站在坡中间，相机在身后
	var player := game.get_node_or_null("Player") as Node3D
	player.global_position = Vector3(hp.x - 6.95, 2.15, hp.z - 0.8)
	player.set("velocity", Vector3.ZERO)
	player.set("_yaw", PI)          # 相机转到坡下、朝 +Z 往上看
	player.set("_pitch", 0.22)
	for _i in 40:
		await physics_frame
	await _shot("_ramp_walk.png")
	print("[ramp] 玩家 y=%.2f  相机 y=%.2f"
		% [player.global_position.y, (player.get("cam") as Node3D).global_position.y])
	quit(0)
