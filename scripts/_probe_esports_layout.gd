extends SceneTree
## 量电竞房的真实内部布局：外壳盒、工位排、椅子、窗帘都在哪。
##
##   godot --path . --headless --script res://scripts/_probe_esports_layout.gd
##
## 为什么要有这个：本喵第一次加灯时按「外壳 x ±5.20、z ±8.42、门口在 -Z」
## 猜，结果灯全装到墙外面了（图里墙上两个亮斑 = 灯穿墙照的）。
## 这次直接量。

const SCENE := "res://scenes/esports_room.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var room := (load(SCENE) as PackedScene).instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	await process_frame

	print("[layout] 根节点 = %s（本地坐标）" % str(room.position))

	# 外壳：找 AABB 最大的那个网格
	var biggest := ""
	var best_vol := -1.0
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for n in room.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		var vol := b.size.x * b.size.y * b.size.z
		if vol > best_vol:
			best_vol = vol
			biggest = mi.name
			lo = b.position
			hi = b.position + b.size
	print("[layout] 最大的网格 = %s" % biggest)
	print("[layout]   AABB 本地 x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f" % [
		lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])
	print("[layout]   尺寸 %.2f × %.2f × %.2f" % [hi.x - lo.x, hi.y - lo.y, hi.z - lo.z])

	# 每个网格的 AABB（按 z 排），看看工位/椅子/窗帘在哪
	print("[layout] ── 全部网格（按 z 排）──")
	var rows: Array = []
	for n in room.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		rows.append({"n": mi.name, "z": b.position.z, "x0": b.position.x, "x1": b.position.x + b.size.x,
			"y0": b.position.y, "y1": b.position.y + b.size.y})
	rows.sort_custom(func(a, b): return a["z"] < b["z"])
	for r in rows:
		print("[layout]   %-26s x %7.2f~%7.2f  y %6.2f~%6.2f  z %7.2f" % [
			r["n"], r["x0"], r["x1"], r["y0"], r["y1"], r["z"]])

	print("[layout] 完成")
	quit(0)
