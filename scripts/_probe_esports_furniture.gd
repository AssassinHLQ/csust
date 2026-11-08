extends SceneTree
## 量电竞房里**显示器 / 椅子**这些家具的实际顶点分布，判断它们是「挂天花板」
## 还是「贴地面」。
##
##   godot --path . --headless --script res://scripts/_probe_esports_furniture.gd
##
## 为什么要量：渲染出来看着「显示器/椅子倒挂在天花板上」，
## 但外壳 AABB 又是正常的（地面 y=0、天花板 y=3.3）。
## 有两种可能：
##   ① 模型真的上下翻了；
##   ② 相机 look_at 的 up 向量搞反，画面是倒的。
## 顶点 y 分布能一锤定音：**家具顶点集中在高 y（2~3.3）还是低 y（0~1）**。

const SCENE := "res://scenes/esports_room.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var room := (load(SCENE) as PackedScene).instantiate()
	root.add_child(room)
	await process_frame
	await process_frame
	await process_frame

	print("[furn] ── 每个网格的顶点 y 分布（局部，取 mesh 自身的）──")
	for n in room.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not (mi.mesh is ArrayMesh):
			continue
		var am := mi.mesh as ArrayMesh
		var ntri := 0
		var ylo := INF
		var yhi := -INF
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			if arr.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for v in verts:
				ylo = minf(ylo, v.y)
				yhi = maxf(yhi, v.y)
			if arr.size() > Mesh.ARRAY_INDEX:
				ntri += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		if ylo == INF:
			continue
		# 只打印「看起来是家具」的（面数不太多、包围盒不太大）
		var b := mi.mesh.get_aabb()
		var vol := b.size.x * b.size.y * b.size.z
		if vol > 3.0 or ntri > 60000:
			continue
		print("[furn]   %-30s 面 %6d  局部 y %7.3f ~ %7.3f  包围盒 y %7.3f~%7.3f" % [
			mi.name, ntri, ylo, yhi, b.position.y, b.position.y + b.size.y])

	# 重点：显示器（JS149 那排）和椅子
	print("[furn] ── 大件（家具）─────────────────────────────────")
	for n in room.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not (mi.mesh is ArrayMesh):
			continue
		var am := mi.mesh as ArrayMesh
		var ntri := 0
		var ylo := INF
		var yhi := -INF
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			if arr.size() <= Mesh.ARRAY_VERTEX:
				continue
			for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				ylo = minf(ylo, v.y)
				yhi = maxf(yhi, v.y)
			if arr.size() > Mesh.ARRAY_INDEX:
				ntri += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		if ylo == INF or ntri < 200:
			continue
		var b := mi.mesh.get_aabb()
		var vol := b.size.x * b.size.y * b.size.z
		if vol < 0.2 or vol > 20.0:
			continue
		print("[furn]   %-30s 面 %6d  局部 y %7.3f ~ %7.3f  高 %.2f" % [
			mi.name, ntri, ylo, yhi, yhi - ylo])

	print("[furn] 完成")
	quit(0)
