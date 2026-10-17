extends SceneTree
## 探针：Godot 4.7 的**自动凸包分解**（`MeshConvexDecompositionSettings` +
## `MeshInstance3D.create_multiple_convex_collisions()`，对应 UE 的 Convex Decomposition）
## 到底能不能在**运行时**用、要花多少毫秒、拆出多少个凸包、总面数多少。
##
## 结论会决定 `boss.gd` 走哪条路：
##   · 够快 → 载入时直接分解，碰撞是「低模凸包集合」，又准又便宜；
##   · 太慢 → 离线烘一次，存成资源。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_convex_bake.gd


const MODELS := [
	"res://models/bosses/Tyrannosaurus.glb",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var paths: Array = OS.get_cmdline_user_args()
	if paths.is_empty():
		paths = MODELS
	for path in paths:
		if not ResourceLoader.exists(path):
			print("!! 没有 %s" % path)
			continue
		var ps := load(path) as PackedScene
		var inst: Node3D = ps.instantiate()
		root.add_child(inst)
		await process_frame

		var meshes: Array[MeshInstance3D] = []
		var stack: Array[Node] = [inst]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				meshes.append(n as MeshInstance3D)
			for c in n.get_children():
				stack.append(c)
		print("\n[convex] %s  网格 %d 个" % [path, meshes.size()])
		if meshes.is_empty():
			continue
		# 取三角形最多的那个当测试对象
		var best: MeshInstance3D = meshes[0]
		var best_tris := 0
		for mi in meshes:
			var arr := mi.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if v.size() > best_tris:
				best_tris = v.size()
				best = mi
		print("   测试网格 '%s' 顶点 %d" % [best.name, best_tris])

		var settings := MeshConvexDecompositionSettings.new()
		settings.max_convex_hulls = 32
		settings.max_num_vertices_per_convex_hull = 32
		settings.convex_hull_downsampling = 4
		settings.convex_hull_approximation = true
		settings.min_volume_per_convex_hull = 0.0001

		var t0 := Time.get_ticks_msec()
		best.create_multiple_convex_collisions(settings)
		var dt := Time.get_ticks_msec() - t0
		print("   分解耗时 **%d ms**" % dt)

		var hulls := 0
		var faces := 0
		for c in best.get_children():
			if c is StaticBody3D:
				for cc in c.get_children():
					if cc is CollisionShape3D and (cc as CollisionShape3D).shape is ConvexPolygonShape3D:
						hulls += 1
						faces += (cc as CollisionShape3D).shape.get_faces().size() / 3
		print("   拆出 **%d** 个凸包，总 **%d** 个三角面" % [hulls, faces])
		inst.queue_free()
	quit(0)
