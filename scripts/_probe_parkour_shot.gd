extends SceneTree
## 探针：给跑酷 **v3**（`scenes/parkour.tscn`，6 段 / 59 站 / 跳距 175 m）出机位图。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_parkour_shot.gd -- --splat=off
##
## ⚠️ 加 `--splat=off`：这一套只关心跑酷，画室609 那 277 万点白白拖慢每一张。
##    代价是图里没有画室（平台地面是兜底方盒）—— 想看两者同框就别加。
##
## 输出：…/_arisu_captures/_parkour/*.png（1600 × 900）—— **14 张**
##   10_start       站在跑道东端往西看：第一眼应该看得出「往那边走」
##   11_edge        平台边缘：起跳段两块极限跳的间距
##   12_bridge      独木桥：0.80 m 宽、中间断开那一段（含断裂处的石台）
##   13_corner      绕角跳：T1 转身台 → 往北的 T2 → 折回西边的 T3
##   14_stairs      台阶链：每级 +0.40、要助跑的四级
##   ── 以下 8 张是 v3 新增段 ──
##   15_sidejump    ★横跳区：5 块窄板 z 向左右交替，一路按 W 是过不去的
##   16_mover       ★移动平台：平台本体 + 两岸缺口 + 第二座平台（同框）
##   17_spiral_low  ★绕柱螺旋塔：**从下往上仰拍**，看得出板绕着柱转圈上去
##   18_spiral_high ★绕柱螺旋塔：高位 3/4 视角，看八级台阶与中央柱
##   19_mech        ★机关区：弹跳板 + 消失方块串联（同框）
##   20_mech_air    ★机关区：上升气流柱 + 第二块弹跳板 + 传送门 + **对岸那张板**
##   21_shaft       ★竖井：从井口往下看错开的四层小台
##   22_island      终点岛：信号塔 + 掩体 + 传送台（台面 y = 8.00）
##   23_plan        近乎垂直俯视：整条 290 m 的落位与走向
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
	#    ⚠️ 跑酷自带的计时 HUD 挂在 **`Parkour/ParkourHUD`**（跑酷场景的子节点，
	#       而且已经被挪到右上角），不在 game 根下 —— 写成
	#       `game.get_node_or_null("ParkourHUD")` 会**静默漏掉**，图上带一大块计时文字。
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

	# ── 段 1~2（v2 原样，机位不变）──
	await _shot("10_start", Vector3(-8.5, 2.0, 4.0), Vector3(-26.0, 0.6, 4.0))
	await _shot("11_edge", Vector3(-19.0, 2.4, 4.0), Vector3(-32.0, 0.5, 4.0))
	await _shot("12_bridge", Vector3(-86.0, 4.6, 11.0), Vector3(-90.0, 0.5, 4.0))
	await _shot("13_corner", Vector3(-92.0, 8.0, -1.0), Vector3(-101.0, 0.6, -1.0))
	await _shot("14_stairs", Vector3(-110.0, 6.0, 3.0), Vector3(-120.0, 1.6, -4.9))
	# ── 段 3 横跳区（X1..X5 在 x −141~−165，z 在 −3.4 / −6.4 之间交替；F1 −170.75）──
	# 斜俯视：贴到 X2~X5 正上方，一眼看出「窄板一左一右」；右下角带出 F1 与 MoverA
	await _shot("15_sidejump", Vector3(-152.0, 7.2, 3.4), Vector3(-160.0, 2.2, -5.6))
	# 移动平台特写：MoverA 在 F1(−170.75)⇄F2(−180.25) 之间，歪着拍才看得见缺口与平台本体
	await _shot("16_mover", Vector3(-175.5, 4.6, 7.5), Vector3(-181.0, 2.2, -5.0))
	# ── 段 4 绕柱螺旋塔（中央柱轴在 x −199.7 / z −4.9，W1 y2.80 → C4 y8.40）──
	# 「从下往上仰拍」：相机压在柱基下面（柱底 y1.8），稍微退远一点让台面吃到光
	await _shot("17_spiral_low", Vector3(-199.7, 1.6, 2.6), Vector3(-199.7, 6.2, -4.9))
	# 高位 3/4：看得到台阶是**绕着柱**上去的，不是一条直线
	await _shot("18_spiral_high", Vector3(-191.5, 12.5, 1.5), Vector3(-200.0, 5.4, -4.9))
	# ── 段 5 机关区 ──
	# 弹跳板（E1→Q1→H1）+ 四块消失方块 V1..V4 同框：贴近到 18 m 内，看得到金色机关板
	await _shot("19_mech", Vector3(-212.0, 14.0, 1.0), Vector3(-224.0, 12.6, -7.5))
	# 上升气流柱（U1 12.80 → U2 17.80）+ 第二块弹跳板 Q2 + 传送门 + **对岸 C5**：
	# 站在气流柱东南下方 20 m 处仰着看，不把整座岛收进来
	await _shot("20_mech_air", Vector3(-238.0, 20.0, 3.0), Vector3(-252.0, 15.5, -7.5))
	# ── 段 6 竖井（J1 y13.80 → J4 y9.60，开口在 z −5.9 / −9.1 之间错开）──
	await _shot("21_shaft", Vector3(-288.0, 17.5, -2.0), Vector3(-300.0, 11.5, -7.5))
	# 终点岛（中心 x −321.9 / z −9.1，台面 y 8.00）
	await _shot("22_island", Vector3(-308.0, 15.0, 2.0), Vector3(-322.0, 9.0, -9.5))
	# 近乎垂直俯视：`look_at` 的 up 不能和视线重合，所以目标点错开 0.5 m
	await _shot("23_plan", Vector3(-175.0, 170.0, -4.0), Vector3(-175.0, 0.0, -4.5))

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
