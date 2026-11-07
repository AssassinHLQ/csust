extends SceneTree
## 验：新壳的 `scenes/esports_room.tscn` 只剩新 GLB —— 旧那套（5 屏 / 显卡架 / 机箱 / 碰撞）
## 必须全部不在，新房间必须在，并且门朝哪一头要量出来给落地演出用。
##   _tools/run_shot.sh res://scripts/_probe_esports_new_glb.gd -- --splat=off --story=off
##
## 出图目录：`_arisu_captures/_esports_new/`
##   10_scene_outside  从 -Z 一侧看这栋房子（判断门是不是在这一头）
##   11_scene_inside   假设门在 -Z，从门口往里看
##   12_scene_topdown  俯视，看图面布局
## 打印：节点清单 / 世界包围盒 / 旧那套的残留检查结果。

const SCENE := "res://scenes/esports_room.tscn"
const OUT := "res://_arisu_captures/_esports_new"
## 旧程序化房间里才有这些东西；新壳里一个都不该有
const MUST_BE_GONE := [
	"Monitor0", "Monitor1", "Monitor2", "Monitor3", "Monitor4",
	"GPU0", "GPU7", "MainDesk", "KeiDesk", "PC5090Rig", "RoomBody",
	"EsportsSign", "EsportsSignBoard", "Poster5090", "CouchSeat", "FrameTable",
]

var _fails := 0


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[newroom] OK   %s" % what)
	else:
		_fails += 1
		print("[newroom] FAIL %s" % what)


func _shot(cam: Camera3D, p: Vector3, t: Vector3, nm: String) -> void:
	cam.global_position = p
	cam.look_at(t, Vector3.UP)
	await _wait(10)
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(nm + ".png"))
	print("[newroom] shot %s" % nm)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.85)
	env.ambient_light_energy = 1.0
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_energy = 1.0
	world.add_child(sun)

	var ps := load(SCENE) as PackedScene
	if ps == null:
		print("[newroom] 加载失败 %s" % SCENE)
		quit(1)
		return
	var room := ps.instantiate() as Node3D
	world.add_child(room)
	await _wait(20)

	# ① 旧那套必须干净
	for nm in MUST_BE_GONE:
		_check(room.find_child(nm, true, false) == null, "旧件 `%s` 已下线" % nm)

	# ② 新房间必须在
	var meshes := room.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() >= 50, "新房间网格 %d 个（应 ≈59）" % meshes.size())

	# ③ 世界包围盒
	var box := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	print("[newroom] 包围盒 pos=%s size=%s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])
	_check(absf(box.size.x - 10.4) < 0.3 and absf(box.size.z - 16.84) < 0.4,
		"尺寸 10.4 × 16.84（实际 %.2f × %.2f）" % [box.size.x, box.size.z])
	_check(absf(box.position.y) < 0.05, "地板在 y=0（实际 %.3f）" % box.position.y)

	# ④ 门在哪一头：使用者给的图里两个门洞开在短墙上 →
	#    短墙在 ±Z（长边 16.84 沿 Z）。这里两头各拍一张，人眼一锤定音。
	var c := box.get_center()
	var s := box.size
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 400.0
	world.add_child(cam)
	cam.current = true
	await _shot(cam, Vector3(c.x, 1.7, c.z - s.z * 1.1), Vector3(c.x, 1.4, c.z), "10_scene_outside_nz")
	await _shot(cam, Vector3(c.x, 1.7, c.z + s.z * 1.1), Vector3(c.x, 1.4, c.z), "10b_scene_outside_pz")
	await _shot(cam, Vector3(c.x, 1.6, c.z - s.z * 0.42), Vector3(c.x, 1.35, c.z), "11_scene_inside")
	await _shot(cam, Vector3(c.x, s.y + 16.0, c.z + 0.01), Vector3(c.x, 0.0, c.z), "12_scene_topdown")
	print("[newroom] 结果：%s（%d 项不合格）" % ["全过" if _fails == 0 else "有红项", _fails])
	quit(0 if _fails == 0 else 1)
