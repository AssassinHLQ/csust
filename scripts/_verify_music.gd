extends SceneTree
## 验数：商店 BGM —— ① ogg 真的带循环 ② 进店播、出店停 ③ 音量/淡入参数
##   godot --path . --headless --script res://scripts/_verify_music.gd -- --splat=off
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== 1. 资源与导入选项 ===")
	print("表里的曲目：%s" % str(Music.names()))
	print("缺文件的曲目：%s（应为空）" % str(Music.missing_files()))
	var path := "res://assets/music/shop_theme.ogg"
	var st := load(path) as AudioStreamOggVorbis
	if st == null:
		print("[错误] 载入 %s 失败" % path)
		quit(1)
		return
	print("载入成功：%s" % st.get_class())
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
	var player := game.get("_player") as CharacterBody3D
	if shop == null or player == null:
		print("[错误] 缺节点")
		quit(1)
		return
	var zone := shop.get_node_or_null("MusicZone") as Area3D
	print("\n=== 2. 触发区 ===")
	print("MusicZone：%s" % ("有" if zone != null else "**没有**"))
	if zone != null:
		var cs := zone.get_node_or_null("") as CollisionShape3D
		for c in zone.get_children():
			var sh := c as CollisionShape3D
			if sh != null and sh.shape is BoxShape3D:
				var b := sh.shape as BoxShape3D
				print("  盒子 %.2f × %.2f × %.2f，中心本地 %s"
					% [b.size.x, b.size.y, b.size.z, str(sh.position)])

	var sp := shop.global_position
	print("\n=== 3. 进店 / 出店 ===")
	print("商店世界原点 %s" % str(sp))

	# 出店位置：商店南墙外（z 比 -12.70 更大）
	player.global_position = Vector3(sp.x, 0.10, sp.z + 6.0)
	player.velocity = Vector3.ZERO
	for _f in 40:
		await process_frame
	print("[店外 %.1f m] current=「%s」 is_playing=%s（应为空/false）"
		% [sp.z + 6.0 - sp.z, Music.current(), str(Music.is_playing())])
	var was_stopped := Music.current() == "" and not Music.is_playing()

	# 进店：柜台前
	player.global_position = Vector3(sp.x - 1.70, 0.10, sp.z)
	player.velocity = Vector3.ZERO
	for _f in 60:
		await process_frame
	print("[店内]       current=「%s」 is_playing=%s（应为 shop/true）"
		% [Music.current(), str(Music.is_playing())])
	var started := Music.current() == "shop" and Music.is_playing()

	# 出店
	player.global_position = Vector3(sp.x, 0.10, sp.z + 8.0)
	player.velocity = Vector3.ZERO
	for _f in 120:
		await process_frame
	print("[再出店]     current=「%s」 is_playing=%s（应为空/false）"
		% [Music.current(), str(Music.is_playing())])
	var stopped := Music.current() == "" and not Music.is_playing()

	print("\n=== 4. 判定 ===")
	print("  循环开关       %s" % ("✔" if st.loop else "✘"))
	print("  进店开始播放   %s" % ("✔" if started else "✘"))
	print("  出店停止播放   %s" % ("✔" if stopped else "✘"))
	print("  店外保持安静   %s" % ("✔" if was_stopped else "✘"))
	print("  音乐长度       %.4f s" % st.get_length())
	quit(0)
