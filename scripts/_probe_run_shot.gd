extends SceneTree
## 背后视角渲图：跑动时「斜不斜」，用**和游戏同一套机位**拍下来对比。
##
## 为什么不用侧视（`_probe_lean_side.gd` 那种）：侧视量的是几何，玩家看到的是
## 「背后 4.2 m、高 1.62、FOV 62」这个构图下的人。用户报的「倾斜」是**这个机位**
## 下的观感，所以这里 1:1 复刻 `player.gd` 的腰射机位。
##
## 用法（要真渲染，不要 --headless）：
##   godot --path <工程> --script res://scripts/_probe_run_shot.gd -- --fix
## 输出：_arisu_captures/_leanrun/{before,after}_p{0..2}.png

const MODEL := "res://models/Arisu_ext.glb"
const CLIP := "Move_Ing"
const PHASES := 3


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(560, 620)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.88, 0.9, 0.94)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.93, 1.0)
	env.ambient_light_energy = 2.4
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.6
	root.add_child(sun)
	# 正面补光：背光下人物是一团黑，看不出「斜」，剪影判读就废了
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 165, 0)
	fill.light_energy = 0.9
	root.add_child(fill)

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	cam.far = 200.0
	root.add_child(cam)
	cam.make_current()
	# 与 player.gd 的腰射机位同一套角度（身后、略高、微俯视），只是**拉近**到 2.4 m
	# 方便看清姿态；构图比例与此一致，改构图不影响「斜不斜」的判断。
	cam.global_position = Vector3(0.0, 1.62, -2.4)
	cam.look_at(Vector3(0.0, 1.12, 0.0), Vector3.UP)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_leanrun")
	DirAccess.make_dir_recursive_absolute(out)

	var do_fix: bool = "--fix" in OS.get_cmdline_user_args()
	for tag in ["before", "after"]:
		var scene: Node = (load(MODEL) as PackedScene).instantiate()
		root.add_child(scene)
		await process_frame
		await process_frame
		var ap := _find_matching(scene, "AnimationPlayer") as AnimationPlayer
		var skel := _find(scene, "Skeleton3D") as Skeleton3D
		if ap == null or skel == null:
			print("!! 缺 AnimationPlayer / Skeleton3D")
			quit(1)
			return
		if tag == "after" and do_fix:
			var rep := PoseFix.fix_run_lean(skel, ap)
			print("[shot] PoseFix applied=%s keys=%d" % [rep["applied"], rep["total"]])
		ap.play(CLIP)
		# 按模型真实包围盒定机位：距离 = 身高 × 2.0，视线中心略高于几何中心，
		# 这样「前后两张、三个相位」的构图完全一致，斜不斜才可比。
		var aabb := _visual_aabb(scene)
		var centre := aabb.get_center()
		var hgt := maxf(aabb.size.y, 0.1)
		# `--side` = 从 +X 侧拍（判「头是不是还低着」最直观），默认从背后拍（玩家视角）
		var side: bool = "--side" in OS.get_cmdline_user_args()
		var offset := Vector3(hgt * 2.0, hgt * 0.28, 0.0) if side else Vector3(0.0, hgt * 0.28, -hgt * 2.0)
		cam.global_position = centre + offset
		cam.look_at(centre + Vector3(0.0, hgt * 0.02, 0.0), Vector3.UP)
		print("[shot] %s aabb=%s 身高=%.2f 机位=%s" % [tag,
			str(aabb.size.snappedf(0.01)), hgt, str(cam.global_position.snappedf(0.01))])
		# 站姿跑：5.2 m/s 是 CYCLE_SPEED 的标称速度，speed_scale = 1
		var length := ap.get_animation(CLIP).length
		for i in PHASES:
			ap.seek(length * float(i) / float(PHASES), true)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var file := "%s/%s%s_p%d.png" % [out, tag, "_side" if side else "", i]
			root.get_texture().get_image().save_png(file)
			print("  [img] %s" % file)
		scene.queue_free()
		await process_frame

	print("[shot] 输出目录：%s" % out)
	quit(0)


## 把所有可见网格的 AABB 变换到世界空间再合并（和 `_probe_lean_side.gd` 同一套）
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
				var b := Transform3D(vi.global_transform.basis, vi.global_transform.origin) * box
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
		if r != null:
			return r
	return null


## 找「有 Normal_Idle」的那个 AnimationPlayer（跳过上层叠加层）
func _find_matching(node: Node, cls: String) -> Node:
	if node.is_class(cls) and (node as AnimationPlayer).has_animation("Normal_Idle"):
		return node
	for c in node.get_children():
		var r := _find_matching(c, cls)
		if r != null:
			return r
	return null
