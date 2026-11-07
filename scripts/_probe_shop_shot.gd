extends SceneTree
## 出图：换了 GLB 屋壳之后的柴关电脑城 —— 正面（招牌 + 入口）、三点透视、店内。
##
## 用法：_tools/run_shot.sh res://scripts/_probe_shop_shot.gd
## 输出：_arisu_captures/_shop_new/*.png
##
## ⚠️ 取景一律按**实测包围盒**算距离，不拍脑袋 —— 上一轮火箭就是凭估算取景，
##    结果怎么调都装不下（真因是 basis 冲掉了缩放）。

const OUT_DIR := "_arisu_captures/_shop_new"
const SHOP_SCENE := "res://scenes/shop_baked.tscn"
const LIGHT_BG := Color(0.58, 0.66, 0.78)

var _shop: Node3D
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)

	var ps := load(SHOP_SCENE) as PackedScene
	if ps == null:
		print("[shot] 载不动 %s" % SHOP_SCENE)
		quit(1)
		return
	_shop = ps.instantiate() as Node3D
	root.add_child(_shop)
	_add_env()
	await _wait(12)

	print("[shot] 布局基准 shop_len=%.2f shop_depth=%.2f，新壳壳深 shell_depth=%.2f，层高 %.2f" % [
		float(_shop.get("shop_len")), float(_shop.get("shop_depth")),
		float(_shop.get("shell_depth")), float(_shop.get("shop_height"))])
	print("[shot] 碰撞盒 %d 个 / 装饰 %d 个" % [
		int(_shop.get("built_count")), int(_shop.get("decor_count"))])

	var shell := _shop.get_node_or_null("Shell")
	print("[shot] Shell 节点 = %s" % ("有" if shell != null else "**没有**"))

	# ⚠️ 只量 Shell（屋壳）本身，别用整个 Shop 节点的包围盒 ——
	#    那里面还有 20×40 m 的 Deck 地板，取景会被它撑开，店缩成一个小点。
	var box := _world_aabb(shell if shell != null else _shop)
	print("[shot] 商店世界包围盒 pos=%s size=%s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])

	var lb := _shop.find_child("SignText", true, false) as Label3D
	if lb != null:
		print("[shot] 招牌文字 = 「%s」 @ %s" % [lb.text, str(lb.global_position.snappedf(0.01))])
	else:
		print("[shot] !! 没找到 SignText")

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.1
	_cam.far = 2000.0
	root.add_child(_cam)

	# 正面 +Z 一侧看（门和招牌都在这一面）
	var c := box.get_center()
	var front_z := box.position.z + box.size.z      # 正面（+Z）
	var back_z := box.position.z                     # 背面（−Z）
	print("[shot] 正面 z = %.2f，背面 z = %.2f，中心 x = %.2f" % [front_z, back_z, c.x])

	# 关键节点世界坐标：判断入口、柜台、芹香到底落在哪
	for nm in ["Body", "Decor"]:
		var holder := _shop.get_node_or_null(nm)
		if holder == null:
			continue
		for ch in holder.get_children():
			if ch is Node3D and String(ch.name) in ["Counter", "CounterTop", "Register",
					"SignBoard", "WallShelf", "WallShelf2", "WallShelf3"]:
				print("[shot]   %-12s @ %s" % [
					ch.name, str((ch as Node3D).global_position.snappedf(0.01))])
	var clerk := _shop.get_node_or_null("ClerkSerika") as Node3D
	if clerk != null:
		print("[shot]   芹香         @ %s" % str(clerk.global_position.snappedf(0.01)))
	else:
		print("[shot]   !! 没有 ClerkSerika")

	# ① 正面**正交立面图**：没有透视畸变，玻璃/实墙/门洞一眼分明
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 16.0
	await _shoot(Vector3(c.x, c.y, front_z + 30.0), Vector3(c.x, c.y, front_z),
		out.path_join("A_front_elevation.png"))
	_cam.size = 8.0
	await _shoot(Vector3(c.x, 2.2, front_z + 30.0), Vector3(c.x, 2.2, front_z),
		out.path_join("B_front_door_zoom.png"))
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE

	# ② 站在房间**中心**（最开阔处）往门口看 —— 这是「从里往外」最稳的机位
	var mid_z := (front_z + back_z) * 0.5
	await _shoot(Vector3(c.x, 1.7, mid_z - 1.5), Vector3(c.x, 1.5, front_z + 3.0),
		out.path_join("C_inside_to_door.png"))
	# ③ 从房间西北角斜看东南（柜台/芹香在东南）
	await _shoot(Vector3(box.position.x + 1.6, 1.7, back_z + 1.6),
		Vector3(box.position.x + box.size.x - 1.0, 1.2, mid_z),
		out.path_join("D_inside_to_counter.png"))
	# ④ 门外 6 m、抬高到 2.2 m 往里看：模拟玩家跑过来的第一眼
	await _shoot(Vector3(c.x, 2.2, front_z + 6.0), Vector3(c.x, 1.6, mid_z),
		out.path_join("E_door_approach.png"))

	print("[shot] 输出目录 %s" % out)
	quit(0)


func _add_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = LIGHT_BG
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.88, 0.92, 1.0)
	e.ambient_light_energy = 1.8
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	root.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 28, 0)
	key.light_energy = 1.7
	key.shadow_enabled = true
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-14, -135, 0)
	fill.light_energy = 0.7
	fill.shadow_enabled = false
	root.add_child(fill)


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
		for ch in n.get_children():
			stack.append(ch)
	return out


func _shoot(from: Vector3, at: Vector3, file: String) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)
	_cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("  [img] %s" % file)


func _wait(n: int) -> void:
	for _i in n:
		await process_frame
