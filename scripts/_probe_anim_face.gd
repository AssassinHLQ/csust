extends SceneTree
## 探针：把爱丽丝的**头和脸**放到画面中间，逐帧看
##   ① 待机（`Normal_Idle`）的「双眼皮打架」到底长什么样；
##   ② 跑步（`Move_Ing`）的头到底歪在哪（俯 / 偏 / 侧倾，各多少度）。
##
## 光看全身图判断不了「头歪」—— 得把数字打出来：把 `Bip001 Head` 的
## 骨骼全局姿势拆成 pitch / yaw / roll，和静止姿势比。
##
## 用法：godot --path <工程> --script res://scripts/_probe_anim_face.gd
## 输出：_arisu_captures/_face/{clip}_{t}.png

const MODEL := "res://models/Arisu_ext.glb"
const CLIPS := ["Normal_Idle", "Move_Ing"]
const TIMES := [0.4, 1.2, 2.0, 2.8]
const OUT := "_arisu_captures/_face"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(640, 640)
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var sk := _find_skel(inst)
	var ap := _find_anim(inst)
	if sk == null or ap == null:
		print("!! 模型里缺骨架或 AnimationPlayer")
		quit(1)
		return

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.88, 0.92)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.8
	env.environment = e
	root.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25, 25, 0)
	key.light_energy = 1.0
	root.add_child(key)

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.02
	root.add_child(cam)
	cam.make_current()

	if "--fix" in OS.get_cmdline_user_args():
		PoseFix.fix_run_lean(sk, ap)
		if "--noroll" not in OS.get_cmdline_user_args():
			PoseFix.fix_head_roll(sk, ap)
		PoseFix.fix_eyelid_sync(sk, ap)
		print("[face] 已套 PoseFix%s" % ("（不含侧倾）" if "--noroll" in OS.get_cmdline_user_args() else ""))

	var head := sk.find_bone("Bip001 Head")
	var neck := sk.find_bone("Bip001 Neck")
	if head < 0:
		print("!! 找不到 Bip001 Head")
		quit(1)
		return
	var rest_head := sk.get_bone_global_rest(head).basis.orthonormalized()

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out)

	for clip in CLIPS:
		if not ap.has_animation(clip):
			print("!! 没有动画 %s" % clip)
			continue
		ap.play(clip)
		ap.speed_scale = 1.0
		print("\n===== %s（%.2f s）=====" % [clip, ap.get_animation(clip).length])
		for t in TIMES:
			ap.seek(float(t), true)
			sk.force_update_all_bone_transforms()
			await process_frame
			sk.force_update_all_bone_transforms()

			var pos: Vector3 = sk.global_transform * sk.get_bone_global_pose(head).origin
			var cur: Basis = sk.get_bone_global_pose(head).basis.orthonormalized()
			var d := rest_head.inverse() * cur
			var eul := d.get_euler()          # 骨架空间里的 (x=俯仰, y=偏航, z=侧倾)
			var npos: Vector3 = sk.global_transform * sk.get_bone_global_pose(neck).origin
			var head_up := (pos - npos).normalized()
			print("  t=%.1f 头骨 euler 俯 %+.1f° 偏 %+.1f° 侧 %+.1f°   头到颈向量 %s" % [
				float(t), rad_to_deg(eul.x), rad_to_deg(eul.y), rad_to_deg(eul.z),
				str(head_up.snappedf(0.01))])

			# 3/4 正面 + 侧面两张
			var aim := pos
			await _shoot(cam, pos + Vector3(0.42, 0.06, 0.78), aim,
				out.path_join("%s_%.1f_f.png" % [clip, float(t)]))
			await _shoot(cam, pos + Vector3(0.86, 0.05, 0.06), aim,
				out.path_join("%s_%.1f_s.png" % [clip, float(t)]))
	print("\n[sensei] 输出 %s" % out)
	quit(0)


func _shoot(cam: Camera3D, from: Vector3, at: Vector3, file: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)


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
