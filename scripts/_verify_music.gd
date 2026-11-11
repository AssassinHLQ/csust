extends SceneTree
## 验数：BGM —— ① ogg 真的带循环 ② 商店：进店播、出店停
##                    ③ 游戏开发部：触发区量得对、进房播、出房停
##                    ④ 电竞房：房子藏着不响、现身才响、出房停
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
	for pair in [["shop_theme.ogg", shop_st], ["gamedev_theme.ogg", gd_st],
			["esports_theme.ogg", es_st]]:
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
	if zone != null:
		_print_zone(zone)

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
	# 触发区应当和房间同量级：这栋房子实测长边约 16.8 m（见 game.gd 的 8.42 半深）
	var es_zone_ok := es_zone != null \
		and es_size.x > 4.0 and es_size.z > 4.0 \
		and es_size.x < 40.0 and es_size.z < 40.0
	print("  盒子 %.2f × %.2f × %.2f（应在 4~40 m 之间，房子长边约 16.8 m）"
		% [es_size.x, es_size.y, es_size.z])

	# 人造玩家：第 1 层 + `player` 组，正好是触发区认的目标
	var probe := CharacterBody3D.new()
	probe.name = "ProbePlayer"
	probe.collision_layer = 1
	probe.collision_mask = 0
	probe.add_to_group("player")
	var probe_cs := CollisionShape3D.new()
	var probe_shape := CapsuleShape3D.new()
	probe_shape.radius = 0.3
	probe_shape.height = 1.6
	probe_cs.shape = probe_shape
	probe.add_child(probe_cs)
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

	print("\n=== 7. 判定 ===")
	print("  循环开关（商店）        %s" % ("✔" if shop_st.loop else "✘"))
	print("  循环开关（游戏开发部）  %s" % ("✔" if gd_st.loop else "✘"))
	print("  循环开关（电竞房）      %s" % ("✔" if es_st.loop else "✘"))
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
	var all_ok := shop_st.loop and gd_st.loop and es_st.loop and shop_started and shop_stopped \
		and was_stopped and zone_ok and gd_started and gd_stopped \
		and es_zone_ok and es_silent_hidden and es_started and es_stopped
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
