extends SceneTree
## 探针：新区域「商店」—— 房子尺寸、地板延伸到虚空、门走不走得进去、碰撞配不配对。
##
## 查七件事：
##   1. 商店长度 = 2 × 初始小屋外墙长（用户：「2 个初始房间这么长」）
##   2. 商店整块在平台外面（平台只到 x = ±20），地板把路接上了
##   3. 地板顶面 = y 0（和平台同高，没有台阶），尽头之外仍是虚空
##   4. 门洞是通的：从店里往北穿门不撞东西；玻璃是撞的
##   5. 墙：从外面往店里穿西墙会撞上
##   6. 每个箱体网格都有同名碰撞盒，且 size 完全一致
##   7. 出四张图（店面正面 / 走道 / 店内 / 店外回看平台）
##
## 用法：godot --path <工程> --script res://scripts/_probe_shop.gd -- --splat=off
## 输出：`_arisu_captures/_shop/90_front.png` 等 4 张

const OUT_DIR := "_shop"
var game: Node3D
var space: PhysicsDirectSpaceState3D
var _cam: Camera3D
var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game = (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 30:
		await process_frame
	paused = false
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")
	space = game.get_world_3d().direct_space_state

	var shop := game.get_node_or_null("Shop") as Node3D
	if shop == null:
		print("!! 场景里没有 Shop 节点")
		quit(1)
		return

	var hut_len := float(shop.get("hut_len"))
	var shop_len := float(shop.get("shop_len"))
	var shop_depth := float(shop.get("shop_depth"))
	var pos := shop.global_position
	var deck: Rect2 = shop.get("deck_rect")

	print("\n── 尺寸 ──")
	print("  初始小屋外墙长 %.2f m → 商店长 %.2f m（%.1f 倍）"
		% [hut_len, shop_len, shop_len / maxf(hut_len, 0.001)])
	print("  商店中心 (%.2f, %.2f, %.2f)　进深 %.2f m" % [pos.x, pos.y, pos.z, shop_depth])
	print("  西墙 x=%.2f　东墙 x=%.2f" % [pos.x - shop_len * 0.5, pos.x + shop_len * 0.5])
	print("  地板 x %.2f ~ %.2f　z %.2f ~ %.2f（%.1f × %.1f m）"
		% [deck.position.x, deck.end.x, deck.position.y, deck.end.y,
			deck.size.x, deck.size.y])
	print("  碰撞盒 %d 个、装饰 %d 个"
		% [int(shop.get("built_count")), int(shop.get("decor_count"))])

	_check(is_equal_approx(shop_len, 2.0 * hut_len), "商店长 = 2 × 小屋长")
	_check(pos.x - shop_len * 0.5 > 20.0, "整间商店在平台外面（西墙 x > 20）")
	_check(deck.position.x < 20.1 and deck.end.x > pos.x + shop_len * 0.5,
		"地板从平台边沿（x %.2f）一直铺到商店东墙外（x %.2f）"
		% [deck.position.x, deck.end.x])

	# ── 地板：同高、无台阶、尽头是虚空 ──
	var mid_x := pos.x
	var mid_z := pos.z
	# 走道上的点都挑在**屋顶外**（店里那几条从 y=1.5 往下打，别打到 roof 2.7）
	var spots := [
		["平台内", Vector2(18.0, mid_z + 2.5)],
		["接缝 x=20", Vector2(20.0, mid_z + 2.5)],
		["地板中 x=25", Vector2(25.0, mid_z + 3.7)],
		["地板东端 x=39", Vector2(39.0, mid_z + 3.7)],
		["地板北端 z=+19", Vector2(25.0, 19.0)],
		["地板南端 z=−19", Vector2(25.0, -19.0)],
		["店里 x=27.3", Vector2(mid_x, mid_z)],
	]
	print("\n── 地板射线（从上往下，应命中 y=0）──")
	for s in spots:
		var p: Vector2 = s[1]
		var hit := _ray(Vector3(p.x, 1.5, p.y), Vector3(p.x, -1.0, p.y))
		var ok := not hit.is_empty() and absf(hit.position.y) < 0.02
		print("  %-14s %s" % [s[0], "命中 y=%.3f（%s）" % [hit.position.y, hit.collider.name]
			if not hit.is_empty() else "**没命中**"])
		_check(ok, "地板 %s 顶面 y=0" % s[0])
	var void_hit := _ray(Vector3(41.5, 1.5, mid_z), Vector3(41.5, -6.0, mid_z))
	print("  虚空 x=41.5    %s" % ("不该有东西，却命中 %s" % void_hit.collider.name
		if not void_hit.is_empty() else "空（正确：地板外仍是虚空）"))
	_check(void_hit.is_empty(), "地板尽头之外是虚空（没有偷偷铺满）")

	# ── 门：通／墙：挡／玻璃：挡 ──
	print("\n── 门与墙 ──")
	var door_in := Vector3(mid_x, 1.2, mid_z - 1.6)
	var door_out := Vector3(mid_x, 1.2, mid_z + 3.0)
	var h := _ray(door_in, door_out)
	print("  门洞（店内外穿行）：%s" % ("撞到 %s" % h.collider.name
		if not h.is_empty() else "通畅"))
	_check(h.is_empty(), "1.2 m 高的门洞是通的")

	var h2 := _ray(Vector3(18.0, 1.2, mid_z), Vector3(24.0, 1.2, mid_z))
	print("  西墙：%s" % ("x=%.2f 处撞到 %s" % [h2.position.x, h2.collider.name]
		if not h2.is_empty() else "穿过去了（**不该**）"))
	_check(not h2.is_empty(), "西墙挡人")

	var h3 := _ray(Vector3(mid_x + 3.0, 1.2, mid_z + 5.0), Vector3(mid_x + 3.0, 1.2, mid_z - 5.0))
	print("  店面玻璃：%s" % ("z=%.2f 处撞到 %s" % [h3.position.z, h3.collider.name]
		if not h3.is_empty() else "穿过去了（**不该**）"))
	_check(not h3.is_empty(), "店面玻璃挡人")

	# ── 网格 / 碰撞盒配对 ──
	print("\n── 网格与碰撞盒 ──")
	var body := shop.get_node_or_null("Body") as StaticBody3D
	var meshes: Array = []
	var shapes := {}
	if body != null:
		for c in body.get_children():
			if c is MeshInstance3D:
				meshes.append(c)
			elif c is CollisionShape3D:
				shapes[c.name] = c
	var missing: Array = []
	var size_bad: Array = []
	for m in meshes:
		var mi := m as MeshInstance3D
		var key := mi.name + "Shape"
		if not shapes.has(key):
			missing.append(mi.name)
			continue
		var cs := shapes[key] as CollisionShape3D
		var bm := mi.mesh as BoxMesh
		var bs := cs.shape as BoxShape3D
		if bm == null or bs == null or not bm.size.is_equal_approx(bs.size) \
				or not cs.position.is_equal_approx(mi.position):
			size_bad.append(mi.name)
	print("  网格 %d 个、碰撞盒 %d 个" % [meshes.size(), shapes.size()])
	print("  缺碰撞盒：%s" % ("无" if missing.is_empty() else ", ".join(missing)))
	print("  尺寸/位置不一致：%s" % ("无" if size_bad.is_empty() else ", ".join(size_bad)))
	_check(missing.is_empty() and size_bad.is_empty(),
		"每个箱体网格都有同尺寸、同位置的碰撞盒")

	var label := shop.find_child("SignText", true, false) as Label3D
	_check(label != null and label.text == str(shop.get("sign_text")),
		"招牌字 =「%s」" % str(shop.get("sign_text")))

	# ── 出图 ──
	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.05
	_cam.far = 300.0
	root.add_child(_cam)
	_cam.make_current()

	var shots := [
		["90_front.png", Vector3(mid_x, 2.4, mid_z + 11.0), Vector3(mid_x, 2.2, mid_z)],
		["91_walk.png", Vector3(21.0, 2.0, mid_z + 3.9), Vector3(32.0, 1.3, mid_z + 1.3)],
		["92_counter.png", Vector3(mid_x - 0.2, 1.8, mid_z - 0.4),
			Vector3(mid_x + 5.4, 0.9, mid_z - 1.2)],
		["93_door.png", Vector3(mid_x + 4.2, 1.7, mid_z - 1.4),
			Vector3(mid_x, 1.5, mid_z + 2.8)],
	]
	for s in shots:
		_cam.global_position = s[1]
		_cam.look_at(s[2], Vector3.UP)
		await _shot(out_dir.path_join(s[0]))

	# 高空俯视：直接对应「用户圈红框的那块」——平台东侧整面带是不是都铺上了
	_cam.global_position = Vector3(28.0, 56.0, 0.01)
	_cam.look_at(Vector3(28.0, 0.0, 0.0), Vector3.FORWARD)
	await _shot(out_dir.path_join("94_air.png"))

	print("\n出图目录：%s" % out_dir)
	print("[probe] 通过 %d、失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	return space.intersect_ray(q)


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  ✔ %s" % what)
	else:
		_fail += 1
		print("  ✘ %s" % what)


func _shot(path: String) -> void:
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	for _i in 6:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("[shot] %s" % path.get_file())
