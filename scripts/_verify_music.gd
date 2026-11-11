extends SceneTree
## 验数：BGM —— ① ogg 真的带循环 ② 商店：进店播、出店停
##                    ③ 游戏开发部：触发区量得对、进房播、出房停
##                    ④ 电竞房：房子藏着不响、现身才响、出房停
##                    ⑤ 画室609：范围按「出门」定（屋里放、出门停、屋顶不算屋里）
##   godot --path . --headless --script res://scripts/_verify_music.gd -- --splat=off
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== 1. 资源与导入选项 ===")
	print("表里的曲目：%s" % str(Music.names()))
	print("缺文件的曲目：%s（应为空）" % str(Music.missing_files()))

	var shop_st := load("res://assets/music/shop_theme.ogg") as AudioStreamOggVorbis
	var gd_st := load("res://assets/music/gamedev_theme.ogg") as AudioStreamOggVorbis
	var es_st := load("res://assets/music/esports_theme.ogg") as AudioStreamOggVorbis
	var r609_st := load("res://assets/music/art609_theme.ogg") as AudioStreamOggVorbis
	for pair in [["shop_theme.ogg", shop_st], ["gamedev_theme.ogg", gd_st],
			["esports_theme.ogg", es_st], ["art609_theme.ogg", r609_st]]:
		var name: String = pair[0]
		var st: AudioStreamOggVorbis = pair[1]
		if st == null:
			print("[错误] 载入 %s 失败" % name)
			quit(1)
			return
		print("\n%s：%s" % [name, st.get_class()])
		print("  loop        = %s   ← 必须是 true" % str(st.loop))
		print("  loop_offset = %.3f" % st.loop_offset)
		print("  长度        = %.4f s" % st.get_length())

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	for _f in 20:
		await process_frame

	var shop := game.get_node_or_null("Shop") as Node3D
	var gdroom := game.get_node_or_null("GameDevRoom") as Node3D
	var player := game.get("_player") as CharacterBody3D
	if shop == null or gdroom == null or player == null:
		print("[错误] 缺节点：shop=%s gdroom=%s player=%s"
			% [str(shop != null), str(gdroom != null), str(player != null)])
		quit(1)
		return

	# ─────────────────────────── 商店 ───────────────────────────
	print("\n=== 2. 商店触发区 ===")
	var zone := shop.get_node_or_null("MusicZone") as Area3D
	print("MusicZone：%s" % ("有" if zone != null else "**没有**"))
	var shop_size := Vector3.ZERO
	if zone != null:
		shop_size = _print_zone(zone)
	# ⚠️ 2026-11-11 用户报过：商店扩建了，音乐范围还是旧的（只盖住前半间）。
	#    判据 = 触发区必须盖住店面地面（`InteriorFloor/FloorShape`）减去内缩量。
	var foot := _aabb_of(shop.get_node_or_null("InteriorFloor/FloorShape") as CollisionShape3D)
	print("  店面地面：%.2f × %.2f m（x × z）中心 (%.2f, %.2f)"
		% [foot.size.x, foot.size.z, foot.get_center().x, foot.get_center().z])
	print("  触发区  ：%.2f × %.2f m（x × z）"
		% [shop_size.x, shop_size.z])
	var shop_zone_ok := zone != null \
		and shop_size.x >= foot.size.x - 2.0 and shop_size.z >= foot.size.z - 2.0 \
		and shop_size.z >= 8.0      # 旧 bug 的 z 只有 5.0 —— 这条直接卡住回退

	var sp := shop.global_position
	print("\n=== 3. 商店：进店 / 出店 ===")
	print("商店世界原点 %s" % str(sp))

	# 出店位置：商店南墙外（z 比 -12.70 更大）
	player.global_position = Vector3(sp.x, 0.10, sp.z + 6.0)
	player.velocity = Vector3.ZERO
	for _f in 40:
		await process_frame
	print("[店外]       current=「%s」 is_playing=%s（应为空/false）"
		% [Music.current(), str(Music.is_playing())])
	var was_stopped := Music.current() == "" and not Music.is_playing()

	# 进店：柜台前
	player.global_position = Vector3(sp.x - 1.70, 0.10, sp.z)
	player.velocity = Vector3.ZERO
	for _f in 60:
		await process_frame
	print("[店内]       current=「%s」 is_playing=%s（应为 shop/true）"
		% [Music.current(), str(Music.is_playing())])
	var shop_started := Music.current() == "shop" and Music.is_playing()

	# 出店
	player.global_position = Vector3(sp.x, 0.10, sp.z + 8.0)
	player.velocity = Vector3.ZERO
	for _f in 120:
		await process_frame
	print("[再出店]     current=「%s」 is_playing=%s（应为空/false）"
		% [Music.current(), str(Music.is_playing())])
	var shop_stopped := Music.current() == "" and not Music.is_playing()

	# ⚠️ 回归：**商店后半间**也必须有音乐（用户 2026-11-11 报的就是这个：
	#    扩建之后判定区还是旧的 5 m 进深，走到后半间音乐就停了）。
	# 用一个「占位玩家」去测：不调 `move_and_slide`，所以不会被家具碰撞推来推去。
	var back := Vector3(sp.x, 0.10, sp.z - 6.0)          # 店面中心 z=-2.6 的后侧
	var shop_back := false
	if zone != null:
		var ghost := _make_probe_player()
		root.add_child(ghost)
		for _f in 10:
			await process_frame
		ghost.global_position = back
		for _f in 60:
			await process_frame
		var in_zone := zone.overlaps_body(ghost)
		print("[商店后半间 %s] current=「%s」 is_playing=%s  重叠=%s（应为 shop/true/true）"
			% [str(back), Music.current(), str(Music.is_playing()), str(in_zone)])
		shop_back = in_zone and Music.current() == "shop" and Music.is_playing()
		# 撤走，别影响后面的房间测试
		ghost.global_position = Vector3(sp.x, 0.10, sp.z + 30.0)
		for _f in 60:
			await process_frame
		ghost.queue_free()
		for _f in 10:
			await process_frame

	# ────────────────────── 游戏开发部活动室 ──────────────────────
	print("\n=== 4. 游戏开发部：触发区 ===")
	var gd_zone := gdroom.get_node_or_null("MusicZone") as Area3D
	print("MusicZone：%s" % ("有" if gd_zone != null else "**没有**"))
	var gd_size := Vector3.ZERO
	var gd_centre := Vector3.ZERO
	if gd_zone != null:
		gd_size = _print_zone(gd_zone)
		gd_centre = gd_zone.global_position

	# 触发区必须**在房间内部**：房间根节点在 (51.44, 0.01, -6.92)，
	# 触发区中心应当离它不远（量错坐标系时这里会明显偏出去）
	var gd_offset := gd_centre - gdroom.global_position
	print("  房间根 %s，触发区中心偏差 %s（应在房间内部，量级 < 8 m）"
		% [str(gdroom.global_position), str(gd_offset)])
	var zone_ok := gd_zone != null \
		and gd_size.x > 3.0 and gd_size.z > 3.0 \
		and Vector2(gd_offset.x, gd_offset.z).length() < 8.0

	print("\n=== 5. 游戏开发部：进房 / 出房 ===")
	# 进房：触发区中心正下方（y 用房间地面，触发区中心在房间半高）
	player.global_position = Vector3(gd_centre.x, gdroom.global_position.y + 0.10, gd_centre.z)
	player.velocity = Vector3.ZERO
	for _f in 60:
		await process_frame
	var gd_overlap := gd_zone != null and gd_zone.overlaps_body(player)
	print("[房内]       current=「%s」 is_playing=%s  区内容器重叠=%s（应为 gamedev/true/true）"
		% [Music.current(), str(Music.is_playing()), str(gd_overlap)])
	print("             玩家落在 %s" % str(player.global_position))
	var gd_started := Music.current() == "gamedev" and Music.is_playing()

	# 出房：往 +x 挪 25 m（房间 +x 侧墙外，中间隔着别的建筑也不会误触）
	player.global_position = Vector3(gd_centre.x + 25.0, 0.10, gd_centre.z)
	player.velocity = Vector3.ZERO
	for _f in 120:
		await process_frame
	print("[房外]       current=「%s」 is_playing=%s（应为空/false）"
		% [Music.current(), str(Music.is_playing())])
	var gd_stopped := Music.current() == "" and not Music.is_playing()

	# ─────────────────────────── 电竞房 ───────────────────────────
	#
	# 单独把 `esports_room.tscn` 摘出来测，不走 `game.tscn`——
	# 那边的电竞房要「买下 → 从天而降」才现身，演出会挪房间、抢相机，
	# 测音乐会被这些干扰。这里直接用一个人造的 `player` 探房间，
	# 顺带把「房子藏着的时候不能出声」这条也验了。
	print("\n=== 6. 电竞房 ===")
	var es_room := (load("res://scenes/esports_room.tscn") as PackedScene).instantiate() as Node3D
	es_room.visible = false          # 和 game.tscn 一样：默认藏着
	root.add_child(es_room)
	for _f in 30:
		await process_frame
	var es_zone := es_room.get_node_or_null("MusicZone") as Area3D
	print("MusicZone：%s" % ("有" if es_zone != null else "**没有**"))
	var es_size := Vector3.ZERO
	var es_centre := Vector3.ZERO
	if es_zone != null:
		es_size = _print_zone(es_zone)
		es_centre = es_zone.global_transform * (es_zone.get_child(0) as CollisionShape3D).position
	# ⚠️ 触发区 = 房间包围盒 **水平每边外扩 2 m**（用户 2026-11-11：
	#    「电竞房判定范围往外扩一圈2m」）。这里用房间自己量出来的那份包围盒对账，
	#    而不是写死数字 —— 房间尺寸还在变。
	var es_bounds := AABB()
	if es_room.has_method("_baked_bounds"):
		es_bounds = es_room.call("_baked_bounds")
	var want_x: float = es_bounds.size.x + 4.0      # 每边 +2
	var want_z: float = es_bounds.size.z + 4.0
	var want_y: float = es_bounds.size.y * 2.0      # 高度仍取 2 倍
	print("  房间包围盒 %.2f × %.2f × %.2f" % [es_bounds.size.x, es_bounds.size.y, es_bounds.size.z])
	print("  期望盒子   %.2f × %.2f × %.2f（水平每边 +2 m）" % [want_x, want_y, want_z])
	var es_zone_ok := es_zone != null and es_bounds.size != Vector3.ZERO \
		and absf(es_size.x - want_x) < 0.05 \
		and absf(es_size.z - want_z) < 0.05 \
		and absf(es_size.y - want_y) < 0.05
	print("  实际盒子   %.2f × %.2f × %.2f" % [es_size.x, es_size.y, es_size.z])

	# 人造玩家：第 1 层 + `player` 组，正好是触发区认的目标
	var probe := _make_probe_player()
	root.add_child(probe)
	for _f in 10:
		await process_frame

	# ① 房子还藏着，人已经站在里面 → 必须不出声
	probe.global_position = es_centre
	probe.velocity = Vector3.ZERO
	for _f in 60:
		await process_frame
	var es_overlap := es_zone != null and es_zone.overlaps_body(probe)
	print("[藏着·人在里面] current=「%s」 is_playing=%s  重叠=%s（应为空/false/true）"
		% [Music.current(), str(Music.is_playing()), str(es_overlap)])
	var es_silent_hidden := es_overlap and Music.current() == "" and not Music.is_playing()

	# ② 房子现身（同 game.gd 的 `_reveal_east_rooms`：只翻 visible）→ 当场补上
	es_room.visible = true
	for _f in 60:
		await process_frame
	print("[现身·人还在里面] current=「%s」 is_playing=%s（应为 esports/true）"
		% [Music.current(), str(Music.is_playing())])
	var es_started := Music.current() == "esports" and Music.is_playing()

	# ③ 走出去 → 停
	probe.global_position = es_centre + Vector3(0.0, 0.0, 60.0)
	probe.velocity = Vector3.ZERO
	for _f in 90:
		await process_frame
	print("[出房] current=「%s」 is_playing=%s（应为空/false）"
		% [Music.current(), str(Music.is_playing())])
	var es_stopped := Music.current() == "" and not Music.is_playing()

	probe.queue_free()

	# ─────────────────────────── 画室 609 ───────────────────────────
	#
	# 用户 2026-11-11：「Lemonade Diary 这个换画室609 的音乐，范围就是按照出门来定」。
	# 这里放的 BGM 不建 Area3D，而是复用 `splat_scene.gd::_is_inside_room()` ——
	# **和「出房间释放泼溅显存」同一套边界**（跨出门框就算出去）。
	# 所以验的就是那套判据：屋里放、出门停、屋顶上不算屋。
	print("\n=== 7. 画室 609 ===")
	var r609 := game.get_node_or_null("Room609")
	if r609 == null:
		print("  **没有 Room609**")
	var r609_track := "" if r609 == null else str(r609.get("room_bgm_track"))
	print("  room_bgm_track =「%s」（应为 room609）" % r609_track)

	var r609_in := false
	var r609_out := false
	var r609_roof := false
	if r609 != null:
		# 范围要等 `_room_xz` 量出来；它读的是 `RoomCollision` 里手摆的墙盒，
		# 跟泼溅加载没关系（`_update_room_bgm()` 里会懒着补量一次）。
		for _f in 240:
			if (r609.get("_room_xz") as Rect2).size != Vector2.ZERO:
				break
			await process_frame
		var rect: Rect2 = r609.get("_room_xz")
		# ⚠️ Rect2 的 `.y` 装的是**世界 z**（见 `_room_xz_from_walls()`）
		var cx := rect.position.x + rect.size.x * 0.5
		var cz := rect.position.y + rect.size.y * 0.5
		# ⚠️ `_room_y_lo` 是**墙盒底**（埋在地下），不是地板；609 地面在 y ≈ 0.03
		var fy := 0.10
		print("  _room_xz = x %.2f~%.2f, z %.2f~%.2f，高度窗口 y %.2f~%.2f"
			% [rect.position.x, rect.position.x + rect.size.x,
				rect.position.y, rect.position.y + rect.size.y,
				float(r609.get("_room_y_lo")), float(r609.get("_room_y_hi"))])

		player.global_position = Vector3(cx, fy, cz)
		player.velocity = Vector3.ZERO
		for _f in 20:
			await process_frame
		print("[画室里 %s] current=「%s」（应为 room609）"
			% [str(player.global_position), Music.current()])
		r609_in = Music.current() == "room609" and Music.is_playing()

		# 出门：往门那一侧（`box_door_side = "z-"`）走出矩形
		player.global_position = Vector3(cx, fy, rect.position.y - 2.0)
		player.velocity = Vector3.ZERO
		# 不淡化之后**应该立刻就停**；留几帧给判据的防抖，并断言「停得快」
		var stop_frames := -1
		for _f in 150:
			await process_frame
			if Music.current() == "" and not Music.is_playing():
				stop_frames = _f
				break
		print("[画室门外 %s] current=「%s」 is_playing=%s（应为空/false，用了 %d 帧）"
			% [str(player.global_position), Music.current(), str(Music.is_playing()), stop_frames])
		r609_out = Music.current() == "" and not Music.is_playing() \
			and stop_frames >= 0 and stop_frames < 30

		# 屋顶上：横向还在矩形内，但高过墙顶 → 也算屋外
		player.velocity = Vector3.ZERO
		player.global_position = Vector3(cx, float(r609.get("_room_y_hi")) + 0.8, cz)
		for _f in 3:
			await process_frame          # 只等 3 帧，再等就被重力拽回屋里了
		print("[画室屋顶 %s] current=「%s」（应为空）"
			% [str(player.global_position), Music.current()])
		r609_roof = Music.current() == ""

	print("\n=== 8. 判定 ===")
	# ⚠️ 用户 2026-11-11：「不要淡入淡出了，所有的」—— 默认淡化必须为 0
	var no_fade := float(Music.FADE_DEFAULT) <= 0.0
	print("  默认不淡化（FADE_DEFAULT=%.1f）%s" % [
		float(Music.FADE_DEFAULT), "✔" if no_fade else "✘"])
	print("  循环开关（商店）        %s" % ("✔" if shop_st.loop else "✘"))
	print("  循环开关（游戏开发部）  %s" % ("✔" if gd_st.loop else "✘"))
	print("  循环开关（电竞房）      %s" % ("✔" if es_st.loop else "✘"))
	print("  循环开关（画室609）     %s" % ("✔" if r609_st.loop else "✘"))
	print("  画室609：接回 1:16      %s（loop_offset = %.4f s，应约 76.40；全长 %.2f s，应 151.90）"
		% [("✔" if r609_st.loop_offset > 75.5 and r609_st.loop_offset < 77.5
				and absf(r609_st.get_length() - 151.90) < 0.05 else "✘"),
			r609_st.loop_offset, r609_st.get_length()])
	print("  商店：触发区盖住店面    %s" % ("✔" if shop_zone_ok else "✘"))
	print("  商店：后半间也有音乐    %s" % ("✔" if shop_back else "✘"))
	print("  商店：进店开始播放      %s" % ("✔" if shop_started else "✘"))
	print("  商店：出店停止播放      %s" % ("✔" if shop_stopped else "✘"))
	print("  商店：店外保持安静      %s" % ("✔" if was_stopped else "✘"))
	print("  开发部：触发区量得对    %s" % ("✔" if zone_ok else "✘"))
	print("  开发部：进房开始播放    %s" % ("✔" if gd_started else "✘"))
	print("  开发部：出房停止播放    %s" % ("✔" if gd_stopped else "✘"))
	print("  电竞房：触发区量得对    %s" % ("✔" if es_zone_ok else "✘"))
	print("  电竞房：藏着时不出声    %s" % ("✔" if es_silent_hidden else "✘"))
	print("  电竞房：现身才出声      %s" % ("✔" if es_started else "✘"))
	print("  电竞房：出房停止播放    %s" % ("✔" if es_stopped else "✘"))
	print("  画室609：曲目接上了     %s" % ("✔" if r609_track == "room609" else "✘"))
	print("  画室609：屋里放         %s" % ("✔" if r609_in else "✘"))
	print("  画室609：出门停         %s" % ("✔" if r609_out else "✘"))
	print("  画室609：屋顶不算屋里   %s" % ("✔" if r609_roof else "✘"))
	var all_ok := no_fade \
		and shop_st.loop and gd_st.loop and es_st.loop and r609_st.loop \
		and r609_st.loop_offset > 75.5 and r609_st.loop_offset < 77.5 \
		and absf(r609_st.get_length() - 151.90) < 0.05 \
		and shop_zone_ok and shop_back and shop_started and shop_stopped \
		and was_stopped and zone_ok and gd_started and gd_stopped \
		and es_zone_ok and es_silent_hidden and es_started and es_stopped \
		and r609_track == "room609" and r609_in and r609_out and r609_roof
	print("\n  总判定：%s" % ("全部通过 ✔" if all_ok else "**有失败 ✘**"))
	quit(0 if all_ok else 1)


## 打印触发区的盒子，返回盒子尺寸
func _print_zone(zone: Area3D) -> Vector3:
	for c in zone.get_children():
		var sh := c as CollisionShape3D
		if sh != null and sh.shape is BoxShape3D:
			var b := sh.shape as BoxShape3D
			print("  盒子 %.2f × %.2f × %.2f，中心本地 %s，世界 %s"
				% [b.size.x, b.size.y, b.size.z, str(sh.position), str(zone.global_position)])
			return b.size
	return Vector3.ZERO


## 一个 `BoxShape3D` 的 `CollisionShape3D` → 它自己的**局部** AABB（含自身 transform）
func _aabb_of(cs: CollisionShape3D) -> AABB:
	if cs == null or not (cs.shape is BoxShape3D):
		return AABB()
	var b := cs.shape as BoxShape3D
	var h := b.size * 0.5
	var out := AABB()
	var seen := false
	for i in 8:
		var p: Vector3 = cs.transform * Vector3(
			h.x if (i & 1) != 0 else -h.x,
			h.y if (i & 2) != 0 else -h.y,
			h.z if (i & 4) != 0 else -h.z)
		out = out.expand(p) if seen else AABB(p, Vector3.ZERO)
		seen = true
	return out


## 造一个「占位玩家」：第 1 层 + `player` 组，正好是触发区认的目标。
## 不调 `move_and_slide()`，所以放哪就是哪，不会被家具碰撞推走。
func _make_probe_player() -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "ProbePlayer"
	p.collision_layer = 1
	p.collision_mask = 0
	p.add_to_group("player")
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.6
	cs.shape = shape
	p.add_child(cs)
	return p
