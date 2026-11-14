extends SceneTree
## 摸清 `esports_room.glb` 里「显示器屏面」到底是哪个网格桶、UV 是怎么排的。
##
## 背景：想用「直接换材质」的办法把 logo 贴满 5 块屏，结果换上去只出现一条窄色带 ——
## 说明这些桶用的是**图集 UV**（每个零件只占大贴图的一小块），不是 0~1 整张。
## 那就得知道：哪个桶是屏面、它有几个 surface、UV 范围多大。
##
##   godot --headless --path . --script res://scripts/_probe_glb_uv.gd

const GLB := "res://models/esports_room/esports_room.glb"


func _initialize() -> void:
	var packed := load(GLB) as PackedScene
	if packed == null:
		print("!! 载不到 %s" % GLB)
		quit(1)
		return
	var inst := packed.instantiate() as Node3D
	get_root().add_child(inst)
	print("======== esports_room.glb 里的网格桶 ========")
	var n := 0
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.mesh.get_aabb()
		# 只看「靠近显示器」那一带：细薄、竖向 0.3~0.6、横向跨很长
		if b.size.x > 0.2 or b.size.y < 0.25 or b.size.z < 4.0:
			continue
		n += 1
		print("\n  [%s]  path=%s" % [m.name, str(inst.get_path_to(m))])
		print("     AABB pos=%s size=%s" % [str(b.position.snappedf(0.001)), str(b.size.snappedf(0.001))])
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if uv.size() == 0:
				print("     surface %d：没有 UV" % si)
				continue
			var u0 := INF
			var u1 := -INF
			var v0 := INF
			var v1 := -INF
			for t in uv:
				u0 = minf(u0, t.x); u1 = maxf(u1, t.x)
				v0 = minf(v0, t.y); v1 = maxf(v1, t.y)
			print("     surface %d：顶点 %d，UV u %.3f~%.3f  v %.3f~%.3f"
				% [si, verts.size(), u0, u1, v0, v1])
			# 顶点在 y/z 上的分布，判断这块是不是「五连屏」
			var y0 := INF
			var y1 := -INF
			var z0 := INF
			var z1 := -INF
			for v in verts:
				y0 = minf(y0, v.y); y1 = maxf(y1, v.y)
				z0 = minf(z0, v.z); z1 = maxf(z1, v.z)
			print("       顶点范围 y %.3f~%.3f  z %.3f~%.3f"
				% [y0, y1, z0, z1])
	if n == 0:
		print("（没有匹配的桶）")
	print("\n共 %d 个候选桶" % n)
	quit(0)
