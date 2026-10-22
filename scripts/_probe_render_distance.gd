extends SceneTree
## 只读探针：渲染距离（设置项 + 裁切 + 摄像机远裁剪面）。
##   godot --headless --path . --script res://scripts/_probe_render_distance.gd
##
## ⚠️ 会临时改 `render_distance`（落盘到 user://settings.cfg），结束时**恢复原值**。

const GAME := "res://scenes/game.tscn"
const LADDER := [100, 300, 1000]

func _initialize() -> void:
	_run.call_deferred()

func _count_visible(game: Node) -> int:
	var n := 0
	for m in game.find_children("*", "GeometryInstance3D", true, false):
		if (m as GeometryInstance3D).is_visible_in_tree():
			n += 1
	return n

func _run() -> void:
	var ps := load(GAME) as PackedScene
	if ps == null:
		print("[rd] 读不到 ", GAME)
		quit(1)
		return
	var game := ps.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	var rd_node := game.get_node_or_null("RenderDistance") as RenderDistance
	if rd_node == null:
		print("[rd] 没有 RenderDistance 节点（game.gd::_setup_render_distance 没跑？）")
		quit(1)
		return

	var old: float = float(GameSettings.value("render_distance"))
	var fails := 0
	var cam := root.get_camera_3d()
	var island := game.get_node_or_null("Parkour/Island") as Node3D
	var shop_body := game.get_node_or_null("Shop/Body") as Node3D
	if cam == null:
		print("[rd] 没有当前摄像机")
		quit(1)
		return
	print("[rd] 摄像机 %s，渲染距离开局 %d m，簇 %d 个"
		% [str(cam.global_position.snappedf(0.01)), int(GameSettings.render_distance()),
			rd_node.clusters.size()])

	var last_visible := -1
	for rd in LADDER:
		GameSettings.set_value("render_distance", float(rd))
		await process_frame
		var got_far := cam.far
		var vis := _count_visible(game)
		var st: Dictionary = rd_node.stats
		var island_vis := island.is_visible_in_tree() if island != null else false
		var shop_vis := shop_body.is_visible_in_tree() if shop_body != null else false
		print("[rd] 设 %4d m → 摄像机 far %7.1f  可见几何 %3d/%3d 帧  簇 %d/%d  网格 %d/%d"
			% [rd, got_far, vis, rd_node.stats.get("meshes", 0),
				int(st.get("visible_clusters", 0)), int(st.get("clusters", 0)),
				int(st.get("visible_meshes", 0)), int(st.get("meshes", 0))])
		print("[rd]     Parkour/Island 可见=%s（598 m 外）  Shop/Body 可见=%s（约 20 m）  "
			% [str(island_vis), str(shop_vis)]
			+ "数字显示=%s" % GameSettings.value_text("render_distance",
				GameSettings.value("render_distance")))
		if not is_equal_approx(got_far, float(rd)):
			print("[rd] ✗ far 应该是 %d，实际 %.1f" % [rd, got_far])
			fails += 1
		if rd <= 300 and island_vis:
			print("[rd] ✗ %d m 时 598 m 外的 Island 应该被裁掉" % rd)
			fails += 1
		if rd >= 1000 and not island_vis:
			print("[rd] ✗ 1000 m 时 Island 应该可见")
			fails += 1
		if not shop_vis:
			print("[rd] ✗ %d m 时 20 m 外的商店不该被裁" % rd)
			fails += 1
		if last_visible >= 0 and vis < last_visible:
			print("[rd] ✗ 可见几何数随渲染距离变大反而减少了（%d → %d）" % [last_visible, vis])
			fails += 1
		last_visible = vis

	# 「伪无极 + 分段」：滑到 437 应该按 400 生效，显示也是 400 m
	GameSettings.set_value("render_distance", 437.0)
	print("[rd] 滑块 437 m → 生效 %d m，显示「%s」，far %.0f"
		% [int(GameSettings.render_distance()),
			GameSettings.value_text("render_distance", GameSettings.value("render_distance")),
			cam.far])
	if int(GameSettings.render_distance()) != 400:
		print("[rd] ✗ 437 应该按 400 m 生效")
		fails += 1
	if int(cam.far) != 400:
		print("[rd] ✗ 437 时 far 应该跟着变成 400")
		fails += 1

	GameSettings.set_value("render_distance", old)
	print("[rd] 恢复原值 %.0f m（生效 %d m）" % [old, int(GameSettings.render_distance())])
	print("[rd] %s（失败 %d 项）" % ["全部通过" if fails == 0 else "有失败", fails])
	quit(0 if fails == 0 else 1)
