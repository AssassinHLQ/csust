extends SceneTree
## 只读探针：这个世界到底有多大 —— 决定「渲染距离」该给多少米才有意义。
##   godot --headless --path . --script res://scripts/_probe_world_extent.gd

const GAME := "res://scenes/game.tscn"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var ps := load(GAME) as PackedScene
	if ps == null:
		print("[ext] 读不到 ", GAME)
		quit(1)
		return
	var game := ps.instantiate()
	root.add_child(game)
	var room: Node = game.find_child("Room609", true, false)
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		if room != null and room.has_method("is_ready") and bool(room.call("is_ready")):
			break
		await process_frame

	var player: Node3D = game.find_child("Player", true, false)
	var eye := Vector3.ZERO
	if player != null:
		var cam := player.find_child("Camera3D", true, false) as Camera3D
		eye = (cam.global_position if cam != null else player.global_position)
	print("[ext] 玩家眼睛 %s" % str(eye.snappedf(0.01)))

	var world := AABB()
	var first := true
	var rows: Array = []
	for n in game.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		# 泼溅/体积罩子那种超大 AABB 单独标出来，别污染「世界有多大」的结论
		var r := a.size.length() * 0.5
		var d := a.get_center().distance_to(eye)
		rows.append({"name": String(mi.get_path()).replace("/root/", ""), "d": d, "r": r})
		if first:
			world = a
			first = false
		else:
			world = world.merge(a)
	print("[ext] 全场景网格 AABB：中心 %s  尺寸 %s m（对角 %.1f m）"
		% [str(world.get_center().snappedf(0.1)), str(world.size.snappedf(0.1)),
			world.size.length()])
	rows.sort_custom(func(a, b) -> bool: return a["d"] > b["d"])
	print("[ext] 离眼睛最远的 10 个网格（d = AABB 中心距离，r = 半对角）")
	for i in mini(10, rows.size()):
		print("[ext]   %7.1f m  r=%6.1f m  %s" % [rows[i]["d"], rows[i]["r"], rows[i]["name"]])
	var maxd := 0.0
	var maxi := 0
	for r2 in rows:
		if r2["d"] > maxd:
			maxd = r2["d"]
			maxi = rows.find(r2)
	print("[ext] 网格 %d 个；最远到眼睛 %.1f m（含半对角 %.1f m）"
		% [rows.size(), maxd, maxd + rows[maxi]["r"]])
	# 每 100 m 一档：这一档里有多少网格、都是什么（按名字前两段归组）
	for band in 10:
		var lo := float(band) * 100.0
		var hi := lo + 100.0
		var cnt := 0
		var groups := {}
		for r3 in rows:
			if r3["d"] >= lo and r3["d"] < hi:
				cnt += 1
				var seg: PackedStringArray = String(r3["name"]).split("/")
				var g := "/".join(seg.slice(0, mini(3, seg.size())))
				groups[g] = int(groups.get(g, 0)) + 1
		if cnt > 0:
			print("[ext]   %4d–%4d m : %3d 个网格  %s" % [int(lo), int(hi), cnt, str(groups)])
	quit(0)
