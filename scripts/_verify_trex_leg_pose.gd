extends SceneTree
## 使用实际霸王龙骨架验证局部姿态、左右摆幅、停步和攻击切换。

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])


func _run() -> void:
	var boss = load("res://scenes/trex_yuuka_boss.tscn").instantiate()
	boss.boot_distance = 0.0
	boss.boot_max_wait = 0.0
	root.add_child(boss)
	boss.set_process(false)
	boss._anim.advance(0.0)
	var skel: Skeleton3D = boss._leg_skel
	var names := ["Bone.014", "Bone.015", "Bone.038", "Bone.039"]
	var indices: Array[int] = []
	var bases: Array[Quaternion] = []
	var peaks := PackedFloat32Array([0, 0, 0, 0])
	for name in names:
		var idx := skel.find_bone(name)
		indices.append(idx)
		bases.append(skel.get_bone_rest(idx).basis.get_rotation_quaternion())
		_check(idx >= 0, "实际模型存在腿骨 " + name)
	var feet := [skel.find_bone("Bone.017"), skel.find_bone("Bone.041")]
	var feet_rest: Array[Vector3] = []
	for idx in feet:
		feet_rest.append(skel.get_bone_global_pose(idx).origin)
	var max_travel := 0.0
	boss._walking = true
	for frame in 1800:
		boss._tick_legs(1.0 / 60.0)
		skel.force_update_all_bone_transforms()
		for k in indices.size():
			peaks[k] = maxf(peaks[k], rad_to_deg(bases[k].angle_to(skel.get_bone_pose_rotation(indices[k]))))
		for k in feet.size():
			max_travel = maxf(max_travel, feet_rest[k].distance_to(skel.get_bone_global_pose(feet[k]).origin))
	for k in indices.size():
		var limit: float = boss.leg_swing_deg if k % 2 == 0 else boss.leg_knee_deg
		_check(peaks[k] <= limit + 0.05 and peaks[k] > limit * 0.8,
			"%s 连跑30秒局部摆幅 %.2f°，限值 %.1f°" % [names[k], peaks[k], limit])
	_check(absf(peaks[0] - peaks[2]) < 0.1, "左右大腿摆幅一致")
	_check(absf(peaks[1] - peaks[3]) < 0.1, "左右小腿摆幅一致")
	_check(max_travel < 0.8, "脚端没有翻转飞起，最大偏移 %.3f 骨架单位" % max_travel)
	boss._walking = false
	boss._tick_legs(1.0 / 60.0)
	for k in indices.size():
		_check(bases[k].angle_to(skel.get_bone_pose_rotation(indices[k])) < 0.001,
			"停步恢复 " + names[k])
	_check(is_equal_approx(boss.model.position.y, boss._model_y0), "停步身体高度复位")
	boss._walking = true
	boss._anim.play("roar")
	boss._anim.advance(0.1)
	boss._tick_legs(1.0 / 60.0)
	for k in indices.size():
		_check(bases[k].angle_to(skel.get_bone_pose_rotation(indices[k])) < 0.001,
			"攻击期间腿不遗留跑姿 " + names[k])
	boss._anim.play("idle")
	boss._anim.advance(0.0)
	boss._tick_legs(0.15)
	_check(bases[0].angle_to(skel.get_bone_pose_rotation(indices[0])) > 0.01, "攻击后可继续正常迈步")
	boss.queue_free()
	await process_frame
	await process_frame
	print("[trex_leg_pose] %d PASS / %d FAIL" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
