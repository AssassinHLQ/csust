extends SceneTree
## 出图：609「出去 → 进去 → 再出来」四张固定机位对照图。
##
##   godot --path . --script res://scripts/_probe_room609_wall_shots.gd -- --no-capture
##
## 用户 2026-11-11：「为什么609出来,进去,再出来就失去了墙?」
## headless 里逻辑是对的（出→卸载+代理显示，进→重载+泼溅显示），所以要看**真画面**。
##
## 机位**完全固定**（不是跟玩家），只有玩家位置在变 —— 四张图直接叠着比就知道墙在不在。
## 相机放在 z− 那面墙外 26 m 处看整个房间盒子（z− 是封死的那面，门在 x+）。
##
## ⚠️ 幕外窗口，不抢用户前台（AGENTS.md 硬要求）：OffWin.apply + --no-capture。

const OffWin := preload("res://scripts/offscreen_window.gd")

const OUT_DIR := "res://_arisu_captures/_fix1111"
const INSIDE := Vector3(-0.5, 0.0, 3.5)
const OUTSIDE := Vector3(-0.5, 0.0, -12.0)
## 固定机位：房间外面，越过 z− 墙看进去
const CAM_POS := Vector3(0.0, 9.0, -26.0)
const CAM_LOOK := Vector3(-0.5, 2.0, 2.0)

var _game: Node3D
var _player: Node3D
var _room: Node
var _cam: Camera3D
var _out_abs := ""


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> void:
	_cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_out_abs, name])
	print("  [shot] %s.png  （玩家 %s / proxy visible=%s / splat=%s）" % [
		name, str(_player.global_position.snappedf(0.1)),
		str((_game.get_node_or_null("RoomProxy") as Node3D).visible),
		"在" if _room.get("splat_node") != null else "null"])


func _goto(pos: Vector3, frames: int) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	await _wait(frames)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("[FAIL] 这支出图探针必须开真窗口（--headless 拿不到渲染纹理）")
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

	# 固定机位相机（不跟玩家）
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 4000.0
	_game.add_child(_cam)
	_cam.global_position = CAM_POS
	_cam.look_at(CAM_LOOK, Vector3.UP)

	# 强制打开卸载开关（用户真实存档里是 true，探针环境这份是 false）
	_room.set("unload_outside_room", true)
	print("  unload_outside_room 强制 = true")

	# 等泼溅就位
	print("=== 等 609 泼溅就位 ===")
	var n := 0
	while not _room.call("is_ready") and n < 6000:
		await _wait(10)
		n += 10
	print("  is_ready=%s" % _room.call("is_ready"))

	# ① 屋里（泼溅）
	await _goto(INSIDE, 30)
	await _shot("1_inside_initial")

	# ② 第 1 次出屋（代理墙应出现）
	await _goto(OUTSIDE, 60)
	await _shot("2_out_first")

	# ③ 第 1 次进屋（重载后泼溅）
	await _goto(INSIDE, 60)
	var m := 0
	while not _room.call("is_ready") and m < 4000:
		await _wait(10)
		m += 10
	await _wait(20)
	await _shot("3_inside_after_reload")

	# ④ 第 2 次出屋（用户报 bug 的那一步）
	await _goto(OUTSIDE, 120)
	await _shot("4_out_second")

	# ⑤ 再进屋看还会不会回来
	await _goto(INSIDE, 60)
	var k := 0
	while not _room.call("is_ready") and k < 4000:
		await _wait(10)
		k += 10
	await _wait(20)
	await _shot("5_inside_again")

	print("出图完成 → %s" % _out_abs)
	quit(0)
