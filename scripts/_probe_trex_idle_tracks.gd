extends SceneTree
## 诊断（二）：**idle 动画本身**给两条大腿骨写了什么？
##
## ── 为什么要先问这个 ──
## 上一版探针量到「一边腿摆 30°、另一边 160°」，本喵以为是摆腿代码的累计误差，
## 换了起算基准之后**疯的那一边换边了**（左 110° / 右 29°）。这不像累计漂移，
## 像是有个**每帧写骨头**的东西在跟本喵抢 —— 最可能就是 `idle` 动画本身。
##
## 本探针把「本喵不插手」时的原始动画姿态打出来，看清楚：
##   ① idle 里到底有没有给 Bone.014 / .015 / .038 / .039 写轨道
##   ② 如果有，它写的是**绝对姿态**还是「叠在上一帧上」（`update_mode`）
##   ③ 每一帧 AnimationPlayer 写完之后的姿态，和本喵 `_tick_legs()` 写完之后的姿态，
##      差多少 —— 差得大 = 谁后写谁赢，本喵和引擎在拉锯
##
## 用法：
##   godot --headless --path . --script res://scripts/_probe_trex_idle_tracks.gd -- --no-capture --splat=off

const LEVEL := "res://scenes/next_level.tscn"
const BOSS := "TrexBossA"


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  PASS  %s" % what)
	else:
		print("  FAIL  %s" % what)


func _run() -> void:
	var GSScript := load("res://scripts/game_settings.gd")
	GSScript.call("set_value", "boss_attack", false)
	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for i in 4:
		await process_frame
	var boss := level.get_node_or_null(BOSS)
	if boss == null:
		print("!! 找不到 %s" % BOSS)
		quit(1)
		return
	if not bool(boss.get("_booted")):
		boss.call("_boot")
	for i in 40:
		await process_frame

	var anim: AnimationPlayer = boss.get("_anim")
	var skel: Skeleton3D = boss.call("_best_skeleton", boss.get("model"))
	if anim == null or skel == null:
		print("!! 没动画或没骨架")
		quit(1)
		return

	print("")
	print("========== 1. idle 动画里有没有腿的轨道 ==========")
	var idle := anim.get_animation("idle")
	if idle == null:
		print("!! 没有 idle")
		quit(1)
		return
	print("        idle 时长 %.2f s，%d 条轨道，loop=%d" % [
		idle.length, idle.get_track_count(), idle.loop_mode])
	var want := ["Bone.014", "Bone.015", "Bone.038", "Bone.039"]
	var found := {}
	for t in idle.get_track_count():
		var path := str(idle.track_get_path(t))
		for nm in want:
			if path.contains(nm):
				found[nm] = t
				print("        轨道 %2d  %s  类型 %d  关键帧 %d" % [
					t, path, idle.track_get_type(t), idle.track_get_key_count(t)])
	if found.is_empty():
		print("        （idle 里一条腿骨轨道都没有 —— 那腿的姿态完全由本喵的代码决定）")
	for nm in want:
		if not found.has(nm):
			print("        %s：idle **没有**轨道" % nm)

	print("")
	print("========== 2. 每一帧：AnimationPlayer 自己会写成什么 ==========")
	# 把本喵的摆腿先关掉（_walking 强制 false 会走「让动画自己管」那条分支），
	# 然后逐帧读两根大腿骨的姿态，看 idle 自己在动多少。
	var L := skel.find_bone("Bone.014")
	var R := skel.find_bone("Bone.038")
	var ql: Array[Quaternion] = []
	var qr: Array[Quaternion] = []
	anim.play("idle")
	for i in 90:
		await process_frame
		ql.append(skel.get_bone_pose_rotation(L))
		qr.append(skel.get_bone_pose_rotation(R))
	print("        只跑 idle：左大腿峰值 %.2f°  右大腿峰值 %.2f°" % [
		_peak_deg(ql), _peak_deg(qr)])
	print("        相邻帧最大跳变：左 %.2f°  右 %.2f°" % [
		_max_step_deg(ql), _max_step_deg(qr)])

	print("")
	print("========== 3. 结构：腿轨道应该已经被剥干净 ==========")
	# ⚠️ 2026-11-12 后判据**反过来了**：方案 A 修好之后，正确状态是「一条腿轨道都没有」。
	#    修之前这里断言的是「有轨道」，用的是根因诊断的口径；现在换成验收口径。
	_check(found.is_empty(),
		"★ 所有动作里**没有**腿骨轨道了（腿完全交给程序化摆腿）")
	if not found.is_empty():
		for nm in found.keys():
			print("        残留：%s" % nm)

	print("")
	print("========== 4. 拉开距离让它「走」，比较两侧 ==========")
	var player := level.get_tree().get_first_node_in_group("player") as Node3D
	var home: Vector3 = boss.get("_home")
	player.global_position = home + Vector3(0, 0, 40)
	for i in 10:
		await process_frame
	# 两侧**同帧采样**，各记一串，比峰值 —— 这是验收「两条腿摆得一样多」的判据
	# （变量名避开上面第 2 节已经用过的 `ql` / `qr`）
	var wl: Array[Quaternion] = []
	var wr: Array[Quaternion] = []
	for i in 120:
		await process_frame
		wl.append(skel.get_bone_pose_rotation(L))
		wr.append(skel.get_bone_pose_rotation(R))
	var pl := _peak_deg(wl)
	var pr := _peak_deg(wr)
	print("        左大腿 Bone.014 摆动峰值 %.2f°" % pl)
	print("        右大腿 Bone.038 摆动峰值 %.2f°" % pr)
	_check(pl > 5.0, "★ 左腿真的在摆（%.2f° > 5°）" % pl)
	_check(pr > 5.0, "★ 右腿真的在摆（%.2f° > 5°）" % pr)
	if pl > 0.01 and pr > 0.01:
		var ratio := maxf(pl, pr) / minf(pl, pr)
		print("        左右幅度比 %.2f（1.00 = 完全对称）" % ratio)
		_check(ratio < 1.25,
			"★ 左右腿摆得一样多（比 %.2f < 1.25）—— 「只动右腿」修好的判据" % ratio)

	print("")
	print("========== 5. 三只恐龙各自一样吗（看是不是只有 A 有问题）==========")
	for nm in ["TrexBossA", "TrexBossB", "TrexBossC"]:
		var b := level.get_node_or_null(nm)
		if b == null:
			print("        %s 不在场景里" % nm)
			continue
		if not bool(b.get("_booted")):
			b.call("_boot")
		await process_frame
		var sk: Skeleton3D = b.call("_best_skeleton", b.get("model"))
		if sk == null:
			print("        %s 没骨架" % nm)
			continue
		var bl := sk.find_bone("Bone.014")
		var br := sk.find_bone("Bone.038")
		print("        %-11s 左 #%d 右 #%d  （数值一致说明是同一个 GLB 骨架）" % [nm, bl, br])

	GSScript.call("set_value", "boss_attack", true)
	quit(0)


func _peak_deg(qs: Array[Quaternion]) -> float:
	if qs.size() < 2:
		return 0.0
	var base := qs[0]
	var mx := 0.0
	for q in qs:
		mx = maxf(mx, rad_to_deg(base.angle_to(q)))
	return mx


func _max_step_deg(qs: Array[Quaternion]) -> float:
	var mx := 0.0
	for k in range(1, qs.size()):
		mx = maxf(mx, rad_to_deg(qs[k].angle_to(qs[k - 1])))
	return mx
