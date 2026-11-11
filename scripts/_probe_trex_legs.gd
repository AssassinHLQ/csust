extends SceneTree
## 诊断：霸王龙的腿骨链条、静置朝向，以及「绕哪根局部轴摆腿」。
##
## 背景：GLB 里**没有走路动作**（只有 bite/charge/idle/roar/stomp/tail_sweep），
## 2026-11-11 用户要求「霸王龙要能跑动，追人那种」，所以腿得**程序化**摆。
##
## 摆腿要绕「模型左右轴」（= 世界 X，因为模型脸朝 +Z）。骨头自己的局部坐标系
## 和它是错开的，所以要先把模型 X 轴换算到每根骨的局部空间：
##   axis_local = bone_rest_basis.inverse() * Vector3.RIGHT
##
##   bash _tools/run_probe.sh res://scripts/_probe_trex_legs.gd -- --no-capture --splat=off

const LEVEL := "res://scenes/next_level.tscn"
const BOSS := "TrexBossA"
## 猜的腿骨名（左腿 .013 髋 → .014 大腿 → .015 小腿 → .016 踝 → .017 脚）
const GUESS := ["Bone.013", "Bone.014", "Bone.015", "Bone.016", "Bone.017",
	"Bone.037", "Bone.038", "Bone.039", "Bone.040", "Bone.041"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for i in 4:
		await process_frame
	var boss := level.get_node_or_null(BOSS)
	if boss == null:
		print("!! 找不到 %s" % BOSS)
		quit(1)
		return
	if not bool(boss.get("_booted")):
		boss.call("_boot")
	for i in 30:
		await process_frame

	var skel: Skeleton3D = boss.call("_best_skeleton", boss.get("model"))
	if skel == null:
		print("!! 没有骨架")
		quit(1)
		return

	print("========== 猜的腿骨 ==========")
	for nm in GUESS:
		var b := skel.find_bone(nm)
		if b < 0:
			print("  %-12s ✗ 骨架里没有这根" % nm)
			continue
		var rest: Transform3D = skel.get_bone_global_rest(b)
		var par := skel.get_bone_parent(b)
		# 骨头到它子骨的方向（判断这条链往下往哪拐）
		var to_child := Vector3.ZERO
		for c in skel.get_bone_count():
			if skel.get_bone_parent(c) == b:
				to_child = skel.get_bone_global_rest(c).origin - rest.origin
				break
		# 模型 X 轴在这根骨局部空间里的方向
		var ax: Vector3 = (rest.basis.inverse() * Vector3.RIGHT).normalized()
		print("  %-12s #%2d 父 %-12s 位置 %-24s 到子骨 %-22s | 局部X轴 %s" % [
			nm, b,
			skel.get_bone_name(par) if par >= 0 else "-",
			str(rest.origin.snappedf(0.01)),
			str(to_child.snappedf(0.01)),
			str(ax.snappedf(0.001))])
	print("")
	print("========== 全部骨头名（找腿用）==========")
	var names := PackedStringArray()
	for b in skel.get_bone_count():
		names.append("%d:%s" % [b, skel.get_bone_name(b)])
	print("  " + ", ".join(names))
	print("")
	quit(0)
