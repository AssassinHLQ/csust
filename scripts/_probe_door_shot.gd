extends SceneTree
## 探针：站在画室 609 门外看那块**淡黄色门板**（护墙有没有漏、颜色对不对）。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_door_shot.gd
##
## ⚠️ 不能加 `--splat=off`：门板是跟着泼溅一起建的，关掉就什么都没有。
## 输出：…/_arisu_captures/_door/*.png

const OUT_SUB := "_door"

var _cam: Camera3D
var _out: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	# 泼溅要解码 277 万点，等久一点
	for _i in 90:
		await process_frame
	var player := game.get_node_or_null("Player") as Player
	if player != null:
		player.set_process_input(false)
	for n in ["HUD", "SettingsMenu", "DialogueBox", "Parkour/ParkourHUD"]:
		var c := game.get_node_or_null(n) as CanvasLayer
		if c != null:
			c.visible = false

	var proxy := game.get_node_or_null("RoomProxy")
	var panel := proxy.get_node_or_null("DoorPanel") if proxy != null else null
	var room := game.get_node_or_null("Room609")
	var box := (room.call("content_world_aabb") as AABB) if room != null else AABB()
	print("[door] 代理门板 = %s；房间盒 pos %s size %s" % [
		str(panel != null), str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.near = 0.05
	_cam.far = 500.0
	root.add_child(_cam)
	_cam.make_current()

	# 门在 z− 面（x ±0.8）。**人必须先站到门外** —— 门内外切换是按玩家位置判的，
	# 只挪相机的话泼溅还亮着，看到的就是一团糊的点云（第一版就栽在这儿）。
	if player != null:
		player.global_position = Vector3(0, player.global_position.y, -9.6)
		player.velocity = Vector3.ZERO
		for _i in 30:
			await process_frame
	await _shot("1_front", Vector3(0.0, 2.0, -14.5), Vector3(0.0, 2.6, -6.78))
	await _shot("2_close", Vector3(0.0, 1.6, -9.6), Vector3(0.0, 1.6, -6.78))
	# 斜着看：检查门板和代理墙的接缝（漏不漏边）
	await _shot("3_angle", Vector3(4.5, 2.6, -12.5), Vector3(0.0, 2.2, -6.78))
	# 回屋里：代理网格隐藏、门板跟着消失，看到的是真的门洞 + 泼溅
	if player != null:
		player.global_position = Vector3(0, player.global_position.y, -4.6)
		for _i in 30:
			await process_frame
	await _shot("4_inside", Vector3(0.0, 1.9, -4.6), Vector3(0.0, 1.9, -6.78))
	print("\n出图目录：%s" % _out)
	quit(0)


func _shot(name: String, pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	if Engine.get_frames_drawn() == before:
		print("  [img] 跳过 %s（3 s 内没有新帧）" % name)
		return
	await _wait(8)
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("[door] %s ← 相机 %s" % [name, str(pos.snappedf(0.1))])


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
