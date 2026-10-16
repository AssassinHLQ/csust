extends SceneTree
## 探针：跑打开火时「身体倾斜了好多」到底是**哪几根骨**在倾。
##
## 用户报：「跑打确实腿动了但是感觉身体倾斜了好多」。
##
## 上半身叠加层（`anim_driver._setup_upper_layer()`）只滤掉了**下半身**
## （`LOWER_KEYWORDS`：thigh/calf/foot/leg/pelvis/hip/root/skirt），
## 于是 `Normal_Attack_Ing` 里**脊椎 / 胸 / 颈**那些「站桩开火」的大幅前倾
## 会一帧盖到跑步的躯干上 —— 本探针把每根骨的倾角量出来，看看是谁。
##
## 判据：每根骨的**全局姿态的「上」轴**（`basis.y`）与骨架「上」轴的夹角。
##   · 站定 / 跑 / 跑+开火 / 站定+开火 四种情况各采样一段，取该骨的最大倾角
##   · 再按「跑+开火 − 跑」的差值排序 —— 差值大的就是叠加层多加的倾
##
## 用法：godot --path <工程> --script res://scripts/_probe_fire_lean.gd -- --splat=off

const SPAWN := Vector3(0, 0.05, 6)
const WINDOW_MS := 700
const TOP := 14          ## 只打印差值最大的前 N 根

var _p: Player
var _anim: AnimDriver
var _sk: Skeleton3D
## 每种情况里几根躯干骨的「上」轴向量（打印用）
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
	print("[probe] 骨架 %d 根骨" % _sk.get_bone_count())

	var conds := [
		{"n": "站定", "run": false, "fire": false},
		{"n": "跑", "run": true, "fire": false},
		{"n": "跑+开火", "run": true, "fire": true},
		{"n": "站定+开火", "run": false, "fire": true},
	]
	var data := {}
	for c in conds:
		data[c["n"]] = await _sample(c)

	# ── 差值排序 ──
	var n := _sk.get_bone_count()
	var order: Array = []
	for i in n:
		var d: float = float(data["跑+开火"][i]) - float(data["跑"][i])
		order.append({"i": i, "d": d})
	order.sort_custom(func(a, b): return a["d"] > b["d"])

	print("\n===== 倾角（骨的「上」轴与骨架「上」轴的夹角，度）=====")
	print("%-26s %8s %8s %8s %8s %8s" % ["骨", "站定", "跑", "跑+开火", "站+开火", "差(跑打-跑)"])
	for k in TOP:
		var i: int = order[k]["i"]
		print("%-26s %8.1f %8.1f %8.1f %8.1f %8.1f" % [
			_sk.get_bone_name(i),
			data["站定"][i], data["跑"][i], data["跑+开火"][i], data["站定+开火"][i],
			order[k]["d"]])

	# ── 全身最直观的一条：胸口在骨架空间里的「上」轴 ──
	print("\n===== 躯干骨的「上」轴向量（骨架空间，归一化）=====")
	for bn in ["Bip001 Spine", "Bip001 Spine1", "Bip001 Neck", "Bip001 Pelvis"]:
		var i := _sk.find_bone(bn)
		if i < 0:
			continue
		for c in conds:
			print("  %-16s %-10s %s" % [bn, c["n"], str(_axes[c["n"]].get(bn, "-"))])

	# ── 叠加层里被保留的「躯干」轨道 ──
	print("\n===== 叠加层（开火动作）里留下的躯干轨道 =====")
	var a: Animation = _anim.upper.get_animation("Normal_Attack_Ing")
	var kept: Array = []
	for t in a.get_track_count():
		var bone := String(a.track_get_path(t))
		var low := bone.to_lower()
		for kw in ["spine", "chest", "neck", "head", "waist", "torso", "clavicle", "shoulder"]:
			if low.contains(kw):
				kept.append(bone.get_slice(":", 1))
				break
	print("  留下 %d 条躯干轨道：%s" % [kept.size(), str(kept.slice(0, 24))])

	_release()
	await _wait(2)
	quit()


## 采样一种情况：每帧记录每根骨的最大倾角，返回那个数组；
## 几根躯干骨的「上」轴向量顺手记到 `_axes[情况]`。
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
		await _wait_ms(120)

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
