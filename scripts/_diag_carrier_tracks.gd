extends SceneTree
## 查：飞行时播的 `Move_Ing` 到底动画了哪些骨。
##
## 为什么要查：`carrier_form.gd` 每帧用 `set_bone_pose_rotation()` 往
## 推进器 / 肩翼 / 炮口骨上叠特效姿态，而 `AnimationPlayer` 默认在 **idle**
## 阶段写骨头（本脚本写在 **physics** 阶段）—— 一帧里 physics 在前、idle 在后。
##
## 关键：`AnimationPlayer` **只覆盖它在当前动画里有轨道的那些骨**。
##   · 若 `Move_Ing` 有 wing/gearboost 的轨道 → 本脚本的叠加被当帧抹掉（特性白写）；
##   · 若没有 → 叠加是有效的。
## 所以这条决定了「骨姿势叠加到底有没有用」，不能靠猜。
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_diag_carrier_tracks.gd

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

## 本脚本会叠加的骨名（子串匹配）
const WATCH := ["bone_wing", "bone_gearboost", "bone_gear_cannon", "Bip001 Pelvis"]


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
		push_error("[Tracks] 变形失败")
		quit(1)
		return
	await process_frame
	var ap := cf.get("_ap") as AnimationPlayer
	if ap == null:
		push_error("[Tracks] 没有 AnimationPlayer")
		quit(1)
		return

	print("")
	print("========== 各动画里、被本脚本叠加的骨有没有轨道 ==========")
	var names: Array[String] = []
	for c in ap.get_animation_list():
		names.append(String(c))
	names.sort()
	for clip in names:
		var anim := ap.get_animation(clip)
		if anim == null:
			continue
		var hits := {}
		for t in anim.get_track_count():
			var path := String(anim.track_get_path(t))
			for w in WATCH:
				if path.contains(w):
					hits[w] = int(hits.get(w, 0)) + 1
		if hits.is_empty():
			print("  %-22s 无（本脚本的叠加不会被覆盖）" % clip)
		else:
			print("  %-22s 有 → %s" % [clip, str(hits)])

	print("")
	print("[Tracks] 完")
	quit(0)
