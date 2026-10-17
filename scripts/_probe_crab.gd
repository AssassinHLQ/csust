extends SceneTree
## 探针：**「右转螃蟹 / 右倾」到底是哪根骨在歪**。
##
## 用户 2026-10-18：
##   「右倾还在」
##   「攻击一下后再开始走路会变成爱丽丝右转螃蟹平移」
##   「走路时攻击一次保持走路会触发右倾」
##
## 排除掉的可能（已经量过，不用再怀疑）：
##   · 动作库：`Cafe_Walk` / `Move_Ing` / `RunFire_Ing` 对锁骨 / 手 / 枪 / 脊椎
##     全都有**旋转**轨道 → `_aim_gun()` 写进去的姿势下一帧就会被动画盖回去，不会残留；
##   · 朝向逻辑：`_fire_held` 一松就 `_facing_yaw = atan2(dir)`，不可能一直朝准星。
##
## 所以「人看着往右拧」只可能是**骨架自己**拧了 —— 也就是动作里 `Bip001`（根骨）
## 的偏航 / 侧倾。这个量必须拿「脚」去量，不能拿 model_root 去量：
##   · 脚轴：`L Toe − R Toe` 的水平投影 vs 角色右方向 `model_root.basis.x`
##     —— 站直时两者平行（0°）；人「横着走」时这个角就是螃蟹角；
##   · 胸椎（`Spine1`）的 up 轴在角色右方向上的分量 = 右倾角。
##
## 顺带把每个状态的枪管方向、`Bip001` 偏航、`speed_scale` 一起打出来。
##
## 用法：
##   godot --path <工程> --headless --script res://scripts/_probe_crab.gd -- --splat=off
## 只读。

var _sk: Skeleton3D
var _p: Player
var _anim: AnimDriver
var _wpn: Weapon


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(12)
	# ⚠️ 开场剧情会把整棵树暂停 —— 暂停时 `AnimDriver._process` 不跑，
	#    `_aim_gun()` 等于没生效。必须解除，否则量到的是「没有瞄准修正」的姿势。
	paused = false
	_p = game.get_node_or_null("Player") as Player
	if _p == null or _p.anim == null:
		print("!! 没有 Player/AnimDriver")
		quit(1)
		return
	_anim = _p.anim as AnimDriver
	_sk = _anim.skeleton
	_wpn = game.get_node_or_null("Player/Weapon") as Weapon
	_p.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(4)

	print("=== 骨架查找 ===")
	for kw in ["Bip001", "Pelvis", "Spine1", "Spine3", "Toe", "Foot", "Clavicle",
			"Hand", "Weapon", "Muzzle"]:
		print("  %-10s → %s" % [kw, _like(kw)])

	print("\n=== 状态序列（每 20 帧一行）===")
	print("  帧  阶段        clip           ss   脚轴-右  脚轴-前  胸右倾  根偏航  枪管-角色  枪管-准星  状态")
	_anim.reset_state()
	_anim.set_locomotion(0.0, true, 0.0)
	await _wait(30)
	_row(0, "站定")
	for spd in [2.4]:
		_anim.reset_state()
		_anim.set_locomotion(0.0, true, 0.0)
		await _wait(20)
		for i in 60:
			_anim.set_locomotion(spd, true, 0.0)
			await process_frame
			if i % 20 == 19:
				_row(i + 1, "走路 %.1f" % spd)
		# 走打
		_anim.request_fire()
		for i in 60:
			_anim.set_locomotion(spd, true, 0.0)
			await process_frame
			if i % 20 == 19:
				_row(i + 1, "走打 %.1f" % spd)
		# 松手（继续走）：`Weapon.trigger_up()` 现在会调 `cancel_fire()`，
		# 这里等价地调一次，看它多久交回走路动画
		_anim.cancel_fire()
		for i in 200:
			_anim.set_locomotion(spd, true, 0.0)
			await process_frame
			if i % 10 == 9 or i == 199:
				_row(i + 1, "松手后")
	quit(0)


func _row(f: int, tag: String) -> void:
	var model := _p.model_root.global_transform.basis
	var fwd := model.z.normalized()
	var right := model.x.normalized()
	var toe_l := _wp("L Toe")
	var toe_r := _wp("R Toe")
	var foot_ax := (toe_l - toe_r)
	foot_ax.y = 0.0
	foot_ax = foot_ax.normalized()
	var foot_vs_right := 0.0
	var foot_vs_fwd := 0.0
	if foot_ax.length_squared() > 0.01:
		foot_vs_right = rad_to_deg(acos(clampf(foot_ax.dot(right), -1.0, 1.0)))
		foot_vs_fwd = rad_to_deg(acos(clampf(absf(foot_ax.dot(fwd)), -1.0, 1.0)))
	var spine_up: Vector3 = _anim.bone_up_axis("Bip001 Spine1")
	var roll := rad_to_deg(asin(clampf(spine_up.dot(right), -1.0, 1.0)))
	# 根骨偏航：`Bip001` 的前向 vs 角色前向
	var root_yaw := 0.0
	var ri := _sk.find_bone("Bip001")
	if ri >= 0:
		var rb := (_sk.global_transform * _sk.get_bone_global_pose(ri)).basis
		var rf := (rb * Vector3.FORWARD)
		rf.y = 0.0
		if rf.length_squared() > 0.01:
			root_yaw = rad_to_deg(atan2(rf.normalized().cross(fwd).y, rf.normalized().dot(fwd)))
	# 枪管方向
	var barrel := _barrel_dir()
	var gun_vs_model := 0.0
	var gun_vs_cam := 0.0
	if barrel.length_squared() > 0.01:
		var b := barrel.normalized()
		gun_vs_model = rad_to_deg(acos(clampf(b.dot(fwd), -1.0, 1.0)))
		var cam: Camera3D = root.get_camera_3d()
		if cam != null:
			gun_vs_cam = rad_to_deg(acos(clampf(b.dot(-cam.global_transform.basis.z.normalized()), -1.0, 1.0)))
	print("  %3d  %-10s %-14s %.2f  %+6.1f°  %+6.1f°  %+6.1f°  %+5.1f°  %+7.1f°   %+6.1f°  %-10s"
		% [f, tag, _anim.current_clip(), _anim.player.speed_scale, foot_vs_right, foot_vs_fwd,
		roll, root_yaw, gun_vs_model, gun_vs_cam, _anim.current_state_name()])


func _barrel_dir() -> Vector3:
	var m := _sk.find_bone(AnimDriver.GUN_MUZZLE_BONE)
	var g := _sk.find_bone(AnimDriver.GUN_BREECH_BONE)
	if m < 0 or g < 0:
		return Vector3.ZERO
	return _wp_bone(m) - _wp_bone(g)


func _wp_bone(i: int) -> Vector3:
	return _sk.global_transform * _sk.get_bone_global_pose(i).origin


func _wp(kw: String) -> Vector3:
	var n := _like(kw)
	if n.is_empty():
		return Vector3.ZERO
	return _wp_bone(_sk.find_bone(n))


## 找到第一根「名字里带 kw」的骨（`L Toe` 之类的短名用）
func _like(kw: String) -> String:
	for i in _sk.get_bone_count():
		var nm := _sk.get_bone_name(i)
		if nm.to_lower().contains(kw.to_lower()):
			return nm
	return ""


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
