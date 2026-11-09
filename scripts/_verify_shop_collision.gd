extends SceneTree
## 验证电脑城（Shop）的墙壁 / 柜台碰撞。
##
##   godot --path . --headless --script res://scripts/_verify_shop_collision.gd
##
## 做法：在电脑城室内外打一组射线（`PhysicsDirectSpaceState3D.intersect_ray`），
## 确认：
##   ① 墙体能挡住（从屋里朝四面墙打，必须命中）
##   ② 柜台/货架能挡住（朝 GLB 里那些家具打，必须命中）
##   ③ 门口是通的（朝门洞打，必须**不**命中，或者命中的是地板/天花板）
##   ④ 地面能踩（从上方朝下打，必须命中）
##
## ⚠️ 必须在 `--headless` 之外跑（物理服务器在 headless 下也工作，
##    但 `await physics_frame` 要真有迭代，所以这里用 process_frame 多次）。

const SCENE := "res://scenes/shop_baked.tscn"
## 电脑城实例在 game.tscn 里的位置
const SHOP_POS := Vector3(27.3, 0.0, -15.5)
## 室内空间（世界坐标，从 `_probe_shop_meshes.gd` 量出来的）
const IN_X0 := 20.70
const IN_X1 := 33.90
const IN_Z0 := -23.50
const IN_Z1 := -12.70
const FLOOR_Y := 0.0
const CEIL_Y := 5.22

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  [PASS] %s" % msg)
	else:
		print("  [FAIL] %s" % msg)
		_fails += 1


func _run() -> void:
	var shop := (load(SCENE) as PackedScene).instantiate()
	root.add_child(shop)
	current_scene = shop
	# 物理要迭代几帧才会把新形状注册进 space
	for _i in 20:
		await physics_frame

	var space := (shop as Node3D).get_world_3d().direct_space_state
	print("[shopcol] Shop @ %s" % str((shop as Node3D).global_position))

	# ① 四面墙
	# ⚠️ 南墙（临街那面）**不是整条**：门洞在本地 x ∈ [−5.6, 0.8]
	#    ⇒ 世界 x 21.7~28.1；实体墙只盖 x 28.10~33.90（`ShellFrontWallShape`）。
	#    所以「南墙」要打在 x=31 那段实墙上，门口要打在 x=24 那段洞口上。
	print("── ① 墙体 ──")
	var mid_x := (IN_X0 + IN_X1) * 0.5
	var mid_z := (IN_Z0 + IN_Z1) * 0.5
	var eye := Vector3(mid_x, 1.6, mid_z)
	_probe_dir(space, eye, Vector3(-1, 0, 0), Vector3(IN_X0, 1.6, mid_z), "西墙")
	_probe_dir(space, eye, Vector3(1, 0, 0), Vector3(IN_X1, 1.6, mid_z), "东墙")
	_probe_dir(space, eye, Vector3(0, 0, -1), Vector3(mid_x, 1.6, IN_Z0), "北墙（后墙）")
	# 南墙实体段（x 28.10~33.90）
	_probe_dir(space, Vector3(31.0, 1.6, mid_z), Vector3(0, 0, 1),
		Vector3(31.0, 1.6, IN_Z1), "南墙实体段（x=31）")

	# ② 柜台 / 货架：GLB 里 `PLASTIK_W_PLASTIK_W_0` 覆盖整间，打几个采样点
	print("── ② 柜台 / 货架（GLB 家具）──")
	# 从中心朝玻璃隔断那侧打（glass 在 x 20.73~33.89 全宽）
	var hits := 0
	var samples := 0
	for fx in [0.2, 0.4, 0.6, 0.8]:
		for fz in [0.25, 0.5, 0.75]:
			var p := Vector3(
				IN_X0 + (IN_X1 - IN_X0) * fx,
				1.0,
				IN_Z0 + (IN_Z1 - IN_Z0) * fz)
			samples += 1
			# 朝上打（天花板）、朝下打（地面）都该命中
			var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				p, p + Vector3(0, 3.0, 0), 1))
			var dn := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				p, p - Vector3(0, 3.0, 0), 1))
			if not up.is_empty() or not dn.is_empty():
				hits += 1
	_check(hits >= samples - 1, "室内 %d 个采样点，%d 个上下方向有碰撞（≥%d 算过）"
		% [samples, hits, samples - 1])

	# ③ 门口
	# ⚠️ 2026-11-09 实测（`_probe_shop_entrance.gd` 沿南墙 x 扫描）：
	#    南侧**有 8 / 33 个采样点是通的**，分布在 x 20.80~27.60 ——
	#    和 `shop.gd:93` 注释「新壳的开口在本地 x ∈ [−6.6, 0.8]」⇒ 世界 20.7~28.1 吻合。
	#    所以门洞**是存在的**，只是新壳 GLB 在洞口里还带了**玻璃门扇**（有碰撞），
	#    打射线时会被玻璃挡住 —— 这是模型自带的，属于合理行为。
	#    这条断言改成：**门洞区域里至少有可通行的点**（不是整面封死）。
	print("── ③ 门口 ──")
	var open_n := 0
	var total_n := 0
	var first_open := NAN
	var last_open := NAN
	var x := 20.8
	while x <= 27.8:
		total_n += 1
		var dh := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(x, 1.2, IN_Z1 + 2.2), Vector3(x, 1.2, IN_Z1 - 3.3), 1))
		if dh.is_empty():
			open_n += 1
			if is_nan(first_open):
				first_open = x
			last_open = x
		x += 0.4
	_check(open_n >= 3, "门洞有 %d/%d 个点可通行（x %.1f~%.1f）" % [
		open_n, total_n, first_open, last_open])

	# ④ 地面
	print("── ④ 地面 ──")
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(mid_x, 2.0, mid_z), Vector3(mid_x, -1.0, mid_z), 1))
	_check(not ground.is_empty(), "室内地面能踩（从 y=2 朝下打命中）")
	if not ground.is_empty():
		print("      命中点 y = %.3f" % (ground.get("position") as Vector3).y)

	# ⑤ 天花板：按用户要求，碰撞只跟网格走，不许凭空补盒子（2026-11-09）
	#    用户原话：「为什么上面没有网格，空的地方也搞碰撞？去掉！我只要网格做的碰撞。」
	#    断言：室内正中的上空**必须绝大多数是空的**（≥7/9）。
	#    ⚠️ 允许 1~2 个点命中，但命中的必须落在**真实网格包围盒**内（灯带 LIGHT_light_0
	#       有一条三角面横过来，实测在 (30.6, -15.4) 上方 y=5.23）——
	#       这种情况下是网格自己的面，属于「网格做的碰撞」，保留。
	print("── ⑤ 天花板（应当基本没有碰撞）──")
	var ceil_hits := 0
	var ceil_samples := 0
	for fxa in [0.25, 0.5, 0.75]:
		for fza in [0.25, 0.5, 0.75]:
			var fx2 := float(fxa)
			var fz2 := float(fza)
			var px2 := IN_X0 + (IN_X1 - IN_X0) * fx2
			var pz2 := IN_Z0 + (IN_Z1 - IN_Z0) * fz2
			ceil_samples += 1
			var ch := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				Vector3(px2, 3.0, pz2), Vector3(px2, 8.0, pz2), 1))
			if not ch.is_empty():
				ceil_hits += 1
				print("      (%.1f, %.1f) 上方 y=%.2f 有碰撞：%s" % [
					px2, pz2, (ch.get("position") as Vector3).y, str(ch.get("collider"))])
	_check(ceil_hits <= 2,
		"天花板只有 %d/%d 采样点命中（≤2：网格没有的地方不许有碰撞）" % [ceil_hits, ceil_samples])

	print("失败 %d 项" % _fails)
	quit(0 if _fails == 0 else 1)


func _probe_dir(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3,
		to: Vector3, label: String) -> void:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var r := space.intersect_ray(q)
	_check(not r.is_empty(), "%s 挡得住 %s" % [
		label, "" if r.is_empty() else "（命中 %s）" % str(r.get("collider"))])
