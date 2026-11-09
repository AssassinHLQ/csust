extends SceneTree
## 量电脑城天花板：`Object002_PLASTIK_W_0` 到底是什么形状。
##
##   godot --path . --headless --script res://scripts/_probe_shop_ceiling.gd
##
## 为什么要单独量：天花板在 GLB 里只有 **24 面、1 cm 厚**（y 5.21~5.22）。
## trimesh 是没有厚度的三角面，从正下方打射线很容易**从三角形之间的缝穿过去**，
## 所以验证脚本里「天花板挡得住」一直只有 1/9 命中。
## 这里把它的顶点逐个打出来，看是**一整块平板**还是**几条细边**。

const SCENE := "res://scenes/shop_baked.tscn"
const TARGET := "Object002_PLASTIK_W_0"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var shop := (load(SCENE) as PackedScene).instantiate()
	root.add_child(shop)
	current_scene = shop
	for _i in 10:
		await process_frame

	var shell := shop.get_node_or_null("Shell")
	if shell == null:
		print("[ceil] !! 没有 Shell")
		quit(1)
		return

	for n in shell.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not (mi.mesh is ArrayMesh):
			continue
		if String(mi.name) != TARGET:
			continue
		var am := mi.mesh as ArrayMesh
		print("[ceil] 找到 %s" % mi.name)
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = PackedInt32Array()
			if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
				idx = arr[Mesh.ARRAY_INDEX]
			print("[ceil]   surface %d：%d 顶点、%d 索引" % [si, verts.size(), idx.size()])
			# 世界坐标下的顶点
			var lo := Vector3(INF, INF, INF)
			var hi := Vector3(-INF, -INF, -INF)
			for v in verts:
				var w: Vector3 = mi.global_transform * v
				lo = lo.min(w)
				hi = hi.max(w)
			print("[ceil]   世界 y %.4f ~ %.4f（厚 %.4f m）" % [
				lo.y, hi.y, hi.y - lo.y])
			print("[ceil]   世界 x %.2f ~ %.2f   z %.2f ~ %.2f" % [
				lo.x, hi.x, lo.z, hi.z])
			# 每个三角形的中心，看是不是铺满
			var tri_n := (idx.size() / 3) if idx.size() > 0 else (verts.size() / 3)
			print("[ceil]   %d 个三角形" % tri_n)
			for t in mini(tri_n, 8):
				var a: Vector3
				var b: Vector3
				var c: Vector3
				if idx.size() > 0:
					a = verts[idx[t * 3]]
					b = verts[idx[t * 3 + 1]]
					c = verts[idx[t * 3 + 2]]
				else:
					a = verts[t * 3]
					b = verts[t * 3 + 1]
					c = verts[t * 3 + 2]
				var wa: Vector3 = mi.global_transform * a
				var wb: Vector3 = mi.global_transform * b
				var wc: Vector3 = mi.global_transform * c
				print("[ceil]     tri%d: x %.2f~%.2f  z %.2f~%.2f" % [
					t, minf(wa.x, minf(wb.x, wc.x)), maxf(wa.x, maxf(wb.x, wc.x)),
					minf(wa.z, minf(wb.z, wc.z)), maxf(wa.z, maxf(wb.z, wc.z))])

	print("[ceil] 完成")
	quit(0)
