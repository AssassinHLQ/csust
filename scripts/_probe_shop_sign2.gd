extends SceneTree
## 诊断：柴关电脑城招牌**水平**没对齐（浮在屋顶上方、侧着立）。
##
## 用户 2026-11-08 第二张图：招牌竖在屋顶上、明显转了向、跟建筑不在一条线上。
##
## ⚠️ 上一版探针只比了「招牌面 z vs Shell 包围盒 z_max」。那个做法有个盲点：
##    包围盒的 z_max 是**整个外壳里最靠前的那个顶点**，不一定是招牌该贴的那面墙
##    （可能是门口台阶、雨棚、某个凸出构件）。所以这次改成：
##      ① 把外壳的网格**逐个**列出世界 Z 范围，看正面墙到底是哪个 z；
##      ② 按高度切片：只看 y ∈ [招牌底, 招牌底+0.72] 这一带里有哪些网格，
##         以及它们的 z 范围 —— 那才是"招牌这一层"的墙；
##      ③ 同时检查招牌的**旋转**（是不是被转歪了）。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_shop_sign2.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("========== 招牌水平对齐诊断 ==========")
	var shop = (load("res://scenes/shop_baked.tscn") as PackedScene).instantiate()
	root.add_child(shop)
	for _i in 10:
		await process_frame

	var shell := shop.get_node_or_null("Shell") as Node3D
	var board := shop.find_child("SignBoard", true, false) as MeshInstance3D
	if shell == null or board == null:
		print("  ✗ 缺 Shell 或 SignBoard")
		quit(1)
		return

	var bb: AABB = board.global_transform * board.get_aabb()
	print("招牌板：世界 pos=%s  包围盒 z=[%.3f, %.3f]  y=[%.3f, %.3f]" % [
		str(board.global_position.snappedf(0.001)),
		bb.position.z, bb.position.z + bb.size.z,
		bb.position.y, bb.position.y + bb.size.y])
	print("招牌板 basis.x=%s（应为 (1,0,0)，否则被转歪了）" % str(board.global_transform.basis.x.snappedf(0.001)))
	print("招牌板 basis.z=%s（板面法线，应为 (0,0,1) 或 (0,0,-1)）" % str(board.global_transform.basis.z.snappedf(0.001)))

	# ── 列出外壳所有网格的世界 Z 范围 ──
	print("\n---------- 1. 外壳所有网格的世界 Z 范围 ----------")
	var rows: Array = []
	var stack: Array[Node] = [shell]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for ch in cur.get_children():
			stack.push_back(ch)
		var mi := cur as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		rows.append({
			"name": String(mi.name),
			"zmin": b.position.z, "zmax": b.position.z + b.size.z,
			"ymin": b.position.y, "ymax": b.position.y + b.size.y,
			"xmin": b.position.x, "xmax": b.position.x + b.size.x,
		})
	# 按 zmax 从大到小排（最靠前的在前）
	rows.sort_custom(func(a, b): return a["zmax"] > b["zmax"])
	for r in rows:
		print("  %-28s z=[%7.3f, %7.3f]  y=[%6.3f, %6.3f]  x=[%7.3f, %7.3f]" % [
			r["name"], r["zmin"], r["zmax"], r["ymin"], r["ymax"], r["xmin"], r["xmax"]])

	# ── 招牌这一层（y 带）里，最靠前的墙是哪个 z ──
	print("\n---------- 2. 招牌所在高度带（y = 招牌底 ± 0.72）的墙 ----------")
	var y0: float = bb.position.y
	var y1: float = bb.position.y + bb.size.y
	var band: Array = []
	for r in rows:
		# 与该高度带有重叠
		if r["ymax"] > y0 + 0.01 and r["ymin"] < y1 - 0.01:
			band.append(r)
	if band.is_empty():
		print("  （这一带没有任何网格 → 招牌悬在建筑上方，前面本来就是空的）")
	else:
		band.sort_custom(func(a, b): return a["zmax"] > b["zmax"])
		for r in band:
			print("  %-28s z=[%7.3f, %7.3f]  y=[%6.3f, %6.3f]" % [
				r["name"], r["zmin"], r["zmax"], r["ymin"], r["ymax"]])
		print("  → 这一带最靠前的墙 z = %.3f（招牌面当前 z = %.3f，差 %.3f m）" % [
			band[0]["zmax"], bb.position.z + bb.size.z,
			(bb.position.z + bb.size.z) - band[0]["zmax"]])

	# ── 整体：外壳顶到底多高，招牌在不在顶上 ──
	print("\n---------- 3. 建筑最高点 vs 招牌 ----------")
	var top := -INF
	var top_name := ""
	for r in rows:
		if r["ymax"] > top:
			top = r["ymax"]
			top_name = r["name"]
	print("  建筑最高点 y = %.3f（%s）" % [top, top_name])
	print("  招牌底   y = %.3f（差 %.3f m）" % [bb.position.y, bb.position.y - top])

	# ── 4. 断言：招牌必须**压在墙面上**，不是站在屋顶棱上 ──
	#
	# 这是 2026-11-08 第二轮反馈（「啊还是浮空」「是水平没对齐上」）的回归门。
	# 第一版修法把招牌底对齐到建筑最高点 5.817 —— 那个高度上已经没有墙了，
	# 所以招牌等于站在屋顶上。判据因此不能只看 y，必须同时满足：
	#   ① 招牌 y 范围**完全落在**某一面墙的 y 范围内（墙面托得住它）；
	#   ② 招牌背面与那面墙的缝 ≤ 0.05 m（贴着，不是飘在前面）；
	#   ③ 招牌板顶不高于墙顶（不能越出屋檐）。
	print("\n---------- 4. 断言：压在正立面上 ----------")
	var ok := true
	var board_y0: float = bb.position.y
	var board_y1: float = bb.position.y + bb.size.y
	var board_back: float = bb.position.z          # 靠墙那侧
	var wall: Dictionary = {}
	for r in rows:
		# 找那面"在招牌高度带上有覆盖、且最靠前"的墙
		if r["ymin"] <= board_y0 + 0.01 and r["ymax"] >= board_y1 - 0.01:
			if wall.is_empty() or r["zmax"] > wall["zmax"]:
				wall = r
	if wall.is_empty():
		print("  ✗ 招牌 y=[%.2f, %.2f] 这一带**根本没有墙**——它悬在建筑外面/上面" % [
			board_y0, board_y1])
		ok = false
	else:
		print("  找到托住招牌的墙：%s  z_max=%.3f  y=[%.3f, %.3f]" % [
			wall["name"], wall["zmax"], wall["ymin"], wall["ymax"]])
		if board_y1 <= wall["ymax"] + 0.01:
			print("  ✓ 招牌整块在墙面高度内（板顶 %.3f ≤ 墙顶 %.3f）" % [board_y1, wall["ymax"]])
		else:
			print("  ✗ 招牌越出墙顶（板顶 %.3f > 墙顶 %.3f）→ 会浮在屋顶上" % [
				board_y1, wall["ymax"]])
			ok = false
		var seam: float = board_back - wall["zmax"]
		if absf(seam) <= 0.05:
			print("  ✓ 招牌背面贴着墙：缝 %.3f m（容差 0.05）" % seam)
		elif seam > 0.05:
			print("  ✗ 招牌离墙 %.3f m —— 飘在前面" % seam)
			ok = false
		else:
			print("  ✗ 招牌嵌进墙里 %.3f m" % -seam)
			ok = false

	if ok:
		print("\n  ★ 全部通过：招牌压在正立面上")
	else:
		print("\n  ★ 有问题，见上面 ✗")

	quit(0 if ok else 1)
