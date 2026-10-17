extends SceneTree
## 探针：**把 Idle 的四个相位贴脸拍出来**，看「右眼半遮瞳孔」到底长什么样。
##
## 为什么要图：数值上左右眼睑的旋转**幅度几乎一样**（20.88° vs 19.13°），
## 但骨尖位置在中段差了 4~8 mm —— 光看数字已经分不清哪边才是「正常」。
##
## 输出 `_arisu_captures/_eyephase/montage.png`：2×2 四张眼周特写（左上→右下 = 时间顺序），
## 每格右下角标相位。同时也逐张存 `t=*.png`。
##
## 用法：godot --path <工程> --script res://scripts/_probe_eye_phases.gd

const MODEL := "res://models/Arisu_ext.glb"
const CLIP := "Normal_Idle"
const PHASES := [0.0, 0.47, 0.93, 1.40]
const OUT_SUB := "_eyephase"
const CELL := Vector2i(360, 260)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = CELL
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	for _i in 4:
		await process_frame
	var sk := _find_skel(inst)
	var ap := _find_anim(inst)
	if sk == null or ap == null:
		print("!! 没有 Skeleton3D / AnimationPlayer")
		quit(1)
		return

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.80, 0.82, 0.86)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.6
	env.environment = e
	root.add_child(env)

	ap.play(CLIP)
	ap.seek(0.0, true)
	for _i in 3:
		await process_frame

	# 相机：正对两眼中点，距离只够装下两只眼
	var pL := _bone_world(sk, "eye_L_1")
	var pR := _bone_world(sk, "eye_R_1")
	var head := _bone_world(sk, "Bip001 Head")
	var mid := (pL + pR) * 0.5
	var right := (pR - pL).normalized()
	var fwd := right.cross(Vector3.UP).normalized()
	if fwd.dot(mid - head) < 0.0:
		fwd = -fwd

	var key := DirectionalLight3D.new()
	key.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), mid + fwd * 2.0)
	key.light_energy = 1.1
	key.shadow_enabled = false
	root.add_child(key)

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.01
	cam.far = 50.0
	root.add_child(cam)
	cam.make_current()
	# 眼睑骨的眼尖在瞳孔**上方**，所以镜头对着「眼心中点再往下 2 cm」
	var aim := mid - Vector3.UP * 0.02
	cam.global_position = aim + fwd * 0.50 + Vector3.UP * 0.01
	cam.look_at(aim, Vector3.UP)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(out)

	var sheet := Image.create(CELL.x * 2, CELL.y * 2, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.12))
	for i in PHASES.size():
		var t := float(PHASES[i])
		ap.seek(t, true)
		for _i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png(out.path_join("t=%.2f.png" % t))
		var dst := Vector2i((i % 2) * CELL.x, (i / 2) * CELL.y)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), dst)
		print("  [img] t=%.2f → %s" % [t, out.path_join("t=%.2f.png" % t)])
	sheet.save_png(out.path_join("montage.png"))
	print("[phase] 拼图 %s" % out.path_join("montage.png"))
	quit(0)


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
		var x := _find_skel(c)
		if x != null:
			return x
	return null


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var x := _find_anim(c)
		if x != null:
			return x
	return null
