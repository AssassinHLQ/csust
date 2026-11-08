extends SceneTree
## 拍：开局（未成交）时东侧的实景 —— 部室 + 地块必须在，电竞房不在。
## 使用者 2026-11-08：「游戏开发部及其地面一直都要在！！只有电竞房是买的」
##
##   & godot --script res://scripts/_probe_east_always_on.gd -- --splat=off --story=off
##
## 出图：`_arisu_captures/_east_always_on/`

const ShopClerkScript := preload("res://scripts/shop_clerk.gd")
const OUT := "res://_arisu_captures/_east_always_on"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, p: Vector3, t: Vector3, nm: String) -> void:
	cam.global_position = p
	if p.distance_to(t) > 0.01:
		cam.look_at(t, Vector3.UP)
	await _wait(8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, nm])
	print("[on] shot %s" % nm)


func _run() -> void:
	await _wait(3)
	ShopClerkScript._bought = false   # 开局，没成交
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await _wait(60)

	# 用游戏自带相机（root 里已有 Camera3D），直接造一个自己的并强制 current
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 900.0
	root.add_child(cam)
	cam.current = true
	await _wait(2)

	# 部室在 (52, 0.01, 0)，地块同位置；从西南斜看过去
	await _shot(cam, Vector3(38.0, 9.0, -18.0), Vector3(52.0, 1.5, 2.0), "01_gamedev_from_west")
	await _shot(cam, Vector3(52.0, 3.0, -16.0), Vector3(52.0, 2.0, 0.0), "02_gamedev_front")
	await _shot(cam, Vector3(52.0, 26.0, -26.0), Vector3(52.0, 0.0, 6.0), "03_east_above")
	# 电竞房该在 (52, 0.01, 13) —— 这块应该是空的
	await _shot(cam, Vector3(52.0, 6.0, 34.0), Vector3(52.0, 1.0, 13.0), "04_esports_should_be_empty")

	print("[on] 状态：LotEast=%s GameDevRoom=%s EsportsRoom=%s"
		% [str((game.get_node("LotEast") as Node3D).visible),
		   str((game.get_node("GameDevRoom") as Node3D).visible),
		   str((game.get_node("EsportsRoom") as Node3D).visible)])
	print("[on] DONE")
	quit(0)
