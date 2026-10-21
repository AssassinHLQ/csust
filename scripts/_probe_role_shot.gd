extends SceneTree
## 渲图探针：**歪头修好没有** —— 同一相位，修前 / 修后各拍正面 + 侧面。
##
## 为什么要渲图：`_probe_role_roll.gd` 只能证明「眼睛连线是水平的」，
## 证明不了「脑袋有没有被拧成麻花」。侧倾修正分摊到脊柱/颈/头，
## 分摊比例不对的话正面会看出脖子歪、侧面会看出脖子仰。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_role_shot.gd -- --splat=off
## 输出：_arisu_captures/_role_roll/{模型}_{before|after}_{front|side}.png

const MODELS := [
	["alice", "res://models/Arisu_ext.glb"],
	["yuzu", "res://models/companions/Yuzu.glb"],
	["momoi", "res://models/companions/Momoi.glb"],
	["midori", "res://models/companions/Midori.glb"],
]
const CLIP := "Move_Ing"
## 取整条循环的 30% 处：支撑腿在下方、手臂摆到最开，最容易看出「歪」
const PHASE := 0.30


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(560, 640)

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
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 165, 0)
	fill.light_energy = 0.9
	root.add_child(fill)

	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.05
	cam.far = 200.0
	root.add_child(cam)
	cam.make_current()

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_role_roll")
	DirAccess.make_dir_recursive_absolute(out)

	for row in MODELS:
		var tag := String(row[0])
		var path := String(row[1])
		for mode in ["before", "after"]:
			var scene := (load(path) as PackedScene).instantiate() as Node3D
			root.add_child(scene)
			await process_frame
			await process_frame
			var ap := _find(scene, "AnimationPlayer") as AnimationPlayer
			var sk := _find(scene, "Skeleton3D") as Skeleton3D
			if ap == null or sk == null:
				print("!! %s 缺 AnimationPlayer / Skeleton3D" % tag)
				scene.queue_free()
				continue
			if mode == "after":
				var r1 := PoseFix.fix_run_lean(sk, ap)
				var r2 := PoseFix.fix_head_roll(sk, ap)
				print("[%s] 前倾 %d 帧 / 侧倾 补 %+.2f°（修前 %+.2f° 修后 %+.2f°）" % [
					tag, int(r1["total"]), float(r2["deg"]),
					float(r2["roll_before"]), float(r2["roll_after"])])
			ap.play(CLIP)
			var aabb := _visual_aabb(scene)
			var centre := aabb.get_center()
			var hgt := maxf(aabb.size.y, 0.1)
			ap.seek(ap.get_animation(CLIP).length * PHASE, true)
			for view in ["front", "side"]:
				# 模型脸朝 +Z：正面 = +Z 方向，侧面 = +X 方向
				var off := Vector3(0.0, hgt * 0.30, hgt * 2.1) if view == "front" \
					else Vector3(hgt * 2.1, hgt * 0.30, 0.0)
				cam.global_position = centre + off
				cam.look_at(centre, Vector3.UP)
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				var file := "%s/%s_%s_%s.png" % [out, tag, mode, view]
				root.get_texture().get_image().save_png(file)
				print("  [img] %s" % file)
			scene.queue_free()
			await process_frame

	print("[shot] 输出目录：%s" % out)
	quit(0)


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


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null
