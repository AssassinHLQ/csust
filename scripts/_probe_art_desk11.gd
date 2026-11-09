extends SceneTree
## 探针 11（收尾验位）：把候选桌子的碰撞盒**画成半透明线框**摆进场景，
## 从出生点和两张近景看它有没有套在那张带抽屉的木办公桌上。
##
## 这是定位的最后一步 —— 前面 10 个探针把「桌面在哪」量成了一堆互相矛盾的候选
## （地板把所有家具连成一片、屏幕矩形又总会连背景），所以改成
## **先摆一个盒子，再人眼核对**：盒子摆对了就照着它加碰撞；摆偏了就按图挪。
##
## 输出 `_arisu_captures/_artdesk/probe11.txt` + `p11_*.png`
## 用法：godot --path . --script res://scripts/_probe_art_desk11.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"

## 候选 AABB（世界）。估法见报告：由出生点截图里桌子的屏幕位置反投影得到，
## 再用点云连通体 #3（x[-0.14,2.32] z[-0.17,2.88]）夹住。
const CAND_LO := Vector3(0.80, 0.0, 1.15)
const CAND_HI := Vector3(2.05, 0.80, 1.95)


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_ABS)
	var out := PackedStringArray()
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

	var sensei := game.get_node_or_null("Sensei") as Node3D
	var sp := sensei.global_position if sensei != null else Vector3(1.8, 0.0, 2.6)
	var player := game.get_node_or_null("Player") as Node3D
	var ppos := player.global_position if player != null else Vector3(0.0, 0.0, 6.0)
	out.append("等 %d 帧；Sensei %s；玩家 %s" % [waited, str(sp.snappedf(0.01)),
		str(ppos.snappedf(0.01))])

	var size := CAND_HI - CAND_LO
	var ctr := (CAND_LO + CAND_HI) * 0.5
	# 半透明盒子（无光照、不写深度 → 能看穿，便于核对边缘）
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.10, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 9
	mi.material_override = mat
	root.add_child(mi)
	mi.global_position = ctr
	# 12 条棱：细长盒（比线粗，缩略图也看得见）
	var edges := [
		[Vector3(0, 1, 1), Vector3(0, 1, -1), Vector3(size.x, 0.02, 0.02), Vector3(0, size.y * 0.5, size.z * 0.5)],
		[Vector3(0, 1, 1), Vector3(0, 1, 1), Vector3(0.02, size.y, 0.02), Vector3(size.x * 0.5, 0, size.z * 0.5)],
		[Vector3(0, 1, 1), Vector3(0, 1, 1), Vector3(0.02, 0.02, size.z), Vector3(size.x * 0.5, size.y * 0.5, 0)],
	]
	for e in edges:
		var base: Vector3 = e[3]
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var esz: Vector3 = e[2]
					var off := Vector3(0, 0, 0)
					if esz.x > esz.y and esz.x > esz.z:
						off = Vector3(0.0, float(sy), float(sz))
					elif esz.y > esz.z:
						off = Vector3(float(sx), 0.0, float(sz))
					else:
						off = Vector3(float(sx), float(sy), 0.0)
					var em := MeshInstance3D.new()
					var eb := BoxMesh.new()
					eb.size = esz
					em.mesh = eb
					var mt2 := StandardMaterial3D.new()
					mt2.albedo_color = Color(1.0, 0.95, 0.15)
					mt2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mt2.no_depth_test = true
					mt2.render_priority = 10
					em.material_override = mt2
					root.add_child(em)
					em.global_position = ctr + Vector3(off.x * base.x, off.y * base.y,
						off.z * base.z)
	var _unused := edges

	out.append("候选 AABB 世界 x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f] 尺寸 %s 中心 %s"
		% [CAND_LO.x, CAND_HI.x, CAND_LO.y, CAND_HI.y, CAND_LO.z, CAND_HI.z,
			str(size), str(ctr)])
	out.append("Room609 是单位变换，所以局部 AABB = 世界 AABB（已实测 basis=I, origin=0）")

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)
	cam.make_current()
	var shots := [
		["p11_00_spawn.png", Vector3(ppos.x, ppos.y + 1.57, ppos.z),
			Vector3(sp.x, sp.y + 1.30, sp.z)],
		["p11_01_close.png", ctr + Vector3(0.2, 1.30, 2.4), Vector3(ctr.x, 0.55, ctr.z)],
		["p11_02_side.png", ctr + Vector3(2.6, 1.20, 0.6), Vector3(ctr.x, 0.55, ctr.z)],
		["p11_03_top.png", Vector3(ctr.x, 4.0, ctr.z + 0.02), Vector3(ctr.x, 0.0, ctr.z)],
	]
	for s in shots:
		var p: Vector3 = s[1]
		var t: Vector3 = s[2]
		cam.global_position = p
		cam.look_at(t, Vector3.UP)
		for _i in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT_ABS.path_join(String(s[0])))
		out.append("[img] %s 相机 (%.2f,%.2f,%.2f)" % [String(s[0]), p.x, p.y, p.z])

	var f := FileAccess.open(OUT_ABS.path_join("probe11.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(out) + "\n")
		f.close()
	for s in out:
		print(s)
	quit(0)