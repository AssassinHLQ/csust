extends SceneTree
## 诊断：机甲炮口焰节点的**真实世界坐标 / 可见性 / 尺寸**。
##
## 跑法：
##   & <godot> --headless --path . --script res://scripts/_diag_cannon_fx.gd -- --no-capture
##
## 为什么要单独一份：`_probe_carrier_shot.gd` 只能出图，图上「看不见」有四种可能
## （没亮 / 亮在别处 / 被模型挡住 / 太小），出图分不出来。这份把数字打出来。

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	MechState.set_carrier_for_test(true)
	var root_node := PlayerScene.instantiate()
	(Engine.get_main_loop() as SceneTree).get_root().add_child(root_node)
	var player := root_node as Player
	await process_frame
	await process_frame

	var cf := player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	var wpn := player.get_node_or_null("Weapon") as Weapon
	cf.set_form(true)
	await process_frame

	print("\n========== 炮口骨的世界坐标 ==========")
	var skel := _carrier_skel(cf)
	for bn in CarrierForm.CANNON_MUZZLE_BONES:
		var bi := skel.find_bone(bn)
		var p: Vector3 = (skel.global_transform * skel.get_bone_global_pose(bi)).origin
		var b: Basis = (skel.global_transform * skel.get_bone_global_pose(bi)).basis
		print("  %-32s index=%3d  pos=%s" % [bn, bi, str(p.snappedf(0.001))])
		print("      basis X=%s Y=%s Z=%s" % [
			str(b.x.snappedf(0.01)), str(b.y.snappedf(0.01)), str(b.z.snappedf(0.01))])

	print("\n========== 炮口焰节点状态（开火前）==========")
	_dump_fx(cf, "before")

	print("\n========== 开火 ==========")
	wpn.current_ammo = wpn.magazine_size
	wpn.set("_cooldown", 0.0)
	var ok := wpn.shoot()
	print("  shoot() = %s，_shot_index = %d" % [str(ok), int(wpn.get("_shot_index"))])
	cf.call("_run_effects", 1.0 / 60.0)

	print("\n========== 炮口焰节点状态（开火后）==========")
	_dump_fx(cf, "after")

	print("\n========== 对比：腿上推进器 ==========")
	var boost: Array = cf.get("_boost_fx")
	for f in boost:
		var h: Node3D = f["holder"]
		print("  boost bone=%d holder_visible=%s world=%s" % [
			int(f["bone"]), str(h.visible), str(h.global_position.snappedf(0.001))])
		for mi in f["layers"]:
			var m := mi as MeshInstance3D
			print("      layer visible=%s scale=%s" % [str(m.visible), str(m.scale.snappedf(0.001))])

	MechState.set_carrier_for_test(false)
	quit(0)


func _dump_fx(cf: CarrierForm, tag: String) -> void:
	var fx: Array = cf.get("_cannon_fx")
	print("  焰口节点数 = %d（cannon_fx_count=%d）" % [fx.size(), cf.cannon_fx_count])
	for i in fx.size():
		var f: Dictionary = fx[i]
		var h: Node3D = f["holder"]
		print("  [%d] bone=%d visible=%s world=%s left=%.3f" % [
			i, int(f["bone"]), str(h.visible),
			str(h.global_position.snappedf(0.001)), float(f["left"])])
		var gb: Basis = h.global_transform.basis
		print("      holder basis Y=%s（火焰沿 −Y 喷）" % str(gb.y.snappedf(0.01)))
		for mi in f["layers"]:
			var m := mi as MeshInstance3D
			print("      layer visible=%s scale=%s" % [str(m.visible), str(m.scale.snappedf(0.001))])
		var l := f["light"] as OmniLight3D
		print("      light energy=%.2f" % l.light_energy)


func _carrier_skel(cf: CarrierForm) -> Skeleton3D:
	var best: Skeleton3D = null
	var stack: Array[Node] = [cf]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			var s := n as Skeleton3D
			if best == null or s.get_bone_count() > best.get_bone_count():
				best = s
		for c in n.get_children():
			stack.append(c)
	return best
