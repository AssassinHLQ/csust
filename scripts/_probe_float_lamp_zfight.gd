extends SceneTree
## 四条现场问题的量测（用户 2026-10-26）：
##   「芹香浮空了 / 上楼梯生硬 / 灯又没有挂到天花板上而是浮空了 / 重叠面需要修复」
##   godot --path . --script res://scripts/_probe_float_lamp_zfight.gd -- --splat=off
##
## ① 芹香的脚：模型原点、抬脚量、骨骼、网格世界包围盒
## ② 天花板灯：房子里每一盏可见灯管到「天花板下表面」的净空（浮空就是这里 > 0）
## ③ 楼梯：真爬一遍，逐帧记 y（看每帧跳多少 —— 生硬就是跳变大）
## ④ 共面重叠：Shop / MeshHut / MondrianHouse 三处**同向面**重合对（会闪的那些）
## 出图：_arisu_captures/_issues1026/{clerk_north,clerk_feet,mondrian_1f_ceiling,
##       mondrian_2f_ceiling,mondrian_door,hut_ceiling,stairs_mid}.png

func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])


## 某棵树里所有网格的世界包围盒
func _tree_aabb(root_node: Node) -> AABB:
	var bb := AABB()
	var first := true
	for mi in root_node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
	return bb


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_issues1026")
	DirAccess.make_dir_recursive_absolute(out)
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.near = 0.02
	cam.far = 500.0
	root.add_child(cam)

	# ══════════ ① 芹香 ══════════
	print("══════ ① 芹香站得对不对 ══════")
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk == null:
		print("[错误] 没有 Shop/ClerkSerika")
		quit(1)
		return
	var shop := game.get_node_or_null("Shop") as Node3D
	var model_root := clerk.get_node_or_null("serika") as Node3D
	if model_root == null:
		for ch in clerk.get_children():
			if ch is Node3D and ch.name != "ClerkBody":
				model_root = ch as Node3D
				break
	var shop_aabb := _tree_aabb(shop)
	print("Shop 地板顶面 y = %.3f（Deck 的顶面）" % shop_aabb.position.y)
	print("ShopClerk 世界坐标 %s" % str(clerk.global_position.snappedf(0.001)))
	print("  模型根 %s：local y = %+.3f，scale = %.3f，floor_y（探针读的）= %.3f"
		% [str(model_root.name) if model_root else "—",
			model_root.position.y if model_root else 0.0,
			model_root.scale.y if model_root else 0.0,
			float(clerk.get("ground_lift"))])
	var skels := clerk.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var skel := skels[0] as Skeleton3D
		var lowest := 999.0
		var lowest_name := ""
		for i in skel.get_bone_count():
			var nm := skel.get_bone_name(i).to_lower()
			if nm.contains("foot") or nm.contains("toe"):
				var wy: float = (skel.global_transform
					* skel.get_bone_global_pose(i).origin).y
				print("  骨 %-24s 世界 y = %+.3f" % [skel.get_bone_name(i), wy])
				if wy < lowest:
					lowest = wy
					lowest_name = skel.get_bone_name(i)
		print("  最低的脚骨：%s  y = %+.3f" % [lowest_name, lowest])
	# 逐网格最小 y（**必须逐网格看**：整体包围盒会被枪/光环带偏 —— 上一版就是这么栽的）
	var body: MeshInstance3D = null
	var body_h := 0.0
	var lows: Array = []
	for mi in clerk.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		lows.append({"n": String(m.name), "lo": a.position.y, "hi": a.end.y})
		if a.size.y > body_h:
			body_h = a.size.y
			body = m
	lows.sort_custom(func(x, y): return float(x["lo"]) < float(y["lo"]))
	print("  最低的 4 个网格：")
	for h in lows.slice(0, 4):
		print("    %-26s y %+.3f ~ %+.3f" % [h["n"], h["lo"], h["hi"]])
	if body != null:
		var ba: AABB = body.global_transform * body.mesh.get_aabb()
		print("  最大的网格（身体）= %s：y %+.3f ~ %+.3f（高 %.3f）"
			% [String(body.name), ba.position.y, ba.end.y, ba.size.y])
		print("  ⇒ **身体**底离地 %+.3f m（正数 = 浮空）" % ba.position.y)

	var base := clerk.global_position
	# 北侧平视全身（她 z = -15.30，柜台 z -17.10 ~ -13.50，从 z = -13.0 往南看无遮挡）
	cam.fov = 34.0
	cam.global_position = Vector3(base.x, 0.80, base.z + 2.30)
	cam.look_at(Vector3(base.x, 0.80, base.z), Vector3.UP)
	await _shot(cam, out, "clerk_north")
	# 贴地特写：相机压到 y = 0.16，专看鞋底和地面的关系
	cam.fov = 45.0
	cam.global_position = Vector3(base.x + 0.35, 0.16, base.z + 1.15)
	cam.look_at(Vector3(base.x, 0.10, base.z), Vector3.UP)
	await _shot(cam, out, "clerk_feet")
	# 和爱丽丝并排：一眼看出「脚踩地了没」+「身高合不合适」
	var pl := game.get("_player") as CharacterBody3D
	if pl != null:
		# ⚠️ 别让玩家挡住她：柜台（x 31.84~32.56）与东墙内表面（x 33.70）之间只有
		#    1.14 m 走道，所以爱丽丝站在她**西侧 0.45 m**、相机从北侧正对两人中间。
		pl.global_position = Vector3(base.x - 0.45, 0.06, base.z + 0.10)
		pl.velocity = Vector3.ZERO
		for _f in 25:
			await process_frame
		cam.fov = 40.0
		cam.global_position = Vector3(base.x - 0.22, 1.00, base.z + 2.60)
		cam.look_at(Vector3(base.x - 0.22, 0.90, base.z), Vector3.UP)
		await _shot(cam, out, "clerk_vs_alice")
		print("  对照图：玩家 %s vs 芹香 %s（地面 y = 0）"
			% [str(pl.global_position.snappedf(0.01)), str(base.snappedf(0.01))])

	# ══════════ ② 天花板灯 ══════════
	print("\n══════ ② 天花板上的灯离天花板多远 ══════")
	var house := game.get_node_or_null("MondrianHouse") as Node3D
	if house != null:
		var slab_bb := AABB()
		var slab_first := true
		for nm in ["SlabE", "SlabWN", "SlabWS"]:
			var n := house.get_node_or_null("Body/" + nm) as MeshInstance3D
			if n == null:
				continue
			var a: AABB = n.global_transform * n.mesh.get_aabb()
			slab_bb = a if slab_first else slab_bb.merge(a)
			slab_first = false
		var roof := house.get_node_or_null("Body/Roof") as MeshInstance3D
		var roof_bottom := (roof.global_transform * roof.mesh.get_aabb()).position.y if roof else 0.0
		print("MondrianHouse 一层天花板下表面（二层楼板底）y = %.3f" % slab_bb.position.y)
		print("MondrianHouse 二层天花板下表面（屋顶底）    y = %.3f" % roof_bottom)
		for mi in house.find_children("Tube*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var a: AABB = m.global_transform * m.mesh.get_aabb()
			var ceil_y := slab_bb.position.y if a.position.y < 5.0 else roof_bottom
			print("  %-10s 顶面 y = %.3f → 到天花板 **%+.3f m**"
				% [String(m.name), a.end.y, ceil_y - a.end.y])
		for mi in house.find_children("DoorLampBody", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var a: AABB = m.global_transform * m.mesh.get_aabb()
			print("  DoorLampBody 中心 z = %.3f（北墙外表面 z = %.3f → 悬在墙外 %.3f m）"
				% [a.get_center().z, house.global_position.z - 6.00,
					(house.global_position.z - 6.00) - a.get_center().z])
	if shop != null:
		var ceil := shop.get_node_or_null("Decor/Ceiling") as MeshInstance3D
		var cb: AABB = ceil.global_transform * ceil.mesh.get_aabb() if ceil else AABB()
		print("Shop 天花板下表面 y = %.3f" % cb.position.y)
		for mi in shop.find_children("CeilingTube*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var a: AABB = m.global_transform * m.mesh.get_aabb()
			print("  %-16s 顶面 y = %.3f → 到天花板 %+.3f m"
				% [String(m.name), a.end.y, cb.position.y - a.end.y])
	var hut := game.get_node_or_null("MeshHut") as Node3D
	if hut != null:
		for nm in ["Hut/Roof", "HutLamp", "LampCord"]:
			var n := hut.get_node_or_null(nm) as Node3D
			if n == null:
				continue
			var desc := ""
			if n is CSGBox3D:
				var b := n as CSGBox3D
				desc = "CSG size %s 中心 %s" % [str(b.size), str(b.global_position.snappedf(0.01))]
			elif n is MeshInstance3D:
				var a: AABB = (n as MeshInstance3D).global_transform \
					* (n as MeshInstance3D).mesh.get_aabb()
				desc = "y %.3f ~ %.3f" % [a.position.y, a.end.y]
			print("MeshHut %-10s %s" % [nm, desc])

	# 天花板特写
	if house != null:
		var hp := house.global_position
		cam.fov = 70.0
		cam.global_position = Vector3(hp.x, 2.20, hp.z + 4.60)
		cam.look_at(Vector3(hp.x, 3.95, hp.z + 0.60), Vector3.UP)
		await _shot(cam, out, "mondrian_1f_ceiling")
		cam.global_position = Vector3(hp.x, 5.60, hp.z + 4.60)
		cam.look_at(Vector3(hp.x, 8.00, hp.z + 0.60), Vector3.UP)
		await _shot(cam, out, "mondrian_2f_ceiling")
		cam.fov = 55.0
		cam.global_position = Vector3(hp.x, 2.00, hp.z - 9.60)
		cam.look_at(Vector3(hp.x, 3.10, hp.z - 6.00), Vector3.UP)
		await _shot(cam, out, "mondrian_door")
	if hut != null:
		cam.fov = 70.0
		cam.global_position = Vector3(14.0, 1.60, -14.6)
		cam.look_at(Vector3(13.4, 4.60, -17.0), Vector3.UP)
		await _shot(cam, out, "hut_ceiling")

	# ══════════ ③ 楼梯：逐帧跳变 ══════════
	print("\n══════ ③ 爬楼梯：每一帧的 y 跳了多少 ══════")
	var player := game.get("_player") as CharacterBody3D
	var rig := player.get_node_or_null("CameraRig") as Node3D if player != null else null
	if house != null and player != null:
		var hp2 := house.global_position
		player.global_position = Vector3(hp2.x - 6.95, 0.10, hp2.z - 5.60)
		player.velocity = Vector3.ZERO
		for _f in 20:
			await process_frame
		Input.action_press("move_back")
		var prev := player.global_position.y
		var prev_cam := player.global_position.y + (rig.position.y if rig != null else 0.0)
		var jumps: Array[float] = []
		var cam_jumps: Array[float] = []
		for _f in 200:
			await process_frame
			var y := player.global_position.y
			var d := y - prev
			if absf(d) > 0.004:
				jumps.append(d)
			prev = y
			var cy := player.global_position.y + (rig.position.y if rig != null else 0.0)
			var dc := cy - prev_cam
			if absf(dc) > 0.004:
				cam_jumps.append(dc)
			prev_cam = cy
		Input.action_release("move_back")
		var mx := 0.0
		var sum := 0.0
		for j in jumps:
			mx = maxf(mx, absf(j))
			sum += absf(j)
		var cmx := 0.0
		var csum := 0.0
		for j in cam_jumps:
			cmx = maxf(cmx, absf(j))
			csum += absf(j)
		print("  **身体**：跳变帧 %d、单帧最大 %.3f m、合计 %.3f m" % [jumps.size(), mx, sum])
		print("  **相机**（人 y + rig.y，就是眼睛的高度）：跳变帧 %d、单帧最大 %.3f m、合计 %.3f m"
			% [cam_jumps.size(), cmx, csum])
		print("  ⇒ 身体一帧跳 %.3f m 是物理本来就有的；相机只要比它小一个量级就算「顺」" % mx)
		# 半山腰出图
		player.global_position = Vector3(hp2.x - 6.95, 0.10, hp2.z - 5.60)
		player.velocity = Vector3.ZERO
		for _f in 20:
			await process_frame
		Input.action_press("move_back")
		for _f in 75:
			await process_frame
		Input.action_release("move_back")
		for _f in 5:
			await process_frame
		cam.fov = 75.0
		cam.global_position = player.global_position + Vector3(1.2, 1.0, -2.6)
		cam.look_at(player.global_position + Vector3(0.0, 0.6, 1.5), Vector3.UP)
		await _shot(cam, out, "stairs_mid")

	# ══════════ ④ 共面重叠（同向面）══════════
	print("\n══════ ④ 三处场地的共面重叠（只算同向面：+面=+面 或 −面=−面）══════")
	for area in [["Shop", shop], ["MeshHut", hut], ["MondrianHouse", house]]:
		var node := area[1] as Node
		if node == null:
			continue
		var list: Array = []
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			list.append({"n": "%s/%s" % [m.get_parent().name, m.name],
				"a": m.global_transform * m.mesh.get_aabb()})
		var found: Array = []
		for i in list.size():
			for j in range(i + 1, list.size()):
				var a: AABB = list[i]["a"]
				var b: AABB = list[j]["a"]
				for axis in 3:
					var a0: float = a.position[axis]
					var a1: float = a0 + a.size[axis]
					var b0: float = b.position[axis]
					var b1: float = b0 + b.size[axis]
					var same_max := absf(a1 - b1) < 0.002
					var same_min := absf(a0 - b0) < 0.002
					if not same_max and not same_min:
						continue
					var area2 := 1.0
					for ax in 3:
						if ax == axis:
							continue
						var lo: float = maxf(a.position[ax], b.position[ax])
						var hi: float = minf(a.position[ax] + a.size[ax],
							b.position[ax] + b.size[ax])
						area2 *= maxf(hi - lo, 0.0)
					if area2 > 0.004:
						found.append({"a": list[i]["n"], "b": list[j]["n"], "ax": axis,
							"area": area2, "face": "+" if same_max else "-"})
		found.sort_custom(func(x, y): return float(x["area"]) > float(y["area"]))
		print("%s：网格 %d 个 → 同向共面 **%d 组**" % [area[0], list.size(), found.size()])
		for h in found.slice(0, 20):
			print("    %-34s ↔ %-34s 轴%d %s面 %.3f m²"
				% [h["a"], h["b"], h["ax"], h["face"], h["area"]])

	print("\n[截图] %s" % out)
	quit(0)
