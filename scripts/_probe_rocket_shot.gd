extends SceneTree
## 出图：把跑酷传送口那枚 Falcon 9 拍下来，并**实测**它到底吃多少显存。
##
## 用法：_tools/run_shot.sh res://scripts/_probe_rocket_shot.gd
## 输出：_arisu_captures/_rocket/*.png
##
## 为什么单独测显存：4096² 的算法（64 MiB/张 + mipmap）只是「未压缩」的理论值，
## 真实占用取决于 Godot 选了哪种 GPU 格式。用 `get_rendering_info` 量
## 「加火箭前 / 加火箭后」的差值，才是能拿去说事的数。

const OUT_DIR := "_arisu_captures/_rocket"
const LIGHT_BG := Color(0.62, 0.70, 0.80)

var _lvl: Node3D
var _cam: Camera3D


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)

	_lvl = (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_lvl)
	_add_env()
	await _wait(10)

	var vram0 := _vram()
	print("[shot] 显存 加火箭前 = %.1f MB" % (vram0 / 1048576.0))

	# 通关 → 传送门 + 火箭一起就位
	_lvl.call("_on_run_finished", 60.0, 55.0)
	await _wait(14)
	var vram1 := _vram()
	print("[shot] 显存 加火箭后 = %.1f MB（增量 %.1f MB）" % [
		vram1 / 1048576.0, (vram1 - vram0) / 1048576.0])

	var rocket := _lvl.get("_finish_rocket") as Node3D
	if rocket == null:
		print("[shot] !! 火箭没生成")
		quit(1)
		return
	print("[shot] 火箭位置 = %s，缩放 %.2f，高 %.1f m" % [
		str(rocket.global_position.snappedf(0.1)),
		rocket.get("rocket_scale"), rocket.call("height")])

	# 逐张贴图的真实尺寸（确认到底是 1024 还是 4096）
	_dump_textures(rocket)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.1
	_cam.far = 2000.0
	root.add_child(_cam)

	var portal := _lvl.get_node_or_null("FinishPortal") as Node3D
	var p := portal.global_position if portal != null else rocket.global_position

	# 不猜取景距离：先量出火箭的世界包围盒，再按包围盒 + FOV 反算距离。
	# （前两版都是拍脑袋给的 40 m，结果 21 m 的箭照样顶出画外 —— 说明
	#   实际尺寸/距离关系和本喵的估算不符，必须量。）
	var box := _world_aabb(rocket)
	print("[shot] 火箭世界包围盒 pos=%s size=%s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])
	var mid := box.get_center()
	var fit_h := maxf(box.size.y, 1.0)
	var half := deg_to_rad(_cam.fov * 0.5)
	# 竖直方向装下整个高度，再留 25% 边
	var dist := (fit_h * 0.5) / tan(half) * 1.25
	print("[shot] 取景：高 %.1f m → 距离 %.1f m（fov %.0f°）" % [fit_h, dist, _cam.fov])

	var dir := Vector3(0.0, 0.0, 1.0)
	await _shoot(mid + dir * dist, mid, out.path_join("1_full_front.png"))
	await _shoot(mid + Vector3(0.55, 0.28, 0.78).normalized() * dist * 1.05, mid,
		out.path_join("2_three_quarter.png"))

	# 玩家当身高参照：看得出 21 m 到底多压场
	var ref := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(ref)
	ref.global_position = box.position + Vector3(box.size.x * 0.5 + 2.6, 0.0, box.size.z * 0.5 + 2.6)
	await _wait(6)
	await _shoot(mid + Vector3(0.5, 0.15, 0.9).normalized() * dist, mid,
		out.path_join("3_with_player.png"))
	ref.queue_free()
	await _wait(2)

	# 发动机 / 级间段特写：只框住底部 4 m
	var low := AABB(box.position, Vector3(box.size.x, 4.0, box.size.z))
	await _shoot(low.get_center() + Vector3(0.4, 0.35, 0.85).normalized() * 9.0,
		low.get_center(), out.path_join("4_engines.png"))
	# 箭顶整流罩：只框住顶部 6 m
	var top_c := box.position + Vector3(box.size.x * 0.5, box.size.y - 6.0, box.size.z * 0.5)
	await _shoot(top_c + Vector3(0.5, 0.2, 0.85).normalized() * 13.0, top_c,
		out.path_join("5_top.png"))

	# ⑤ 飞行中：真的起飞，飞到巡航中段时冻结时间再拍
	await _flight_shot(out.path_join("5_in_flight.png"))

	print("[shot] 输出目录 %s" % out)
	quit(0)


## 起飞后在巡航中段冻结 `Engine.time_scale` 拍一张（否则 220 m/s 三帧就飞出画面）
func _flight_shot(file: String) -> void:
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(player)
	await _wait(4)

	var rocket := _lvl.get("_finish_rocket") as Node3D
	if rocket == null:
		return
	var shed := _lvl.get_node_or_null("Island/Props/Shed") as Node3D
	_lvl.call("_start_ride", rocket, _lvl.call("_island_spot"),
		shed.global_position + Vector3(0.0, 0.1, 0.6), player, "出图", false)

	# 升空 1.10 s 之后进巡航，取巡航中段
	while float(rocket.get("_elapsed")) < 1.10 + 1.30:
		await physics_frame
	Engine.time_scale = 0.0
	await _wait(2)

	var at := rocket.global_position
	print("[shot] 飞行中位置 = %s（巡航高度）" % str(at.snappedf(0.1)))
	# 45 m 外看 21 m 的箭：整枚进画，还能看见下方的赛道
	var cam_at := at + Vector3(42.0, 2.0, 42.0)
	await _shoot(cam_at, at + Vector3(0.0, 10.5, 0.0), file)

	Engine.time_scale = 1.0


func _dump_textures(rocket: Node3D) -> void:
	var seen := {}
	for n in rocket.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if not (mat is BaseMaterial3D):
				continue
			var bm := mat as BaseMaterial3D
			var key := bm.resource_name
			if seen.has(key):
				continue
			seen[key] = true
			var names := ["albedo", "normal", "metallic", "roughness"]
			var texs := [bm.albedo_texture, bm.normal_texture,
				bm.metallic_texture, bm.roughness_texture]
			var parts: Array[String] = []
			for i in 4:
				var t := texs[i] as Texture2D
				if t != null:
					parts.append("%s=%dx%d" % [names[i], t.get_width(), t.get_height()])
			print("[shot]   材质 %-18s %s" % [
				key if key != "" else "(未命名)", ", ".join(parts)])


func _vram() -> int:
	return int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))


## 节点下所有可见网格的世界包围盒
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
