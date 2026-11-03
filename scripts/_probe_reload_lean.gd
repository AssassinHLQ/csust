extends SceneTree
## 探针：**跑着换弹**时身体是不是被掰歪了（用户 2026-11-03 报「整个人歪着」）。
##
##   _tools/run_probe.sh res://scripts/_probe_reload_lean.gd -- --splat=off
##
## 做法照 `_probe_fire_lean.gd`：每根骨记「全局姿态的上轴与骨架上轴的夹角」，
## 四种情况各采样一段，再按「跑+换弹 − 跑」的差值排序 —— 差值大的就是元凶。
##
## 额外打印**当时在播哪一层**、那一层的 `Normal_Reload` 还剩多少条轨道
## （躯干 / 手臂有没有被滤掉）。这是判「歪」到底来自动作数据还是来自叠加层选择的关键。

const SPAWN := Vector3(0, 0.05, 6)
const WINDOW_MS := 700
const TOP := 12

var _p: Player
var _anim: AnimDriver
var _sk: Skeleton3D
var _axes := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)
	_p = game.get_node_or_null("Player") as Player
	if _p == null:
		print("!! 没有 Player")
		quit(1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_anim = _p.anim as AnimDriver
	_sk = _anim.skeleton
	if _sk == null:
		print("!! 没有 Skeleton3D")
		quit(1)
		return
	print("[reload] 骨架 %d 根骨" % _sk.get_bone_count())
	print("[reload] IDLE_SPEED=%.2f  跑速门槛=%s" % [
		AnimDriver.IDLE_SPEED, str(AnimDriver.WALK_THRESHOLD)])

	var conds := [
		{"n": "站定", "run": false, "fire": false, "reload": false},
		{"n": "跑", "run": true, "fire": false, "reload": false},
		{"n": "跑+换弹", "run": true, "fire": false, "reload": true},
		{"n": "站定+换弹", "run": false, "fire": false, "reload": true},
		{"n": "跑+开火", "run": true, "fire": true, "reload": false},
	]
	var data := {}
	for c in conds:
		data[c["n"]] = await _sample(c)

	var n := _sk.get_bone_count()
	var order: Array = []
	for i in n:
		order.append({"i": i, "d": float(data["跑+换弹"][i]) - float(data["跑"][i])})
	order.sort_custom(func(a, b): return a["d"] > b["d"])

	print("\n===== 倾角（骨的「上」轴与骨架「上」轴的夹角，度）=====")
	print("%-26s %7s %7s %9s %9s %9s %10s" % [
		"骨", "站定", "跑", "跑+换弹", "站定+换弹", "跑+开火", "差(换弹-跑)"])
	for k in TOP:
		var i: int = order[k]["i"]
		print("%-26s %7.1f %7.1f %9.1f %9.1f %9.1f %10.1f" % [
			_sk.get_bone_name(i),
			data["站定"][i], data["跑"][i], data["跑+换弹"][i],
			data["站定+换弹"][i], data["跑+开火"][i], order[k]["d"]])

	print("\n===== 躯干骨的上轴向量（骨架空间）=====")
	for bn in ["Bip001 Spine", "Bip001 Spine1", "Bip001 Neck", "Bip001 Pelvis"]:
		for c in conds:
			var a: Dictionary = _axes.get(c["n"], {})
			print("  %-16s %-10s %s" % [bn, c["n"], str(a.get(bn, "-"))])

	_release()
	await _wait(2)

	# ── 移动层里 `Normal_Reload` 到底还留着哪些骨 ──
	print("\n===== UpperBodyMove 里 Normal_Reload 留下的轨道 =====")
	var a: Animation = _anim.upper_move.get_animation("Normal_Reload")
	var kept: Array = []
	var trunkish: Array = []
	for t in a.get_track_count():
		var bone := String(a.track_get_path(t).get_concatenated_subnames())
		kept.append(bone)
		var low := bone.to_lower()
		for kw in ["spine", "chest", "neck", "head", "pelvis", "hip", "thigh",
				"calf", "leg", "torso", "waist", "upperarm", "forearm", "hand"]:
			if low.contains(kw):
				trunkish.append(bone)
				break
	print("  共 %d 条" % kept.size())
	print("  其中疑似躯干/腿/手臂（本该被滤掉的）：%s" % str(trunkish))

	# ★ 重点：名字为空的轨道 = **节点轨道**（不是骨骼轨道），`_bone_of()` 返回 ""
	#   于是任何关键字都匹配不上，两层都没滤掉它。如果是模型根节点的 transform，
	#   播出来就是「整个人被掰歪」。
	for pair in [["UpperBody", _anim.upper], ["UpperBodyMove", _anim.upper_move]]:
		var l: AnimationPlayer = pair[1]
		if l == null or not l.has_animation("Normal_Reload"):
			continue
		var an: Animation = l.get_animation("Normal_Reload")
		var node_tracks: Array = []
		for t in an.get_track_count():
			var p := an.track_get_path(t)
			if not String(p).contains(":"):
				node_tracks.append("%s [type=%d]" % [str(p), an.track_get_type(t)])
		print("  %-14s 节点轨道 %d 条：%s" % [pair[0], node_tracks.size(), str(node_tracks)])

	quit()


func _sample(c: Dictionary) -> Array:
	_release()
	_p.velocity = Vector3.ZERO
	_p.global_position = SPAWN
	_p._yaw = 0.0
	_p._facing_yaw = PI
	_p.model_root.rotation.y = PI
	_anim.state = AnimDriver.State.LOCOMOTION
	_anim.stop_upper_layer()
	await _wait(6)
	if c["run"]:
		Input.action_press("move_forward")
		Input.action_press("sprint")
		await _wait_ms(600)
	if c["fire"]:
		_anim.request_fire()
		await _wait_ms(80)
	if c["reload"]:
		_anim.request_reload()
		await _wait_ms(80)

	# 播的是哪一层、那一层的 Normal_Reload 还剩多少条轨道
	var layer: AnimationPlayer = _anim.active_upper_layer()
	var layer_name := "<null>"
	var tracks := -1
	if layer != null:
		layer_name = String(layer.name)
		if layer.has_animation("Normal_Reload"):
			tracks = layer.get_animation("Normal_Reload").get_track_count()
	print("\n[reload] 「%s」→ 应使用层=%s  Normal_Reload 轨道数=%d" % [c["n"], layer_name, tracks])
	# 三层是不是**同时在播** —— 如果站定层（带躯干轨道）没停，
	# 它会在 upper_move 之后按树序执行，把躯干又写回站桩姿势。
	for pair in [["UpperBody", _anim.upper], ["UpperBodyMove", _anim.upper_move],
			["Arms", _anim.arms]]:
		var l: AnimationPlayer = pair[1]
		if l == null:
			print("        %-14s <null>" % pair[0])
			continue
		print("        %-14s playing=%-5s clip=%-20s pos=%.2f prio=%d" % [
			pair[0], str(l.is_playing()), String(l.current_animation),
			l.current_animation_position, l.process_priority])

	var n := _sk.get_bone_count()
	var worst := []
	worst.resize(n)
	worst.fill(0.0)
	var axes := {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < WINDOW_MS:
		await process_frame
		for i in n:
			var up := _sk.get_bone_global_pose(i).basis.y.normalized()
			var deg := rad_to_deg(Vector3.UP.angle_to(up))
			if deg > worst[i]:
				worst[i] = deg
		for bn in ["Bip001 Spine", "Bip001 Spine1", "Bip001 Neck", "Bip001 Pelvis"]:
			var i := _sk.find_bone(bn)
			if i >= 0:
				axes[bn] = str(_sk.get_bone_global_pose(i).basis.y.normalized().snappedf(0.01))
	_release()
	_axes[c["n"]] = axes
	return worst


func _release() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right",
			"sprint", "crouch", "jump"]:
		Input.action_release(a)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
