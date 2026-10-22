extends SceneTree
## 只读探针：`shop.build()` 那 107 ms 到底花在哪 —— 逐段计时（不 build 商店，只量单品）。

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# 1) 小空模型加载 + 实例化 + _ready
	var t0 := Time.get_ticks_usec()
	var ps := load("res://models/npc/sora/sora.glb") as PackedScene
	var t1 := Time.get_ticks_usec()
	var node := ps.instantiate() if ps != null else null
	var t2 := Time.get_ticks_usec()
	var clerk := ShopClerk.new()
	var t3 := Time.get_ticks_usec()
	root.add_child(clerk)
	var t4 := Time.get_ticks_usec()
	print("[cost] 小空 glb load %6.2f ms / instantiate %6.2f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	print("[cost] ShopClerk.new %6.2f ms / add_child(_ready=载模型) %6.2f ms" % [(t3 - t2) / 1000.0, (t4 - t3) / 1000.0])
	if node != null:
		node.queue_free()
	clerk.queue_free()
	await process_frame

	# 2) 155 个盒子（独立网格+独立材质，和 shop.gd 的写法一致）
	var p := Node3D.new()
	root.add_child(p)
	var t5 := Time.get_ticks_usec()
	for i in 155:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 0.1, 0.45)
		mi.mesh = bm
		mi.material_override = StandardMaterial3D.new()
		mi.position = Vector3(float(i % 20), 0.0, float(i / 20))
		p.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		p.add_child(cs)
	var t6 := Time.get_ticks_usec()
	print("[cost] 155 个盒子（网格+材质+碰撞盒，共 310 节点）%6.2f ms" % ((t6 - t5) / 1000.0))
	p.queue_free()
	quit(0)
