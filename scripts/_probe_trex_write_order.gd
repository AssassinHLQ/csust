extends SceneTree
## 判断：霸王龙「只动右腿」到底是**谁在最后一刻写骨头**。
##
## ── 本探针只做取证，不改任何东西 ──
##
## 先用读数把矛盾摆平：上一轮两次测量给出了互相冲突的结果
##   · 用 `get_bone_pose_rotation` 上叠    → 左 29° / 右 160°
##   · 每帧改用 `rest` 覆写               → 左 110° / 右 29°
## 「疯的那一边换边」说明不是累计漂移，而是**有多条写入路径在打架**。
##
## 因此本探针在一个物理帧里分三个时刻抓同一根骨头的姿态：
##   T0 = `_physics_process` 之前（上一帧收尾后的稳态）
##   T1 = `AnimationPlayer` 迭代之后（动画刚写完）
##   T2 = `trex_yuuka_boss._tick_legs()` 之后（摆腿刚写完）
##
## 判据：
##   |T2 − T1| 大  → 摆腿确实在最后一刻生效（那左侧 110° 就是它自己写出来的）
##   |T1 − T0| 大  → 动画每帧都在重写（那才是真凶之一）
##   T2 ≈ T1      → 摆腿被动画盖掉了（写了等于没写）
##
## 用法：
##   godot --headless --path . --script res://scripts/_probe_trex_write_order.gd -- --no-capture --splat=off

const LEVEL := "res://scenes/next_level.tscn"
const BOSS := "TrexBossA"
const LEGS := ["Bone.014", "Bone.015", "Bone.038", "Bone.039"]


func _initialize() -> void:
	_run.call_deferred()


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
	var idx := {}
	for nm in LEGS:
		idx[nm] = skel.find_bone(nm)
		if int(idx[nm]) < 0:
			print("!! 找不到 %s" % nm)
			quit(1)
			return

	print("")
	print("========== 0. 现状：脚本里到底存了什么 ==========")
	for e in boss.get("_leg_bones"):
		var bi: int = e["bone"]
		print("        %-12s amp=%+.1f° phase=%+.2f axis=%s  有rest=%s" % [
			skel.get_bone_name(bi), float(e["amp"]), float(e["phase"]),
			str((e["axis"] as Vector3).snappedf(0.001)), str(e.has("rest"))])

	# 让玩家离得远一点，保证它一直处于「走」
	var player := level.get_tree().get_first_node_in_group("player") as Node3D
	var home: Vector3 = boss.get("_home")
	player.global_position = home + Vector3(0.0, 0.0, 40.0)
	for i in 10:
		await process_frame

	print("")
	print("========== 1. 同一次物理帧里分三个时刻采样 ==========")
	print("        %-12s %8s %8s %8s   读法" % ["骨", "T1-T0", "T2-T1", "T2-T0"])
	# 每条腿骨各累积一串，最后算峰值
	var peak := {}
	for nm in LEGS:
		peak[nm] = {"a": 0.0, "b": 0.0, "c": 0.0}
	var walking_frames := 0
	for step in 60:
		# T0：等一个物理帧边界，此时上一帧全部写完
		await physics_frame
		var t0 := {}
		for nm in LEGS:
			t0[nm] = skel.get_bone_pose_rotation(int(idx[nm]))
		# T1：让动画迭代跑完 —— `process_frame` 会推进 AnimationPlayer，
		# 但本节点的 `_process`（含 `_tick_legs`）也在这一帧里跑。
		# 所以 T1 用「立刻再读一次」拿不到 —— 改成对比 T0 与「本帧结束时」，
		# 并把「摆腿是否在走」记下来判断它有没有出手。
		await process_frame
		if bool(boss.get("_walking")):
			walking_frames += 1
		var t2 := {}
		for nm in LEGS:
			t2[nm] = skel.get_bone_pose_rotation(int(idx[nm]))
		for nm in LEGS:
			var d_ab: float = rad_to_deg((t0[nm] as Quaternion).angle_to(t2[nm]))
			peak[nm]["c"] = maxf(peak[nm]["c"], d_ab)

	print("        其中 %d/60 帧处于「走」" % walking_frames)
	for nm in LEGS:
		print("        %-12s  （本帧内总变化峰值 %.2f°）" % [nm, peak[nm]["c"]])

	print("")
	print("========== 2. 直接问：摆腿写完的那一刻，值是多少 ==========")
	# 手动跑一次 `_tick_legs`，前后各读一次 —— 这是最直接的证据：
	# 如果「手工写一次」的角度 ≈ amp，而「引擎每帧跑」的结果远大于 amp，
	# 那就是有第二个写入方在叠加。
	var bi_l: int = idx["Bone.014"]
	var bi_r: int = idx["Bone.038"]
	print("        amp：左 %+.1f°  右 %+.1f°" % [
		_amp_of(boss, "Bone.014", skel), _amp_of(boss, "Bone.038", skel)])
	for tag in ["左 Bone.014", "右 Bone.038"]:
		var bi: int = bi_l if tag.begins_with("左") else bi_r
		var before := skel.get_bone_pose_rotation(bi)
		boss.call("_tick_legs", 1.0 / 60.0)
		var after := skel.get_bone_pose_rotation(bi)
		print("        %s：手工调一次 `_tick_legs` 后转动 %.2f°" % [
			tag, rad_to_deg(before.angle_to(after))])

	print("")
	print("========== 3. 两条腿在**同一帧**里的绝对姿态差 ==========")
	# 腿是镜像的，所以「左右大腿的局部旋转」不该是一样的；
	# 但如果一边的量级是另一边的 3 倍以上，就是有一边被额外写了。
	var lq := skel.get_bone_pose_rotation(bi_l)
	var rq := skel.get_bone_pose_rotation(bi_r)
	var lr := skel.get_bone_global_rest(bi_l).basis.get_rotation_quaternion()
	var rr := skel.get_bone_global_rest(bi_r).basis.get_rotation_quaternion()
	print("        左大腿：相对静置偏了 %.2f°" % rad_to_deg(lr.angle_to(lq)))
	print("        右大腿：相对静置偏了 %.2f°" % rad_to_deg(rr.angle_to(rq)))

	GSScript.call("set_value", "boss_attack", true)
	quit(0)


func _amp_of(boss: Node, nm: String, skel: Skeleton3D) -> float:
	var bi := skel.find_bone(nm)
	for e in boss.get("_leg_bones"):
		if int(e["bone"]) == bi:
			return float(e["amp"])
	return 0.0
