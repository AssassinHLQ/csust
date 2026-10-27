extends SceneTree
## 验：芹香改回原生缩放后，身高/胶囊/提示牌高度是否对得上；并出一张柜台前的实拍。
##   _tools/run_shot.sh res://scripts/_probe_clerk_shot2.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	for c in game.find_children("*", "CanvasLayer", true, false):
		var cl: CanvasLayer = c as CanvasLayer
		if cl != null:
			cl.visible = false

	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk == null:
		print("[FAIL] 没找到芹香")
		quit(1)
		return
	var lo := INF
	var hi := -INF
	for c in clerk.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var low := String(mi.name).to_lower()
		if low.contains("halo") or low.contains("weapon") or low.contains("mouth"):
			continue
		var w: AABB = mi.global_transform * mi.get_aabb()
		lo = minf(lo, w.position.y)
		hi = maxf(hi, w.position.y + w.size.y)
	print("芹香身体：底 %.3f、顶 %.3f、高 %.3f" % [lo, hi, hi - lo])
	var body := clerk.get_node_or_null("ClerkBody/CollisionShape3D") as CollisionShape3D
	if body == null:
		var b2 := clerk.get_node_or_null("ClerkBody")
		if b2 != null and b2.get_child_count() > 0:
			body = b2.get_child(0) as CollisionShape3D
	if body != null and body.shape is CapsuleShape3D:
		var cap := body.shape as CapsuleShape3D
		print("胶囊：高 %.3f、半径 %.3f、中心 y %.3f → 顶面 %.3f"
			% [cap.height, cap.radius, body.position.y, body.position.y + cap.height * 0.5])
	var hint := clerk.get_node_or_null("TalkHint") as Node3D
	if hint != null:
		print("提示牌 y = %.3f" % hint.position.y)

	var cam := Camera3D.new()
	game.add_child(cam)
	cam.global_position = clerk.global_position + Vector3(-2.6, 1.15, 0.35)
	cam.look_at(clerk.global_position + Vector3(0, 0.55, 0))
	cam.current = true
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_clerk_size_after.png")
	img.save_png(out)
	print("[截图] %s" % out)
	quit(0)
