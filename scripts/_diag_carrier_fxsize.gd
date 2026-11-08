extends SceneTree
## 量推进器特效每一层的**实际世界尺寸**（半径 / 长度），以及挂点位置。
##
## 为什么：本喵连着几版出图都是「一团光晕、没有焰形」，靠看图调不出来。
## 这里直接把每层的 AABB 量出来 —— 如果焰的长度是 0.1 m，那它在画面上
## 必然只是一团光；如果长度正常，那就是**加色混合把它烧白了**。
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_diag_carrier_fxsize.gd

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
		push_error("[FxSize] 变形失败")
		quit(1)
		return
	await process_frame
	var skel := cf.get("_skel") as Skeleton3D
	var carrier := cf.get("_carrier") as Node3D
	if skel == null:
		push_error("[FxSize] 没骨架")
		quit(1)
		return

	# 起飞 + 给满推力
	cf.call("_take_off")
	player.global_position.y = 40.0
	cf.set("_hold_y", 40.0)
	player.set("velocity", Vector3.ZERO)
	cf.set("_vert_want", 1.0)
	cf.set("_thrust", 1.0)
	for i in 20:
		cf.call("_sync_face")
		cf.call("_run_effects", 1.0 / 60.0)
		await process_frame

	print("")
	print("========== 推进器每层的实际尺寸（满推力）==========")
	var boost: Array = cf.get("_boost_fx")
	print("  推进器挂点 %d 个" % boost.size())
	for fx in boost:
		var layers: Array = fx["layers"]
		var holder: Node3D = fx["holder"]
		print("  ── bone %d   挂点世界位置 %s" % [
			int(fx["bone"]), str(holder.global_position.snappedf(0.01))])
		for li in layers.size():
			var mi := layers[li] as MeshInstance3D
			if mi == null:
				continue
			var aabb := mi.global_transform * mi.get_aabb()
			var sc := mi.scale
			print("     层%d  scale=(%.3f, %.3f, %.3f)  世界尺寸=(%.3f, %.3f, %.3f)  可见=%s" % [
				li, sc.x, sc.y, sc.z,
				aabb.size.x, aabb.size.y, aabb.size.z, str(mi.visible)])
			var m := mi.material_override as StandardMaterial3D
			if m != null:
				print("        emission_energy=%.2f  albedo_a=%.2f  blend=%d" % [
					m.emission_energy_multiplier, m.albedo_color.a, m.blend_mode])

		# 挂点与骨骼原点的差（外推偏移生效了吗）
		var bi: int = fx["bone"]
		var bone_org := (skel.global_transform * skel.get_bone_global_pose(bi)).origin
		print("     挂点相对骨原点偏移 = %.3f m" % holder.global_position.distance_to(bone_org))

	print("")
	print("========== 网格本身的尺寸（缩放前）==========")
	var mesh = cf.call("_make_flame_mesh")
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		var aabb := am.get_aabb()
		print("  ArrayMesh AABB size = %s  (原点应该在根部)" % str(aabb.size.snappedf(0.001)))
		print("  → 缩放后世界长度 = scale.y × %.3f" % aabb.size.y)

	quit(0)
