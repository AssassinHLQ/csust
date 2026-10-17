extends SceneTree
## 探针：`RunFire_Ing` 里的枪，跟**开火动作**里的枪，在**同一具骨架**上到底差多少度。
##
## 用户 2026-10-18：「跑打时怎枪不是朝前的」。
##
## 前面的量法有一个坑：拿「场景里的枪管方向」跟「模型根节点的 −Z」比 —— 那混进了
## 模型朝向、动作相位、上一套动作的残留。这里改成**只比骨架空间**：
##   同一个 tick，分别把 `RunFire_Ing` 和 `Normal_Attack_Ing` 塞进同一个
##   `AnimationPlayer`、seek 到同一时刻，量 (muzzle − magazine) 的夹角。
## Blender 那边自检是 0.0°，所以这里只要不是 0°，就是**导进 Godot 之后**丢的。
##
## 用法：godot --path <工程> --headless --script res://scripts/_probe_gun_clip_angle.gd

const FPS := 24.0
const SAMPLES := [0, 5, 10, 15, 20, 32, 48]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(320, 200)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame
	var p := game.get_node_or_null("Player") as Player
	if p == null or p.anim == null:
		print("[ga] !! 没有 Player")
		quit(1)
		return
	p.set_physics_process(false)
	var anim := p.anim as AnimDriver
	var ap := anim.player
	var sk := anim.skeleton
	ap.speed_scale = 0.0

	var worst := 0.0
	# 角色前方在**骨架空间**是 +X（`_blender_arisu/build_anim.py`：`FWD = (1,0,0)`）
	var fwd := Vector3(1.0, 0.0, 0.0)
	for f in SAMPLES:
		var t := float(f) / FPS
		var run := await _barrel(ap, sk, anim.extra_clip, t)
		var att := await _barrel(ap, sk, "Normal_Attack_Ing", t)
		var run_ang := rad_to_deg(run.angle_to(fwd))
		var att_ang := rad_to_deg(att.angle_to(fwd))
		worst = maxf(worst, run_ang)
		print("[ga] 第 %2d 帧（%.2f s）  跑打 %s → 离前方 %.1f°   开火 %s → 离前方 %.1f°"
			% [f, t, str(run.snappedf(0.01)), run_ang, str(att.snappedf(0.01)), att_ang])
	print("[ga] 跑打：枪管离正前方最远 %.1f°（判据 < 20°）；开火动作本身仍斜 %.0f° —— 这是素材如此"
		% [worst, rad_to_deg((await _barrel(ap, sk, "Normal_Attack_Ing", 0.0)).angle_to(fwd))])
	quit(0)


## 骨架空间里的枪管方向（不含节点自身的朝向）
func _barrel(ap: AnimationPlayer, sk: Skeleton3D, clip: String, t: float) -> Vector3:
	if not ap.has_animation(clip):
		return Vector3.ZERO
	ap.play(clip)
	ap.seek(t, true)
	for _i in 2:
		await process_frame
	var mi := sk.find_bone("bone_Railgun_Muzzle_01")
	var gi := sk.find_bone("bone_magazine")
	if mi < 0 or gi < 0:
		return Vector3.ZERO
	var m := sk.get_bone_global_pose(mi).origin
	var g := sk.get_bone_global_pose(gi).origin
	return (m - g).normalized()
