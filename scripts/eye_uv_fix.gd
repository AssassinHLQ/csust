class_name EyeUvFix
extends RefCounted
## ⚠️ **实验性，未接线（不进游戏）。** 记录一条走不通的修法，别当成品用。
##
## 尝试：把右眼各组顶点的 UV 用「质心反射」`u' = uL + uR − u` 翻到左眼那张图上。
## 结果（`_probe_eye_uvfix.gd`，`--headless`）：
##     eye_R_2  Δu=+0.0671    eye_R  +0.0560    eye_R_1  +0.0732
##     bone_eye_D_R_02  +0.2169   bone_eye_D_R  +0.1191   bone_eye_D_R_01  +0.1011
## 右眼不是「一个整体被平移」：**各子区的左右偏移量互不相同**（0.056 ~ 0.217），
## 所以任何**单一**映射规则都会让一部分顶点采样到错误的图集区域 —— 眼睛贴图会花掉，
## 不会变对称。要修只能在**源模型（Blender）**里重做右眼 UV，或者在 Godot 里做
## **逐顶点对应**（把左眼顶点按镜像位置配对，再逐点抄 UV）。
##
## 保留这份代码是因为里面那套「按骨名分桶统计 UV 质心」的测量方法还有用
## （`_probe_eye_weights.gd` 是同一个思路的只读版）。
##
## ── 下面这段是最初的判断依据（结论仍然成立）──
## ── 为什么是 UV，不是骨骼 ──
## 排掉的三条路（都有量化依据，见 `_probe_eyelids*.gd` / `_probe_eye_mirror.gd`）：
##   1. 眼睑骨旋转幅度左右一样（`eye_L_1` 20.88° vs `eye_R_1` 19.13°）；
##   2. 把左眼的局部旋转按三种镜像公式抄给右眼，正视图**四格完全一样**；
##   3. 蒙皮结构对称（同骨名顶点数一样，质心差 1~2 mm）。
## 而 UV 质心是**明确不一样**的（`_probe_eye_weights.gd`）：
##
##     eye_L    UV 质心 (0.7222, 0.3507)     eye_R    (0.6662, 0.3507)
##     eye_L_1  (0.6882, 0.3999)             eye_R_1  (0.6150, 0.3999)
##     eye_L_2  (0.8508, 0.3249)             eye_R_2  (0.7838, 0.3249)
##
## **v 一分不差、u 差 0.06 左右**，而且每一对的 UV 矩形**尺寸完全相同**
## （0.9372×0.4416 / 0.9215×0.6241 / 0.9482×0.5347）——
## 这就是「同一个图集里左右眼各占一格、两格里画的是两张不同的眼图」。
## 右眼那一格是半睁的，所以看起来上眼睑盖住瞳孔。
##
## ── 做法 ──
## 对每一对（左骨、右骨）顶点组：把右组顶点的 UV 从**右格**归一化，
## 再按 u 镜像铺进**左格**。这样右眼用的就是左眼那张图（镜像），两只眼就一样了。
##
## ⚠️ 只处理「UV 矩形不一样」的组：`Xtra_eyeR/L`、`Eyering_*` 两组本来就用同一格
##    （UV 质心完全相同），重映射反而会弄坏。
## ⚠️ 带形态键的网格一律跳过（嘴那 10 块，见 `face_fix.gd`）。


## 返回 {meshes, surfaces, verts, pairs:[{l, r, dx}], skipped}
static func mirror_right_eye_uvs(root: Node) -> Dictionary:
	var report := {"meshes": 0, "surfaces": 0, "verts": 0, "pairs": [] as Array, "skipped": 0}
	if root == null:
		return report

	for mi in _all_meshes(root):
		var m := mi.mesh
		if not (m is ArrayMesh) or mi.skin == null:
			continue
		if m.get_blend_shape_count() > 0:
			report["skipped"] = int(report["skipped"]) + 1
			continue
		var res := _fix_mesh(mi as MeshInstance3D, m as ArrayMesh)
		if res.is_empty():
			continue
		report["meshes"] = int(report["meshes"]) + 1
		report["surfaces"] = int(report["surfaces"]) + int(res["surfaces"])
		report["verts"] = int(report["verts"]) + int(res["verts"])
		var pairs: Array = report["pairs"]
		pairs.append_array(res["pairs"])
	return report


static func _fix_mesh(mi: MeshInstance3D, m: ArrayMesh) -> Dictionary:
	var skin := mi.skin
	var surf := m.get_surface_count()
	const MIN_W := 0.2

	# ① 每个顶点上**所有权重 ≥ 0.2 的骨**都算（不能只看「主骨」：眼睛顶点的主骨
	#    往往是 Head，眼睛骨只占 0.3 —— 第一版按主骨分桶，99 个组里一个 eye 都没进）
	var uvs_by_bone := {}
	var bones_by_surf: Array = []
	for s in surf:
		var arr := m.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var ts: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var per_vert: Array = []
		if not bs.is_empty() and not ws.is_empty() and not ts.is_empty():
			var per := bs.size() / maxi(vs.size(), 1)
			for v in vs.size():
				var names: Array = []
				var weights: Array = []
				for k in per:
					var idx := v * per + k
					if idx >= bs.size():
						break
					if ws[idx] < MIN_W:
						continue
					var bn := String(skin.get_bind_name(bs[idx]))
					if bn.is_empty():
						continue
					names.append(bn)
					weights.append(ws[idx])
					if not uvs_by_bone.has(bn):
						uvs_by_bone[bn] = []
					uvs_by_bone[bn].append(ts[v])
				per_vert.append({"n": names, "w": weights})
		bones_by_surf.append(per_vert)

	# ② 每组的 UV 质心 + 配对
	#
	# ⚠️ 为什么不用「UV 矩形」去对槽位：两组共享同一块 UV 岛，边界顶点会污染矩形，
	#    实测左右两组的矩形**完全一样**（Δx=0），按矩形平移根本动不了。
	#    真正有区别的是**质心**：u 差 0.05~0.07，v 一分不差。
	#    所以用**质心反射**：右眼每个顶点的 u 映射成 `uL + uR - u`
	#    —— 等于把它翻到左眼那张图上的镜像位置。
	var cu := {}
	var cv := {}
	for bn in uvs_by_bone:
		var pts: Array = uvs_by_bone[bn]
		var s := Vector2.ZERO
		for p in pts:
			s += p
		s /= float(maxi(pts.size(), 1))
		cu[bn] = s.x
		cv[bn] = s.y
	var mapping := {}
	var pairs: Array = []
	for bn in cu:
		var s := String(bn)
		var low := s.to_lower()
		if not low.contains("eye") or low.contains("eyebrow") or low.contains("eyeblow"):
			continue
		var pair := _pair(s)
		if pair == s or not cu.has(pair):
			continue
		var ur := float(cu[s])
		var ul := float(cu[pair])
		# 已经共用同一处采样的（Xtra_eye / Eyering）：不碰
		if absf(ur - ul) < 0.005:
			continue
		mapping[s] = {"c": ur + ul}
		pairs.append({"l": pair, "r": s, "dx": ul - ur})

	if mapping.is_empty():
		print("[EyeUvFix] %s：没有可映射的组（uvs_by_bone=%d）" % [
			mi.name, uvs_by_bone.size()])
		return {}

	# ③ 重建每个面：按主骨把 UV 换到左格（u 镜像）
	var out := ArrayMesh.new()
	var verts := 0
	for s in surf:
		var arr := m.surface_get_arrays(s)
		var ts: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var pv: Array = bones_by_surf[s]
		for v in ts.size():
			if v >= pv.size():
				break
			var info: Dictionary = pv[v]
			var names: Array = info["n"]
			var weights: Array = info["w"]
			# 这个顶点上「属于右眼组」的骨里，权重最大的那根
			var best := ""
			var bw := -1.0
			for i in names.size():
				var nm := String(names[i])
				if not mapping.has(nm):
					continue
				if float(weights[i]) > bw:
					bw = float(weights[i])
					best = nm
			if best.is_empty():
				continue
			var mp: Dictionary = mapping[best]
			ts[v] = Vector2(float(mp["c"]) - ts[v].x, ts[v].y)
			verts += 1
		arr[Mesh.ARRAY_TEX_UV] = ts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, m.surface_get_material(s))
	mi.mesh = out
	return {"surfaces": surf, "verts": verts, "pairs": pairs}


static func _rect(pts: Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## 右 → 左的骨名。先按 `_R` 换（`bone_eye_D_R_01`、`eye_R_1`），再按 `eyeR` 换。
static func _pair(name: String) -> String:
	if name.contains("_R"):
		return name.replace("_R", "_L")
	if name.contains("eyeR"):
		return name.replace("eyeR", "eyeL")
	return name


static func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D and (x as MeshInstance3D).mesh != null:
			out.append(x as MeshInstance3D)
		for c in x.get_children():
			stack.append(c)
	return out
