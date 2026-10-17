extends SceneTree
## 探针：**「眼皮还在动」是哪个骨在动**。
##
## 用户 2026-10-18：「最后为什么眼皮还在动，之前不是都删眼睛那儿的动画了吗」。
##
## 已知（`_verify_blink.gd` 守着）：`PoseFix.freeze_eyelids()` 删掉了
## `Bip001 eye_L_1 / eye_L_2 / eye_R_1 / eye_R_2` **四根骨的全部轨道**，
## 真播 2 秒时这四根骨的局部旋转一动不动。
## 但脸上一共 **24 根**「眼 / 眉 / 睫毛」骨，`_probe_blink_src.gd` 列出来的
## 每一根都是 54 条轨道 —— 冻结只盖住了其中四根。
##
## 这个探针把「相对头骨」的旋转逐帧量出来，按幅度排序：
##   · 幅度 < 1°   → 不动（说明冻结有效）
##   · 幅度 > 3°   → 它就是用户看到的「还在动」的那个
##
## 用法：
##   godot --path <工程> --headless --script res://scripts/_probe_face_motion.gd -- --splat=off
## 只读。

## 要量的骨：名字里带这些片段的都算「脸」
const FACE_KW := ["eye", "eyering", "eyeblow", "brow", "lash", "mabuta", "head",
	"neck", "jaw", "mouth", "face", "cheek", "target"]
const CLIPS := ["Normal_Idle", "Cafe_Walk", "Move_Ing"]
const FRAMES := 150


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(640, 360)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 12:
		await process_frame
	paused = false
	var p := game.get_node_or_null("Player") as Player
	if p == null or p.anim == null:
		print("!! 没有 Player/AnimDriver")
		quit(1)
		return
	var anim := p.anim as AnimDriver
	var sk := anim.skeleton
	p.set_physics_process(false)
	print("=== 冻结报告：tracks=%d / 动作 %d 个，missing=%s ===" % [
		int(anim.blink_fix.get("tracks", 0)),
		(anim.blink_fix.get("clips", []) as Array).size(),
		str(anim.blink_fix.get("missing", []))])

	var head := sk.find_bone("Bip001 Head")
	if head < 0:
		head = sk.find_bone("Bip001 Neck")
	print("头骨 = %s (%d)\n" % [sk.get_bone_name(head) if head >= 0 else "?", head])

	for clip in CLIPS:
		if not anim.player.has_animation(String(clip)):
			continue
		anim.reset_state()
		anim.player.play(String(clip), 0.0, 1.0)
		# 先走两帧让姿势稳定
		for _i in 4:
			await process_frame
		var base := {}
		var base_s := {}
		var base_p := {}
		var names := _face_bones(sk)
		for i in names:
			base[i] = _rel(sk, i, head)
			base_s[i] = sk.get_bone_pose_scale(i)
			base_p[i] = sk.get_bone_pose_position(i)
		var peak := {}
		var peak_s := {}
		var peak_p := {}
		for i in names:
			peak[i] = 0.0
			peak_s[i] = 0.0
			peak_p[i] = 0.0
		for _f in FRAMES:
			await process_frame
			for i in names:
				var d: float = rad_to_deg((base[i] as Quaternion).angle_to(_rel(sk, i, head)))
				if d > float(peak[i]):
					peak[i] = d
				# ⚠️ 眨眼不一定靠**旋转**：很多素材是把眼球骨（`eye_L`）的 **scale** 压扁，
				#    只量旋转会漏掉整整一类眨眼。
				var sc: Vector3 = sk.get_bone_pose_scale(i)
				var sd: float = maxf(maxf(absf(sc.x - 1.0), absf(sc.y - 1.0)), absf(sc.z - 1.0))
				sd = maxf(sd, (sc - (base_s[i] as Vector3)).length())
				if sd > float(peak_s[i]):
					peak_s[i] = sd
				var pd: float = (sk.get_bone_pose_position(i) - (base_p[i] as Vector3)).length()
				if pd > float(peak_p[i]):
					peak_p[i] = pd
		var rows := []
		for i in names:
			rows.append([float(peak[i]) + float(peak_s[i]) * 100.0 + float(peak_p[i]) * 100.0, i])
		rows.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
		print("[%s] %.2f s —— 相对头骨的最大旋转（%d 帧）" % [clip,
			anim.player.get_animation(String(clip)).length, FRAMES])
		var shown := 0
		for r in rows:
			if float(r[0]) < 0.5 and shown >= 6:
				continue
			var i2 := int(r[1])
			print("    %6.2f°  scale 差 %.3f  pos 差 %.4f m  %s" % [float(peak[i2]),
				float(peak_s[i2]), float(peak_p[i2]), sk.get_bone_name(i2)])
			shown += 1
			if shown >= 14:
				break
		print("")
	quit(0)


## 相对头骨的局部旋转（把头的世界旋转除掉，只剩「脸上自己转了多少」）
func _rel(sk: Skeleton3D, i: int, head: int) -> Quaternion:
	if head < 0:
		return sk.get_bone_pose_rotation(i)
	var w := sk.get_bone_global_pose(i).basis.get_rotation_quaternion()
	var h := sk.get_bone_global_pose(head).basis.get_rotation_quaternion()
	return h.inverse() * w


func _face_bones(sk: Skeleton3D) -> Array:
	var out := []
	for i in sk.get_bone_count():
		var low := sk.get_bone_name(i).to_lower()
		for k in FACE_KW:
			if low.contains(String(k)):
				out.append(i)
				break
	return out
