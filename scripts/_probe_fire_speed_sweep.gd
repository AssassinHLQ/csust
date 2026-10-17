extends SceneTree
## 探针：**速度扫描** —— 开火时用的上层到底是哪一层，躯干有没有被那一层掰走。
##
## 怀疑：层的选择看的是 `request_fire()` 那一帧的 `_speed`。
##   速度 < `WALK_THRESHOLD`(2.8) → `UpperBodyIdle`（**不滤躯干**）→ 站桩开火那套
##   上半身盖到走路/慢跑姿势上；> 2.8 → `UpperBodyMove`（滤躯干）→ 跑步姿势保持。
## 所以「刚要起步就扣扳机」和「跑起来再扣」看起来会完全不同。
##
## 每个速度量三次：只移动 / 开火中 / 开火结束后。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_fire_speed_sweep.gd -- --splat=off

const GAME := "res://scenes/game.tscn"
const SPEEDS := [0.0, 0.8, 1.6, 2.4, 3.2, 4.5, 6.8]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)
	var p := game.get_node_or_null("Player")
	var anim = p.get("anim")
	p.set_physics_process(false)

	print("\n=== 速度扫描（躯干 up = head−pelvis 与世界上方向夹角余弦；1.0=完全直立）===")
	print("%6s  %8s  %8s  %8s  %-18s" % ["速度", "只移动", "开火中", "开火后", "开火时的层"])
	for v in SPEEDS:
		anim.call("set_locomotion", v, true, 0.0)
		await _wait(26)
		var base := _up(anim)
		var layer := "—"
		anim.call("set_locomotion", v, true, 0.0)
		anim.call("request_fire")
		await _wait(8)
		var fired := _up(anim)
		var l = anim.call("active_upper_layer")
		layer = "null" if l == null else String(l.name)
		await _wait(80)                      # 等这一发动作播完
		anim.call("set_locomotion", v, true, 0.0)
		await _wait(10)
		var after := _up(anim)
		print("%6.1f  %8.3f  %8.3f  %8.3f  %-18s   Δ(开火−只移动)=%+.1f°" % [
			v, base, fired, after, layer, rad_to_deg(acos(clampf(fired, -1.0, 1.0))
				- acos(clampf(base, -1.0, 1.0)))])
		# 收尾：把上层关掉，免得漏到下一个速度
		anim.call("set_locomotion", 0.0, true, 0.0)
		await _wait(20)
	quit(0)


func _up(anim) -> float:
	var sk: Skeleton3D = anim.get("skeleton")
	var head := _bone_world(sk, "head")
	var hips := _bone_world(sk, "pelvis")
	var d := head - hips
	if d.length() < 0.0001:
		return 0.0
	return Vector3.UP.dot(d.normalized())


func _bone_world(sk: Skeleton3D, keyword: String) -> Vector3:
	var k := keyword.to_lower()
	for b in sk.get_bone_count():
		if String(sk.get_bone_name(b)).to_lower().contains(k):
			return sk.global_transform * sk.get_bone_global_pose(b).origin
	return Vector3.ZERO


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
