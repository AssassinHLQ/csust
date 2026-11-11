extends SceneTree
## 诊断：霸王龙 73 根骨在**身体空间**的位置，以及每根被分到哪个切片。
##
## 目的：查「碰撞盒比身体胖一圈」到底是哪几根骨造成的 ——
## 怀疑混进了**光环 / 手里那把枪**这类挂件的骨（用户原图里光环处就有一根绿线）。
##
##   bash _tools/run_probe.sh res://scripts/_probe_trex_bones.gd -- --no-capture --splat=off

const LEVEL := "res://scenes/next_level.tscn"
const BOSS := "TrexBossA"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for i in 4:
		await process_frame
	var boss := level.get_node_or_null(BOSS)
	if boss == null:
		print("!! 找不到 %s" % BOSS)
		quit(1)
		return
	if not bool(boss.get("_booted")):
		boss.call("_boot")
	for i in 30:
		await process_frame

	var skel: Skeleton3D = boss.call("_best_skeleton", boss.get("model"))
	if skel == null:
		print("!! 没有骨架")
		quit(1)
		return
	var to_body: Transform3D = (boss as Node3D).global_transform.affine_inverse()
	var xf := to_body * skel.global_transform

	print("========== 骨骼 %d 根（身体空间）==========" % skel.get_bone_count())
	var pts: Array[Vector3] = []
	for i in skel.get_bone_count():
		var p: Vector3 = xf * skel.get_bone_global_pose(i).origin
		pts.append(p)
		print("  #%2d %-24s pos ( %7.2f, %6.2f, %7.2f )  父 %s" % [
			i, skel.get_bone_name(i), p.x, p.y, p.z,
			skel.get_bone_name(skel.get_bone_parent(i)) if skel.get_bone_parent(i) >= 0 else "-"])

	var overall := _aabb(pts)
	print("")
	print("整体包围盒：pos %s  size %s" % [
		str(overall.position.snappedf(0.01)), str(overall.size.snappedf(0.01))])

	# 按「到躯干中心线的距离」找离群骨：以中位数为准
	var xs := _sorted_axis(pts, 0)
	var med_x := xs[xs.size() / 2]
	var ys := _sorted_axis(pts, 1)
	var med_y := ys[ys.size() / 2]
	var zs := _sorted_axis(pts, 2)
	var med_z := zs[zs.size() / 2]
	print("中位骨位置：( %.2f, %.2f, %.2f )" % [med_x, med_y, med_z])
	print("")
	print("========== 离中位骨最远的 15 根 ==========")
	var idx: Array[int] = []
	for i in pts.size():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		return pts[a].distance_squared_to(Vector3(med_x, med_y, med_z)) \
			> pts[b].distance_squared_to(Vector3(med_x, med_y, med_z)))
	for k in mini(15, idx.size()):
		var i := idx[k]
		var p := pts[i]
		print("  #%2d %-24s pos ( %7.2f, %6.2f, %7.2f ) 距中位 %6.2f m" % [
			i, skel.get_bone_name(i), p.x, p.y, p.z,
			p.distance_to(Vector3(med_x, med_y, med_z))])

	print("")
	print("========== 现有切片（哪几根被分到哪片）==========")
	var slices: Array = boss.get("_slices")
	for si in slices.size():
		var s: Dictionary = slices[si]
		var ids: PackedInt32Array = s["bones"]
		var names := PackedStringArray()
		for bi in ids:
			names.append(skel.get_bone_name(bi))
		var cs: CollisionShape3D = s["cs"]
		var last: AABB = s["last"]
		print("  片 %d：%d 根 ｜ 盒 size %s ｜ %s" % [
			si, ids.size(), str(last.size.snappedf(0.01)),
			", ".join(names)])
	print("")
	quit(0)


func _sorted_axis(pts: Array[Vector3], ax: int) -> Array[float]:
	var out: Array[float] = []
	for p in pts:
		out.append(p[ax])
	out.sort()
	return out


func _aabb(pts: Array[Vector3]) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)
