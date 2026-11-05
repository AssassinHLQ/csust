extends SceneTree
## 量一个模型在 Godot 里的**真实成本**：显存 / draw call / 帧时间。
##
## 为什么不能只看 Blender 的三角数：三角数只决定 GPU 顶点着色的一半，
## 真正决定「卡不卡」的还有 draw call、材质数、贴图尺寸、影子 pass。
## 这个探针把模型单独放进一个空场景量一遍，再和现有电竞房对比。
##
## 用法（必须真窗口：headless 没有渲染设备，读不到显存/draw call）：
##   _tools/run_shot.sh res://scripts/_probe_model_cost.gd -- --model=res://models/xxx.glb
##   _tools/run_shot.sh res://scripts/_probe_model_cost.gd -- --model=res://scenes/esports_room.tscn
##
## 输出：stdout + <工程>/_log/model_cost.txt

const WARMUP := 20
const MEASURE := 60

var _lines: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model := "res://scenes/esports_room.tscn"
	var label := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			model = a.substr(8)
		elif a.begins_with("--label="):
			label = a.substr(8)

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1600, 900)
	await process_frame
	await process_frame
	Engine.max_fps = 0
	root.scaling_3d_scale = 0.5

	# 空场景底噪：先量一次「什么都没有」的显存，才能算出模型自己占多少
	var vram_empty := await _settle_and_read()
	_log("空场景底噪：显存 %.0f MiB" % vram_empty)

	if not ResourceLoader.exists(model):
		_log("!! 载入不了 %s" % model)
		_write_out()
		quit(1)
		return
	var packed: PackedScene = load(model)
	if packed == null:
		_log("!! %s 不是 PackedScene" % model)
		_write_out()
		quit(1)
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	# 把模型摆到相机前面，保证它真的在视野里（不然剔除掉就量不到成本）
	_fit_camera(inst)

	var vram_loaded := await _settle_and_read()
	var r := await _measure()

	# 统计节点
	var meshes: Array[MeshInstance3D] = []
	_collect(inst, meshes)
	var tris := 0
	var surfaces := 0
	var mats := {}
	var ver := 0
	for m in meshes:
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			surfaces += 1
			var mat := m.mesh.surface_get_material(s)
			mats[mat.get_instance_id() if mat != null else 0] = true
			if m.mesh is ArrayMesh:
				var a: Array = (m.mesh as ArrayMesh).surface_get_arrays(s)
				if a.size() > Mesh.ARRAY_VERTEX and a[Mesh.ARRAY_VERTEX] != null:
					ver += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				if a.size() > Mesh.ARRAY_INDEX and a[Mesh.ARRAY_INDEX] != null:
					tris += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				elif a.size() > Mesh.ARRAY_VERTEX and a[Mesh.ARRAY_VERTEX] != null:
					tris += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3

	_log("")
	_log("=== %s ===" % (label if label != "" else model.get_file()))
	_log("网格节点 %d | 顶点 %d | 三角 %d | 表面 %d | 材质 %d" % [
		meshes.size(), ver, tris, surfaces, mats.size()])
	_log("显存 %.0f MiB（模型自己 +%.0f MiB）" % [vram_loaded, vram_loaded - vram_empty])
	_log("帧时间 p50 %.2f ms | p99 %.2f ms | 平均 %.1f fps" % [r["p50"], r["p99"], r["fps"]])
	_log("draw call %d | 图元 %d | 渲染对象 %d" % [r["draw"], r["prim"], r["obj"]])

	_write_out()
	quit(0)


## 把相机摆到能看见整个模型的位置（按包围盒算距离）。
func _fit_camera(inst: Node) -> void:
	var cam := root.get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		root.add_child(cam)
		cam.current = true
	var box := _world_aabb(inst)
	if box.size == Vector3.ZERO:
		return
	var radius := box.size.length() * 0.5
	var center := box.get_center()
	var dist := radius / tan(deg_to_rad(cam.fov * 0.5)) * 1.15
	cam.global_position = center + Vector3(dist * 0.7, dist * 0.45, dist * 0.7)
	cam.look_at(center, Vector3.UP)
	cam.far = maxf(cam.far, dist * 6.0)
	_log("模型包围盒 %s（中心 %s），相机放在 %.1f m 外" % [
		str(box.size.snappedf(0.01)), str(center.snappedf(0.01)), dist])


func _world_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _all_mesh_instances(node):
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


func _all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect(node, out)
	return out


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	var mi := node as MeshInstance3D
	if mi != null:
		out.append(mi)
	for c in node.get_children():
		_collect(c, out)


func _settle_and_read() -> float:
	for i in 40:
		await RenderingServer.frame_post_draw
	return float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0


func _measure() -> Dictionary:
	for i in WARMUP:
		await RenderingServer.frame_post_draw
	var dts := PackedFloat32Array()
	var prev := Time.get_ticks_usec()
	for i in MEASURE:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		dts.append(float(now - prev) / 1000.0)
		prev = now
	var s := PackedFloat32Array(dts)
	s.sort()
	var n := s.size()
	var sum := 0.0
	for v in s:
		sum += v
	return {
		"p50": s[int(n * 0.5)],
		"p99": s[mini(int(n * 0.99), n - 1)],
		"fps": 1000.0 / maxf(sum / float(n), 1e-6),
		"draw": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prim": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"obj": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
	}


func _write_out() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_log")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("model_cost.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()


func _log(s: String) -> void:
	print("[cost] " + s)
	_lines.append(s)
