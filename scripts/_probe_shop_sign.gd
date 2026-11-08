extends SceneTree
## 诊断：柴关电脑城招牌**浮空**。
##
## 用户 2026-11-08 截图：招牌整块悬在半空，既没贴墙也没贴屋顶。
##
## 量三件事：
##   ① 新屋壳（GLB）真实包围盒 —— 招牌该贴的那面墙在哪；
##   ② `SignBoard` / `SignText` 的世界坐标与实际包围盒；
##   ③ 换算成「招牌底边 vs 墙面」的差距，直接看出浮了多少米。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_shop_sign.gd

func _initialize() -> void:
	_run.call_deferred()


func _aabb_of(n: Node) -> AABB:
	## 累加子树里所有网格的世界包围盒。
	##
	## ⚠️ 不按 `is_visible_in_tree()` 过滤：headless 下窗口没有焦点，
	##    有节点会因此被判成不可见，滤掉之后量出来的盒子会偏矮
	##    （第一版就漏了 0.17 m，导致误判成"代码记的 shop_height 偏高"）。
	##    这里只按"有没有 mesh"筛，跟渲染无关。
	var out := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for ch in cur.get_children():
			stack.push_back(ch)
		var mi := cur as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _run() -> void:
	print("========== 柴关电脑城招牌诊断 ==========")
	# ⚠️ 只加载 `shop_baked.tscn`，不加载整个 `game.tscn`。
	#    加载 game.tscn 会把 splat / 波次 Boss / 音频全拖进来，headless 下
	#    退出清理时偶发 Segmentation fault（exit 139）—— 断言其实已经全过，
	#    但退出码是脏的，不方便当回归门用。单独加载商店场景又快又干净。
	var shop = (load("res://scenes/shop_baked.tscn") as PackedScene).instantiate()
	root.add_child(shop)
	for _i in 10:
		await process_frame
	# 商店场景是烘焙产物，位置在 game.tscn 里才被摆到 (27.3, 0, -11.37)；
	# 单独加载时在原点，量包围盒不受影响（只要两者一致）。
	print("  shop 节点：%s  global=%s" % [shop.name, str(shop.global_position.snappedf(0.01))])
	print("  shop_height = %.2f   shop_depth = %.2f   shell_depth = %.2f" % [
		float(shop.get("shop_height")), float(shop.get("shop_depth")),
		float(shop.get("shell_depth"))])

	# ── ① 新屋壳真实尺寸 ──
	print("\n---------- 1. 屋壳（GLB）真实包围盒 ----------")
	var shell := shop.get_node_or_null("Shell") as Node3D
	if shell != null:
		var sb := _aabb_of(shell)
		print("  世界包围盒：pos=%s size=%s" % [
			str(sb.position.snappedf(0.01)), str(sb.size.snappedf(0.01))])
		print("  → 墙面 z_max = %.2f（朝 +Z 那面）  屋顶 y_max = %.2f" % [
			sb.position.z + sb.size.z, sb.position.y + sb.size.y])
		print("  → 本地相对 shop：pos=%s size=%s" % [
			str((sb.position - shop.global_position).snappedf(0.01)),
			str(sb.size.snappedf(0.01))])
	else:
		print("  （没有 Shell 节点 → 用的是程序化 `_build_shell()`）")

	# ── ② 招牌 ──
	print("\n---------- 2. 招牌位置 ----------")
	var board := shop.find_child("SignBoard", true, false) as MeshInstance3D
	var text := shop.find_child("SignText", true, false) as Label3D
	if board == null:
		print("  ✗ 没找到 SignBoard")
	else:
		var bb := _aabb_of(board)
		print("  SignBoard 世界 pos=%s" % str(board.global_position.snappedf(0.01)))
		print("  SignBoard 包围盒 pos=%s size=%s" % [
			str(bb.position.snappedf(0.01)), str(bb.size.snappedf(0.01))])
		print("  → 板底 y = %.2f   板面 z = %.2f" % [
			bb.position.y, bb.position.z + bb.size.z])
	if text != null:
		print("  SignText 世界 pos=%s" % str(text.global_position.snappedf(0.01)))

	# ── ③ 差距 ──
	print("\n---------- 3. 浮空量 ----------")
	if shell != null and board != null:
		var sb2 := _aabb_of(shell)
		var bb2 := _aabb_of(board)
		var wall_top := sb2.position.y + sb2.size.y
		var wall_front := sb2.position.z + sb2.size.z
		var gap_y := bb2.position.y - wall_top
		var gap_z := (bb2.position.z + bb2.size.z) - wall_front
		print("  墙面顶 y = %.2f" % wall_top)
		print("  招牌底 y = %.2f" % bb2.position.y)
		print("  → 垂直方向差了 **%.2f m**（>0 = 浮在屋顶上方，<0 = 陷进墙里）" % gap_y)
		print("  墙面   z = %.2f" % wall_front)
		print("  招牌面 z = %.2f" % (bb2.position.z + bb2.size.z))
		print("  → 水平方向差了 **%.2f m**（>0 = 凸出墙面，<0 = 缩进墙里）" % gap_z)

		# ── 断言（2026-11-08 用户：「招牌怎么浮空了，放墙上对齐」）──
		print("\n---------- 4. 断言 ----------")
		var ok := true
		if absf(gap_y) <= 0.02:
			print("  ✓ 招牌底边贴着屋顶：差 %.3f m（容差 0.02）" % gap_y)
		else:
			print("  ✗ 招牌浮空/陷墙 %.3f m —— 应由 0 变成 ±（用户要的是贴墙顶）" % gap_y)
			ok = false
		# 水平：凸出墙面一点是**对的**（板要挂在外墙上，不能嵌进去）
		if gap_z > 0.02 and gap_z < 0.30:
			print("  ✓ 招牌凸出墙面 %.3f m（合理安装厚度 0.02~0.30）" % gap_z)
		else:
			print("  ✗ 招牌水平位置不对：%.3f m（应在 0.02~0.30）" % gap_z)
			ok = false
		# 招牌不能被塞进屋顶以下（看不见）
		if bb2.position.y >= wall_top - 0.02:
			print("  ✓ 招牌没有陷到屋顶以下（板底 %.2f ≥ 屋顶 %.2f）" % [
				bb2.position.y, wall_top])
		else:
			print("  ✗ 招牌陷进墙里了（板底 %.2f < 屋顶 %.2f）" % [bb2.position.y, wall_top])
			ok = false
		quit(0 if ok else 1)
		return

	quit(0)
