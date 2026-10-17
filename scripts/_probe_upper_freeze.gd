extends SceneTree
## 探针：跑打开火的上半身，**逐骨**跟「只跑」差多少 —— 冻结相位，只换叠加层。
##
## 做法（README §1.20「量这个必须冻结相位」）：
##   基础层 `Move_Ing` 停在同一帧（`speed_scale = 0` + `seek(0.30)`），
##   然后只把叠加层接上去（`upper_move` / `upper`），再逐根骨比全局旋转。
##   这样两份快照的**下半身和跑步相位完全相同**，差多少都是叠加层贡献的。
##
## 目的：`ARM_KEYWORDS` 加进移动层之后，跑打开火应该和只跑**逐骨几乎相同**
##       （只剩头发 / 武器 / 挂饰那几簇在动）。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_upper_freeze.gd -- --splat=off

const GAME := "res://scenes/game.tscn"
const CLIP := "Normal_Attack_Ing"
const BASE_T := 0.30
const LAYER_T := 0.40


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)
	var p := game.get_node_or_null("Player")
	var anim = p.get("anim")
	p.set_physics_process(false)
	var sk: Skeleton3D = anim.get("skeleton")
	var base: AnimationPlayer = anim.get("player")
	var upper_move: AnimationPlayer = anim.get("upper_move")
	var upper: AnimationPlayer = anim.get("upper")

	# 先让 `_speed` 落到跑的速度（层选择用），再把基础层冻在同一帧
	anim.call("set_locomotion", 6.8, true, 0.0)
	await _wait(4)
	base.speed_scale = 0.0
	base.play("Move_Ing")
	base.seek(BASE_T, true)
	await _wait(3)
	var run := _snap(sk)

	# ── 跑 + 开火（移动层）──
	upper_move.speed_scale = 0.0
	upper_move.play(CLIP)
	upper_move.seek(LAYER_T, true)
	await _wait(3)
	var run_fire := _snap(sk)
	print("\n=== 只跑 vs 跑+开火（移动层，同一跑步相位）===")
	_diff(sk, run, run_fire)
	print("  移动层滤掉：下半身 %d 条 / 躯干 %d 条 / 手臂 %d 条" % [
		int(anim.get("lower_tracks_removed")), int(anim.get("trunk_tracks_removed")),
		int(anim.get("arm_tracks_removed"))])
	upper_move.stop()

	# ── 反向对照：站定待机 vs 站定开火（静止层，不该被滤）──
	base.play("Normal_Idle")
	base.seek(BASE_T, true)
	await _wait(3)
	var idle := _snap(sk)
	upper.speed_scale = 0.0
	upper.play(CLIP)
	upper.seek(LAYER_T, true)
	await _wait(3)
	var stand_fire := _snap(sk)
	print("\n=== 站定待机 vs 站定开火（静止层，反向对照，必须差很多）===")
	_diff(sk, idle, stand_fire)
	quit(0)


func _snap(sk: Skeleton3D) -> Array:
	var out := []
	for i in sk.get_bone_count():
		out.append(sk.get_bone_global_pose(i).basis.orthonormalized()
			.get_rotation_quaternion())
	return out


func _diff(sk: Skeleton3D, a: Array, b: Array) -> void:
	var buckets := {}
	for i in mini(a.size(), b.size()):
		var q1: Quaternion = a[i]
		var q2: Quaternion = b[i]
		var deg := rad_to_deg(q1.angle_to(q2))
		var g := _group(String(sk.get_bone_name(i)))
		if not buckets.has(g):
			buckets[g] = [0.0, 0]
		if deg > buckets[g][0]:
			buckets[g][0] = deg
		if deg > 0.5:
			buckets[g][1] += 1
	print("  按组（最大夹角 / 差 >0.5° 的根数）：")
	for g in ["躯干", "手臂", "武器", "头发", "脸", "其它"]:
		if buckets.has(g):
			print("    %-4s  %6.1f°  / %3d 根" % [g, buckets[g][0], buckets[g][1]])


func _group(bone: String) -> String:
	var s := bone.to_lower()
	for k in ["spine", "chest", "neck", "pelvis", "head"]:
		if s.contains(k):
			return "躯干" if not s.contains("eye") else "脸"
	for k in ["clavicle", "shoulder", "upperarm", "forearm", "deltoid",
			"twist", "hand", "finger", "arm"]:
		if s.contains(k):
			return "手臂"
	for k in ["weapon", "railgun", "magazine", "muzzle", "point"]:
		if s.contains(k):
			return "武器"
	if s.contains("hair"):
		return "头发"
	for k in ["eye", "eyering", "eyebrow", "xtra"]:
		if s.contains(k):
			return "脸"
	return "其它"


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
