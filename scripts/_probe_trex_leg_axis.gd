extends SceneTree
## 诊断：霸王龙「跑步只动右腿」——量化**两条腿各自摆了多少度**。
##
## ── 为什么用户看到的和自检说的不一样 ──
## `_verify_trex_chase.gd` 第 4 节只量了 `Bone.014`（**左**大腿）的相邻帧转动，
## 有 0.15° 就算「腿在摆」。它**没量右腿**，也没量「摆腿方向对不对」。
## 探针量的东西和用户看到的东西不是同一件 —— 这正是「量具选错」的老毛病。
##
## 本探针量三件事，左右两腿各量一遍：
##   ① 摆腿轴在**模型空间**里到底是哪个方向（应该是左右轴 = 模型 X）
##      —— 绕错轴的话腿会**扭麻花 / 内外八字**，而不是前后迈步
##   ② 摆动角度的**峰值**（度），左右对比
##   ③ 大腿骨在**模型空间**里的位移轨迹 —— 前后(pitch) / 内外(roll) / 扭转(yaw)
##      各占多少，这才叫「腿在迈步」还是「腿在拧」
##
## 用法：
##   godot --headless --path . --script res://scripts/_probe_trex_leg_axis.gd -- --no-capture --splat=off

const LEVEL := "res://scenes/next_level.tscn"
const BOSS := "TrexBossA"
## 采样帧数（跑起来之后）
const FRAMES := 90

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _run() -> void:
	var GSScript := load("res://scripts/game_settings.gd")
	GSScript.call("set_value", "boss_attack", false)

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
	for i in 40:
		await process_frame

	var skel: Skeleton3D = boss.call("_best_skeleton", boss.get("model"))
	if skel == null:
		print("!! 没骨架")
		quit(1)
		return

	print("")
	print("========== 1. 摆腿配置（`_leg_bones` 里记的东西）==========")
	var legs: Array = boss.get("_leg_bones")
	print("        共 %d 条记录" % legs.size())
	for e in legs:
		var bi: int = e["bone"]
		var ax: Vector3 = e["axis"]
		print("        %-12s #%2d  axis=%s  phase=%.2f  amp=%.1f°" % [
			skel.get_bone_name(bi), bi, str(ax.snappedf(0.001)),
			float(e["phase"]), float(e["amp"])])

	print("")
	print("========== 2. 摆腿轴对不对（换算回模型空间该是 ±X）==========")
	# ⚠️ 上一版这里的判据是「轴垂直于骨纵向」，结果**错判成 PASS**：
	#    点乘 0.000 只说明它垂直于骨轴，不说明绕它转就是**前后迈步** ——
	#    实际量出来末端轨迹 X 0.440 / Z 0.185，是左右拧。
	#    正确判据只有一条：把轴换算回**模型空间**，它必须和 ±X 平行。
	for nm in ["Bone.014", "Bone.038"]:
		var bi := skel.find_bone(nm)
		if bi < 0:
			_check(false, "找得到 %s" % nm)
			continue
		var rest := skel.get_bone_global_rest(bi)
		var axis_local := Vector3.ZERO
		for e in legs:
			if int(e["bone"]) == bi:
				axis_local = (e["axis"] as Vector3).normalized()
				break
		# 轴在**模型**空间里实际指向哪 —— 用 rest.basis 换回去
		var axis_model := (rest.basis * axis_local).normalized()
		print("        %-12s 摆腿轴(局部)=%s → **模型空间** %s" % [
			nm, str(axis_local.snappedf(0.001)), str(axis_model.snappedf(0.001))])
		_check(absf(axis_model.x) > 0.95,
			"★ %s 的摆腿轴 = 模型左右轴 X（|x| %.2f > 0.95）" % [nm, absf(axis_model.x)])

	print("")
	print("========== 3. 跑起来：左右腿各摆多少度 ==========")
	var player := level.get_tree().get_first_node_in_group("player") as Node3D
	var home: Vector3 = boss.get("_home")
	player.global_position = home + Vector3(0, 0, 40)
	for i in 10:
		await process_frame

	var L := skel.find_bone("Bone.014")
	var R := skel.find_bone("Bone.038")
	var Lc := skel.find_bone("Bone.015")
	var Rc := skel.find_bone("Bone.039")
	# 记录每帧「大腿骨在模型空间里的朝向向量」
	var mid_l := Vector3.ZERO
	var mid_r := Vector3.ZERO
	print("        跑动中：左大腿 %s / 右大腿 %s" % [
		"有" if L >= 0 else "无", "有" if R >= 0 else "无"])
	var ql: Array[Quaternion] = []
	var qr: Array[Quaternion] = []
	var cl: Array[Quaternion] = []
	var cr: Array[Quaternion] = []
	var walked := 0
	for i in FRAMES:
		await process_frame
		if bool(boss.get("_walking")):
			walked += 1
		ql.append(skel.get_bone_pose_rotation(L))
		qr.append(skel.get_bone_pose_rotation(R))
		if Lc >= 0:
			cl.append(skel.get_bone_pose_rotation(Lc))
		if Rc >= 0:
			cr.append(skel.get_bone_pose_rotation(Rc))

	print("        其中 %d/%d 帧处于「走」状态" % [walked, FRAMES])
	var l_amp := _peak_deg(ql)
	var r_amp := _peak_deg(qr)
	var lc_amp := _peak_deg(cl)
	var rc_amp := _peak_deg(cr)
	print("        左大腿 Bone.014 摆动峰值 %.2f°" % l_amp)
	print("        右大腿 Bone.038 摆动峰值 %.2f°" % r_amp)
	print("        左小腿 Bone.015 摆动峰值 %.2f°" % lc_amp)
	print("        右小腿 Bone.039 摆动峰值 %.2f°" % rc_amp)
	_check(l_amp > 5.0, "★ 左腿真的在摆（%.2f° > 5°）" % l_amp)
	_check(r_amp > 5.0, "★ 右腿真的在摆（%.2f° > 5°）" % r_amp)
	# 左右幅度不该差太多 —— 差一倍就说明有一边被压住了
	if l_amp > 0.01 and r_amp > 0.01:
		var ratio := maxf(l_amp, r_amp) / minf(l_amp, r_amp)
		print("        左右幅度比 %.2f（1.00 = 匀称）" % ratio)
		_check(ratio < 1.6, "左右腿幅度接近（比 %.2f < 1.6）" % ratio)

	print("")
	print("========== 4. 迈步还是拧麻花（看大腿骨模型的位移分量）==========")
	# 大腿骨末端（子骨静置位置）在这一串姿态下走出的轨迹，投影到模型空间的三个轴
	var bi := skel.find_bone("Bone.014")
	var rest := skel.get_bone_global_rest(bi)
	var child := skel.find_bone("Bone.015")
	var local_child := rest.basis.inverse() * (skel.get_bone_global_rest(child).origin - rest.origin)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for q in ql:
		var tip: Vector3 = (Basis(q) * local_child)
		lo = lo.min(tip)
		hi = hi.max(tip)
	var span := hi - lo
	print("        左大腿末端轨迹跨度（模型空间）X %.3f  Y %.3f  Z %.3f m" % [span.x, span.y, span.z])
	# 迈步 = 前后位移（Z）最大；拧麻花 = 内外位移（X）或上下（Y）为主
	var main_axis := "Z（前后迈步 ✓）"
	if span.x > span.z and span.x > span.y:
		main_axis = "X（左右拧 / 内外八字 ✗）"
	elif span.y > span.z and span.y > span.x:
		main_axis = "Y（上下抖 ✗）"
	print("        主位移轴 = %s" % main_axis)
	_check(span.z >= span.x and span.z >= span.y,
		"★ 迈步方向是**前后**（Z %.3f ≥ X %.3f、Y %.3f）" % [span.z, span.x, span.y])

	print("")
	print("========== 结果 ==========")
	print("  %d 项通过，%d 项失败" % [_pass, _fail])
	GSScript.call("set_value", "boss_attack", true)
	quit(0 if _fail == 0 else 1)


## 一串姿态里相对第一帧的最大旋转角（度）
func _peak_deg(qs: Array[Quaternion]) -> float:
	if qs.size() < 2:
		return 0.0
	var base := qs[0]
	var mx := 0.0
	for q in qs:
		mx = maxf(mx, rad_to_deg(base.angle_to(q)))
	return mx
