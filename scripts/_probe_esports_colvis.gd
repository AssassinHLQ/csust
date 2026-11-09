extends SceneTree
## 把电竞房的**碰撞盒**画出来拍照，用来肉眼找「偏大 / 偏移」的盒子。
##
##   godot --path . --position -4000,-4000 --resolution 1280x720 --windowed \
##         --audio-driver Dummy --script res://scripts/_probe_esports_colvis.gd -- --no-capture
##
## 原理：Godot 的 `SceneTree.debug_collisions_hint = true` 会把所有碰撞形状
## 用线框画在场景上（就是编辑器里选中时那种淡蓝色盒子）。
## 对着屋子拍几张，就能看出哪个盒子比它该包的墙大。
##
## 输出：res://_arisu_captures/_esports_colvis/

const SCENE := "res://scenes/esports_room.tscn"
const OUT := "res://_arisu_captures/_esports_colvis"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# ★ 打开碰撞调试绘制
	debug_collisions_hint = true

	var room := (load(SCENE) as PackedScene).instantiate() as Node3D
	# 房间在 game.tscn 里是 (53.27, 3.90, 13.26) 转 -90°；
	# 这里单独摆它，摆到原点方便拍
	root.add_child(room)
	await _wait(60)

	# 量房间包围盒（用低模档）
	var low := room.get_node_or_null("Room") as Node3D
	var box := AABB()
	var first := true
	for m in low.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	var c := box.position + box.size * 0.5
	print("[colvis] 房间 AABB pos=%s size=%s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])

	# 只留碰撞盒、把网格网格藏掉一半亮度不易看 —— 干脆用纯色环境
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.95)
	env.ambient_light_energy = 0.6
	we.environment = env
	root.add_child(we)

	var cam := Camera3D.new()
	cam.far = 200.0
	cam.near = 0.05
	root.add_child(cam)
	cam.current = true

	# ★ 把**网格全藏掉**，只留碰撞线框 —— 否则屋顶挡住里面看不见
	for m in room.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).visible = false
	await _wait(10)

	# 从外面四角 + 俯视看
	await _shot(cam, c + Vector3(box.size.x, box.size.y * 2.0, box.size.z), c, "01_iso.png", 60.0)
	await _shot(cam, c + Vector3(-box.size.x, box.size.y, box.size.z), c, "02_iso2.png", 60.0)
	await _shot(cam, c + Vector3(0.01, 14.0, 0.0), c, "03_top.png", 55.0)
	# 屋里平视（门口在 +Z）
	await _shot(cam, Vector3(c.x, box.position.y + 1.6, box.position.z + box.size.z - 1.0),
		Vector3(c.x, box.position.y + 1.2, box.position.z), "04_inside.png", 75.0)
	await _shot(cam, Vector3(c.x - box.size.x * 0.5, box.position.y + 1.6, c.z),
		Vector3(c.x + box.size.x * 0.5, box.position.y + 1.0, c.z), "05_side.png", 75.0)

	# 把最大的 12 个盒子列出来，方便对号入座
	print("[colvis] ── 最大的 12 个碰撞盒 ──")
	var body := room.find_child("AutoCol", true, false)
	var rows: Array = []
	for ch in body.get_children():
		var cs := ch as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var s: Vector3 = (cs.shape as BoxShape3D).size
		rows.append({"n": String(cs.name), "c": cs.position, "s": s,
			"v": s.x * s.y * s.z})
	rows.sort_custom(func(a, b): return a["v"] > b["v"])
	for i in mini(12, rows.size()):
		var r: Dictionary = rows[i]
		var cc: Vector3 = r["c"]
		var ss: Vector3 = r["s"]
		print("[colvis]   %-16s 中心(%6.2f,%5.2f,%6.2f) 尺寸 %.2f×%.2f×%.2f  体积 %6.2f" % [
			r["n"], cc.x, cc.y, cc.z, ss.x, ss.y, ss.z, r["v"]])
	quit(0)


func _shot(cam: Camera3D, pos: Vector3, target: Vector3, name: String, fov := 60.0) -> void:
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	cam.fov = fov
	await _wait(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "/" + name))
	print("[colvis] 拍到 %s" % name)
