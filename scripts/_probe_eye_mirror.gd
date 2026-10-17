extends SceneTree
## 探针：**四种镜像候选各渲一格**，看哪一格「右眼和左眼一样开」。
##
## 为什么必须渲图：数值（骨尖高度）对 1 cm 的短骨不敏感，三种候选差 0.1 mm 量不出来。
##
## ⚠️ 关键手法：`seek()` 写一次姿态后把 `AnimationPlayer.active = false` **关掉**，
##    否则下一帧动画会把我们手写的姿态覆盖掉（前面两版探针都栽在这，
##    量出来「所有候选都没效果」）。
##
## 输出 `_arisu_captures/_eyemirror/montage.png`：四格 = 原样 / m1 / m2 / m3，
## 相位固定 t=0.93（左右差最大的那一帧）。
##
## 用法：godot --path <工程> --script res://scripts/_probe_eye_mirror.gd

const MODEL := "res://models/Arisu_ext.glb"
const CLIP := "Normal_Idle"
const T := 0.93
const OUT_SUB := "_eyemirror"
const CELL := Vector2i(360, 300)

const CANDS := [
	["none", Vector4(1, 1, 1, 1)],
	["m1", Vector4(1, -1, -1, 1)],
	["m2", Vector4(-1, 1, -1, 1)],
	["m3", Vector4(-1, -1, 1, 1)],
]


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
	ap.seek(T, true)
	for _i in 3:
		await process_frame

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
	# ⚠️ **正对脸**：用「眼轴 × 上」算出来的是斜视角，会把远侧那只眼压扁，
	#    看着就像「半闭」—— 那是**透视**，不是眼睑。模型 rotation.y = 0 时脸朝世界 +Z。
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.17
	cam.near = 0.01
	cam.far = 50.0
	root.add_child(cam)
	cam.make_current()
	var aim := mid - Vector3.UP * 0.012
	cam.global_position = aim + Vector3(0, 0, 0.6)
	cam.look_at(aim, Vector3.UP)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(out)
	var sheet := Image.create(CELL.x * 2, CELL.y * 2, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.12))

	var li1 := _bone(sk, "eye_L_1")
	var ri1 := _bone(sk, "eye_R_1")
	var li2 := _bone(sk, "eye_L_2")
	var ri2 := _bone(sk, "eye_R_2")
	if li1 < 0 or ri1 < 0:
		print("!! 找不到眼睑骨")
		quit(1)
		return

	for i in CANDS.size():
		var tag := String(CANDS[i][0])
		var f: Vector4 = CANDS[i][1]
		ap.active = true
		ap.play(CLIP)
		ap.seek(T, true)
		await process_frame
		# 关键：写完就关，别让下一帧动画覆盖
		ap.active = false
		for pr in [[li1, ri1], [li2, ri2]]:
			if int(pr[0]) < 0 or int(pr[1]) < 0:
				continue
			var q := sk.get_bone_pose_rotation(int(pr[0]))
			sk.set_bone_pose_rotation(int(pr[1]),
				Quaternion(q.x * f.x, q.y * f.y, q.z * f.z, q.w * f.w).normalized())
		sk.force_update_all_bone_transforms()
		for _i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png(out.path_join("%s.png" % tag))
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL),
			Vector2i((i % 2) * CELL.x, (i / 2) * CELL.y))
		print("  [img] %s → %s" % [tag, out.path_join("%s.png" % tag)])

	sheet.save_png(out.path_join("montage.png"))
	print("[mirror] 拼图 %s（左上 none / 右上 m1 / 左下 m2 / 右下 m3）"
		% out.path_join("montage.png"))
	quit(0)


func _bone(sk: Skeleton3D, name: String) -> int:
	var i := sk.find_bone(name)
	if i >= 0:
		return i
	for b in sk.get_bone_count():
		if String(sk.get_bone_name(b)).to_lower().contains(name.to_lower()):
			return b
	return -1


func _bone_world(sk: Skeleton3D, bone: String) -> Vector3:
	var i := _bone(sk, bone)
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
