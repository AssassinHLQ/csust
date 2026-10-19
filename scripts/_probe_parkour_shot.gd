extends SceneTree
## 探针：给跑酷 **v3**（`scenes/parkour.tscn`，6 段 / 59 站 / 跳距 175 m）出机位图。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_parkour_shot.gd -- --splat=off
##
## ⚠️ 加 `--splat=off`：这一套只关心跑酷，画室609 那 277 万点白白拖慢每一张。
##    代价是图里没有画室（平台地面是兜底方盒）—— 想看两者同框就别加。
##
## 输出：…/_arisu_captures/_parkour/*.png（1600 × 900）—— **30 张**
##   （下面这份旧清单只覆盖 10~23；后面加了期货通 / 比特币三线 / 期权 / A股 / 外汇 /
##     暗网比纳 / **36·37 内存条市场**，编号以 `_shot()` 调用处为准。）
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
	#    `Parkour/ParkourHUD` 是 2026-10-18 删掉的那套计时 HUD（用户嫌挡视线），
	#    这里留着只是**防御**：万一以后又加回来，出图不会突然多一块文字。
	for n in ["HUD", "SettingsMenu", "DialogueBox", "Parkour/ParkourHUD",
			"Parkour/Futures/FuturesHUD"]:
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

	# ── 第 0 步：跑酷准备区（金色垫子 + 同伴原地待命）──
	# 先把人挪到垫子上，让「踏入 → 同伴待命」真的发生，再拍同伴站定的样子
	if p != null:
		p.global_position = Vector3(-9.0, 0.10, 4.0)
		await _wait(10)
	await _shot("09_ready_zone", Vector3(-1.0, 4.6, 12.0), Vector3(-9.0, 1.2, 4.0))
	# ── 段 1~2（v2 原样，机位不变）──
	await _shot("10_start", Vector3(-8.5, 2.0, 4.0), Vector3(-26.0, 0.6, 4.0))
	await _shot("11_edge", Vector3(-19.0, 2.4, 4.0), Vector3(-32.0, 0.5, 4.0))
	await _shot("12_bridge", Vector3(-86.0, 4.6, 11.0), Vector3(-90.0, 0.5, 4.0))
	await _shot("13_corner", Vector3(-92.0, 8.0, -1.0), Vector3(-101.0, 0.6, -1.0))
	await _shot("14_stairs", Vector3(-110.0, 6.0, 3.0), Vector3(-120.0, 1.6, -4.9))
	# 先让玩家真的踩两块 K 线（保证金会按牌子上的涨跌幅结算），HUD 才是活的
	var pk := game.get_node_or_null("Parkour") as Parkour
	var player := game.get_node_or_null("Player") as Player
	if pk != null and player != null:
		for nm in ["K3", "K7", "K9"]:
			for idx in pk.node_count():
				if pk.label_at(idx) != nm:
					continue
				var bb := pk.box_at(idx)
				player.global_position = Vector3(bb.position.x + bb.size.x * 0.5,
					pk.top_at(idx) + 0.05, bb.position.z + bb.size.z * 0.5)
				player.velocity = Vector3.ZERO
				await _wait(8)
				break
	# ── 段 3 同花顺期货通（K1..K13 散在 x −143~−221、z −11~−3、台面 2.00 → 6.80 → 2.00）──
	await _shot("15_flush_entry", Vector3(-134.0, 3.4, 2.0), Vector3(-152.0, 3.2, -6.5))
	# 整场的 3/4 俯瞰：13 块四面散开的红绿块 + 中间那条会动的板
	await _shot("16_futures_field", Vector3(-176.0, 16.0, 26.0), Vector3(-180.0, 5.5, -7.5))
	# 升降台 + 一字板 + 平移台：站到南边近处看缺口
	await _shot("17_futures_lift", Vector3(-158.0, 9.5, 1.5), Vector3(-171.0, 6.4, -8.4))
	# 究极蓝块（强制平仓）：把相位推到实体段再拍
	var fut := game.get_node_or_null("Parkour/Futures") as ParkourFutures
	if fut != null and fut.hazards.size() > 0:
		fut._t = fut.blue_period - fut.blue_live + 0.2
		await _wait(4)
	await _shot("18_futures_blue", Vector3(-148.0, 6.5, -2.0), Vector3(-157.0, 4.4, -8.0))
	# ── 第 4 段：比特币三线（J0 −227.55 / 三道 z −1,−10,−19 / M0 −256.65）──
	# 站在分叉台上看三条道分开：三块价目牌 + 结算门槛牌
	await _shot("19_branch_split", Vector3(-222.0, 7.0, 9.0), Vector3(-238.0, 3.0, -10.0))
	# 俯瞰三条道（跨道缺口 6 m，跳不过去）
	await _shot("20_branch_lanes", Vector3(-246.0, 22.0, 26.0), Vector3(-246.0, 2.0, -10.0))
	# 结算台 + 那块会被改写的牌子
	await _shot("21_branch_merge", Vector3(-251.0, 6.5, 4.0), Vector3(-259.0, 2.5, -9.5))
	# ── 第 5~7 段：期权 / A股 / 外汇（都在 z −1.7 这条线上，x −262 ~ −337）──
	await _shot("22_option", Vector3(-257.0, 6.0, 9.0), Vector3(-272.0, 2.6, -1.7))
	await _shot("23_ashare", Vector3(-285.0, 7.0, 8.0), Vector3(-300.0, 2.5, -1.7))
	await _shot("24_fx", Vector3(-317.0, 7.0, 8.0), Vector3(-331.0, 2.4, -1.7))
	# ── 第 8 段 暗网黑市（DK1 −344.45 … DK10 −397.85）──
	# ⚠️ 比纳现在**延迟加载**（玩家跑进黑市才由 `DarkGate` 生成）：
	#    探针不跑图，得手工喊一次，再把它钉在本段中点上方，这两张图才有它入镜。
	var gate := game.get_node_or_null("Parkour/Route/DarkGate") as DarkGate
	if gate != null:
		var dark := gate.spawn()
		if dark != null:
			dark.global_position = Vector3(-374.0, 12.4, -1.7)
			dark.set_physics_process(false)      # 出图时别朝镜头打激光/炮弹
	await _wait(6)
	# 这一张**故意把 HUD 打开**：让「比纳」那行血条也进画面
	var hud_layer := game.get_node_or_null("HUD") as CanvasLayer
	if hud_layer != null:
		hud_layer.visible = true
	await _shot("25_dark_run", Vector3(-338.0, 8.0, 9.0), Vector3(-368.0, 5.0, -1.7))
	if hud_layer != null:
		hud_layer.visible = false
	await _shot("26_dark_boss", Vector3(-356.0, 14.0, 5.5), Vector3(-374.0, 12.0, -1.7))
	# ── 第 9 段「内存条市场」（X1..X5；台面改成 PCB + 金手指，头顶吊架）──
	await _shot("27_sidejump", Vector3(-414.2, 7.2, 3.4), Vector3(-422.2, 2.2, -5.6))
	await _shot("28_mover", Vector3(-437.8, 4.6, 7.5), Vector3(-443.3, 2.2, -5.0))
	# ── 第 10 段「内存条螺旋塔」（柱轴 x −461.8 / z −4.9，每层插三根散热鳍片）──
	await _shot("29_spiral_low", Vector3(-461.8, 1.6, 2.6), Vector3(-461.8, 6.2, -4.9))
	await _shot("30_spiral_high", Vector3(-453.6, 12.5, 1.5), Vector3(-462.1, 5.4, -4.9))
	# ── 内存条市场全景 + 塔（2026-10-19 新加的两张）──
	await _shot("36_ram_market", Vector3(-402.0, 9.0, 8.0), Vector3(-420.0, 2.0, -5.0))
	await _shot("37_ram_tower", Vector3(-452.0, 9.5, 4.0), Vector3(-466.0, 5.0, -5.0))
	# ── 第 11 段 机关区 ──
	await _shot("31_mech", Vector3(-474.0, 14.0, 1.0), Vector3(-486.0, 12.6, -7.5))
	await _shot("32_mech_air", Vector3(-500.0, 20.0, 3.0), Vector3(-514.0, 15.5, -7.5))
	# ── 第 12 段 竖井 / 终点岛 ──
	await _shot("33_shaft", Vector3(-550.0, 17.5, -2.0), Vector3(-562.0, 11.5, -7.5))
	await _shot("34_island", Vector3(-570.0, 15.0, 2.0), Vector3(-584.0, 9.0, -9.5))
	await _shot("35_plan", Vector3(-404.0, 210.0, -4.0), Vector3(-404.0, 0.0, -4.5))


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
