extends SceneTree
## 探针：**眼睑动画到底写在哪根骨上，左右差多少**。
##
## 背景：用户报「右眼上眼睑掉下来半遮瞳孔，镜像开也没感觉到」。
## 上一版把 `eye_R_1/2` 抄到 `eye_L_1/2`（`PoseFix.EYELID_PAIRS`），但量出来
## 左右眼睑尖的高度差几乎不变（-6.56 → -6.44 mm）—— 说明**抄错骨了**。
##
## 这个探针把 24 根名字带 eye/lid 的骨全扫一遍：
##   · 每条动画里它有没有 **rotation 轨道**（有轨道的骨才是动画真正写的那种）；
##   · 在 `Normal_Idle` 上采 16 个相位，算「局部旋转相对静置」的**变化范围（度）**；
##   · 左 / 右成对并排，一眼看出哪一对是「左边动、右边不动」。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_eyelids.gd

const MODEL := "res://models/Arisu_ext.glb"
const CLIPS := ["Normal_Idle", "Move_Ing"]
const SAMPLES := 16
const KEYWORDS := ["eye", "lid"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var sk := _find_skel(inst)
	var ap := _find_anim(inst)
	if sk == null or ap == null:
		print("!! 没有 Skeleton3D / AnimationPlayer")
		quit(1)
		return

	var bones: Array[int] = []
	for i in sk.get_bone_count():
		var n := String(sk.get_bone_name(i)).to_lower()
		for k in KEYWORDS:
			if n.contains(k):
				bones.append(i)
				break

	# 每条动画里这些骨的旋转轨道情况
	var tracks := {}
	for clip in CLIPS:
		if not ap.has_animation(clip):
			continue
		var a := ap.get_animation(clip)
		var have := {}
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var path := String(a.track_get_path(t))
			have[path.substr(path.rfind(":") + 1)] = true
		tracks[clip] = have

	print("[lid] 名字带 eye/lid 的骨 %d 根" % bones.size())
	print("\n%-24s %-8s %-8s %-10s %s" % ["骨", "Idle范围°", "Move范围°", "有轨道(Idle)", "静置角°"])

	# 每条动画上的旋转变化范围（度）
	var ranges := {}
	for clip in CLIPS:
		if not ap.has_animation(clip):
			continue
		var a := ap.get_animation(clip)
		ap.play(clip)
		var lo := {}
		var hi := {}
		for i in bones:
			var rest := sk.get_bone_rest(i).basis.get_rotation_quaternion()
			lo[i] = 999.0
			hi[i] = -999.0
		for k in SAMPLES:
			ap.seek(a.length * float(k) / float(SAMPLES), true)
			await process_frame
			for i in bones:
				var rest := sk.get_bone_rest(i).basis.get_rotation_quaternion()
				var q := sk.get_bone_pose_rotation(i)
				var d := rad_to_deg(q.angle_to(rest))
				lo[i] = minf(float(lo[i]), d)
				hi[i] = maxf(float(hi[i]), d)
		var r := {}
		for i in bones:
			r[i] = float(hi[i]) - float(lo[i])
		ranges[clip] = r

	var idle_have: Dictionary = tracks.get("Normal_Idle", {})
	print()
	for i in bones:
		var name := String(sk.get_bone_name(i))
		var ridle := float(ranges.get("Normal_Idle", {}).get(i, 0.0))
		var rmove := float(ranges.get("Move_Ing", {}).get(i, 0.0))
		print("%-24s %8.2f %8.2f  %-6s %6.1f" % [
			name, ridle, rmove, ("有轨道" if idle_have.has(name) else "**没有**"),
			rad_to_deg(sk.get_bone_rest(i).basis.get_rotation_quaternion().get_angle())])

	# 成对的直接给差值
	print("\n===== 左右成对（名字里的 L/R 互换）=====")
	for i in bones:
		var name := String(sk.get_bone_name(i))
		var other := ""
		if name.contains("_L"):
			other = name.replace("_L", "_R")
		elif name.contains("_R"):
			other = name.replace("_R", "_L")
		elif name.contains("eyeblowL"):
			other = name.replace("eyeblowL", "eyeblowR")
		elif name.contains("eyeblowR"):
			other = name.replace("eyeblowR", "eyeblowL")
		elif name.contains("eyeL"):
			other = name.replace("eyeL", "eyeR")
		elif name.contains("eyeR"):
			other = name.replace("eyeR", "eyeL")
		if other.is_empty():
			continue
		var j := sk.find_bone(other)
		if j < 0 or j < i:
			continue
		var a1 := float(ranges.get("Normal_Idle", {}).get(i, 0.0))
		var a2 := float(ranges.get("Normal_Idle", {}).get(j, 0.0))
		print("  %-22s %7.2f   vs  %-22s %7.2f   差 %+6.2f°" % [
			name, a1, other, a2, a1 - a2])
	quit(0)


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
