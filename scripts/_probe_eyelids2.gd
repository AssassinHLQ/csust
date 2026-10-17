extends SceneTree
## 探针：**镜像公式三选一，让眼睑尖的实际高度投票**。
##
## 已知（`_probe_eyelids.gd` 骨扫描）：
##   · `eye_L_1` / `eye_R_1` 的旋转**幅度一样**（Idle 20.88° vs 19.13°），
##     但眼睑尖在头空间里差了 **7 mm**：左 (+0.036,+0.076,+0.041) / 右 (+0.078,+0.069,−0.036)。
##   ⇒ 不是「只驱动了一只眼」，而是**镜像骨吃了同样的局部旋转** → 一只开、一只合。
##
## 修法是把左眼的局部旋转按正确的镜像公式抄给右眼。四元数镜像有三种候选
##   m1 = ( x, −y, −z,  w)   m2 = (−x,  y, −z,  w)   m3 = (−x, −y,  z,  w)
## 哪个对不靠推公式，靠量：抄完看右眼尖能不能对上左眼（镜像是 z 翻转）。
##
## ⚠️ 两个坑（都踩过）：
##   1. **不要用 `set_bone_pose_rotation()` 试**：`AnimationPlayer` 每帧把姿态写回去，
##      手动设的值活不过一帧（第一版量出来「三种候选全没效果」就是这么来的）。
##      正确做法是**改动画数据**，让它按正常管线播放。
##   2. 本版本的 `AnimationMixer` 没有 `ANIMATION_PROCESS_MANUAL` 这个枚举，
##      所以也别想着去关自动更新。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_eyelids2.gd

const MODEL := "res://models/Arisu_ext.glb"
const CLIP := "Normal_Idle"
const T := 0.93          ## 左右差最大的相位（`_probe_eyelids.gd` 量的）

var _sk: Skeleton3D
var _ap: AnimationPlayer
var _orig: Animation


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	_sk = _find_skel(inst)
	_ap = _find_anim(inst)
	if _sk == null or _ap == null:
		print("!! 没有 Skeleton3D / AnimationPlayer")
		quit(1)
		return
	_orig = _ap.get_animation(CLIP).duplicate(true)

	print("[lid2] 相位 t=%.2f —— 眼睑尖（头空间：x=前后 y=上下 z=左右，单位 m）" % T)
	await _play_original()
	_show("原样")

	var cands := [
		["m1(x,-y,-z,w)", Vector4(1, -1, -1, 1)],
		["m2(-x,y,-z,w)", Vector4(-1, 1, -1, 1)],
		["m3(-x,-y,z,w)", Vector4(-1, -1, 1, 1)],
	]
	for c in cands:
		var a: Animation = _orig.duplicate(true)
		var n1 := _mirror_track(a, "eye_L_1", "eye_R_1", c[1])
		var n2 := _mirror_track(a, "eye_L_2", "eye_R_2", c[1])
		_install(a)
		await _play_original()
		_show("%s (%d/%d 帧)" % [String(c[0]), n1, n2])

	# 反向对照：旧代码的方向（右 → 左）
	var b: Animation = _orig.duplicate(true)
	var m1 := _mirror_track(b, "eye_R_1", "eye_L_1", Vector4(1, -1, -1, 1))
	var m2 := _mirror_track(b, "eye_R_2", "eye_L_2", Vector4(1, -1, -1, 1))
	_install(b)
	await _play_original()
	_show("旧方向 R→L (%d/%d 帧)" % [m1, m2])

	print("\n[lid2] 目标：右眼尖 ≈ 左眼尖的 z 镜像 ⇒ |Δy| 与 |Δx| 都该接近 0")
	quit(0)


func _play_original() -> void:
	_ap.play(CLIP)
	_ap.seek(T, true)
	await process_frame
	await process_frame
	_sk.force_update_all_bone_transforms()


func _install(a: Animation) -> void:
	var lib := _ap.get_animation_library(&"")
	if lib == null:
		return
	lib.remove_animation(CLIP)
	lib.add_animation(CLIP, a)


## 把 `from_bone` 的旋转轨道按 `f` 镜像写进 `to_bone`，返回写了多少帧。
func _mirror_track(a: Animation, from_bone: String, to_bone: String, f: Vector4) -> int:
	var src := _find_rot(a, from_bone)
	if src < 0:
		return 0
	var dst := _find_rot(a, to_bone)
	var path := String(a.track_get_path(src))
	var head := path.substr(0, path.rfind(":"))
	if dst < 0:
		dst = a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(dst, NodePath(head + ":" + to_bone))
	else:
		while a.track_get_key_count(dst) > 0:
			a.track_remove_key(dst, a.track_get_key_count(dst) - 1)
	for k in a.track_get_key_count(src):
		var q: Quaternion = a.track_get_key_value(src, k)
		var m := Quaternion(q.x * f.x, q.y * f.y, q.z * f.z, q.w * f.w).normalized()
		a.track_insert_key(dst, a.track_get_key_time(src, k), m)
	return a.track_get_key_count(src)


func _find_rot(a: Animation, bone: String) -> int:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var path := String(a.track_get_path(t))
		if path.substr(path.rfind(":") + 1) == bone or path.ends_with(bone):
			return t
	return -1


func _tips() -> Dictionary:
	var out := {}
	var head := _bone("Bip001 Head")
	if head < 0:
		return out
	var inv := (_sk.global_transform * _sk.get_bone_global_pose(head)).affine_inverse()
	for nm in ["eye_L_1", "eye_R_1"]:
		var i := _bone(nm)
		if i < 0:
			continue
		var w := _sk.global_transform * _sk.get_bone_global_pose(i)
		out[nm] = inv * (w * Vector3(0, 0.01, 0))
	return out


func _show(tag: String) -> void:
	var t := _tips()
	var l: Vector3 = t.get("eye_L_1", Vector3.ZERO)
	var r: Vector3 = t.get("eye_R_1", Vector3.ZERO)
	# 右眼应该等于左眼的 z 镜像
	print("  %-22s L(%+.3f,%+.3f,%+.3f)  R(%+.3f,%+.3f,%+.3f)   Δx=%+6.2f  Δy=%+6.2f mm" % [
		tag, l.x, l.y, l.z, r.x, r.y, r.z, (r.x - l.x) * 1000.0, (r.y - l.y) * 1000.0])


func _bone(name: String) -> int:
	var i := _sk.find_bone(name)
	if i >= 0:
		return i
	for b in _sk.get_bone_count():
		if String(_sk.get_bone_name(b)).to_lower().contains(name.to_lower()):
			return b
	return -1


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
