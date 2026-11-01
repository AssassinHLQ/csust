extends SceneTree
## 量每段动作里下巴 / 尾巴 / 后腿的最大旋转角度（度）。
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var boss := (load("res://scenes/trex_yuuka_boss.tscn") as PackedScene).instantiate()
	boss.set("boot_distance", 0.0)
	boss.set("boot_max_wait", 0.0)
	var holder := Node3D.new()
	root.add_child(holder)
	holder.add_child(boss)
	for _i in 6:
		await process_frame
	var model: Node3D = boss.get("model")
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var watch := {"下巴": sk.find_bone("Bone.005"), "尾巴中段": sk.find_bone("Bone.009"),
		"左腿": sk.find_bone("Bone.014")}
	var rest := {}
	for k in watch:
		rest[k] = sk.get_bone_pose_rotation(watch[k])
	for clip in ["bite", "tail_sweep", "stomp", "charge", "roar", "idle"]:
		ap.play(clip)
		var peak := {"下巴": 0.0, "尾巴中段": 0.0, "左腿": 0.0}
		var frames := int(ap.get_animation(clip).length * 60.0) + 2
		for _i in frames:
			await process_frame
			var t := ap.current_animation_position
			for k in watch:
				var a := absf(rad_to_deg(rest[k].angle_to(sk.get_bone_pose_rotation(watch[k]))))
				peak[k] = maxf(peak[k], a)
		print("[peak] %-11s 下巴 %5.1f°  尾巴 %5.1f°  左腿 %5.1f°" % [
			clip, peak["下巴"], peak["尾巴中段"], peak["左腿"]])
		ap.stop()
		for _i in 3:
			await process_frame
		for k in watch:
			rest[k] = sk.get_bone_pose_rotation(watch[k])
	quit(0)
