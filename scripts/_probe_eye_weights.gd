extends SceneTree
## 探针：**左右眼周围那一圈顶点，到底蒙皮到哪根骨上**。
##
## 为什么要它：已经量出来
##   · 眼睑骨 `eye_L_1` / `eye_R_1` 的旋转**幅度一样**（20.88° vs 19.13°）；
##   · 把左眼的局部旋转按三种镜像公式抄给右眼，**渲出来的图一模一样**（`_probe_eye_mirror.gd`）；
## 那说明「右眼半遮」根本不是这俩骨在管。于是直接查**蒙皮权重**：
## 取右眼周围一个球里的顶点，把它们 4 个权重按骨名汇总，看谁在管这块皮。
##
## ⚠️ `ARRAY_BONES` 里存的是 **skin 的 bind 下标**，不是骨骼下标 ——
##    必须过 `Skin.get_bind_bone()` 换回来（README §1.8 同一个坑）。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_eye_weights.gd

const MODEL := "res://models/Arisu_ext.glb"
const RADIUS := 0.035      ## 球半径（米，模型空间）


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var sk := _find_skel(inst)
	if sk == null:
		print("!! 没有 Skeleton3D")
		quit(1)
		return

	# 眼睛在**静置姿态**下的位置 —— 统一换到**世界**坐标比，别再混空间
	# （第一版拿骨架空间和世界坐标比，只命中 2 个顶点）
	var center := {}
	for side in ["L", "R"]:
		var i := _bone(sk, "eye_" + side)
		if i < 0:
			print("!! 找不到 eye_%s" % side)
			continue
		center[side] = sk.global_transform * sk.get_bone_global_rest(i).origin

	for side in ["L", "R"]:
		if not center.has(side):
			continue
		print("\n===== 眼%s 周围 %.1f cm 内的顶点：骨权重汇总 =====" % [side, RADIUS * 100.0])
		_tally(inst, sk, center[side])
	quit(0)


func _tally(root_node: Node, sk: Skeleton3D, at: Vector3) -> void:
	var totals := {}
	var verts := 0
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var m := mi.mesh
			var skin := mi.skin
			if m is ArrayMesh and skin != null:
				print("  [%s] surfaces=%d binds=%d bind0→骨%d" % [
					mi.name, m.get_surface_count(), skin.get_bind_count(),
					skin.get_bind_bone(0) if skin.get_bind_count() > 0 else -2])
				var xf := mi.global_transform
				for s in m.get_surface_count():
					var arr := m.surface_get_arrays(s)
					var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
					var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
					if bs.is_empty() or ws.is_empty():
						continue
					var per := bs.size() / maxi(vs.size(), 1)     # 每顶点几根骨
					for v in vs.size():
						if (xf * vs[v]).distance_to(at) > RADIUS:
							continue
						verts += 1
						for k in per:
							var idx := v * per + k
							if idx >= bs.size():
								break
							var w := ws[idx]
							if w <= 0.001:
								continue
							var bone_i := skin.get_bind_bone(bs[idx])
							var bn := String(sk.get_bone_name(bone_i)) if bone_i >= 0 else "?"
							totals[bn] = float(totals.get(bn, 0.0)) + w
		for c in n.get_children():
			stack.append(c)
	print("  命中顶点 %d 个" % verts)
	var names := totals.keys()
	names.sort_custom(func(a, b): return float(totals[a]) > float(totals[b]))
	var shown := 0
	for nm in names:
		print("    %-26s %6.1f%%" % [nm, 100.0 * float(totals[nm]) / maxf(float(verts), 1.0)])
		shown += 1
		if shown >= 12:
			break


func _bone(sk: Skeleton3D, name: String) -> int:
	var i := sk.find_bone(name)
	if i >= 0:
		return i
	for b in sk.get_bone_count():
		if String(sk.get_bone_name(b)).to_lower().contains(name.to_lower()):
			return b
	return -1


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var x := _find_skel(c)
		if x != null:
			return x
	return null
