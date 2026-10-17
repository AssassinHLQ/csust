extends SceneTree
## 探针：**609 门内 / 门外各拍一张**，验「门外网格、门内泼溅」这套切换。
##
## 判定不是看代码，是看两个状态：
##   · 玩家挪到房间外 30 m → 代理网格 `RoomProxy.visible = true`、泼溅 `visible = false`
##   · 玩家挪到房间正中   → 反过来
## 然后把这两种状态下**同一台固定相机**拍到的画面存下来。
##
## 输出 `_arisu_captures/_roomswap/outside.png / inside.png`
##
## 用法：godot --path <工程> --script res://scripts/_probe_room_swap_shot.gd
##      （**不要**加 --splat=off，这套切换要真泼溅）

const OUT_SUB := "_roomswap"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1000, 620)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)

	# 藏掉 HUD / 同伴（同伴会走到镜头前）
	for n in ["HUD", "SettingsMenu", "DialogueBox"]:
		var c: Node = game.get_node_or_null(n)
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	for c in game.get_children():
		if c is Companion:
			(c as Node3D).visible = false

	# 等房间泼溅真正就位（277 万点，第一次要解码）
	var room: Node = game.get_node_or_null("Room609")
	if room == null:
		print("!! 场景里没有 Room609")
		quit(1)
		return
	var waited := 0
	while waited < 1200 and not bool(room.call("is_ready")):
		await process_frame
		waited += 1
	print("[swap] 等房间就位：%d 帧 → is_ready=%s" % [waited, str(room.call("is_ready"))])

	var player := game.get_node_or_null("Player") as Node3D
	if player == null:
		print("!! 没有 Player")
		quit(1)
		return

	# 房间矩形 / 代理节点（从 game 的私有变量读，探针不嫌它私有）
	var box: AABB = game.get("_room_box")
	var proxy := game.get_node_or_null("RoomProxy") as Node3D
	var splat: Node3D = room.get("splat_node") as Node3D
	if box.size.length() <= 0.0 or proxy == null:
		print("!! 没建出代理网格（_room_box=%s proxy=%s）" % [str(box), str(proxy)])
		quit(1)
		return
	var center := box.position + box.size * 0.5
	print("[swap] 房间矩形 size=%s center=%s" % [
		str(box.size.snappedf(0.01)), str(center.snappedf(0.01))])

	# 固定相机：斜上方看整间房
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)
	cam.make_current()
	var reach := maxf(box.size.x, box.size.z) * 1.15
	var eye := center + Vector3(0.72, 0.62, 0.72).normalized() * reach + Vector3.UP * 2.0
	cam.global_position = eye
	cam.look_at(center, Vector3.UP)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(out)

	# ── 门外：把玩家挪到 30 m 外 ──
	player.global_position = center + Vector3(0.72, 0.0, 0.72).normalized() * 30.0 \
		+ Vector3.UP * 0.05
	await _settle()
	print("[swap] 门外：proxy.visible=%s  splat.visible=%s" % [
		str(proxy.visible), str(splat.visible if splat != null else null)])
	await _shoot(cam, out.path_join("outside.png"))

	# ── 门内：玩家站到房间正中 ──
	player.global_position = Vector3(center.x, 0.05, center.z)
	await _settle()
	print("[swap] 门内：proxy.visible=%s  splat.visible=%s" % [
		str(proxy.visible), str(splat.visible if splat != null else null)])
	# 门内换成平视：从房间一角看向对面（斜上方是从墙外看，进不去）
	cam.global_position = Vector3(center.x - box.size.x * 0.35, 1.65,
		center.z - box.size.z * 0.35)
	cam.look_at(Vector3(center.x + box.size.x * 0.3, 1.4, center.z + box.size.z * 0.3),
		Vector3.UP)
	await _shoot(cam, out.path_join("inside.png"))
	quit(0)


func _settle() -> void:
	for _i in 12:
		await process_frame


func _shoot(cam: Camera3D, file: String) -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("  [img] %s" % file)
