extends SceneTree
## 探针：给「跑酷路线」（`scenes/parkour.tscn`）出机位图。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_parkour_shot.gd -- --splat=off
##
## ⚠️ 加 `--splat=off`：这一套只关心跑酷，画室609 那 277 万点白白拖慢每一张。
##    代价是图里没有画室（平台地面是兜底方盒）—— 想看两者同框就别加。
##
## 输出：…/_arisu_captures/_parkour/*.png（1600 × 900）
##   10_start     站在跑道东端往西看：第一眼应该看得出「往那边走」
##   11_edge      平台边缘：10 跳的连线 + 尽头的岛
##   12_side      南侧高空侧视：整条路线的高度剖面（先升到 +5.70 再落到 +4.70）
##   13_plan      近乎垂直俯视：板的落位与间距
##   14_beam      站在窄梁中段往前看（0.80 m 宽那一段）
##   15_landing   最后一跳的落点：岛面东侧净空 + 四角警示柱
##   16_tower     岛上看信号塔与掩体
##   17_return    传送台特写（「回平台」唯一的路）
##
## 顺手关掉 HUD / 设置 / 对话框，图里只有场景本身。

const OUT_SUB := "_parkour"

var _cam: Camera3D
var _out: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)

	# 图里不要 UI。⚠️ 必须是 `CanvasLayer`（HUD/设置/对话框都是 CanvasLayer，
	#    不是 CanvasItem，用 `as CanvasItem` 会拿到 null 而静默失效）。
	for n in ["HUD", "SettingsMenu", "DialogueBox"]:
		var c := game.get_node_or_null(n) as CanvasLayer
		if c != null:
			c.visible = false
	var p := game.get_node_or_null("Player")
	if p != null:
		p.set_process_input(false)

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)

	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.near = 0.05
	_cam.far = 500.0
	root.add_child(_cam)
	_cam.make_current()

	await _shot("10_start", Vector3(-8.5, 2.0, 4.0), Vector3(-24.0, 0.6, 4.0))
	await _shot("11_edge", Vector3(-18.5, 2.2, 4.0), Vector3(-27.0, 0.5, 4.0))
	await _shot("12_side", Vector3(-45.0, 22.0, 42.0), Vector3(-52.0, 3.5, 3.5))
	# 近乎垂直俯视：`look_at` 的 up 不能和平行方向的视线重合，所以目标点错开 0.5 m
	await _shot("13_plan", Vector3(-56.0, 62.0, 4.0), Vector3(-56.0, 0.0, 3.5))
	await _shot("14_beam", Vector3(-39.5, 2.6, 4.4), Vector3(-58.0, 3.6, 3.4))
	await _shot("15_landing", Vector3(-71.0, 7.5, 3.0), Vector3(-80.0, 4.7, 3.0))
	await _shot("16_tower", Vector3(-79.5, 6.6, 4.0), Vector3(-90.2, 12.0, 1.0))
	await _shot("17_return", Vector3(-85.0, 7.0, 10.0), Vector3(-88.2, 5.0, 8.0))

	print("\n出图目录：%s" % _out)
	quit(0)


func _shot(name: String, pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	# 多等几帧：阴影、灯光、网格都稳定下来再抓
	await _wait(8)
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("[parkour] %s  ← 相机 %s" % [name, str(pos.snappedf(0.1))])


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
