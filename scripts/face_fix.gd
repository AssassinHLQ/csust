class_name FaceFix
extends RefCounted
## 把「贴在脸上的那一层」沿法线推开一点点，解决 z-fighting。
##
## ── 为什么需要 ──
## 爱丽丝的 `Aris_Original_Body` 一个网格上挂了 5 个材质，其中
## `Aris_Original_Face`（脸皮，不透明）和 `Aris_Original_EyeMouth`（眼睛+嘴，`alphaMode = MASK`）
## 是**贴在同一张脸上的两层**，都 `doubleSided`、几何几乎共面。
## 两个面在同一深度上互相抢 → 眼睛/眼睑那一圈会出现「双层线」，用户说的「双眼皮打架」。
##
## ── 为什么是推法线，而不是 render_priority / 关深度测试 ──
## * `render_priority` 只对**半透明**材质有效，MASK（alpha 剪切）走的是不透明队列；
## * 关 `depth_test` 会让眼睛直接盖到头发和手上 —— 换个角度就穿帮。
## 唯一稳的办法是让两层**真的不在同一个深度**上：把上面那层沿法线外推一个极小量。
## 推的量是「网格高度的万分之几」—— 0.8/10000 × 1.7 m ≈ 0.14 mm，肉眼看不出来，
## 但足够让深度值拉开。
##
## 用法：
##   FaceFix.separate_face_layers(model_root)   # 载入模型之后调一次
##
## ⚠️ **带形态键（blend shape）的网格一律跳过。**
##    爱丽丝那 10 块 `Mouth_*` 用的是 `Aris_Original_EyeMouth_Mouth_70x` 材质，
##    名字里带 `EyeMouth`，会被下面的关键字命中；而它们正是靠 `target_0`
##    把自己**整体挪走 0.6 m** 藏起来的（探针实测位移长度 0.6033 m）。
##    `add_surface_from_arrays()` 只搬顶点/法线/UV，**不搬 blend shape** ——
##    重建一次，形态键就没了，10 张嘴会全部贴回脸上。用户报的「多个嘴巴网格重叠」
##    就是这个（实测：FaceFix 之后 10 块 Mouth_* 的 `blend_shapes` 全变 0）。

## 这些材质算「贴在脸上的层」，要往前推
const LAYER_KEYWORDS := ["EyeMouth", "Eyebrow"]


## 返回 {surfaces:int, verts:int, meshes:int, skipped:int} 报告，自检可以读。
static func separate_face_layers(root: Node, ratio := 0.0008) -> Dictionary:
	var report := {"surfaces": 0, "verts": 0, "meshes": 0, "skipped": 0}
	if root == null:
		return report
	for mi in _all_meshes(root):
		var m := mi.mesh
		if not (m is ArrayMesh):
			continue
		# ⚠️ 见文件头：形态键搬不过去，带形态键的网格**绝不能**重建
		if m.get_blend_shape_count() > 0:
			report["skipped"] = int(report["skipped"]) + 1
			continue
		var box := mi.get_aabb()
		var push := maxf(box.size.y * ratio, 0.00001)
		var touched := 0
		var out := ArrayMesh.new()
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			var name := "" if mat == null else mat.resource_name
			var arr := m.surface_get_arrays(s)
			if _is_face_layer(name):
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				if normals.size() == verts.size():
					for i in verts.size():
						verts[i] = verts[i] + normals[i] * push
					arr[Mesh.ARRAY_VERTEX] = verts
					report["verts"] = int(report["verts"]) + verts.size()
					touched += 1
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, mat)
		if touched > 0:
			mi.mesh = out
			report["meshes"] = int(report["meshes"]) + 1
			report["surfaces"] = int(report["surfaces"]) + touched
	return report


static func _is_face_layer(mat_name: String) -> bool:
	for k in LAYER_KEYWORDS:
		if mat_name.contains(k):
			return true
	return false


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
