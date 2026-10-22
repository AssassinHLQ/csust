extends SceneTree
## 只读探针：量「代码建块」和「场景实例化」的单价，顺便验证「烤成 .tscn」这条路。
##   godot --headless --path . --script res://scripts/_probe_block_cost.gd

const N := 200

func _initialize() -> void:
	_run.call_deferred()

func _box(parent: Node3D, shared_mesh: BoxMesh, shared_mat: StandardMaterial3D, i: int) -> void:
	var mi := MeshInstance3D.new()
	if shared_mesh == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 1.0, 0.1)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.6, 0.7)
		mat.roughness = 0.4
		bm.material = mat
		mi.mesh = bm
	else:
		mi.mesh = shared_mesh
		mi.material_override = shared_mat
	mi.position = Vector3(float(i % 20) * 1.2, 0.0, float(i / 20) * 1.2)
	parent.add_child(mi)

func _bench(label: String, fn: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	fn.call()
	var dt := (Time.get_ticks_usec() - t0) / 1000.0
	print("[blk] %-34s %d 块 %8.2f ms   %7.4f ms/块" % [label, N, dt, dt / N])
	return dt

func _run() -> void:
	# A 每块独立网格 + 独立材质（shop.gd 现在就是这么干的）
	var pa := Node3D.new()
	root.add_child(pa)
	var a := _bench("A 代码·独立网格+独立材质", func() -> void:
		for i in N:
			_box(pa, null, null, i))
	pa.queue_free()
	await process_frame

	# B 共享网格 + 共享材质
	var pb := Node3D.new()
	root.add_child(pb)
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 1.0, 0.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.6, 0.7)
	var b := _bench("B 代码·共享网格+共享材质", func() -> void:
		for i in N:
			_box(pb, bm, mat, i))
	pb.queue_free()
	await process_frame

	# C MultiMesh：一次 dispatch，200 个实例
	var pc := Node3D.new()
	root.add_child(pc)
	var c := _bench("C 代码·MultiMesh 200 实例", func() -> void:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bm
		mm.instance_count = N
		for i in N:
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(float(i % 20) * 1.2, 0.0, float(i / 20) * 1.2)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		pc.add_child(mmi))
	pc.queue_free()
	await process_frame

	# D 先建好、烤成 .tscn、再实例化 —— 验证「烘焙」这条路
	var pd := Node3D.new()
	root.add_child(pd)
	for i in N:
		_box(pd, null, null, i)
	var t0 := Time.get_ticks_usec()
	var packed := PackedScene.new()
	packed.pack(pd)
	var t1 := Time.get_ticks_usec()
	var path := "user://_probe_block_bake.tscn"
	ResourceSaver.save(packed, path)
	var t2 := Time.get_ticks_usec()
	var reloaded := load(path) as PackedScene
	var t3 := Time.get_ticks_usec()
	var inst := reloaded.instantiate()
	pd.add_child(inst)
	var t4 := Time.get_ticks_usec()
	print("[blk] D 烘焙：pack %6.2f ms / save %6.2f ms / load %6.2f ms / instantiate %6.2f ms（%.4f ms/块）"
		% [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0, (t4 - t3) / 1000.0 / N])
	print("[blk] 同一批 %d 块：代码 A=%.2f ms  B=%.2f ms  MultiMesh=%.2f ms  烤后实例化=%.2f ms"
		% [N, a, b, c, (t4 - t3) / 1000.0])
	quit(0)
