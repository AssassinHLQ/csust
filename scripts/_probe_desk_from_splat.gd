extends SceneTree
## 探针：从画室609 的**泼溅点云**里直接找出桌子（不靠肉眼在截图上量）。
##   godot --path . --headless --script res://scripts/_probe_desk_from_splat.gd -- --splat=off
##
## 思路：桌子最明显的特征是**一片水平的大面**（桌面），高度约 0.72~0.85 m，
## 而且那块面**不在墙边**。做法：
##   ① 拿 splat_scene 里解码好的点（`SplatScene` 已经把点存起来了，看它的字段）；
##   ② 按 y 分层（每 5 cm 一层），统计每层的点数和它们的水平包围盒；
##   ③ 桌面对应的那一层会有一个「面积中等、密度高、四周是空的」团块。
##
## 如果拿不到原始点，就退而用**物理射线扫地面**：桌面上方打射线会命中桌面网格
## —— 但画室是泼溅、没有碰撞网格，所以这条路本来就不通。
## 因此这个探针只尝试「从点云里找」，拿不到就明确说拿不到。
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	paused = false
	var room := game.get_node_or_null("Room609") as SplatScene
	if room == null:
		print("[错误] 没有 Room609")
		quit(1)
		return
	print("SplatScene 就位：%s" % room.get_class())

	# 把 SplatScene 里所有可能藏着点的属性都看一眼
	print("\n—— SplatScene 的成员（找点数据）——")
	for p in room.get_property_list():
		var nm: String = p["name"]
		if nm.begins_with("_") or nm in ["script", "sog_path", "display_name", "venue",
				"box_door_side"]:
			var v: Variant = room.get(nm)
			var ts := type_string(typeof(v))
			if ts in ["Object", "Nil"]:
				continue
			print("  %-22s %-10s %s" % [nm, ts, str(v).substr(0, 70)])

	# 常见字段名直接试
	print("\n—— 猜字段 ——")
	for cand in ["_points", "points", "splat_points", "_cloud", "cloud", "positions",
			"_positions", "pos_array", "_pos", "pcd"]:
		if room.get(cand) != null:
			var val: Variant = room.get(cand)
			print("  命中 `%s`：%s" % [cand, type_string(typeof(val))])

	# 子节点里找 MultiMesh / PointMesh / MeshInstance
	print("\n—— Room609 下的渲染节点 ——")
	for c in room.find_children("*", "", true, false):
		if c is MeshInstance3D or c is MultiMeshInstance3D or c is GeometryInstance3D:
			print("  %-28s %s" % [c.name, c.get_class()])
	quit(0)
