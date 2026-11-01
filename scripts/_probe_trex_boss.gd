extends SceneTree
## 验第二关的霸王龙：模型/骨架/动作，并确认动作真的在动骨头。
##   godot --path . --headless --script res://scripts/_probe_trex_boss.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var boss := (load("res://scenes/trex_yuuka_boss.tscn") as PackedScene).instantiate()
	boss.set("boot_distance", 0.0)
	boss.set("boot_max_wait", 0.0)
	boss.set("height", 9.0)
	var ground := Node3D.new()
	root.add_child(ground)
	ground.add_child(boss)
	for _i in 6:
		await process_frame

	print("[trex] model=%s 骨=%d 量法=%s 尺寸=%s" % [
		"有" if boss.get("model") != null else "无",
		boss.get("bone_count"), boss.get("measure_kind"), str(boss.get("visual_size"))])
	var model: Node3D = boss.get("model")
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if ap == null:
		print("[trex] 找不到 AnimationPlayer")
		quit(1)
		return
	print("[trex] 动作：%s" % str(ap.get_animation_list()))
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var jaw := sk.find_bone("Bone.005")
	var tail := sk.find_bone("Bone.009")
	for clip in ["idle", "bite", "tail_sweep", "stomp", "charge", "roar"]:
		ap.play(clip)
		var before_jaw := sk.get_bone_pose_rotation(jaw)
		var before_tail := sk.get_bone_pose_rotation(tail)
		for _i in 12:
			await process_frame
		var d_jaw: float = before_jaw.angle_to(sk.get_bone_pose_rotation(jaw))
		var d_tail: float = before_tail.angle_to(sk.get_bone_pose_rotation(tail))
		print("[trex] %-11s 下巴动 %.1f°  尾巴动 %.1f°  长度 %.2fs" % [
			clip, rad_to_deg(d_jaw), rad_to_deg(d_tail), ap.get_animation(clip).length])
	quit(0)
