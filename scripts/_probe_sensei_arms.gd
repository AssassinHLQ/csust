extends SceneTree
## 探针：搞清卡通版老师的骨架里，**哪根骨、绕哪个轴、往哪边转**才能把 T-pose 的手臂放下来。
##
## 两个坑（都是本探针踩出来的）：
## 1. `hand.l` / `forearm.l` 在导出后**挂在 `c_traj` 下面**，不在 `arm.l` 的子树里，
##    所以「转 arm.l 看 hand.l 动没动」永远是 Δ=0，量不出东西。
##    → 改用「转某根骨后，它子树里最深那根骨的位移」当指标。
## 2. `ARRAY_BONES` 里的索引是 **skin 的 bind 索引**，不是 `Skeleton3D` 的骨索引。
##    不经过 `Skin.get_bind_bone()` 换算，权重统计会全跑到 `head.x` 上去（踩过）。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_sensei_arms.gd

const GLB := "res://models/npc/sensei.glb"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node = (load(GLB) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var sk := _find_skel(inst)
	if sk == null:
		print("!! 没有骨架")
		quit(1)
		return
	print("[arms] 骨头 %d 根" % sk.get_bone_count())

	# ── 真正吃权重的骨（走 skin 映射）──
	var w := {}
	var total := 0.0
	for mi in _all_meshes(inst):
		if not (mi.mesh is ArrayMesh):
			continue
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_BONES == 0:
				continue
			var arr := mi.mesh.surface_get_arrays(s)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			for k in bones.size():
				var bind := bones[k]
				if bind < 0:
					continue
				var bi := _bind_to_bone(mi, bind)
				if bi < 0:
					continue
				w[bi] = float(w.get(bi, 0.0)) + weights[k]
				total += weights[k]
	var keys: Array = w.keys()
	keys.sort_custom(func(a, b): return w[a] > w[b])
	print("[arms] 权重总和 %.0f，吃权重的骨 %d 根，前 18：" % [total, keys.size()])
	var line: Array[String] = []
	for k in mini(18, keys.size()):
		var b: int = keys[k]
		line.append("%s(%.0f)" % [sk.get_bone_name(b), w[b]])
	print("        " + ", ".join(line))

	# ── 手臂链上各骨「转一下，子树末端动多少」──
	var cands := ["arm.l", "shoulder.l", "arm_stretch.l", "arm_twist.l", "forearm.l", "hand.l",
		"c_shoulder.l", "spine_03.x", "c_spine_03.x"]
	var axes := {"X": Vector3(1, 0, 0), "Y": Vector3(0, 1, 0), "Z": Vector3(0, 0, 1)}
	for name in cands:
		var idx := sk.find_bone(name)
		if idx < 0:
			continue
		var tip := _deepest(sk, idx)
		var rest_tip: Vector3 = sk.get_bone_global_pose(tip).origin
		var rest_self: Vector3 = sk.get_bone_global_pose(idx).origin
		var best := ""
		var best_dy := 0.0
		for key in axes:
			for sign_f in [-1.0, 1.0]:
				sk.reset_bone_poses()
				sk.set_bone_pose_rotation(idx, _delta(sk, idx, axes[key], 55.0 * sign_f))
				var p: Vector3 = sk.get_bone_global_pose(tip).origin
				var dy := p.y - rest_tip.y
				if absf(dy) > absf(best_dy):
					best_dy = dy
					best = "%s%+.0f°" % [key, 55.0 * sign_f]
		sk.reset_bone_poses()
		print("    %-14s 权重 %6.0f  末端 %-14s 最大 Δy=%+.3f (%s)%s" % [
			name, float(w.get(idx, 0.0)), sk.get_bone_name(tip), best_dy, best,
			"  ← 有效" if absf(best_dy) > 0.02 else ""])
		if rest_self.y < 0.0:
			break
	quit(0)


## skin 的 bind 索引 → Skeleton3D 骨索引
func _bind_to_bone(mi: MeshInstance3D, bind: int) -> int:
	if mi.skin != null and bind < mi.skin.get_bind_count():
		var b := mi.skin.get_bind_bone(bind)
		if b >= 0:
			return b
		# bind_bone 为 -1 表示挂在 skeleton 根下，名字里带骨名
		var nm := mi.skin.get_bind_name(bind)
		if nm != "":
			var sk := _find_skel(mi)
			if sk != null:
				return sk.find_bone(nm)
	return bind


## 子树里「离根最远」的那根骨（用静止位置的长度近似）
func _deepest(sk: Skeleton3D, idx: int) -> int:
	var best := idx
	var best_len := 0.0
	var origin: Vector3 = sk.get_bone_global_rest(idx).origin
	var stack: Array[int] = [idx]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		var p: Vector3 = sk.get_bone_global_rest(cur).origin
		var d := p.distance_to(origin)
		if d > best_len:
			best_len = d
			best = cur
		for c in sk.get_bone_count():
			if sk.get_bone_parent(c) == cur:
				stack.append(c)
	return best


func _delta(sk: Skeleton3D, idx: int, axis: Vector3, deg: float) -> Quaternion:
	var g := Basis.IDENTITY
	var parent := sk.get_bone_parent(idx)
	if parent >= 0:
		g = sk.get_bone_global_rest(parent).basis.orthonormalized()
	var gq := g.get_rotation_quaternion()
	return (gq.inverse() * Quaternion(axis, deg_to_rad(deg)) * gq).normalized()


func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D and (x as MeshInstance3D).mesh != null:
			out.append(x as MeshInstance3D)
		for c in x.get_children():
			stack.append(c)
	return out


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null
