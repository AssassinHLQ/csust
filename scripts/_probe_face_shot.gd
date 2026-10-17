extends SceneTree
## 探针：**只加载模型**，把脸上那几种修法各出一张图，一次跑完三种组合。
##
## 为什么不在 `game.tscn` 里拍：`anim_driver` 一 `_ready()` 就把修法都吃进去了，
## 事后再想「如果没修会怎样」已经来不及（网格重建是不可逆的）。只有单独加载
## `Arisu_ext.glb`、自己决定打不打补丁，才能做真正的 A/B。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_face_shot.gd -- [--splat=off]
##
## 输出（`_arisu_captures/_face/`）：
##   raw.png          原样
##   facefix.png      只推脸皮/眼睛层（跳过带形态键的嘴）
##   facefix_lid.png  再叠上眼睑镜像
##   mouth.png        嘴部特写（验「只有一张嘴」）

const MODEL := "res://models/Arisu_ext.glb"
const CLIP := "Normal_Idle"
const SEEK := 0.8
const OUT_DIR := "_arisu_captures/_face"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(720, 820)
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	for _i in 4:
		await process_frame

	# 亮背景 + 环境光：贴脸看细节，别让场景的「夕阳」把脸压成一块黑
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.80, 0.82, 0.86)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.6
	env.environment = e
	root.add_child(env)

	var ap := _find_anim(inst)
	var sk := _find_skel(inst)
	if ap == null or sk == null:
		print("!! 模型里没有 AnimationPlayer / Skeleton3D")
		quit(1)
		return
	ap.play(CLIP)
	ap.seek(SEEK, true)
	for _i in 4:
		await process_frame

	# 脸朝哪：左右眼骨给横轴，横轴 × 世界上 = 脸法线；正负号用「眼睛在头骨前面」定
	var hl := _bone_world(sk, "eye_L_1")
	var hr := _bone_world(sk, "eye_R_1")
	var head := _bone_world(sk, "Bip001 Head")
	if not hl.is_finite() or not hr.is_finite() or not head.is_finite():
		print("!! 找不到眼骨 / 头骨")
		quit(1)
		return
	var mid: Vector3 = (hl + hr) * 0.5
	var right: Vector3 = (hr - hl).normalized()
	var fwd: Vector3 = right.cross(Vector3.UP).normalized()
	if fwd.dot(mid - head) < 0.0:
		fwd = -fwd
	print("[face] 眼距 %.3f m  脸法线 %s  眼心 %s" % [
		hl.distance_to(hr), str(fwd.snappedf(0.01)), str(mid.snappedf(0.01))])

	var key := DirectionalLight3D.new()
	key.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), mid + fwd * 2.0)
	key.light_energy = 1.15
	key.shadow_enabled = false
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	var side: Vector3 = right.cross(fwd).normalized()
	fill.global_transform = Transform3D(
		Basis.looking_at(-(fwd * 0.5 + side * 0.85).normalized(), Vector3.UP), mid + side)
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	root.add_child(fill)

	var cam := Camera3D.new()
	cam.fov = 28.0
	cam.near = 0.01
	cam.far = 100.0
	root.add_child(cam)
	cam.make_current()

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	# ── 变体 1：原样 ──
	_report(inst, "raw")
	await _shoot(cam, mid, fwd, 0.62, out.path_join("raw.png"))

	# ── 变体 2：只推脸皮/眼睛层（嘴跳过）──
	var rep := FaceFix.separate_face_layers(inst)
	print("[face] FaceFix：surface=%d verts=%d meshes=%d **skipped=%d**" % [
		int(rep["surfaces"]), int(rep["verts"]), int(rep["meshes"]), int(rep["skipped"])])
	_report(inst, "facefix")
	await _shoot(cam, mid, fwd, 0.62, out.path_join("facefix.png"))

	# ── 变体 3：再叠眼睑镜像 ──
	var lrep := PoseFix.fix_eyelid_sync(sk, ap)
	print("[face] 眼睑镜像：%s" % str(lrep))
	await _shoot(cam, mid, fwd, 0.62, out.path_join("facefix_lid.png"))

	# ── 嘴特写：只要下半张脸 ──
	await _shoot(cam, mid - Vector3.UP * 0.03, fwd, 0.26, out.path_join("mouth.png"))
	quit(0)


## 逐块报告嘴：形态键还在不在、morph_0 多少（权重 0 = 露在脸上）。
func _report(inst: Node, tag: String) -> void:
	var mouths: Array[MeshInstance3D] = []
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and String(n.name).begins_with("Mouth_"):
			mouths.append(n as MeshInstance3D)
		for c in n.get_children():
			stack.append(c)
	mouths.sort_custom(func(a, b): return a.name < b.name)
	var lost := 0
	var shown := 0
	for mi in mouths:
		var bs: int = 0
		if mi.mesh != null:
			bs = mi.mesh.get_blend_shape_count()
		if bs <= 0:
			lost += 1
		elif mi.get_blend_shape_value(0) < 0.01:
			shown += 1
	print("[face] %-12s 嘴 %d 块：丢形态键 %d、露在脸上 %d（该是 0 / 1）" % [
		tag, mouths.size(), lost, shown])


func _shoot(cam: Camera3D, at: Vector3, fwd: Vector3, dist: float, file: String) -> void:
	cam.global_position = at + fwd * dist + Vector3.UP * 0.01
	cam.look_at(at, Vector3.UP)
	for _i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("  [img] %s" % file)


func _bone_world(sk: Skeleton3D, bone: String) -> Vector3:
	var i := sk.find_bone(bone)
	if i < 0:
		for b in sk.get_bone_count():
			if String(sk.get_bone_name(b)).to_lower().contains(bone.to_lower()):
				i = b
				break
	if i < 0:
		return Vector3.INF
	return sk.global_transform * sk.get_bone_global_pose(i).origin


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null
