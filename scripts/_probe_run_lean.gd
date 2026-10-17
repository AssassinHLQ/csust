extends SceneTree
## 探针：量跑步动作（`Move_Ing`）的**前倾**与**侧倾**，判断「感觉还是有点斜」到底是哪一种。
##
## 为什么要分开量：
##   前倾（pitch，绕 X）= 跑步该有的前扑，靠**改动作数据**减小（§5.4 已经减过一轮）；
##   侧倾（roll，绕 Z）= 身体左右歪，那是**动作本身有问题**，跟相机无关；
##   两种在背后视角的截图里都长成「人往一边倒」，但修法完全不同。
##
## 量的是骨架局部空间里「骨盆 → 颈」这条弦，以及 Spine1 的上轴：
##     pitch = atan2(d.z, d.y)   （模型脸朝 +Z，向前为正）
##     roll  = atan2(d.x, d.y)   （向右为正）
##
## 用法：
##   & $godot --headless --path <工程> --script res://scripts/_probe_run_lean.gd

const MODEL := "res://models/Arisu_ext.glb"
const SAMPLE := 24

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("================ 跑步姿态：前倾 vs 侧倾 ================")
	print("模型：%s" % MODEL)
	print("")
	print("%-12s %-26s %-26s %-22s" % ["clips", "躯干 pitch 均值/峰值", "躯干 roll 均值/峰值", "Spine1 上轴 roll"])
	print("-------------------------- -------------------------- -------------------------- ----------------------")

	var scene: Node = load(MODEL).instantiate()
	root.add_child(scene)
	await process_frame
	var skel := _find_first(scene, "Skeleton3D") as Skeleton3D
	var ap := _find_player(scene)
	if skel == null or ap == null:
		print("!! 找不到骨架或 AnimationPlayer")
		quit(1)
		return

	var pel := skel.find_bone("Bip001 Pelvis")
	var s1 := skel.find_bone("Bip001 Spine1")
	var neck := skel.find_bone("Bip001 Neck")
	print("骨骼索引  pelvis=%d spine1=%d neck=%d" % [pel, s1, neck])
	if "--fix" in OS.get_cmdline_user_args():
		var rep := PoseFix.fix_run_lean(skel, ap)
		print("已应用 PoseFix：changed=%s 关键帧=%d" % [rep["applied"], rep["total"]])
		for b in rep["bones"]:
			print("   %-16s %+5.1f°  轴 %s  帧 %d" % [b, rep["bones"][b]["deg"],
				rep["bones"][b]["axis"], rep["bones"][b]["keys"]])
		if not rep["missing"].is_empty():
			print("   缺失：%s" % str(rep["missing"]))
	print("")

	# 逐段拆开看「前倾是哪一段贡献的」：骨盆→脊椎→胸→颈，一环一环量。
	var sp := skel.find_bone("Bip001 Spine")
	var head := skel.find_bone("Bip001 Head")
	print("分段前倾（pitch，正 = 向前）：")
	print("%-12s %-10s %-10s %-10s %-10s %-10s" % ["clip", "pelvis", "pel-spine", "sp-spine1", "spine1-neck", "neck-head"])
	for clip in ["Normal_Idle", "Move_Ing"]:
		if not ap.has_animation(clip):
			continue
		ap.play(clip)
		var length := ap.get_animation(clip).length
		var sums := [0.0, 0.0, 0.0, 0.0, 0.0]
		for i in SAMPLE:
			ap.seek(length * float(i) / float(SAMPLE), true)
			await process_frame
			var xf := skel.global_transform
			var p: Vector3 = xf * skel.get_bone_global_pose(pel).origin
			var s: Vector3 = xf * skel.get_bone_global_pose(sp).origin
			var s1p: Vector3 = xf * skel.get_bone_global_pose(s1).origin
			var n: Vector3 = xf * skel.get_bone_global_pose(neck).origin
			var h: Vector3 = xf * skel.get_bone_global_pose(head).origin
			sums[1] += _seg(p, s)
			sums[2] += _seg(s, s1p)
			sums[3] += _seg(s1p, n)
			sums[4] += _seg(n, h)
		print("%-12s %-10s %+9.1f° %+9.1f° %+9.1f° %+9.1f°" % [
			clip, "—", sums[1] / SAMPLE, sums[2] / SAMPLE, sums[3] / SAMPLE, sums[4] / SAMPLE])
	print("")

	for clip in ["Normal_Idle", "Move_Ing", "Cafe_Walk"]:
		if not ap.has_animation(clip):
			print("%-12s 没有这条动作" % clip)
			continue
		ap.play(clip)
		var length := ap.get_animation(clip).length
		var pitch := PackedFloat32Array()
		var roll := PackedFloat32Array()
		var s1_roll := PackedFloat32Array()
		var s1_pitch := PackedFloat32Array()
		for i in SAMPLE:
			ap.seek(length * float(i) / float(SAMPLE), true)
			await process_frame
			var xf := skel.global_transform
			var p: Vector3 = xf * skel.get_bone_global_pose(pel).origin
			var n: Vector3 = xf * skel.get_bone_global_pose(neck).origin
			var d := n - p
			pitch.append(rad_to_deg(atan2(d.z, d.y)))
			roll.append(rad_to_deg(atan2(d.x, d.y)))
			var up: Vector3 = (xf.basis * skel.get_bone_global_pose(s1).basis.y).normalized()
			s1_roll.append(rad_to_deg(atan2(up.x, up.y)))
			s1_pitch.append(rad_to_deg(atan2(up.z, up.y)))
		print("%-12s %+7.1f° / %+7.1f°      %+7.1f° / %+7.1f°      %+7.1f° / %+7.1f°" % [
			clip, _mean(pitch), _peak(pitch), _mean(roll), _peak_abs(roll),
			_mean(s1_roll), _peak_abs(s1_roll)])
		print("             Spine1 pitch %+6.1f° / %+6.1f°   站直参考：Idle 的 pitch 应接近 0"
			% [_mean(s1_pitch), _peak(s1_pitch)])

	print("")
	print("—— 判读 ——")
	print("  roll 均值 < 3°  ⇒ 不是「左右歪」，是跑步应有的前倾，只能改动作数据")
	print("  roll 峰值 > 8°  ⇒ 动作里真的有左右晃，需要单独处理")
	scene.queue_free()
	await process_frame
	quit(1 if _fail else 0)


## 一段骨链的「向前」倾角：a→b 相对竖直，向 +Z（脸的方向）为正
func _seg(a: Vector3, b: Vector3) -> float:
	var d := b - a
	if Vector2(d.z, d.y).length() < 0.0001:
		return 0.0
	return rad_to_deg(atan2(d.z, d.y))


func _mean(v: PackedFloat32Array) -> float:
	if v.is_empty():
		return 0.0
	var s := 0.0
	for x in v:
		s += x
	return s / float(v.size())


func _peak(v: PackedFloat32Array) -> float:
	var m := -999.0
	for x in v:
		m = maxf(m, x)
	return m


func _peak_abs(v: PackedFloat32Array) -> float:
	var m := 0.0
	for x in v:
		m = maxf(m, absf(x))
	return m


func _find_first(n: Node, cls: String) -> Node:
	if n == null:
		return null
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find_first(c, cls)
		if r != null:
			return r
	return null


func _find_player(n: Node) -> AnimationPlayer:
	if n == null:
		return null
	if n is AnimationPlayer and n.has_animation("Normal_Idle"):
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r != null:
			return r
	return null
