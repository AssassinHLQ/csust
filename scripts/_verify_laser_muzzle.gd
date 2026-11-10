extends SceneTree
## 自检：普通状态开火**只有激光线，没有枪口圆球**。
##
## 用户 2026-11-10（附截图）：「普通爱丽丝普通攻击不要出现那个圆球只要激光线就可以」
##
## 那个球是 `weapon.gd::_muzzle_flash_beam()` 建的一颗 SphereMesh + 一盏 OmniLight3D。
## 本探针开一枪，然后数 `_fx_root` 下的球，看：
##   ① 枪口附近**没有**球（那个球应该没了）
##   ② 激光光柱**在**（CylinderMesh 的 holder）
##   ③ 机甲状态开火时，炮口闪光**仍然保留**
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_verify_laser_muzzle.gd

const GAME := "res://scenes/game.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


## 数 `_fx_root` 下的球（SphereMesh）和光柱（CylinderMesh），并报告球离枪口多远
func _survey(wpn: Node, muzzle_at: Vector3) -> Dictionary:
	var spheres: Array = []
	var cylinders := 0
	var fx_root := wpn.get("_fx_root") as Node
	if fx_root == null:
		return {"spheres": spheres, "cylinders": cylinders}
	for c in fx_root.get_children():
		for d in c.get_children():
			if not (d is MeshInstance3D):
				continue
			var mi := d as MeshInstance3D
			if mi.mesh is SphereMesh:
				spheres.append({"node": mi, "dist": mi.global_position.distance_to(muzzle_at)})
			elif mi.mesh is CylinderMesh:
				cylinders += 1
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is SphereMesh:
			var m2 := c as MeshInstance3D
			spheres.append({"node": m2, "dist": m2.global_position.distance_to(muzzle_at)})
		elif c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh:
			cylinders += 1
	return {"spheres": spheres, "cylinders": cylinders}


func _run() -> void:
	print("========== 激光枪口球自检 ==========")
	var level := (load(GAME) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 15:
		await process_frame

	var player := level.get_node_or_null("Player")
	var wpn := player.get_node_or_null("Weapon") if player else null
	if wpn == null:
		push_error("[verify] 没有 Weapon")
		quit(1)
		return

	# 确认是普通状态（laser_gun 开、beam_mode 关）
	print("  laser_gun = %s   beam_mode = %s" % [
		str(wpn.get("laser_gun")), str(wpn.get("beam_mode"))])
	_check(bool(wpn.get("laser_gun")), "普通状态 laser_gun = true")
	_check(not bool(wpn.get("beam_mode")), "机甲 beam_mode = false（确实是普通状态）")

	var muzzle := wpn.get_node_or_null("Muzzle") as Node3D
	var mpos := muzzle.global_position if muzzle != null else Vector3.ZERO
	print("  枪口世界位置 = %s" % str(mpos.snappedf(0.01)))

	# 开一枪
	wpn.call("trigger_down")
	await process_frame
	wpn.call("trigger_up")
	for _i in 3:
		await process_frame

	var s1 := _survey(wpn, mpos)
	print("\n── 开火后 ──")
	print("  SphereMesh 球数 = %d" % (s1["spheres"] as Array).size())
	for sp in s1["spheres"]:
		var mi := sp["node"] as MeshInstance3D
		print("    球 @ %s  离枪口 %.2f m" % [
			str(mi.global_position.snappedf(0.01)), float(sp["dist"])])
	print("  CylinderMesh 光柱层数 = %d" % int(s1["cylinders"]))

	# ① 枪口 0.6 m 内不该有球
	var near_spheres := 0
	for sp in s1["spheres"]:
		if float(sp["dist"]) < 0.6:
			near_spheres += 1
	_check(near_spheres == 0,
		"枪口附近**没有圆球**（%.1f m 内 %d 个，应为 0）" % [0.6, near_spheres])

	# ② 激光光柱在（每层一个 CylinderMesh，共 5 层）
	_check(int(s1["cylinders"]) >= 3,
		"激光光柱**在**（%d 层圆柱）" % int(s1["cylinders"]))

	# ③ 机甲状态仍保留炮口闪光
	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	MechStateScript.call("set_carrier_for_test", true)
	var carrier := player.get_node_or_null("Arisu/CarrierForm")
	if carrier != null:
		carrier.call("set_form", true)
		for _i in 25:
			await process_frame
		wpn.call("trigger_down")
		await process_frame
		wpn.call("trigger_up")
		for _i in 3:
			await process_frame
		var s2 := _survey(wpn, mpos)
		print("\n── 机甲状态开火 ──")
		print("  SphereMesh 球数 = %d（炮口闪光是保留的）" % (s2["spheres"] as Array).size())
		_check(not bool(wpn.get("laser_gun")) or bool(wpn.get("beam_mode")),
			"机甲状态下 beam_mode = true")

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 普通攻击只有激光线" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)
