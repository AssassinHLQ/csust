extends SceneTree
## 探针：**先扣扳机、后起跑** —— 那一发会不会一直用「站桩层」把躯干锁住。
##
## 怀疑的路径（`AnimDriver._play_once()`）：
##   层是在**开火那一瞬间**按 `_speed` 选的，选完这一发就定死了：
##       `_speed <= IDLE_SPEED` → `upper`（完整站桩上半身，**含脊椎/颈/头**）
##       `_speed >  IDLE_SPEED` → `upper_move`（滤掉躯干）
##   所以「站着扣扳机 → 立刻按 Shift 跑起来」这一发会在**整段 1.07 s 的连射**里
##   继续用站桩层，躯干被锁在站桩姿势 —— 观感就是「跑起来身体还后仰着」。
##
## 本探针：站着开火 → 第 10 帧开始跑（6.8）→ 每 15 帧量一次躯干 up，
## 一直到这一发结束。再补一个对照组：跑起来再开火。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_fire_then_run.gd -- --splat=off

const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)
	var p := game.get_node_or_null("Player")
	var anim = p.get("anim")
	p.set_physics_process(false)

	print("\n=== A. 先站着开火，第 10 帧开始跑 ===")
	anim.call("set_locomotion", 0.0, true, 0.0)
	await _wait(24)
	print("  开火前（站）up=%.3f" % _up(anim))
	anim.call("request_fire")
	await _wait(10)
	print("  开火中（还没跑）up=%.3f  层=%s" % [_up(anim), _layer(anim)])
	for i in 6:
		anim.call("set_locomotion", 6.8, true, 0.0)
		await _wait(15)
		print("  跑起来 +%2d 帧  up=%.3f  层=%s  基=%s" % [
			(i + 1) * 15, _up(anim), _layer(anim), anim.get("player").current_animation])

	print("\n=== B. 对照：先跑起来再开火 ===")
	anim.call("set_locomotion", 6.8, true, 0.0)
	await _wait(40)
	print("  跑着（没开火）up=%.3f" % _up(anim))
	anim.call("request_fire")
	for i in 4:
		anim.call("set_locomotion", 6.8, true, 0.0)
		await _wait(15)
		print("  跑 +%2d 帧  up=%.3f  层=%s" % [
			(i + 1) * 15, _up(anim), _layer(anim)])
	quit(0)


func _layer(anim) -> String:
	var l = anim.call("active_upper_layer")
	if l == null:
		return "null"
	return "%s%s" % [String(l.name), "" if l.is_playing() else "(停)"]


func _up(anim) -> float:
	var sk: Skeleton3D = anim.get("skeleton")
	var head := _bone_world(sk, "head")
	var hips := _bone_world(sk, "pelvis")
	var d := head - hips
	if d.length() < 0.0001:
		return 0.0
	return Vector3.UP.dot(d.normalized())


func _bone_world(sk: Skeleton3D, keyword: String) -> Vector3:
	for b in sk.get_bone_count():
		if String(sk.get_bone_name(b)).to_lower().contains(keyword):
			return sk.global_transform * sk.get_bone_global_pose(b).origin
	return Vector3.ZERO


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
