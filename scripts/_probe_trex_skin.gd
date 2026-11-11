extends SceneTree
## 诊断：霸王龙的蒙皮网格能不能按「每根骨的顶点」量出真实粗细。
##
## 背景：现在的碰撞盒是拿**骨骼点**（一条稀疏中心线）算 AABB + 固定余量，
## 所以躯干那格小、腿那格粗、尾巴尖还鼓出去 —— 用户 2026-11-11：
## 「这跟模型对不上 脚怎么这么粗? 尾巴这么大, 身体却这么小」。
##
## 想改成「每根骨 → 它主导的那些顶点 → 骨头空间里的 AABB」，先确认：
##   ① 网格有没有 `skin` / `ARRAY_BONES` / `ARRAY_WEIGHTS`
##   ② 每根骨分到多少顶点（太少的就是没用的挂件骨）
##   ③ 每根骨在骨头空间里的盒子有多大（= 真实粗细）
##
##   bash _tools/run_probe.sh res://scripts/_probe_trex_skin.gd -- --no-capture --splat=off

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
	var n := skel.get_bone_count()

	print("========== 网格明细 ==========")
	var total_v := 0
	var skinned := 0
	var stack: Array[Node] = [boss.get("model")]
	var meshes: Array[MeshInstance3D] = []
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			meshes.append(c as MeshInstance3D)
		for ch in c.get_children():
			stack.append(ch)
	for mi in meshes:
		if mi.mesh == null:
			continue
		var surf := mi.mesh.get_surface_count()
		var has_skin := mi.skin != null
		var bones_ok := false
		var vcount := 0
		for s in surf:
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			vcount += v.size()
			if arr[Mesh.ARRAY_BONES] != null and arr[Mesh.ARRAY_WEIGHTS] != null:
				bones_ok = true
		total_v += vcount
		if has_skin and bones_ok:
			skinned += 1
		print("  %-34s 面 %d ｜ 顶点 %5d ｜ skin %s ｜ 骨骼数组 %s ｜ 可见 %s" % [
			mi.name, surf, vcount, str(has_skin), str(bones_ok), str(mi.is_visible_in_tree())])
	print("  合计：%d 块网格，其中 %d 块可用（skin + 骨骼数组），顶点 %d" % [
		meshes.size(), skinned, total_v])

	# 每根骨主导的顶点 → 骨头空间 AABB
	print("")
	print("========== 每根骨的真实粗细（骨头空间 AABB）==========")
	var info := _per_bone_boxes(skel, boss.get("model"))
	var total_assigned := 0
	for b in n:
		var d: Dictionary = info.get(b, {})
		if d.is_empty():
			print("  %-22s 0 顶点（没有网格跟着它）" % skel.get_bone_name(b))
			continue
		var bb: AABB = d["box"]
		total_assigned += int(d["count"])
		print("  %-22s %5d 顶点 ｜ 盒 %-24s ｜ 体积 %7.2f" % [
			skel.get_bone_name(b), int(d["count"]),
			str(bb.size.snappedf(0.01)), bb.size.x * bb.size.y * bb.size.z])
	print("  被分配的顶点合计 %d" % total_assigned)
	print("")
	quit(0)


## 每个顶点归给「权重最大的那根骨」，再在**骨头空间**里求 AABB。
## 返回 { 骨索引: { "count": int, "box": AABB } }
func _per_bone_boxes(skel: Skeleton3D, model: Node) -> Dictionary:
	var out := {}
	var xf := (model as Node3D).global_transform   # 模型空间 = 骨架空间（骨架在模型里是单位阵）
	var bone_xf: Array[Transform3D] = []
	for b in skel.get_bone_count():
		bone_xf.append(xf * skel.get_bone_global_pose(b))
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh != null and mi.skin != null and mi.is_visible_in_tree():
				_accumulate(mi, bone_xf, out)
		for ch in c.get_children():
			stack.append(ch)
	return out


func _accumulate(mi: MeshInstance3D, bone_xf: Array[Transform3D], out: Dictionary) -> void:
	var skin := mi.skin
	var nb := bone_xf.size()
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var bones_raw = arr[Mesh.ARRAY_BONES]
		var weights_raw = arr[Mesh.ARRAY_WEIGHTS]
		if bones_raw == null or weights_raw == null:
			continue
		var bones: PackedInt32Array = bones_raw
		var weights: PackedFloat32Array = weights_raw
		var per := bones.size() / verts.size()
		if per <= 0:
			continue
		for vi in verts.size():
			var best := 0
			var bw := weights[vi * per]
			for k in range(1, per):
				var w := weights[vi * per + k]
				if w > bw:
					bw = w
					best = k
			var b := bones[vi * per + best]
			if b < 0 or b >= nb:
				continue
			# 顶点从网格(绑定)空间 → 骨架空间
			var p_skel: Vector3 = skin.get_bind_pose(b) * verts[vi]
			# → 骨头空间
			var p_bone: Vector3 = bone_xf[b].affine_inverse() * p_skel
			if not out.has(b):
				out[b] = { "count": 0, "box": AABB(p_bone, Vector3.ZERO) }
			var d: Dictionary = out[b]
			d["count"] = int(d["count"]) + 1
			var bb: AABB = d["box"]
			bb = bb.expand(p_bone)
			d["box"] = bb
			out[b] = d
