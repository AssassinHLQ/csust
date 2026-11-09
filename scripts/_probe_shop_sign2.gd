extends SceneTree
## 回归门：柴关电脑城招牌必须**压在实墙上**。
##
## 2026-11-08 用户连报三次「浮空 / 还是有缝」，根因是招牌对着**门口开口**而不是实墙。
## 之前几版探针都只比"外壳整体包围盒"，那面墙横跨整个立面，看不出开口，
## 所以一直误报通过。
##
## 这里的判据：
##   ① 招牌 x 区间必须完全落在**前墙碰撞体** `ShellFrontWallShape` 的 x 区间内
##      —— 碰撞体才是"真的挡在这里的墙"，视觉玻璃区只是半透明，背后是空的；
##   ② 招牌背面 z 与前墙面 z 的缝 ≤ 0.05 m；
##   ③ 招牌 y 不越出墙顶。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_shop_sign2.gd

func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> int:
	print(("  ✓ " if ok else "  ✗ ") + msg)
	return 0 if ok else 1


func _xform_aabb(n: Node3D, size: Vector3) -> AABB:
	var b := AABB(-size * 0.5, size)
	return n.global_transform * b


func _run() -> void:
	print("========== 招牌贴合回归门 ==========")
	var shop = (load("res://scenes/shop_baked.tscn") as PackedScene).instantiate()
	root.add_child(shop)
	for _i in 10:
		await process_frame

	var fail := 0
	var board := shop.find_child("SignBoard", true, false) as MeshInstance3D
	var front_col := shop.find_child("ShellFrontWallShape", true, false) as CollisionShape3D
	if board == null or front_col == null:
		print("  ✗ 缺 SignBoard 或 ShellFrontWallShape")
		quit(1)
		return

	var bb: AABB = board.global_transform * board.get_aabb()
	var shape := front_col.shape as BoxShape3D
	var wb: AABB = _xform_aabb(front_col, shape.size)

	print("招牌 x=[%.2f, %.2f]  y=[%.2f, %.2f]  z=[%.2f, %.2f]" % [
		bb.position.x, bb.position.x + bb.size.x,
		bb.position.y, bb.position.y + bb.size.y,
		bb.position.z, bb.position.z + bb.size.z])
	print("前墙 x=[%.2f, %.2f]  y=[%.2f, %.2f]  z=[%.2f, %.2f]" % [
		wb.position.x, wb.position.x + wb.size.x,
		wb.position.y, wb.position.y + wb.size.y,
		wb.position.z, wb.position.z + wb.size.z])

	print("\n---------- 断言 ----------")
	# ① x 完全在实墙内
	var x_in := bb.position.x >= wb.position.x - 0.01 \
		and bb.position.x + bb.size.x <= wb.position.x + wb.size.x + 0.01
	fail += _check(x_in, "招牌横向完全落在实墙区间内（招牌 x=[%.2f, %.2f] ⊂ 墙 x=[%.2f, %.2f]）" % [
		bb.position.x, bb.position.x + bb.size.x,
		wb.position.x, wb.position.x + wb.size.x])

	# ② 背面贴墙
	var seam: float = bb.position.z - (wb.position.z + wb.size.z)
	fail += _check(absf(seam) <= 0.05, "招牌背面贴着墙面：缝 %.3f m（容差 0.05）" % seam)

	# ③ 不越出墙顶
	var y_in := bb.position.y + bb.size.y <= wb.position.y + wb.size.y + 0.02
	fail += _check(y_in, "招牌板顶不越出墙顶（板顶 %.2f ≤ 墙顶 %.2f）" % [
		bb.position.y + bb.size.y, wb.position.y + wb.size.y])

	if fail == 0:
		print("\n  ★ 全部通过：招牌压在实墙上")
	else:
		print("\n  ★ %d 项失败 —— 招牌会浮空/悬空" % fail)
	quit(0 if fail == 0 else 1)
