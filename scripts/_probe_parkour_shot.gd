extends SceneTree
## 探针：给跑酷 **v2**（`scenes/parkour.tscn`，4 段 / 33 站 / 206 m）出机位图。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_parkour_shot.gd -- --splat=off
##
## ⚠️ 加 `--splat=off`：这一套只关心跑酷，画室609 那 277 万点白白拖慢每一张。
##    代价是图里没有画室（平台地面是兜底方盒）—— 想看两者同框就别加。
##
## 输出：…/_arisu_captures/_parkour/*.png（1600 × 900）
##   10_start     站在跑道东端往西看：第一眼应该看得出「往那边走」
##   11_edge      平台边缘：起跳段两块极限跳的间距
##   12_bridge    独木桥：0.80 m 宽、中间断开那一段（含断裂处的石台）
##   13_corner    绕角跳：T1 转身台 → 往北的 T2 → 折回西边的 T3
##   14_stairs    台阶链：每级 +0.40、要助跑的四级
##   15_tower     上升塔：从 C2 一路 +0.80 到 U6（最高点 6.80）
##   16_longjump  5 m 级长跳：U6 → C3（贴边起跳那一跳）
##   17_descent   下降链：−1.0~−1.2，落在 1.6 m 小石台上
##   18_island    终点岛：信号塔 + 掩体 + 传送台
##   19_plan      近乎垂直俯视：整条 206 m 的落位与走向
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
	#    ⚠️ 跑酷自带的计时 HUD 挂在 **`Parkour/ParkourHUD`**（跑酷场景的子节点），
	#       不在 game 根下 —— 写成 `game.get_node_or_null("ParkourHUD")` 会静默漏掉。
	for n in ["HUD", "SettingsMenu", "DialogueBox", "Parkour/ParkourHUD"]:
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

	await _shot("10_start", Vector3(-8.5, 2.0, 4.0), Vector3(-26.0, 0.6, 4.0))
	await _shot("11_edge", Vector3(-19.0, 2.4, 4.0), Vector3(-32.0, 0.5, 4.0))
	await _shot("12_bridge", Vector3(-86.0, 4.6, 11.0), Vector3(-90.0, 0.5, 4.0))
	await _shot("13_corner", Vector3(-92.0, 8.0, -1.0), Vector3(-101.0, 0.6, -1.0))
	await _shot("14_stairs", Vector3(-110.0, 6.0, 3.0), Vector3(-120.0, 1.6, -4.9))
	await _shot("15_tower", Vector3(-146.0, 13.0, 5.0), Vector3(-152.0, 4.6, -8.0))
	await _shot("16_longjump", Vector3(-168.0, 11.0, -3.0), Vector3(-174.0, 6.8, -11.7))
	await _shot("17_descent", Vector3(-186.0, 12.0, -4.0), Vector3(-198.0, 3.4, -11.7))
	await _shot("18_island", Vector3(-213.0, 7.0, -4.0), Vector3(-226.0, 1.6, -11.0))
	# 近乎垂直俯视：`look_at` 的 up 不能和视线重合，所以目标点错开 0.5 m
	await _shot("19_plan", Vector3(-118.0, 118.0, -6.0), Vector3(-118.0, 0.0, -6.5))

	print("\n出图目录：%s" % _out)
	quit(0)


## 出一张图。
##
## ⚠️ 等的是「**真的有新帧画出来**」，而且**有界**：窗口被别的窗口遮住 / 被最小化 /
##    GPU 被抢时，帧可能长时间不来 —— 无界等一帧会把整台自检挂死
##    （v1 的 `_verify_boss` 就这样卡了 19 分钟）。2 s 等不到就跳过这张图。
func _shot(name: String, pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	if Engine.get_frames_drawn() == before:
		print("  [img] 跳过 %s（窗口 2 s 内没有画出新帧）" % name)
		return
	# 再多等几帧：阴影、灯光、CSG 网格都稳定下来再抓
	await _wait(6)
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("[parkour] %s  ← 相机 %s" % [name, str(pos.snappedf(0.1))])


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
