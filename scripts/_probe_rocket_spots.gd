extends SceneTree
## 出图：两个停机位各拍一张 —— 跑道口（传送门脚下）和岛上（传送台旁）。
##
## 用法：_tools/run_shot.sh res://scripts/_probe_rocket_spots.gd
## 输出：_arisu_captures/_rocket_spots/*.png
##
## 为什么必须看图而不是只看数值：岛上那个停机位挪到了 `pad + (0,0,-4)`
## （原来 −3 的位置上方 18 m 处有信号塔平台 x −597~−593、z −6.5~−2.5），
## 42 m 高的箭体到底有没有穿过去，只有渲染出来才知道 —— 包围盒相交只能算个大概。

const OUT_DIR := "_arisu_captures/_rocket_spots"
const LIGHT_BG := Color(0.62, 0.70, 0.80)

var _lvl: Node3D
var _cam: Camera3D
var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)

	_lvl = (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_lvl)
	_add_env()
	await _wait(12)

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out)

	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.1
	_cam.far = 3000.0
	root.add_child(_cam)

	var home: Vector3 = _lvl.call("_home_spot")
	var island: Vector3 = _lvl.call("_island_spot")
	print("[spots] 跑道口停机位 = %s" % str(home.snappedf(0.01)))
	print("[spots] 岛上停机位   = %s" % str(island.snappedf(0.01)))

	# 两枚到底在不在、各在哪
	for r in [_lvl.get("_finish_rocket"), _lvl.get("_return_rocket")]:
		var n := r as Node3D
		if n == null or not is_instance_valid(n):
			print("[spots] !! 有一枚是 null")
			continue
		var box := _world_aabb(n)
		print("[spots] 火箭 @ %s  包围盒 size=%s  占位=%s" % [
			str(n.global_position.snappedf(0.1)), str(box.size.snappedf(0.1)),
			str(bool(n.call("is_placeholder")))])

	# 身高参照
	var ref := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(ref)
	ref.global_position = home + Vector3(3.2, 0.0, 3.2)
	await _wait(6)

	# ① 跑道口：火箭站在传送门里（侧面 3/4）
	await _fit_shot(home, Vector3(0.62, 0.30, 0.72), 1.30, _out.path_join("1_home_gate.png"))

	# ② 岛上：火箭 + 传送台 + 信号塔（看有没有穿塔）
	ref.global_position = island + Vector3(3.2, 0.0, -3.2)
	await _wait(4)
	await _fit_shot(island, Vector3(-0.55, 0.26, 0.79), 1.75, _out.path_join("2_island_pad.png"))

	# ③ 岛上俯视：从塔顶往下看，直接看穿模
	await _shoot(island + Vector3(26.0, 55.0, 30.0), island + Vector3(0.0, 16.0, 0.0),
		_out.path_join("3_island_top.png"))

	# ④ 两枚对飞：真的开一趟，巡航中段冻结时间，两枚都在天上
	await _crossover_shot(ref, _out.path_join("4_crossover.png"))

	print("[spots] 输出目录 %s" % _out)
	quit(0)


## 按「要装下 42 m 的箭」反算距离再取景（别拍脑袋给 40 m，装不下）
func _fit_shot(ground: Vector3, dir: Vector3, margin: float, file: String) -> void:
	var h := 42.0
	var half := deg_to_rad(_cam.fov * 0.5)
	var dist := (h * 0.5) / tan(half) * margin
	var look := ground + Vector3(0.0, h * 0.46, 0.0)
	await _shoot(ground + dir.normalized() * dist, look, file)


## 开一趟「回程」，在巡航中段把时间冻住 —— 载人那枚 45 m、空载那枚 95 m
##
## ⚠️ 必须复用**同一个**玩家实例（`ref`）：`parkour.gd::_on_return_pad_entered`
##    第一件事就是 `if body != _player: return`，场景里多一个 `player` 组的人
##    （比例参照那一个）就会被判成「不是我」，传送台永远不触发 —— 踩过一次。
func _crossover_shot(player: Node3D, file: String) -> void:
	var pad := _lvl.get_node_or_null("Island/Props/ReturnPad") as Node3D
	await _wait(4)
	player.global_position = pad.global_position + Vector3(0.0, 0.10, 0.0)
	var g := 0
	while not bool(_lvl.get("_riding")) and g < 120:
		g += 1
		await physics_frame
	if not bool(_lvl.get("_riding")):
		print("[spots] !! 没起飞（踩传送台没触发）")
		return

	# 谁在载人：**不能**用 `is_riding()` 区分 —— 它返回的是 `_active`，
	# 空载摆渡那枚此刻也在飞，同样是 true。要用 `_ferry` 标志。
	var rider: Node3D = null
	var ferry: Node3D = null
	for r in [_lvl.get("_finish_rocket"), _lvl.get("_return_rocket")]:
		var n := r as Node3D
		if n == null or not is_instance_valid(n):
			continue
		if bool(n.get("_ferry")):
			ferry = n
		else:
			rider = n
	if rider == null:
		print("[spots] !! 找不到载人那枚")
		return

	# 升空 1.10 s 之后进巡航，取巡航中段
	while float(rider.get("_elapsed")) < 1.10 + 1.30:
		await physics_frame
	Engine.time_scale = 0.0
	await _wait(3)

	var mid := rider.global_position
	if ferry != null:
		mid = (rider.global_position + ferry.global_position) * 0.5
	print("[spots] 冻结时：载人 %s / 摆渡 %s" % [
		str(rider.global_position.snappedf(0.1)),
		str(ferry.global_position.snappedf(0.1)) if ferry != null else "无"])
	await _shoot(mid + Vector3(150.0, -20.0, 150.0), mid + Vector3(0.0, 10.0, 0.0), file)
	Engine.time_scale = 1.0


func _shoot(from: Vector3, at: Vector3, file: String) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)
	_cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("  [img] %s" % file)


func _world_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D and (n as VisualInstance3D).is_visible_in_tree():
			var vi := n as VisualInstance3D
			var b := vi.get_aabb()
			if b.size.length() > 0.0001:
				var wb := vi.global_transform * b
				out = wb if first else out.merge(wb)
				first = false
		for c in n.get_children():
			stack.append(c)
	return out


func _add_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = LIGHT_BG
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.86, 0.90, 1.0)
	e.ambient_light_energy = 2.0
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	root.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 32, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, -140, 0)
	fill.light_energy = 0.6
	fill.shadow_enabled = false
	root.add_child(fill)


func _wait(n: int) -> void:
	for _i in n:
		await process_frame
