extends SceneTree
## 诊断：`Aris_Original_Body_001` 的眉毛被切成「2 层」到底是哪两层。
##   godot --path . --headless --script res://scripts/_diag_arislayer.gd -- --splat=off

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 120:
		await process_frame
	paused = false
	# 读**原始模型**（场景里那份已经被改过了）
	var ps := load("res://models/Arisu_ext.glb") as PackedScene
	var inst := ps.instantiate()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not (m.mesh is ArrayMesh):
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat == null or not String(mat.resource_name).to_lower().contains("brow"):
				continue
			print("网格 %s / surface %d / 材质 %s" % [String(m.name), s,
				String(mat.resource_name)])
			var arr := am.surface_get_arrays(s)
			var isl := FaceFix._islands_from(arr)
			print("  连通块 %d 个：" % isl.size())
			var order: Array = []
			for i in isl.size():
				order.append(i)
			order.sort_custom(func(a, b):
				return float(isl[a]["lo"].z) < float(isl[b]["lo"].z))
			var cur_hi := -1e9
			var layer := 0
			for i in order:
				var lo: float = (isl[i]["lo"] as Vector3).z
				var hi: float = (isl[i]["hi"] as Vector3).z
				var gap := lo - cur_hi
				var is_new := cur_hi > -1e8 and gap > FaceFix.LAYER_GAP
				if is_new:
					layer += 1
					cur_hi = -1e9
				print("    块 %2d 顶点 %2d  z %+.4f~%+.4f  间隙 %+.4f %s"
					% [i, (isl[i]["verts"] as PackedInt32Array).size(), lo, hi, gap,
						"**新层 → %d**" % layer if is_new else ""])
				cur_hi = maxf(cur_hi, hi)
			print("  ⇒ 共 %d 层" % (layer + 1))
	inst.free()
	quit(0)
