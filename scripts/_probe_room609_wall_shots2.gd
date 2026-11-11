extends SceneTree
## 出图：609「出去 → 进去 → 再出来」—— **屋内平视** + **屋顶上方俯视** 两个固定机位。
##
##   godot --path . --script res://scripts/_probe_room609_wall_shots2.gd -- --no-capture
##
## 用户 2026-11-11：「为什么609出来,进去,再出来就失去了墙?」
## 第一版（`_probe_room609_wall_shots.gd`）从 26 m 外拍，5 步状态机全对、代理/泼溅互斥正常。
## 所以换成「人站在屋里往外看」和「站在屋顶上方往下看」两个机位，看的是**墙本身**。
##
## 同时记录 `camera.far`（用户设置 render_distance=100，本喵的 `_update_camera_far()`
## 会临时撑大它 —— 如果还原错了，远处的东西会被裁掉，表现就像「墙没了」）。
##
## ⚠️ 幕外窗口，不抢用户前台（AGENTS.md 硬要求）。

const OffWin := preload("res://scripts/offscreen_window.gd")

const OUT_DIR := "res://_arisu_captures/_fix1111"
const INSIDE := Vector3(-0.5, 0.0, 3.5)
const OUTSIDE := Vector3(-0.5, 0.0, -12.0)
## 机位 A：屋里靠 z+ 那头顶，平视往 z−（门那侧）看，能看见四面墙
const CAM_A_POS := Vector3(0.0, 1.7, 12.0)
const CAM_A_LOOK := Vector3(-0.5, 1.7, -6.0)
## 机位 B：屋顶上方，俯视整个房间（看屋面板 + 四周墙顶）
const CAM_B_POS := Vector3(18.0, 16.0, -14.0)
const CAM_B_LOOK := Vector3(-0.5, 2.0, 3.0)

var _game: Node3D
var _player: Node3D
var _room: Node
var _cam_a: Camera3D
var _cam_b: Camera3D
var _out_abs := ""


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(prefix: String) -> void:
	var proxy := _game.get_node_or_null("RoomProxy") as Node3D
	var line := "  [shot] %-26s proxy=%-5s splat=%-4s" % [
		prefix, str(proxy.visible) if proxy != null else "无",
		"在" if _room.get("splat_node") != null else "null"]
	for pair in [["a", _cam_a], ["b", _cam_b]]:
		var cam: Camera3D = pair[1]
		cam.make_current()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s_%s.png" % [_out_abs, prefix, pair[0]])
		line += "  far_%s=%.0f" % [pair[0], cam.far]
	print(line)


func _goto(pos: Vector3, frames: int) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	await _wait(frames)


func _wait_ready(max_loops: int) -> void:
	var n := 0
	while not _room.call("is_ready") and n < max_loops:
		await _wait(10)
		n += 10


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("[FAIL] 必须开真窗口")
		quit(1)
		return
	await OffWin.apply(self, Vector2i(1600, 900))
	for w in OffWin.is_safe():
		print("  [safe] %s" % w)

	_out_abs = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out_abs)

	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_game)
	_player = _game.get_node_or_null("Player") as Node3D
	_room = _game.get_node_or_null("Room609")
	if _player == null or _room == null:
		print("[FAIL] 没有 Player / Room609")
		quit(1)
		return

	_cam_a = Camera3D.new()
	_cam_a.fov = 70.0
	_cam_a.far = 4000.0
	_game.add_child(_cam_a)
	_cam_a.global_position = CAM_A_POS
	_cam_a.look_at(CAM_A_LOOK, Vector3.UP)

	_cam_b = Camera3D.new()
	_cam_b.fov = 60.0
	_cam_b.far = 4000.0
	_game.add_child(_cam_b)
	_cam_b.global_position = CAM_B_POS
	_cam_b.look_at(CAM_B_LOOK, Vector3.UP)

	print("  unload_outside_room = %s（用户存档里是 true）" % _room.get("unload_outside_room"))
	print("  render_distance     = %.0f" % GameSettings.render_distance())

	print("=== 等泼溅就位 ===")
	await _wait_ready(6000)
	print("  is_ready=%s" % _room.call("is_ready"))

	await _goto(INSIDE, 40)
	await _shot("1_inside_initial")

	await _goto(OUTSIDE, 90)
	await _shot("2_out_first")

	await _goto(INSIDE, 60)
	await _wait_ready(4000)
	await _wait(30)
	await _shot("3_inside_reloaded")

	await _goto(OUTSIDE, 150)
	await _shot("4_out_second")

	await _goto(INSIDE, 60)
	await _wait_ready(4000)
	await _wait(30)
	await _shot("5_inside_again")

	print("出图完成 → %s" % _out_abs)
	quit(0)
