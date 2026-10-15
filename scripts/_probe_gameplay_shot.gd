extends SceneTree
## 探针：用**玩家自己的相机**拍一张真实 gameplay 视角的图。
##
## 与 `_probe_splat_backend.gd` 的区别：那边为了做 A/B 把相机写死了，这边故意
## 用玩家相机 + 不冻任何东西，拍出来的就是玩家按下 F5 之后看到的样子 ——
## 用来回答「我这边看着好好的，你那边缺了什么」这类现场问题。
##
## ⚠️ 玩家相机是弹簧跟随 + 鼠标视角，帧数相同也可能因为真实耗时不同而相位不同，
##    所以这张图只用于**看有没有 / 缺什么**，不能用于逐像素比对。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_gameplay_shot.gd -- --tag=xxx
##   （可加 --splat=off / --venue=room 等，参数会原样透传给 SplatScene）
## 输出：…/_arisu_captures/_gameplay/<tag>.png，并打印场景状态清单

const OUT_REL := "..\\_arisu_captures\\_gameplay"
const WAIT_FRAMES := 150

var _tag := "shot"
## 窗口尺寸什么时候设：
##   early  = 加载场景**之前**就设成 2560×1400（探针原来一直这么干）
##   late   = 先加载场景、等泼溅就位，**最后**才设尺寸（模拟「最大化发生在启动之后」）
##   native = 完全不碰尺寸，让 project.godot 的 window/size/mode=2 自己决定
##
## 为什么要区分：Compute 后端把泼溅渲进**离屏缓冲**，那个缓冲的尺寸来自
## `scene_buffers.get_internal_size()`。如果它只在第一帧建立、之后不跟着视口走，
## 那么「窗口在启动过程中变大」就会让**泼溅停留在小尺寸再放大**——表现是
## 背景一坨糊、而网格角色依然清晰。
var _window_mode := "early"
## 从房间外面拍：把相机架到平台上看房间，用来验证「挖洞之后房间外还有地面」。
var _outside := false
## 自由相机（世界坐标）。两个都给才生效 —— 用来看平台上到底哪里破了洞。
var _eye := Vector3.INF
var _look := Vector3.INF


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--window="):
			_window_mode = a.substr(9)
		elif a.begins_with("--eye="):
			_eye = _parse_vec3(a.substr(6))
		elif a.begins_with("--look="):
			_look = _parse_vec3(a.substr(7))
		elif a == "--outside":
			_outside = true
	_run.call_deferred()


func _parse_vec3(s: String) -> Vector3:
	var p := s.split(",")
	if p.size() != 3:
		push_warning("--eye/--look 要写 x,y,z，收到的是「%s」" % s)
		return Vector3.ZERO
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _run() -> void:
	if _window_mode == "early":
		root.size = Vector2i(2560, 1400)
	await process_frame
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_gameplay")
	DirAccess.make_dir_recursive_absolute(out)
	print("[shot] 窗口模式 = %s  加载前 root.size = %s" % [_window_mode, str(root.size)])

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	# 给足时间：解码、排序表落地、玩家落地站稳
	for i in WAIT_FRAMES:
		await process_frame

	if _window_mode == "late":
		root.size = Vector2i(2560, 1400)
		print("[shot] 现在才把窗口设成 %s（模拟启动后才最大化）" % str(root.size))
		for i in 60:
			await process_frame

	print("[shot] 出图时 root.size = %s  Viewport.size = %s" % [
		str(DisplayServer.window_get_size()), str(root.size)])

	var cam := root.get_camera_3d()
	if cam == null:
		push_error("没有当前相机")
		quit(1)
		return

	if _eye.is_finite() and _look.is_finite():
		var free0 := Camera3D.new()
		free0.name = "FreeCam"
		free0.fov = 62.0
		free0.near = 0.05
		free0.far = 2000.0
		root.add_child(free0)
		free0.global_position = _eye
		if not free0.global_position.is_equal_approx(_look):
			free0.look_at(_look, Vector3.UP)
		free0.make_current()
		cam = free0
		for i in 20:
			await process_frame
	elif _outside:
		# 站到房间 +X 那一侧的平台上回头看 —— 挖洞之后这里必须有可见地面。
		var room: Node = game.get_node_or_null("Room609")
		var box: AABB = room.call("content_world_aabb")
		var free := Camera3D.new()
		free.name = "OutsideCam"
		free.fov = 62.0
		free.near = 0.05
		free.far = 500.0
		root.add_child(free)
		free.global_position = Vector3(box.position.x + box.size.x + 6.0, 2.2,
			box.position.z + box.size.z * 0.5)
		free.look_at(Vector3(box.position.x + box.size.x * 0.5, 1.2,
			box.position.z + box.size.z * 0.5), Vector3.UP)
		free.make_current()
		cam = free
		for i in 20:
			await process_frame
	print("[shot] 相机「%s」 pos %s rot %s  compositor=%s" % [
		cam.name, str(cam.global_position.snappedf(0.01)),
		str(cam.global_rotation_degrees.snappedf(0.1)),
		"有" if cam.compositor != null else "无"])

	# 场景状态清单：这一节就是用来回答「谁不见了」的。
	var player: Node = game.get_node_or_null("Player")
	var floor_node: Node = game.get_node_or_null("Floor")
	var mesh: Node = floor_node.get_node_or_null("Mesh") if floor_node != null else null
	print("[shot] Player  pos %s  parent_visible=%s" % [
		str((player as Node3D).global_position.snappedf(0.01)) if player is Node3D else "?",
		str((player as CanvasItem).visible) if player is CanvasItem else "（非 2D）"])
	print("[shot] Floor      visible=%s" % str((floor_node as Node3D).visible))
	print("[shot] Floor/Mesh visible=%s  pos %s" % [
		str((mesh as Node3D).visible) if mesh is Node3D else "（无此节点）",
		str((mesh as Node3D).position.snappedf(0.001)) if mesh is Node3D else "-"])
	if floor_node != null:
		var carved: Node = floor_node.get_node_or_null("FloorCarved")
		if carved == null:
			print("[shot] FloorCarved  : 无（方盒地板是整块）")
		else:
			var slab: Node = carved.get_node_or_null("Slab")
			var hole: Node = carved.get_node_or_null("RoomHole")
			print("[shot] FloorCarved  : Slab size=%s  洞 size=%s  洞世界位置=%s" % [
				str((slab as CSGBox3D).size) if slab is CSGBox3D else "?",
				str((hole as CSGBox3D).size) if hole is CSGBox3D else "?",
				str((hole as Node3D).global_position.snappedf(0.01)) if hole is Node3D else "?"])
	for c in game.get_children():
		if String(c.name).begins_with("Room") or String(c.name).begins_with("Splat"):
			var pts: Variant = c.get("point_count")
			var sn: Variant = c.get("splat_node")
			print("[shot] %-12s venue=%-6s 点数=%s splat_node=%s" % [
				c.name, str(c.get("venue")), str(pts),
				"有" if sn != null else "None"])
			if sn != null:
				print("[shot]   └─ 世界内容盒 %s" % str(c.call("content_world_aabb")))
				_report_floor_coverage(c)

	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path := out.path_join("%s.png" % _tag)
	img.save_png(path)
	print("[shot] 出图 %s" % path)
	quit(0)


## 量「扫描出来的地面在 x/z 上铺到哪」，再和挖洞用的 content 盒比。
##
## 为什么要量这个：平台上的洞是按 content 盒挖的。**如果地面点并没有铺满 content 盒**
## （室内重建里墙根、角落、被家具挡住的区域常常缺数据），差出来的那一圈就是
## 「平台没有、地面也没有」的真空。目测在远处根本分不出来，所以直接数点。
func _report_floor_coverage(room: Node) -> void:
	var sn: Node = room.get("splat_node")
	if sn == null:
		return
	var res: Resource = sn.get("gaussian")
	if res == null:
		return
	var xyz: PackedVector3Array = res.get("xyz")
	var total := xyz.size()
	if total == 0:
		return
	# anchor_source.y 就是「源坐标里的地面高度」（它被对到 anchor_world 上）
	var floor_y: float = (room.get("anchor_source") as Vector3).y
	var band := 0.15          # ±0.15 源单位；乘 world_scale 后约 ±0.6 m
	var step := maxi(1, total / 400000)
	var wscale: float = float(room.get("world_scale"))
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var kept := 0
	var i := 0
	while i < total:
		var p := xyz[i]
		if absf(p.y - floor_y) <= band:
			lo = lo.min(p)
			hi = hi.max(p)
			kept += 1
		i += step
	var cmin: Vector3 = room.get("content_min")
	var cmax: Vector3 = room.get("content_max")
	print("[shot] 地面带 |y - %.3f| <= %.2f：命中 %d / 抽样 %d" % [
		floor_y, band, kept, (total + step - 1) / step])
	print("[shot]   地面 x/z   = %s .. %s" % [str(lo.snappedf(0.01)), str(hi.snappedf(0.01))])
	print("[shot]   content x/z = %s .. %s" % [str(cmin.snappedf(0.01)), str(cmax.snappedf(0.01))])
	print("[shot]   每边差（正数 = 那一圈是真空）世界米：x- %.2f  x+ %.2f  z- %.2f  z+ %.2f" % [
		(lo.x - cmin.x) * wscale, (cmax.x - hi.x) * wscale,
		(lo.z - cmin.z) * wscale, (cmax.z - hi.z) * wscale])
