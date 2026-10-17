extends SceneTree
## 探针：玩家什么时候会「躺下」。
##
## 判据用**世界空间**的躯干朝向，不碰动画/骨骼名：
##   `up = Vector3.UP.dot((head_world - hips_world).normalized())`
##   站着 ≈ +1.0，躺平 ≈ 0.0，倒立 ≈ −1.0。
##
## 覆盖的状态：待机 / 走 / 跑 / 蹲 / 开镜 / 开火 / 跑打 / 换弹 / 停火之后 / 落地。
## 每个状态都打印「up + 当前动画名 + AnimationPlayer.active」，出问题的那一档
## 一眼就能对上。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_player_down.gd -- --splat=off

const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)

	var p := game.get_node_or_null("Player")
	if p == null:
		print("!! 没有 Player")
		quit(1)
		return
	var anim = p.get("anim")
	if anim == null:
		print("!! Player 上没有 anim")
		quit(1)
		return

	# 玩家自己每帧拿真实速度喂 set_locomotion（站着就是 0），接管之后好控制
	p.set_physics_process(false)

	print("\n=== 玩家：世界空间躯干朝向 ===")
	print("%-22s %7s  %-24s %-8s" % ["状态", "up", "animation", "active"])
	_report(anim, "初始（待机）")

	anim.call("set_locomotion", 1.6, true, 0.0)
	await _wait(10)
	_report(anim, "走 1.6")

	anim.call("set_locomotion", 6.8, true, 0.0)
	await _wait(10)
	_report(anim, "跑 6.8")

	# 站桩开火
	anim.call("set_locomotion", 0.0, true, 0.0)
	await _wait(4)
	anim.call("request_fire")
	await _wait(4)
	_report(anim, "站桩开火")

	# 跑打
	anim.call("set_locomotion", 6.8, true, 0.0)
	anim.call("request_fire")
	await _wait(4)
	_report(anim, "跑打")

	# 开火动作播完之后（一次性动作结束 → 回 LOCOMOTION）
	anim.call("set_locomotion", 6.8, true, 0.0)
	await _wait(90)
	_report(anim, "跑打（动作播完）")

	# 停火：从跑切回待机
	anim.call("set_locomotion", 0.0, true, 0.0)
	await _wait(30)
	_report(anim, "停火回待机")

	# 换弹
	anim.call("request_reload")
	await _wait(6)
	_report(anim, "换弹")

	# 空中（跳跃）
	anim.call("set_locomotion", 0.0, false, 4.0)
	await _wait(10)
	_report(anim, "空中 vy=+4")

	# 下落
	anim.call("set_locomotion", 2.0, false, -9.0)
	await _wait(10)
	_report(anim, "下落 vy=−9")

	# 落地后
	anim.call("set_locomotion", 0.0, true, 0.0)
	await _wait(20)
	_report(anim, "落地后")

	print("\n=== 骨骼原始读数（最后一帧）===")
	_dump_bones(anim)
	quit(0)


func _report(anim, label: String) -> void:
	var up := _trunk_up(anim)
	var ap: AnimationPlayer = anim.get("player")
	var cur := "—"
	if ap != null:
		var list := ap.get_animation_list()
		for name in list:
			if ap.is_playing():
				cur = String(name)
				break
	print("%-22s %7.3f  %-24s %s" % [label, up, cur, str(ap.active if ap else false)])


## 世界的「躯干上方向」：头 − 髋，归一化后与全局 UP 点乘。
func _trunk_up(anim) -> float:
	var sk: Skeleton3D = anim.get("skeleton")
	if sk == null:
		return -999.0
	var head := _bone_world(sk, "head")
	var hips := _bone_world(sk, "pelvis")
	if head == Vector3.ZERO or hips == Vector3.ZERO:
		return -999.0
	var d := head - hips
	if d.length() < 0.0001:
		return -999.0
	return Vector3.UP.dot(d.normalized())


func _bone_world(sk: Skeleton3D, keyword: String) -> Vector3:
	var idx := -1
	var k := keyword.to_lower()
	for b in sk.get_bone_count():
		if String(sk.get_bone_name(b)).to_lower().contains(k):
			idx = b
			break
	if idx < 0:
		return Vector3.ZERO
	return sk.global_transform * sk.get_bone_global_pose(idx).origin


func _dump_bones(anim) -> void:
	var sk: Skeleton3D = anim.get("skeleton")
	if sk == null:
		print("!! 没有 skeleton")
		return
	for k in ["pelvis", "spine1", "head"]:
		var idx := -1
		for b in sk.get_bone_count():
			if String(sk.get_bone_name(b)).to_lower().contains(k):
				idx = b
				break
		if idx < 0:
			print("  %-8s 找不到" % k)
			continue
		var g := sk.get_bone_global_pose(idx)
		print("  %-8s name=%-18s 世界位置 %s  上轴 %s" % [
			k, sk.get_bone_name(idx),
			str(_bone_world(sk, k).snappedf(0.01)),
			str(g.basis.y.normalized().snappedf(0.01))])


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
