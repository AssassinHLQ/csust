extends SceneTree
## 列载体骨架里所有带 wing / pod / boost / gear 的骨名。
## 用来给「肩翼 / 导弹荚的小喷口」找对骨名（用户 2026-11-08）。
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_diag_carrier_bones.gd

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	MechState.set_carrier_for_test(true)
	var stage := Node3D.new()
	root.add_child(stage)
	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame
	var cf := player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	if cf == null or not cf.set_form(true):
		push_error("[Bones] 变形失败")
		quit(1)
		return
	await process_frame
	var skel := cf.get("_skel") as Skeleton3D
	if skel == null:
		push_error("[Bones] 没骨架")
		quit(1)
		return

	print("")
	print("========== 带 wing / pod / boost / gear 的骨 ==========")
	var n := 0
	for i in skel.get_bone_count():
		var bn := String(skel.get_bone_name(i))
		var low := bn.to_lower()
		if low.contains("wing") or low.contains("pod") or low.contains("boost") \
				or low.contains("gear") or low.contains("missile"):
			print("  %3d  %s" % [i, bn])
			n += 1
	print("  （共 %d 根）" % n)

	print("")
	print("========== 肩翼 / 导弹荚候选（带 _01/_02 的是翼片）==========")
	for i in skel.get_bone_count():
		var bn := String(skel.get_bone_name(i))
		if bn.contains("wing_L") or bn.contains("wing_R") \
				or bn.contains("missilepod") or bn.contains("pod"):
			print("  %3d  %s" % [i, bn])

	print("")
	print("[Bones] 完")
	quit(0)
