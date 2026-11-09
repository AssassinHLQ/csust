extends SceneTree
## 探针：机甲**从本体 glb 借来的战斗动作**是否真的搬进来了、能不能播。
##
## 跑法：
##   & <godot> --headless --path . --script res://scripts/_probe_carrier_anims.gd -- --no-capture
##
## 验的东西：
##   ① `Arisu_Battle.glb` 的 18 条目标动作全部搬进机甲 AnimationPlayer
##   ② 轨道前缀被正确改写（不是「加载成功但一根骨不动」）
##   ③ 每条动作在机甲骨架上**真正能驱动骨骼**（对比播放前后骨姿态）
##   ④ 循环动作是 LOOP_LINEAR，一次性动作是 LOOP_NONE
##   ⑤ 开火会触发 `Normal_Attack_Ing`（2026-11-09 起走**上半身叠加层** `_upper`）

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

var _fails: Array[String] = []
var _checks := 0


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  PASS  %s" % msg)
	else:
		print("  FAIL  %s" % msg)
		_fails.append(msg)


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
	_ok(cf != null, "CarrierForm 在")
	if cf == null:
		_done()
		return
	_ok(cf.set_form(true), "变形成功")
	await process_frame

	print("\n===== 1. 借动作报告 =====")
	var rep: Dictionary = cf.borrow_report
	_ok(bool(rep.get("ok", false)), "借动作成功（ok=true）")
	var merged: Array = rep.get("merged", [])
	print("       搬进来 %d 条" % merged.size())
	for m in merged:
		print("         %-22s → %-22s %5.2f s  %3d 轨道" % [
			String(m["from"]), String(m["to"]), float(m["seconds"]), int(m["tracks"])])
	print("       目标轨道前缀：%s" % str(rep.get("head_to", "")))
	var miss: Dictionary = rep.get("missing_bones", {})
	print("       目标骨架没有的骨（轨道已删）：%d 种 %s" % [miss.size(), str(miss.keys())])

	print("\n===== 2. 机甲 AnimationPlayer 里的动作清单 =====")
	var ap: AnimationPlayer = cf.get("_ap")
	_ok(ap != null, "拿到 AnimationPlayer")
	var clips := ap.get_animation_list()
	var clip_names: Array[String] = []
	for c in clips:
		clip_names.append(String(c))
	print("       共 %d 条：%s" % [clips.size(), ", ".join(clip_names)])

	var want := [
		"Normal_Idle", "Move_Ing", "Normal_Attack_Ing", "Normal_Reload",
		"Vital_Death", "Vital_Dying_Ing", "Vital_Panic", "Vital_Retreat",
		"Exs01", "Exs02_01", "Exs02_02",
		"Exs01_Cutin_01", "Exs01_Cutin_02", "Exs02_Cutin_01", "Exs02_Cutin_02",
	]
	var missing_clips: Array[String] = []
	for c in want:
		if not ap.has_animation(c):
			missing_clips.append(c)
	_ok(missing_clips.is_empty(), "15 条目标动作全在（缺 %d：%s）" % [
		missing_clips.size(), ", ".join(missing_clips)])

	print("\n===== 3. 轨道前缀是否改写正确 =====")
	var bad_prefix := 0
	for c in want:
		if not ap.has_animation(c):
			continue
		var a := ap.get_animation(c)
		for t in mini(a.get_track_count(), 3):
			var path := String(a.track_get_path(t))
			if path.find("CH0334_Carrier_Mesh") < 0:
				bad_prefix += 1
				if bad_prefix <= 3:
					print("         !! %s track%d = %s" % [c, t, path])
	_ok(bad_prefix == 0, "采样轨道的路径都指向机甲骨架（异常 %d 条）" % bad_prefix)

	print("\n===== 4. 每条动作**真正能驱动骨骼**吗 =====")
	var skel: Skeleton3D = cf.get("_skel")
	_ok(skel != null, "拿到机甲骨架")
	var dead: Array[String] = []
	for c in want:
		if not skel or not ap.has_animation(c):
			continue
		# 播到动作中段，量「有多少根骨的姿态偏离了 rest」
		var a := ap.get_animation(c)
		ap.play(c, 0.0, 1.0)
		ap.seek(a.length * 0.5, true)
		await process_frame
		var moved := 0
		var sample := ["Bip001 Pelvis", "Bip001 Spine1", "Bip001 L UpperArm", "Bip001 R UpperArm",
			"Bip001 L Thigh", "Bip001 R Thigh"]
		for bn in sample:
			var bi := skel.find_bone(bn)
			if bi < 0:
				continue
			var q := skel.get_bone_pose_rotation(bi)
			if absf(q.w) < 0.99999:
				moved += 1
		if moved == 0:
			dead.append(c)
	_ok(dead.is_empty(), "没有「播了但骨头不动」的动作（死动作：%s）" % ", ".join(dead))

	print("\n===== 5. 循环模式 =====")
	for c in ["Normal_Idle", "Move_Ing"]:
		if ap.has_animation(c):
			var m := ap.get_animation(c).loop_mode
			print("       %-14s loop_mode = %d（期望 2 = LOOP_LINEAR）" % [c, m])
			_ok(m == Animation.LOOP_LINEAR, "%s 是循环" % c)
	for c in ["Normal_Attack_Ing", "Vital_Death"]:
		if ap.has_animation(c):
			var m := ap.get_animation(c).loop_mode
			print("       %-18s loop_mode = %d（期望 0 = LOOP_NONE）" % [c, m])
			_ok(m == Animation.LOOP_NONE, "%s 是一次性" % c)

	print("\n===== 6. 开火触发攻击动作 =====")
	var wpn := player.get_node_or_null("Weapon") as Weapon
	cf.set("_oneshot_left", 0.0)
	cf.set("_last_shot_index", 0)
	wpn.current_ammo = wpn.magazine_size
	wpn.set("_cooldown", 0.0)
	wpn.shoot()
	cf.call("_run_effects", 1.0 / 60.0)
	var cur := String(ap.current_animation)
	var left := float(cf.get("_oneshot_left"))
	# ⚠️ 2026-11-09：开火改成**只叠上半身**（方案 A），动作不再落在基础层 `_ap`，
	#    而是落在叠加层 `_upper`；基础层这时**应该继续播移动动作**（腿不能冻）。
	#    叠加层没建出来时（载具 glb 缺失）才退回基础层 —— 两条路都要认，
	#    否则这条断言会站在旧设计那一边，以后谁改回去都不报警。
	var upper := cf.get("_upper") as AnimationPlayer
	var layer: AnimationPlayer = ap
	var layer_name := "基础层"
	if upper != null and upper.has_animation("Normal_Attack_Ing"):
		layer = upper
		layer_name = "叠加层"
	cur = String(layer.current_animation)
	print("       开火后 %s.current_animation = %s，_oneshot_left = %.2f（叠加层存在=%s）" % [
		layer_name, cur, left, str(upper != null)])
	_ok(cur == "Normal_Attack_Ing", "开火触发了 Normal_Attack_Ing（实际 %s）" % cur)
	if layer == upper:
		# 走叠加层时基础层不该被切成开火动作 —— 那就是「腿冻住」的旧症状
		_ok(String(ap.current_animation) != "Normal_Attack_Ing",
			"基础层没被切成开火动作（仍是 %s，腿继续动）" % ap.current_animation)
	_ok(left > 0.0, "一次性动作锁生效（%.2f s）" % left)

	MechState.set_carrier_for_test(false)
	_done()


func _done() -> void:
	print("\n========== 结果 ==========")
	if _fails.is_empty():
		print("全部 %d 项通过" % _checks)
	else:
		print("%d / %d 项失败：" % [_fails.size(), _checks])
		for f in _fails:
			print("  - %s" % f)
	print("")
	quit(0 if _fails.is_empty() else 1)
