extends SceneTree
## 探针：第二场景 Boss 血条**长什么样、在屏幕哪**（出图 + 打坐标）。
##
## 用法：& <godot_console.exe> --path . --script res://scripts/_probe_next_level_bossbar.gd -- --splat=off --no-capture
## 出图：_arisu_captures/_next_level_bossbar/bars.png

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "_next_level_bossbar"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	print("[焦点自检] %s" % str(OffWin.is_safe()))

	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _i in 200:
		await process_frame
	paused = false
	for _f in 40:
		await process_frame

	# 藏掉非 HUD 的 CanvasLayer？不 —— 血条就在 HUD 里，别藏
	var hud := level.get_node_or_null("HUD") as CanvasLayer
	print("HUD: %s" % str(hud))

	# 打印每条血条 + 名字标签的位置和尺寸
	for c in hud.get_children():
		var nm := String(c.name)
		if not (nm.begins_with("BossBar") or nm.begins_with("BossName")):
			continue
		var ctrl := c as Control
		if ctrl == null:
			continue
		print("  %-12s rect 位置 %s  尺寸 %s  visible=%s"
			% [nm, str(ctrl.position), str(ctrl.size), str(ctrl.visible)])
		if ctrl is ProgressBar:
			var pb := ctrl as ProgressBar
			print("                value %.2f / %.2f" % [pb.value, pb.max_value])

	# 出图
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	# 站到能看见三只恐龙的位置（它们在世界哪？打印一下）
	var pos_list: Array[String] = []
	for node in get_nodes_in_group("bosses"):
		if level.is_ancestor_of(node):
			var n3 := node as Node3D
			pos_list.append("%s@%s" % [String(n3.name), str(n3.global_position.round())])
	print("  Boss 位置：%s" % ", ".join(pos_list))

	# 相机：站在场地中央上方，俯瞰三只
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 500.0
	cam.fov = 65.0
	root.add_child(cam)
	var first: Node3D = null
	for node in get_nodes_in_group("bosses"):
		if level.is_ancestor_of(node):
			first = node as Node3D
			break
	if first != null:
		var p := first.global_position
		cam.global_position = p + Vector3(0, 14.0, -18.0)
		cam.look_at(p + Vector3(0, 1.5, 0), Vector3.UP)
		cam.make_current()
		for _f in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png("%s/bars.png" % out)
		print("  [图] %s/bars.png" % out)

	quit(0)
