extends SceneTree
## 在**游戏实际场景**里拍电竞房（用 game.tscn，位置/朝向跟玩家看到的一致）。
##
##   godot --path . --windowed --script res://scripts/_probe_esports_ingame.gd
##
## ⚠️ 为什么不用独立场景（`esports_room.tscn`）拍：使用者在编辑器里把电竞房
##    **绕 Y 转了 90°**（game.tscn 里 basis 是旋转矩阵，x=53.27、y=3.90），
##    独立实例拍出来的视角跟玩家看到的完全不一样 —— 白调了好几轮灯光参数。
##    这里直接用 game.tscn，相机按**玩家站在东侧门外往里看**的角度摆。
##
## 输出：res://_arisu_captures/_esports_ingame/

const GAME := "res://scenes/game.tscn"
const OUT := "res://_arisu_captures/_esports_ingame"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var t := create_timer(300.0, true)
	t.timeout.connect(func():
		print("[ingame] !! 看门狗超时")
		quit(1))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var game := (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await _wait(90)

	# 电竞房（打开它，不管 visible 设置）
	var room := game.get_node_or_null("EsportsRoom") as Node3D
	if room == null:
		print("[ingame] !! 没有 EsportsRoom")
		quit(1)
		return
	room.visible = true
	print("[ingame] EsportsRoom 位置 %s  旋转 %s" % [
		str(room.global_position.snappedf(0.01)),
		str(room.global_rotation_degrees.snappedf(0.1))])

	# 房间在世界里的包围盒 → 算相机位置
	var box := AABB()
	var first := true
	for m in room.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	print("[ingame] 房间世界 AABB  pos=%s size=%s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])

	# 灯有多少
	var nlights := 0
	for n in room.find_children("*", "Light3D", true, false):
		nlights += 1
	print("[ingame] 房间里 %d 盏灯" % nlights)

	var cam := Camera3D.new()
	cam.far = 300.0
	cam.near = 0.05
	root.add_child(cam)
	cam.current = true

	var c := box.position + box.size * 0.5
	# 从四个方向往里看（房间是斜的，用世界轴向扫一圈最省事）
	for i in 4:
		var ang := float(i) * PI * 0.5
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		await _shot(cam, c + Vector3(dir.x, 0.0, dir.z) * (box.size.length() * 0.7),
			c + Vector3(0, -0.3, 0), "dir%d.png" % i, 70.0)
	# 从门口高度平视
	await _shot(cam, c + Vector3(0.0, 1.7, 0.0), c + Vector3(0.0, 1.2, -8.0), "eye.png", 70.0)
	# 俯视
	await _shot(cam, c + Vector3(0.01, 18.0, 0.0), c, "top.png", 60.0)

	quit(0)


func _shot(cam: Camera3D, pos: Vector3, target: Vector3, name: String, fov := 60.0) -> void:
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	cam.fov = fov
	await _wait(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "/" + name))
	print("[ingame] 拍到 %s" % name)
