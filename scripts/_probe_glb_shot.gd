extends SceneTree
## 探针：把任意一个 GLB 拎出来单独拍 4 个方位（0/90/180/270 度）+ 一张特写，
## 用来看清「模型到底长什么样、脸朝哪边、有没有多余的控制骨骼小方块」。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_glb_shot.gd -- <glb> <输出目录> [--hide-cs]
## 例：
##   ... -- res://models/npc/sensei_new.glb _arisu_captures/_newsensei --hide-cs

const LIGHT_BG := Color(0.88, 0.9, 0.94)

var _glb := ""
var _out := ""
var _hide_cs := false


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	for a in argv:
		if a.begins_with("--"):
			if a == "--hide-cs":
				_hide_cs = true
		elif _glb.is_empty():
			_glb = a
		else:
			_out = a
	_run.call_deferred()


func _run() -> void:
	if _glb.is_empty():
		print("!! 没给 GLB 路径")
		quit(1)
		return
	if _out.is_empty():
		_out = "_arisu_captures/_glb"
	root.size = Vector2i(820, 900)

	var ps: PackedScene = load(_glb)
	if ps == null:
		print("!! 载入失败：%s" % _glb)
		quit(1)
		return
	var inst: Node3D = ps.instantiate()
	root.add_child(inst)
	await _wait(10)

	# 世界环境：亮背景 + 高环境光，避免把暗色模型拍成黑块
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = LIGHT_BG
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 2.4
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	root.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 34, 0)
	key.light_energy = 1.1
	key.shadow_enabled = false
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -140, 0)
	fill.light_energy = 0.5
	fill.shadow_enabled = false
	root.add_child(fill)

	var all := _visual_aabb(inst)
	print("[glb] %s" % _glb)
	print("[glb] 总包围盒 size=%s  center=%s" % [
		str(all.size.snappedf(0.001)), str(all.get_center().snappedf(0.001))])

	var meshes := _collect_meshes(inst)
	print("[glb] 可见网格 %d 个" % meshes.size())
	var cs: Array[Node] = []
	for m in meshes:
		if _is_control(m):
			cs.append(m)
	if not cs.is_empty():
		print("[glb] !! 控制骨骼小方块 %d 个：%s%s" % [
			cs.size(), _names(cs, 6), "（已隐藏）" if _hide_cs else "（仍显示）"])
	if _hide_cs:
		for n in cs:
			if n is GeometryInstance3D:
				(n as GeometryInstance3D).visible = false
		await _wait(4)

	# 主体网格的自检：面数、材质、是否吃到顶点色
	for m in meshes:
		if _is_control(m):
			continue
		var mi := m as MeshInstance3D
		var mats: Array[String] = []
		var tris := 0
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			mats.append("%s(albedo=%s vcol=%s)" % [
				"<无>" if mat == null else mat.resource_name,
				"-" if not (mat is BaseMaterial3D) else str((mat as BaseMaterial3D).albedo_color),
				"-" if not (mat is BaseMaterial3D) else str((mat as BaseMaterial3D).vertex_color_use_as_albedo)])
			tris += mi.mesh.surface_get_array_len(s) / 3
		print("[glb] 主体 '%s'  surfaces=%d tris≈%d  %s" % [
			mi.name, mi.mesh.get_surface_count(), tris, " | ".join(mats)])
	var sk := _find_skel(inst)
	if sk != null:
		print("[glb] 骨架骨头数 = %d" % sk.get_bone_count())

	var body := _visual_aabb(inst)
	print("[glb] 主体包围盒 size=%s" % str(body.size.snappedf(0.001)))
	var c := body.get_center()
	var h := maxf(body.size.y, 0.2)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(_out)
	DirAccess.make_dir_recursive_absolute(out)

	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.near = 0.02
	cam.far = 300.0
	root.add_child(cam)
	cam.make_current()

	var dist := h * 1.55
	for az in [0, 90, 180, 270]:
		var rad := deg_to_rad(float(az))
		var dir := Vector3(sin(rad), 0, cos(rad))
		await _shoot(cam, c + dir * dist + Vector3.UP * (h * 0.10), c,
			out.path_join("az%03d.png" % az))
	# 上半身特写（看脸有没有）
	await _shoot(cam, c + Vector3(0, h * 0.20, dist * 0.52), c + Vector3(0, h * 0.22, 0),
		out.path_join("closeup.png"))

	print("[glb] 输出 %s" % out)
	quit(0)


func _is_control(n: Node) -> bool:
	return n.name.to_lower().begins_with("cs_")


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _names(arr: Array, n: int) -> String:
	var out: Array[String] = []
	for i in mini(n, arr.size()):
		out.append(str(arr[i].name))
	if arr.size() > n:
		out.append("…")
	return ", ".join(out)


func _collect_meshes(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D:
			out.append(x)
		for c in x.get_children():
			stack.append(c)
	return out


func _shoot(cam: Camera3D, from: Vector3, at: Vector3, file: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("  [img] %s" % file)


func _visual_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D and (n as VisualInstance3D).is_visible_in_tree():
			var vi := n as VisualInstance3D
			var box := vi.get_aabb()
			if box.size.length() > 0.0001:
				var b := Transform3D(vi.global_transform.basis, vi.global_transform.origin) * box
				out = b if first else out.merge(b)
				first = false
		for c in n.get_children():
			stack.append(c)
	return out


func _wait(frames: int) -> void:
	for _i in frames:
		await process_frame
