extends SceneTree
## 探针：量「弹丸视觉起点」到底落在哪 —— 枪口骨 / 右手骨 / 弹道起点（相机那条线）。
##
## 背景（README §1.9）：Arisu.glb 的枪**不在手上**，它挂在一条根级骨骼
## `Bip001_Weapon` 上、位置是**世界坐标动画**，所以枪（和枪口骨）会飘在身体以外
## 约 0.6 m。弹丸/火光从那儿出来时，玩家看到的是「子弹从身后/侧后方飞出去」。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_weapon.gd -- --splat=off
##
## 输出每列：
##   枪口相对玩家的位置（玩家局部坐标，-Z 是正前方）
##   枪口在弹道方向上的投影（< 0 = 起点在弹道之后 → 就是「太靠后」）
##   右手骨同上

var _player: Player
var _weapon: Weapon
var _skel: Skeleton3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	# 同伴/泼溅与本探针无关：把同伴摘掉免得抢骨骼查找，泼溅用 --splat=off 关
	for child in game.get_children():
		if child is Companion:
			child.free()
	root.add_child(game)
	await _wait(40)

	_player = game.get_node_or_null("Player")
	_weapon = _player.get_node_or_null("Weapon") as Weapon if _player else null
	_skel = _player.get_node_or_null("Arisu/Model/Aris_Original_Mesh/bone_root/Bip001/Skeleton3D") as Skeleton3D
	if _player == null or _weapon == null or _skel == null:
		push_error("[weapon] 没找到 player / weapon / skeleton")
		quit(1)
		return

	print("[weapon] 骨架 = %s（%d 骨）" % [_skel.get_path(), _skel.get_bone_count()])
	for bone_name in ["bone_Railgun_Muzzle_03", "bone_Railgun_Muzzle_01", "Bip001 R Hand", "Bip001 L Hand"]:
		var idx := _skel.find_bone(bone_name)
		print("[weapon] 骨 %-24s 索引 = %d" % [bone_name, idx])
	print("[weapon] weapon._muzzle_bone = %d" % int(_weapon.get("_muzzle_bone")))

	# 让玩家站在平台中央、面朝 -Z（出生朝向），相机绕角 0
	_player.global_position = Vector3(0, 0.05, 0)
	_player._yaw = 0.0
	_player._facing_yaw = PI
	_player.model_root.rotation.y = PI
	_player.rig.rotation.y = 0.0
	_player._pitch = -0.04
	await _wait(60)

	var clips := ["Normal_Idle", "Normal_Attack_Ing", "Move_Ing"]
	var driver: AnimDriver = _player.get_node_or_null("Arisu/Model/AnimDriver") as AnimDriver
	for clip in clips:
		if driver != null and driver.has_method("play"):
			driver.play(clip, 0.0)
		await _wait(20)
		_report(clip)
	_report("（当前动作）")

	# 实际开一枪，看弹丸创建在哪儿
	print("[weapon] ---- 开一枪，看弹丸/火光起点 ----")
	_weapon.call("shoot")
	await _wait(2)
	var cam := _player.cam
	var origin := cam.global_position
	print("[weapon] 相机 %s   弹道起点 %s   枪口 %s" % [
		str(cam.global_position.snappedf(0.01)),
		str(origin.snappedf(0.01)),
		str(_weapon.muzzle.global_position.snappedf(0.01))])
	quit(0)


func _report(clip: String) -> void:
	var cam := _player.cam
	var fwd := -cam.global_transform.basis.z
	var origin := cam.global_position
	# 玩家的局部坐标（-Z 是正前方）
	var to_local := _player.global_transform.affine_inverse()
	var muzzle_local: Vector3 = to_local * _weapon.muzzle.global_position
	var hand_idx := _skel.find_bone("Bip001 R Hand")
	var hand_world: Vector3 = _skel.global_transform * _skel.get_bone_global_pose(hand_idx).origin
	var hand_local: Vector3 = to_local * hand_world
	# 在弹道方向上，枪口/右手相对弹道起点是「靠前」还是「靠后」
	var m_along := (_weapon.muzzle.global_position - origin).dot(fwd)
	var h_along := (hand_world - origin).dot(fwd)
	var m_lat := ((_weapon.muzzle.global_position - origin) - fwd * m_along).length()
	var h_lat := ((hand_world - origin) - fwd * h_along).length()
	print("[weapon] %-18s 枪口: 局部 %s  沿弹道 %+.3f 横向 %.3f   |  右手: 局部 %s  沿弹道 %+.3f 横向 %.3f" % [
		clip, str(muzzle_local.snappedf(0.01)), m_along, m_lat,
		str(hand_local.snappedf(0.01)), h_along, h_lat])


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
