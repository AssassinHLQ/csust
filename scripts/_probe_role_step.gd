extends SceneTree
## 诊断探针：小桃的跑姿，**分步**加到哪一步坏掉。
##
## 变体：raw（不修）/ lean（只收前倾）/ lean+roll（再加侧倾修正）
## 每个变体都渲正面 + 侧面，并用「眼睛中点 − 头骨原点」当脸的朝向，
## 量一组**不依赖骨骼局部轴约定**的角度：
##     roll  = asin(right.y)            右耳抬高为正
##     pitch = asin(face · UP)          抬头为正（低头为负）
##
## 用法：godot --path <工程> --script res://scripts/_probe_role_step.gd -- --splat=off
## 输出：_arisu_captures/_role_step/{变体}_{front|side}.png

const MODEL := "res://models/companions/Momoi.glb"
const CLIP := "Move_Ing"
const PHASE := 0.30


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(520, 620)
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
	cam.fov = 40.0
	cam.near = 0.05
	root.add_child(cam)
	cam.make_current()

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_role_step")
	DirAccess.make_dir_recursive_absolute(out)

	# ⚠️ 三个变体必须用**三份独立的资源**：`_apply_delta` 改的是 Animation 对象本身，
	#    同一份 glb 反复 instancing 拿到的是**同一个** Animation（资源缓存），
	#    所以「raw」必须最先拍，否则拍到的是已经修过的数据。
	for variant in ["raw", "lean", "lean_roll"]:
		var scene := (load(MODEL) as PackedScene).instantiate() as Node3D
		root.add_child(scene)
		await process_frame
		await process_frame
		var ap := _find(scene, "AnimationPlayer") as AnimationPlayer
		var sk := _find(scene, "Skeleton3D") as Skeleton3D
		if variant != "raw":
			var r1 := PoseFix.fix_run_lean(sk, ap)
			print("[%s] 前倾 %d 帧" % [variant, int(r1["total"])])
		if variant == "lean_roll":
			var r2 := PoseFix.fix_head_roll(sk, ap)
			print("[%s] 侧倾 %+.2f°（修前 %+.2f° 修后 %+.2f°）" % [variant,
				float(r2["deg"]), float(r2["roll_before"]), float(r2["roll_after"])])
		ap.play(CLIP)
		ap.seek(ap.get_animation(CLIP).length * PHASE, true)
		await process_frame
		await process_frame
		sk.force_update_all_bone_transforms()
		var m := _face_angles(sk)
		print("[%s] roll %+.2f°  pitch %+.2f°" % [variant, float(m["roll"]),
			float(m["pitch"])])
		var aabb := _visual_aabb(scene)
		var centre := aabb.get_center()
		var hgt := maxf(aabb.size.y, 0.1)
		for view in ["front", "side"]:
			var off := Vector3(0.0, hgt * 0.30, hgt * 2.0) if view == "front" \
				else Vector3(hgt * 2.0, hgt * 0.30, 0.0)
			cam.global_position = centre + off
			cam.look_at(centre, Vector3.UP)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var file := "%s/%s_%s.png" % [out, variant, view]
			root.get_texture().get_image().save_png(file)
			print("  [img] %s" % file)
		scene.queue_free()
		await process_frame
	quit(0)


## 脸的朝向 = 眼睛中点 − 头骨原点；左右轴 = 右眼 − 左眼。全部换到世界空间。
func _face_angles(sk: Skeleton3D) -> Dictionary:
	var out := {"roll": 0.0, "pitch": 0.0}
	var eL := sk.find_bone("Bip001 eye_L")
	var eR := sk.find_bone("Bip001 eye_R")
	var hd := sk.find_bone("Bip001 Head")
	if eL < 0 or eR < 0 or hd < 0:
		return out
	var xf := sk.global_transform
	var pl: Vector3 = xf * sk.get_bone_global_pose(eL).origin
	var pr: Vector3 = xf * sk.get_bone_global_pose(eR).origin
	var ph: Vector3 = xf * sk.get_bone_global_pose(hd).origin
	var right := (pr - pl).normalized()
	var face := ((pl + pr) * 0.5 - ph).normalized()
	out["roll"] = rad_to_deg(asin(clampf(right.y, -1.0, 1.0)))
	out["pitch"] = rad_to_deg(asin(clampf(face.y, -1.0, 1.0)))
	return out


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
