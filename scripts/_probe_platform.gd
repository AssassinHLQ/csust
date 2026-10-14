extends SceneTree
## 试不同 top_gap，对比「默认视角」与「平台边缘低头」两种看法，并检查 floaters 会不会飘到平台上方。
##
## 背景：内容 99.9‰ 顶面被放到 -top_gap，但数据里还有 0.1% 的离群 floaters 高到
## 居中坐标 y=1.88（99.9‰ 只有 0.43），×25 后比内容顶面还高 36 m ——
## gap 不够大时它们会飘在平台上方，看起来像天上的白斑。
##
## 用法：godot --path <工程> --script res://scripts/_probe_platform.gd

const CASES := [
	{"scale": 25.0, "gap": 12.0},
	{"scale": 8.0, "gap": 12.0},
	{"scale": 15.0, "gap": 20.0},
	{"scale": 12.0, "gap": 14.0},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	# 本探针只关心校园那份的下沉量：入树前摘掉画室609（见 _verify_splat.gd 的注释）
	var room := game.get_node_or_null("Room609")
	if room != null:
		room.free()
	root.add_child(game)
	await process_frame
	await process_frame

	var player: Player = game.get_node("Player")
	var splat: SplatScene = game.get_node("SplatScene")
	var guard := 0
	while guard < 30000 and not splat.is_ready():
		await process_frame
		guard += 1
	if not splat.is_ready():
		push_error("[probe] 泼溅没加载起来")
		quit(1)
		return

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_splat")
	DirAccess.make_dir_recursive_absolute(out)

	# floaters 最高点（居中坐标 aabb 的 max.y）换到世界空间
	var floater_top := splat.splat_aabb.position.y + splat.splat_aabb.size.y
	var content_top := splat.content_max.y

	for case_value in CASES:
		var item: Dictionary = case_value
		var gap: float = item["gap"]
		var scale: float = item["scale"]
		splat.world_scale = scale
		splat.top_gap = gap
		splat.apply_transform()
		await process_frame
		var ft: float = floater_top * scale - gap - content_top * scale
		print("=== 缩放 ×%.0f  top_gap %.0f m  内容世界尺寸 %.0f × %.0f m  顶面 y=%.1f  floaters 最高 y=%.1f  %s ===" % [
			scale, gap,
			(splat.content_max.x - splat.content_min.x) * scale,
			(splat.content_max.z - splat.content_min.z) * scale,
			splat.content_top_y(), ft,
			"（飘在平台上方）" if ft > 0.0 else "（已遮住）"])

		# ① 出生点默认视角
		player.global_position = Vector3(0, 0.05, 6)
		player._yaw = 0.0
		player._facing_yaw = PI
		player.model_root.rotation.y = PI
		player._pitch = -0.04
		await _wait(25)
		await _shot(out.path_join("70_s%02d_gap%02d_spawn.png" % [int(scale), int(gap)]))

		# ② 走到 -Z 边缘低头看校园
		player.global_position = Vector3(0, 0.05, -16)
		player._pitch = -0.55
		await _wait(25)
		await _shot(out.path_join("71_s%02d_gap%02d_lookdown.png" % [int(scale), int(gap)]))

	print("[probe] 输出目录：%s" % out)
	quit(0)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("  [img] %s" % path)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
