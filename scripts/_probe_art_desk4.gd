extends SceneTree
## 探针 4：把候选桌面**投影到出生点视角的画面上**并贴编号标签。
##
## 前面两个探针给出的都是数字，但「老师左边那张桌子」是**看图说话** —— 必须把
## 候选框画到同一张渲染图上，才能确认哪一个是用户截图里那张。
## 做法：`Camera3D.unproject_position()` 求屏幕坐标，再用 `CanvasLayer` + `Label`
## 贴字（Label3D 在 `no_depth_test` 下会被泼溅的合成器吃掉）。
##
## 输出：`_arisu_captures/_artdesk/probe04.txt` + `p4_*.png`
## 用法：godot --path . --script res://scripts/_probe_art_desk4.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"

## 探针 3 的 20 个水平面块（世界 lo/hi 的 xz，y = 桌面高度）
const PLANES := [
	["A1", -4.82, 2.14, -3.42, 3.26, 0.687],
	["A2", 2.34, 4.06, 2.98, 4.94, 0.885],
	["A3", 1.74, 5.70, 2.42, 6.54, 0.863],
	["A4", -4.62, 4.30, -3.74, 5.22, 0.878],
	["A5", -4.70, 3.30, -3.58, 3.98, 0.715],
	["A6", 1.74, 7.50, 2.50, 8.54, 0.803],
	["A7", -3.94, -2.06, -3.42, -1.50, 0.874],
	["A8", 2.38, 10.14, 3.14, 11.02, 0.878],
	["A9", -4.14, 9.38, -3.26, 10.10, 0.814],
	["A10", -5.22, -0.70, -4.74, 0.22, 0.690],
	["A11", -2.82, 8.46, -2.30, 9.02, 0.841],
	["A12", -3.14, 3.74, -2.62, 4.30, 0.878],
	["A13", 2.94, 9.46, 3.42, 9.98, 0.867],
	["A14", 3.46, -0.98, 4.14, -0.38, 0.853],
	["A15", -4.50, 6.82, -3.86, 7.42, 0.674],
	["A16", -3.54, 0.46, -3.02, 0.94, 0.876],
	["A17", -3.54, 12.06, -3.02, 12.62, 0.884],
	["A18", -3.62, 4.30, -3.10, 4.82, 0.676],
	["A19", -2.34, 3.86, -1.86, 4.26, 0.676],
	["A20", -2.82, 2.58, -2.18, 2.94, 0.669],
]

var _rep := PackedStringArray()
var _cam: Camera3D
var _layer: CanvasLayer


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(OUT_ABS)
	var game: Node = (load(GAME_PATH) as PackedScene).instantiate()
	root.add_child(game)
	var room := game.get_node_or_null("Room609") as Node3D
	var waited := 0
	while waited < 9000 and (room == null or not bool(room.call("is_ready"))):
		await process_frame
		waited += 1
	paused = false
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		elif c is Companion:
			(c as Node3D).visible = false
	_p("等 %d 帧" % waited)

	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.near = 0.02
	_cam.far = 400.0
	root.add_child(_cam)
	_cam.make_current()
	_layer = CanvasLayer.new()
	_layer.layer = 100
	root.add_child(_layer)

	var sensei := game.get_node_or_null("Sensei") as Node3D
	var sp := Vector3(1.8, 0.0, 2.6)
	if sensei != null:
		sp = sensei.global_position
	var player := game.get_node_or_null("Player") as Node3D
	var ppos := Vector3(0.0, 0.05, 6.0)
	if player != null:
		ppos = player.global_position
	_p("玩家 %s；Sensei %s" % [str(ppos.snappedf(0.01)), str(sp.snappedf(0.01))])

	# 视角 1：玩家出生点的真实第一人称（镜头高度取 1.62 m，和玩家相机 1.35 + 抬一点近似）
	var eye := Vector3(ppos.x, ppos.y + 1.57, ppos.z)
	# 玩家出生时朝哪儿？scene 里 Player 无旋转，相机 rig 父节点无旋转 → 朝 -Z
	await _labeled_shot(eye, eye + Vector3(0.0, 0.0, -10.0), "p4_00_spawn_forward.png",
		sp, true)
	# 视角 2：朝 Sensei
	await _labeled_shot(eye, Vector3(sp.x, sp.y + 1.30, sp.z), "p4_01_spawn_sensei.png",
		sp, true)
	# 视角 3：站在 Sensei 身边，朝房间中央
	await _labeled_shot(Vector3(sp.x, 1.62, sp.z + 1.2),
		Vector3(-3.0, 1.20, 1.0), "p4_02_near_sensei.png", sp, true)

	# 每个平面单独近景（相机放在正上方 2.6 m 斜 45°，看清桌面形状 + 桌下）
	for e in PLANES:
		var id := String(e[0])
		var x0 := float(e[1])
		var z0 := float(e[2])
		var x1 := float(e[3])
		var z1 := float(e[4])
		var y := float(e[5])
		var ctr := Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5)
		var away := Vector3(0.0, 0.0, 3.5) - ctr
		away.y = 0.0
		if away.length() < 0.6:
			away = Vector3(0.0, 0.0, 1.0)
		away = away.normalized()
		var cp := ctr + away * 2.0
		cp.y = 1.85
		await _labeled_shot(cp, Vector3(ctr.x, y - 0.15, ctr.z),
			OUT_ABS.path_join("p4_%s.png" % id), sp, false)

	_flush()
	quit(0)


func _labeled_shot(from: Vector3, to: Vector3, path: String, sp: Vector3,
		with_all: bool) -> void:
	_cam.global_position = from
	_cam.look_at(to, Vector3.UP)
	for c in _layer.get_children():
		c.queue_free()
	await _settle()

	# 真渲染帧 → 存图
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if with_all:
		# 先存无标签版本（人眼看构图），再画标签
		img.save_png(path.get_basename() + "_clean.png")

	# 画标签（2D）
	var box := ColorRect.new()
	box.color = Color(1.0, 0.25, 0.2, 0.30)
	box.size = Vector2(10, 10)
	box.visible = false
	_layer.add_child(box)
	var idx := 0
	for e in PLANES:
		var id := String(e[0])
		var x0 := float(e[1])
		var z0 := float(e[2])
		var x1 := float(e[3])
		var z1 := float(e[4])
		var y := float(e[5])
		var ctr := Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5)
		if _cam.is_position_behind(ctr):
			continue
		var s := _cam.unproject_position(ctr)
		# 外框四角投影（做粗略轮廓）
		var corners := [
			Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
		var pts: Array[Vector2] = []
		var behind := false
		for cc in corners:
			var cv: Vector3 = cc
			if _cam.is_position_behind(cv):
				behind = true
				break
			pts.append(_cam.unproject_position(cv))
		if behind:
			pts.clear()
		if pts.size() == 4:
			var lo := pts[0]
			var hi := pts[0]
			for p in pts:
				lo = lo.min(p)
				hi = hi.max(p)
			var r := ColorRect.new()
			r.color = Color(1.0, 0.30, 0.22, 0.16)
			r.position = lo
			r.size = hi - lo
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_layer.add_child(r)
		var l := Label.new()
		l.text = "%s y%.2f %.1f×%.1f" % [id, y, x1 - x0, z1 - z0]
		l.position = s + Vector2(4.0, -10.0)
		l.add_theme_color_override("font_color", Color(1.0, 0.30, 0.22))
		l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_font_size_override("font_size", 15)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(l)
		idx += 1
	# Sensei 标签
	if not _cam.is_position_behind(sp + Vector3(0.0, 1.0, 0.0)):
		var sl := Label.new()
		sl.text = "SENSEI →"
		sl.position = _cam.unproject_position(sp + Vector3(0.0, 1.0, 0.0)) + Vector2(4, -30)
		sl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		sl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		sl.add_theme_constant_override("outline_size", 7)
		sl.add_theme_font_size_override("font_size", 20)
		_layer.add_child(sl)
	# 相机位置 + 朝向（左上角）
	var info := Label.new()
	info.text = "cam (%.2f,%.2f,%.2f) → %s   标签 %d" % [from.x, from.y, from.z,
		str(-_cam.global_transform.basis.z.snappedf(0.01)), idx]
	info.position = Vector2(12, 8)
	info.add_theme_color_override("font_color", Color(0.9, 1.0, 0.5))
	info.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	info.add_theme_constant_override("outline_size", 6)
	info.add_theme_font_size_override("font_size", 18)
	_layer.add_child(info)
	await _settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	_p("[img] %-24s cam(%7.2f,%5.2f,%7.2f) 标签 %d"
		% [path.get_file(), from.x, from.y, from.z, idx])


func _settle() -> void:
	for _i in 8:
		await process_frame


func _p(s: String) -> void:
	_rep.append(s)


func _flush() -> void:
	var f := FileAccess.open(OUT_ABS.path_join("probe04.txt"), FileAccess.WRITE)
	if f == null:
		print("\n".join(_rep))
		return
	f.store_string("\n".join(_rep) + "\n")
	f.close()
	print("[probe4] 写入 %s/probe04.txt" % OUT_ABS)
