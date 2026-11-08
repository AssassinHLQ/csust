extends SceneTree
## 量推进器骨（`bone_gearboost_L/R`）与肩翼 / 导弹荚骨在**世界空间**的位置和朝向。
##
## 用户 2026-11-08：「飞行特效太粗糙」→ 优化时发现：焰从腿**内侧**斜插出来，
## 像两把刀。本喵要确认推进器骨到底在腿的哪一侧、朝哪个方向，
## 别再凭感觉摆。
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_diag_carrier_nozzle.gd

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

const BONES := [
	"bone_gearboost_L", "bone_gearboost_R",
	"bone_gear_wing_L", "bone_gear_wing_R",
	"bone_missilepod_L", "bone_missilepod_R",
	"Bip001 L Toe", "Bip001 R Toe",
	"Bip001 Pelvis",
]


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
		push_error("[Nozzle] 变形失败")
		quit(1)
		return
	await process_frame
	var skel := cf.get("_skel") as Skeleton3D
	var carrier := cf.get("_carrier") as Node3D
	if skel == null:
		push_error("[Nozzle] 没骨架")
		quit(1)
		return

	# 模型正面（水平）
	var fwd := carrier.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var pelvis_i := skel.find_bone("Bip001 Pelvis")
	var pelvis := (skel.global_transform * skel.get_bone_global_pose(pelvis_i)).origin \
		if pelvis_i >= 0 else Vector3.ZERO

	print("")
	print("========== 各骨的世界位置（相对胯骨，投影到「右 / 前 / 上」）==========")
	print("   %-20s %8s %8s %8s   朝向(local Y 朝天?)" % ["骨", "右", "前", "上"])
	for bn in BONES:
		var i := skel.find_bone(String(bn))
		if i < 0:
			print("   %-20s  <不存在>" % bn)
			continue
		var xf := skel.global_transform * skel.get_bone_global_pose(i)
		var p := xf.origin - pelvis
		var lx := xf.basis.y.normalized()
		var lz := xf.basis.z.normalized()
		print("   %-20s %+8.2f %+8.2f %+8.2f    localY·上=%+.2f  localZ·前=%+.2f" % [
			bn, p.dot(right), p.dot(fwd), p.y,
			lx.dot(Vector3.UP), lz.dot(fwd)])

	print("")
	print("========== 结论提示 ==========")
	print("   「右」为正 = 在身体右侧；「上」为负 = 在胯以下")
	print("   推进器的 localY 如果「·上」接近 +1，说明它朝天喷；接近 −1 才是朝下")
	quit(0)
