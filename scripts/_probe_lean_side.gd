extends SceneTree
## 侧视渲图：同一相位下对比 Arisu.glb 与 Arisu_ext.glb 的跑动躯干前倾。
## 渲染完再用 tools/make_lean_compare.py 拼成上下对照图。
##
## 用法（要真渲染，不要 --headless）：
##   godot --path <工程> --script res://scripts/_probe_lean_side.gd
## 输出：…/_arisu_captures/_lean_side/<模型名>_p<相位>.png

const FILES := ["res://models/Arisu.glb", "res://models/Arisu_ext.glb"]
const PHASES := 4
const CLIP := "Move_Ing"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(420, 620)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.93, 0.94, 0.96)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, -140, 0)
	sun.light_energy = 0.9
	root.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.02
	cam.far = 100.0
	root.add_child(cam)
	cam.make_current()

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_lean_side")
	DirAccess.make_dir_recursive_absolute(out)

	for path_value in FILES:
		var path: String = path_value
		var label: String = path.get_file().get_basename()
		var scene: Node = (load(path) as PackedScene).instantiate()
		root.add_child(scene)
		await process_frame
		await process_frame

		var ap := _find(scene, "AnimationPlayer") as AnimationPlayer
		if not ap.has_animation(CLIP):
			push_error("%s 没有 %s" % [path, CLIP])
			continue
		ap.play(CLIP)

		# 固定机位：两个模型必须完全同机位才能直接对比
		# （模型高约 1.5，相机在 +X 侧 2.4 m、视线高 0.72，fov 30 → 人物正好占满画幅）
		var aabb := _visual_aabb(scene)
		cam.global_position = Vector3(2.4, 0.75, 0.0)
		cam.look_at(Vector3(0.0, 0.72, 0.0), Vector3.UP)
		print("[lean] %s  视觉包围盒 size=%s（只作参考，机位固定）" % [
			label, str(aabb.size.snappedf(0.01))])

		var length := ap.get_animation(CLIP).length
		for i in PHASES:
			ap.seek(length * float(i) / float(PHASES), true)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var file := "%s/%s_p%d.png" % [out, label, i]
			root.get_texture().get_image().save_png(file)
			print("  [img] %s" % file)
		scene.queue_free()
		await process_frame

	print("[lean] 输出目录：%s" % out)
	quit(0)


## 把所有可见网格的 AABB 变换到世界空间再合并
func _visual_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			var box := vi.get_aabb()
			if box.size.length() > 0.0001:
				var world := Transform3D(vi.global_transform.basis, vi.global_transform.origin)
				var b := world * box
				out = b if first else out.merge(b)
				first = false
		for c in n.get_children():
			stack.append(c)
	return out


func _find(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
