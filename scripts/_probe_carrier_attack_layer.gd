extends SceneTree
## 验「机甲开火 = 只叠上半身」（用户 2026-11-09 选定的方案 A）。
##
## 用户原话：「爱丽丝机甲攻击动画为什么僵硬」。
##
## 病根：`Normal_Attack_Ing` 是**整身**动作，而载具没有叠加层，只能独占播放 ——
## `_process()` 在 `_oneshot_left` 期间直接 return，移动动画停刷 1.07 s；
## 再叠上 0.10 s 一发的射速，就是「10 发里 9 发身体不动」。
##
## 修法照 `anim_driver.gd::_setup_upper_layer()`：另建一个 AnimationPlayer 当兄弟节点，
## 装「滤掉下半身 + 躯干」的副本，`process_priority` 大 1 ⇒ 后写赢。
##
## 这条探针量四件事：
##   ① 叠加层建出来了、在树里、`process_priority` 比基础层大
##   ② 副本确实滤掉了下半身 / 躯干（按骨名抽查），且**保留了手臂**
##   ③ 开火时：`_upper` 在播，而**基础层的 `_ap` 仍在播移动动作**（腿没被冻）
##   ④ 开火不再独占：`_oneshot_full == false`
##
##   _tools/run_probe.sh res://scripts/_probe_carrier_attack_layer.gd

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

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
	MechState.set_carrier_for_test(true)

	var stage := Node3D.new()
	stage.name = "AttackStage"
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 0.4, 80)
	col.shape = box
	col.position.y = -0.2
	floor_body.add_child(col)
	stage.add_child(floor_body)

	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame

	var cf := player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	if cf == null:
		push_error("[AtkLayer] 没有 CarrierForm")
		quit(1)
		return
	if not cf.set_form(true):
		push_error("[AtkLayer] 变形成功不了（模型可能没放）")
		quit(1)
		return
	# 给 `add_child.call_deferred` 一帧落地
	for i in 5:
		await process_frame

	var ap := cf.get("_ap") as AnimationPlayer
	var upper := cf.get("_upper") as AnimationPlayer

	print("")
	print("========== 1. 叠加层建出来了 ==========")
	_check(upper != null, "`_upper` 存在")
	if upper == null:
		print("\n叠加层没建出来，后面没法验")
		MechState.set_carrier_for_test(false)
		quit(1)
		return
	_check(upper.is_inside_tree(), "在场景树里（不在树里 ⇒ 一帧都不更新，而且是静默失败）")
	_check(upper.get_parent() == ap.get_parent(), "与基础层同一个父节点（轨道路径才对得上）")
	_check(upper.root_node == ap.root_node, "`root_node` 与基础层一致")
	_check(upper.process_priority > ap.process_priority,
		"`process_priority` 比基础层大（%d > %d ⇒ 后写赢）" % [
			upper.process_priority, ap.process_priority])

	print("")
	print("========== 2. 副本滤得对不对 ==========")
	var clip := String(cf.get("ATTACK_CLIP")) if cf.get("ATTACK_CLIP") != null else "Normal_Attack_Ing"
	if not upper.has_animation(clip):
		_check(false, "叠加层里有 %s" % clip)
	else:
		_check(true, "叠加层里有 %s" % clip)
		var full: Animation = ap.get_animation(clip)
		var cut: Animation = upper.get_animation(clip)
		print("       轨道数：原来 %d → 叠加上半身 %d（滤掉 %d）" % [
			full.get_track_count(), cut.get_track_count(),
			full.get_track_count() - cut.get_track_count()])
		_check(cut.get_track_count() > 0, "滤完还剩轨道（不是把整条都滤空了）")
		_check(cut.get_track_count() < full.get_track_count(), "确实比原来少")

		# 按骨名抽查：腿 / 躯干必须没了，手臂必须还在
		var lower_kw: Array = cf.get("LOWER_KEYWORDS")
		var trunk_kw: Array = cf.get("TRUNK_KEYWORDS")
		var leg := 0
		var trunk := 0
		var arm := 0
		for t in cut.get_track_count():
			var path_s := String(cut.track_get_path(t))
			var i := path_s.rfind(":")
			var bone := path_s.substr(i + 1).to_lower() if i >= 0 else ""
			for k in lower_kw:
				if bone.contains(String(k)):
					leg += 1
					break
			for k in trunk_kw:
				if bone.contains(String(k)):
					trunk += 1
					break
			if bone.contains("arm") or bone.contains("hand") or bone.contains("shoulder"):
				arm += 1
		print("       剩下来的轨道里：腿 %d 条 / 躯干 %d 条 / 手臂 %d 条" % [leg, trunk, arm])
		_check(leg == 0, "下半身一条不剩（腿由基础层管）")
		_check(trunk == 0, "躯干一条不剩（否则开火会从飞行前倾弹成站桩）")
		_check(arm > 0, "手臂还在（开火动作得有东西在动）")

	print("")
	print("========== 3. 开火时基础层还在播移动动作 ==========")
	# 让基础层先播上移动动作（模拟飞行中）
	cf.set("_airborne", true)
	player.set("velocity", Vector3(6, 0, 0))
	for i in 12:
		await process_frame
	var base_before := ap.current_animation
	print("       开火前基础层 = %s，叠加层 = %s" % [
		base_before, upper.current_animation])

	var wpn := cf.call("_weapon") as Node
	_check(wpn != null, "拿得到 Weapon")
	if wpn != null:
		# `_shot_index` 每发 +1；`_run_effects` 每帧读它 → 手动 +1 就等于开了一枪
		var si := int(wpn.get("_shot_index"))
		wpn.set("_shot_index", si + 1)
		for i in 3:
			await process_frame
		print("       开火后基础层 = %s（playing=%s），叠加层 = %s（playing=%s）" % [
			ap.current_animation, str(ap.is_playing()),
			upper.current_animation, str(upper.is_playing())])
		_check(upper.is_playing(), "叠加层在播开火动作")
		_check(ap.is_playing(), "**基础层仍在播**（腿没被冻住 = 修好了）")
		_check(not bool(cf.get("_oneshot_full")),
			"开火是「叠加」而不是「整身独占」（`_oneshot_full` = false）")
		# 基础层不该被换成开火动作
		_check(ap.current_animation != clip,
			"基础层没有被切成开火动作（仍是 %s）" % ap.current_animation)

	print("")
	print("========== 4. 量骨头：开火期间腿到底动没动 ==========")
	# ⚠️ 这一节才是**真凭据**。前面「`_ap.is_playing()`」只说明播放器在跑；
	#    用户看到的「僵硬」是**骨头不动**。按 README §1.8 的规矩：判「有没有动」要看
	#    **旋转**（位置在有些动作里本来就不变）。
	var skel := cf.get("_skel") as Skeleton3D
	if skel == null:
		_check(false, "拿得到骨架")
	else:
		var thigh := -1
		var upper_arm := -1
		for bi in skel.get_bone_count():
			var bn := skel.get_bone_name(bi)
			if thigh < 0 and bn.contains("Thigh") and bn.contains("L"):
				thigh = bi
			if upper_arm < 0 and bn.contains("UpperArm") and bn.contains("L"):
				upper_arm = bi
		print("       骨：左大腿 = %s(#%d)，左上臂 = %s(#%d)" % [
			skel.get_bone_name(thigh) if thigh >= 0 else "没找到", thigh,
			skel.get_bone_name(upper_arm) if upper_arm >= 0 else "没找到", upper_arm])

		# 再打一枪，然后连采 40 帧
		if wpn != null:
			wpn.set("_shot_index", int(wpn.get("_shot_index")) + 1)
		for i in 4:
			await process_frame
		var thigh_prev := skel.get_bone_global_pose(thigh).basis.get_rotation_quaternion() \
			if thigh >= 0 else Quaternion()
		var arm_prev := skel.get_bone_global_pose(upper_arm).basis.get_rotation_quaternion() \
			if upper_arm >= 0 else Quaternion()
		var thigh_max := 0.0
		var arm_max := 0.0
		for i in 40:
			await process_frame
			if thigh >= 0:
				var q := skel.get_bone_global_pose(thigh).basis.get_rotation_quaternion()
				thigh_max = maxf(thigh_max, rad_to_deg(q.angle_to(thigh_prev)))
				thigh_prev = q
			if upper_arm >= 0:
				var q2 := skel.get_bone_global_pose(upper_arm).basis.get_rotation_quaternion()
				arm_max = maxf(arm_max, rad_to_deg(q2.angle_to(arm_prev)))
				arm_prev = q2
		print("       开火这 40 帧里：大腿单帧最大转动 %.3f°，上臂单帧最大转动 %.3f°" % [
			thigh_max, arm_max])
		# 腿由基础层的 `Move_Ing` 提供 ⇒ 必须一直在动（修复前是 0：被整身独占冻住）
		_check(thigh_max > 0.05,
			"**腿一直在动**（大腿 %.3f° > 0.05°；整身独占时会冻成 0）" % thigh_max)
		# 上臂由叠加层提供 ⇒ 开火时也要在动
		_check(arm_max > 0.05, "上臂也在动（%.3f° > 0.05°）" % arm_max)

	MechState.set_carrier_for_test(false)
	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
