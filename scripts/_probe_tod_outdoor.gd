extends SceneTree
## 时间系统**户外**效果：同一机位，08 / 12 / 18 三个时刻各出一张。
##
##   _tools/run_shot.sh res://scripts/_probe_tod_outdoor.gd
##
## 输出 `_log/todout_08.png` / `_log/todout_12.png` / `_log/todout_18.png`。
## 机位在 40×40 平台上看向柴关电脑城（那是网格，会跟着太阳变）。

const OUT := "res://_log/todout_%02d.png"
const HOURS := [8.0, 12.0, 18.0]
const EYE := Vector3(-2.0, 7.0, 4.0)
const LOOK := Vector3(27.0, 3.5, 13.5)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(16)

	var tod := root.get_node_or_null("TimeOfDay")
	if tod == null:
		print("!! 没有 TimeOfDay 自动加载 —— project.godot 的 [autoload] 生效了吗？")
		quit(1)
		return
	# 探针里别让它自己走，手动定格
	tod.set_process(false)

	# 把玩家藏起来，只拍环境（避免人挡在镜头前）
	var p := game.get_node_or_null("Player") as Node3D
	if p != null:
		p.global_position = Vector3(4.0, 0.2, -14.0)

	var cam := Camera3D.new()
	cam.fov = 55.0
	root.add_child(cam)
	cam.global_position = EYE
	cam.look_at(LOOK, Vector3.UP)
	cam.current = true

	for h in HOURS:
		tod.set_hours(float(h))
		await _wait(10)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := OUT % int(h)
		var abs_path := ProjectSettings.globalize_path(path)
		var err := img.save_png(abs_path)
		print("[todout] %02d:00  elev=%.1f° -> %s err=%d" % [
			int(h), tod.elevation_for(float(h)), path, err])

	quit(0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
