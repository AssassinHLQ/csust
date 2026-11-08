extends SceneTree
## 演出验收：新电竞房「天降 + 落地起灰 + 环绕运镜」。
##   _tools/run_shot.sh res://scripts/_verify_esports_drop.gd -- --splat=off --story=off
##
## 做法：直接进 `game.tscn`（和真游戏同一条路），先把 `ShopClerk._bought` 置真再加载，
## 让 `game.gd::_setup_east_rooms()` 走「已成交」分支 → 演出一开场。
## 然后按帧数打点出图，覆盖：下落中段 / 刚落地 / 灰尘炸开 / 环绕中段 / 环绕末段。
## 每张图同时打印：平均亮度（判断是不是一片黑）、房间 y（判断下落曲线）。
##
## 出图目录：`_arisu_captures/_esports_drop/`

const OUT := "res://_arisu_captures/_esports_drop"
## 演出时间轴（和 esports_drop.gd 对齐）：FALL 1.45 + 0.25 前摇，之后环绕 6.2
const SHOTS := [
	[0.45, "01_falling"],
	[1.05, "02_about_to_land"],
	[1.30, "03_impact"],
	[1.75, "04_dust_spread"],
	[2.80, "05_dust_big"],
	[4.10, "06_orbit_mid"],
	[5.20, "07_orbit_late"],
]

var _fails := 0
var _drop: Node = null


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[drop] OK   %s" % what)
	else:
		_fails += 1
		print("[drop] FAIL %s" % what)


func _brightness() -> float:
	var img := root.get_texture().get_image()
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 12):
		for x in range(0, img.get_width(), 12):
			var c := img.get_pixel(x, y)
			sum += c.r + c.g + c.b
			n += 1
	return sum / maxf(float(n), 1.0)


func _snap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(tag + ".png"))
	print("[drop] 图 %-18s 亮度 %.3f" % [tag, _brightness()])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	# 先置成交，再加载场景 —— 这样 `_ready` 里就走「已成交 → 开演」
	ShopClerk._bought = true
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(2)

	var room := game.get_node_or_null("EsportsRoom") as Node3D
	_check(room != null, "场景里有 EsportsRoom")
	var drop := game.get_node_or_null("EsportsDrop")
	_check(drop != null, "成交后自动挂上 EsportsDrop（演出脚本）")
	if room == null or drop == null:
		print("[drop] 结果：起不来（%d 项不合格）" % _fails)
		quit(1)
		return
	_drop = drop

	# ⚠️ 不能写死 0.01，也不能现读 `room.position.y` —— `_ready` 跑完时
	#    演出已经把房子抬到 `_base_y + DROP_HEIGHT` 了，现读会拿到半空中的值。
	#    正确做法：取演出脚本开场记下的 `_base_pos`（= 场景里的设计位置）。
	#    使用者 2026-11-08 把 EsportsRoom 挪到了 y≈3.90 并转了个角度，
	#    落地高度跟着节点的世界 Y 走（这是设计）。
	var base_pos: Vector3 = drop.get("_base_pos")
	var base_y := base_pos.y
	print("[drop] 基准（_base_pos）= %s  y=%.4f" % [str(base_pos), base_y])
	var cam: Camera3D = drop.get("_cam")
	_check(cam != null, "演出相机已建")
	if cam != null:
		_check(cam.current, "演出相机已接管（current = true）")
		print("[drop] fov = %.1f（要求 ≥ 70 才叫「广」）" % cam.fov)
		_check(cam.fov >= 70.0, "视角够广")

	# 打点出图：`SceneTree` 脚本在 `_initialize` 之后**不会自动跑 `_process`**，
	# 所以这里每帧手动喂时间 —— 和游戏里 `_process(delta)` 完全同一条路。
	var dt := 1.0 / 60.0
	var elapsed := 0.0
	# ⚠️ `await process_frame` 一次可能跨好几帧（加载卡顿），所以每一步都要问引擎：
	#    「现在过了多少秒？」—— 用 `drop._t`，不用自己累加的 elapsed。
	#    第一版就是累加 1/60 攒到 0.55 s 才去看，而那一瞬间场景可能已经跳了 1 秒多，
	#    于是「下落中」抓到的已经是落地后的状态（y 已经回到 0.01）。
	for item in SHOTS:
		var want: float = item[0]
		while float(drop.get("_t")) < want and not bool(drop.get("_done")):
			drop._process(root.get_process_delta_time())
			await process_frame
		await _snap(String(item[1]))
		if item[1] == "01_falling":
			var y := room.position.y
			print("[drop] 下落中 t=%.2f 房间 y = %.2f（应 > %.2f）" % [
				float(drop.get("_t")), y, base_y + 5.0])
			_check(y > base_y + 5.0, "下落阶段房子确实在天上")
		if item[1] == "03_impact":
			_check(absf(room.position.y - base_y) < 0.2, "落地后房子回到原位 y=%.3f" % room.position.y)
			var dust: Array = drop.get("_dust")
			_check(dust.size() >= 5, "灰尘层 %d 个（这一版要 ≥5）" % dust.size())
			# 粒子只在落地那一刻发出**一个**脉冲（explosiveness ≈ 1），
			# 一两百毫秒后就 `emitting = false` 了 —— 所以这里判断的是
			# **它曾经喷过**（`emitting` 或「已经吐过粒子」），不是"现在还在喷"。
			var fired := 0
			var total_amount := 0
			for d in dust:
				if not is_instance_valid(d):
					continue
				var gp := d as GPUParticles3D
				total_amount += gp.amount
				if gp.emitting or gp.has_meta("drop_fired"):
					fired += 1
			print("[drop] 灰尘：%d 层 / 合计 %d 颗，%d 层已触发" % [dust.size(), total_amount, fired])
			_check(fired >= 5, "落地瞬间 %d 层灰尘已触发" % fired)
			_check(total_amount >= 2000, "灰尘总量 %d 颗（这一版要 ≥2000）" % total_amount)
			var sheet := drop.get("_dust_sheet") as MeshInstance3D
			_check(sheet != null and sheet.visible, "贴地尘毯已打开")
			var shake := float(drop.get("_shake"))
			print("[drop] 镜头抖动 %.2f / 时间冻结 %.2f s" % [shake, float(drop.get("_hitstop"))])

	# 等演出收尾，确认相机交还
	for _i in 900:
		if bool(drop.get("_done")):
			break
		drop._process(dt)
		elapsed += dt
		await process_frame
	_check(bool(drop.get("_done")), "演出已收尾")
	var p = game.get_node_or_null("Player")
	if p != null:
		var pcam: Camera3D = p.get("cam")
		_check(pcam != null and pcam.current, "相机已交还玩家")
	_check(absf(room.position.y - base_y) < 0.001, "收尾后房子 y 复位（%.4f）" % room.position.y)
	await _snap("07_after")

	ShopClerk._bought = false
	print("[drop] 结果：%s（%d 项不合格）" % ["全过" if _fails == 0 else "有红项", _fails])
	quit(0 if _fails == 0 else 1)
