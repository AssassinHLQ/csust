extends SceneTree
## 复现「第二场景卡在校园渲染器加载中」：从 game.tscn 走门进 next_level，
## 然后查 campus_ggs 到底卡在哪一步。
##   _tools/run_shot.sh res://scripts/_probe_scene_switch_ggs.gd -- --story=off


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _report(tag: String) -> void:
	var scene := current_scene
	print("[sw] ── %s ──" % tag)
	print("[sw]   current_scene = %s" % (str(scene.scene_file_path) if scene != null else "null"))
	var cam := root.get_camera_3d()
	print("[sw]   根视口相机 = %s" % (str(cam) if cam != null else "**null**"))
	var ggs := scene.get_node_or_null("CampusGGS") if scene != null else null
	if ggs == null:
		print("[sw]   没有 CampusGGS 节点")
		return
	print("[sw]   CampusGGS: gave_up=%s ready_done=%s released=%s total=%d is_ready=%s" % [
		str(ggs.get("_gave_up")), str(ggs.get("_ready_done")),
		str(ggs.get("_released")), int(ggs.get("_total")), str(ggs.call("is_ready"))])
	print("[sw]   ggs.cam = %s   rasterizer=%s  quad=%s" % [
		str(ggs.get("cam")), str(ggs.get("rasterizer")), str(ggs.get("quad"))])
	var ov := ggs.get("_overlay") as CanvasLayer
	if ov != null:
		var lbl := ov.find_children("*", "Label", true, false)
		print("[sw]   遮罩 visible=%s 文本=%s" % [
			str(ov.visible), (lbl[0] as Label).text if not lbl.is_empty() else "?"])
	var pl := scene.get_node_or_null("Player")
	if pl != null:
		var pc := pl.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
		print("[sw]   玩家相机 current=%s" % (str(pc.current) if pc != null else "没找到"))


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await _wait(180)
	await _report("切换前")

	var gate := game.get_node_or_null("MondrianHouse/MondrianGate")
	if gate == null:
		print("[sw] 找不到 MondrianGate")
		quit(1)
		return
	gate.call("enter")

	# 等换场景 + 预载：判据改成 is_ready()（玩家在厅里时应立刻为真）
	var waited := 0
	for i in 20:
		await _wait(60)
		waited = i + 1
		var scene := current_scene
		var ggs := scene.get_node_or_null("CampusGGS") if scene != null else null
		if ggs != null and bool(ggs.call("is_ready")):
			print("[sw] 第 %d 秒：is_ready() 为真" % waited)
			break
	await _report("切换后")

	# 决定性验证：换完之后画面是厅还是黑屏
	await _wait(60)
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://_log/after_switch.png"))
	print("[sw] 截图 → res://_log/after_switch.png（应为大厅，不是黑屏+加载文本）")
	quit(0)