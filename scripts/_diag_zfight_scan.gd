extends SceneTree
## 找第二场景里「两块几何几乎完全重叠」的网格对 —— z-fighting（重叠面闪烁）的来源。
##
## 用户 2026-11-08：「第二场景的房子很多重叠面闪烁」。
##
## 判据（不需要渲染，纯 AABB）：
##   ① 世界包围盒**中心几乎重合**、**尺寸几乎相同** → 两份同一块几何被摆了两遍
##      （最典型的闪烁来源：两个面共面，深度值打架）。
##   ② 其中一块在某个轴上**极薄**（板/面片）且另一块与之共面 → 面贴在面上。
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_diag_zfight_scan.gd

const LEVEL := "res://scenes/next_level.tscn"
## 中心距离小于这个（米）就算「位置几乎一样」
const CENTER_TOL := 0.06
## 三个轴尺寸差都小于这个（米）就算「大小几乎一样」
const SIZE_TOL := 0.06
## 一个轴小于这个（米）就算「薄板」
const THIN := 0.05


func _initialize() -> void:
	_run()


## 一块网格在**世界空间**的包围盒。
##
## ⚠️ 蒙皮网格（`mi.skin != null`）的 `get_aabb()` 是**绑定空间**的，乘
##    `global_transform` 出来是错的（`boss.gd` 的 `_mesh_box()` 上面记着这个大坑：
##    霸王龙的网格跨度是骨架的 ~298 倍）。本探针只用来查**静态建筑**，
##    所以这里遇到蒙皮网格直接跳过，不给出误导性的数字。
func _world_aabb(mi: MeshInstance3D) -> AABB:
	if mi.skin != null:
		return AABB()
	return mi.global_transform * mi.get_aabb()


func _run() -> void:
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[Zfight] 加载不了 %s" % LEVEL)
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	for i in 6:
		await process_frame
	# 有些几何是延迟建的
	for i in 40:
		await process_frame

	var items: Array = []      # {node, path, aabb, thin_axis}
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree():
				var surfaces := 0
				for s in mi.mesh.get_surface_count():
					surfaces += 1
				var aabb := _world_aabb(mi)
				if aabb.size.length() > 0.001:
					var thin := -1
					for a in 3:
						if aabb.size[a] < THIN:
							thin = a
					items.append({
						"node": mi, "path": str(level.get_path_to(mi)),
						"aabb": aabb, "thin": thin, "surfaces": surfaces,
					})
		for c in n.get_children():
			stack.append(c)

	print("")
	print("========== 第二场景可见网格：%d 块 ==========" % items.size())

	var dup := 0
	var strong := 0
	var weak := 0
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Dictionary = items[i]
			var b: Dictionary = items[j]
			var aa: AABB = a["aabb"]
			var bb: AABB = b["aabb"]
			var dc := aa.get_center().distance_to(bb.get_center())
			var ds: Vector3 = (aa.size - bb.size).abs()
			if dc <= CENTER_TOL and ds.x <= SIZE_TOL and ds.y <= SIZE_TOL and ds.z <= SIZE_TOL:
				dup += 1
				if dup <= 25:
					print("  [重合] %s" % a["path"])
					print("         %s   中心差 %.3f m  尺寸 %s vs %s" % [
						b["path"], dc, str(aa.size.snappedf(0.01)), str(bb.size.snappedf(0.01))])
				continue
			# ── 面贴面检测（不限厚薄）──
			# ⚠️ 第一版只查「薄片」（< 5 cm），**漏掉厚墙与厚墙之间的贴面** ——
			#    两堵 0.3 m 厚的墙，只要某一侧面重合 1 mm 一样会打架。
			#    所以这里对每个轴各看一次：两块的**同侧**面是否几乎重合
			#    （同侧 = min-min 或 max-max；min 对 max 是正常的堆叠接触，不算）。
			var ta := -1
			var td := 999.0
			for ax in 3:
				var d := minf(
					absf(aa.position[ax] - bb.position[ax]),
					absf((aa.position[ax] + aa.size[ax]) - (bb.position[ax] + bb.size[ax])))
				if d < td:
					td = d
					ta = ax
			if ta < 0 or td > 0.005:
				continue
			var ax0 := -1
			var ax1 := -1
			for ax in 3:
				if ax == ta:
					continue
				if ax0 < 0:
					ax0 = ax
				else:
					ax1 = ax
			var ov0 := minf(aa.position[ax0] + aa.size[ax0], bb.position[ax0] + bb.size[ax0]) \
				- maxf(aa.position[ax0], bb.position[ax0])
			var ov1 := minf(aa.position[ax1] + aa.size[ax1], bb.position[ax1] + bb.size[ax1]) \
				- maxf(aa.position[ax1], bb.position[ax1])
			if ov0 <= 0.0 or ov1 <= 0.0:
				continue
			var area_a := maxf(aa.size[ax0] * aa.size[ax1], 1e-9)
			var area_b := maxf(bb.size[ax0] * bb.size[ax1], 1e-9)
			var cover := (ov0 * ov1) / minf(area_a, area_b)
			if cover < 0.5:
				continue
			var ratio := sqrt(minf(area_a, area_b) / maxf(area_a, area_b))
			if ratio >= 0.5 and td <= 0.002:
				strong += 1
				if strong <= 20:
					print("  [强共面] %s" % a["path"])
					print("           vs %s   轴 %s 面差 %.4f m  大小比 %.2f  遮盖 %.0f%%  尺寸 %s / %s" % [
						b["path"], "XYZ"[ta], td, ratio, cover * 100.0,
						str(aa.size.snappedf(0.01)), str(bb.size.snappedf(0.01))])
			else:
				weak += 1
				if weak <= 15:
					print("  [弱贴面] %s  ↔  %s   轴 %s 面差 %.4f m 大小比 %.2f 遮盖 %.0f%%" % [
						a["path"], b["path"], "XYZ"[ta], td, ratio, cover * 100.0])

	print("")
	print("========== 结果 ==========")
	print("  完全重合的网格对（尺寸+位置都一样）：%d" % dup)
	print("  强共面薄板对（两块同轴薄、几乎等大、面贴面）：%d" % strong)
	print("  弱贴面对（一薄一厚 / 大小差很多）：%d" % weak)
	quit(0)
