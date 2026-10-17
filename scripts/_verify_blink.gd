extends SceneTree
## 验「**不再眨眼**」。
##
## 用户 2026-10-17：「眼睛那里停止算了，不要眨眼的动画了」。
##
## 修法见 `pose_fix.gd::freeze_eyelids()`：把 `Bip001 eye_L/R_1/2` 四根骨上的
## **所有轨道**从每个动作里删掉。没有轨道就没人写它们，骨永远停在 rest（全开）。
##
## 这个验证只认机器能判的四条：
##   1. 报告里确实删了轨道（`blink_fix.tracks > 0`）
##   2. 基础层 + 两个叠加层（`upper` / `upper_move`）里，这四根骨的轨道数都是 **0**
##   3. 真播 `Normal_Idle` 两秒，四根骨的局部旋转**全程不动**（最大变化角 < 0.01°）
##   4. 左眼 ≠ 右眼这种「只冻住一半」的漏网：四根骨都要在冻结名单里被找到
##
## 用法：
##   godot --path <工程> --script res://scripts/_verify_blink.gd -- --splat=off

const WINDOW_MS := 2000
## 骨不许动到这个量。0.01° 已经比四元数 float32 噪声大一个量级。
const STILL_TOL_DEG := 0.01

var _fail := 0
var _pass := 0
var _m := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)
	var p := game.get_node_or_null("Player") as Player
	if p == null:
		print("!! 场景里没有 Player")
		quit(1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var anim := p.anim as AnimDriver
	if anim == null or anim.skeleton == null:
		print("!! Player 上没有 AnimDriver / Skeleton3D")
		quit(1)
		return
	var sk := anim.skeleton

	# ── 1. 报告 ──
	var rep: Dictionary = anim.blink_fix
	print("[blink] blink_fix = applied=%s  tracks=%d  clips=%d  missing=%s"
		% [rep.get("applied", false), int(rep.get("tracks", 0)),
		(rep.get("clips", []) as Array).size(), str(rep.get("missing", []))])
	_check(bool(rep.get("applied", false)), "启动时确实删掉了眼睑轨道")
	_check(int(rep.get("tracks", 0)) > 0, "删掉的轨道数 > 0（实测 %d）" % int(rep.get("tracks", 0)))
	_check((rep.get("missing", []) as Array).is_empty(), "四根眼睑骨名全部找得到")

	# ── 2. 三层播放器里都不能再有这几根骨的轨道 ──
	var players: Array = []
	for nm in ["player", "upper", "upper_move"]:
		var ap: AnimationPlayer = anim.get(nm)
		if ap != null:
			players.append({"tag": nm, "ap": ap})
	var left := 0
	for e in players:
		var ap: AnimationPlayer = e["ap"]
		var hit := 0
		for clip in ap.get_animation_list():
			var a := ap.get_animation(String(clip))
			if a == null:
				continue
			for t in a.get_track_count():
				var bone := _bone_of(String(a.track_get_path(t)))
				if PoseFix.BLINK_BONES.has(bone):
					hit += 1
		print("[blink] %-11s 动作 %2d 个，眼睑轨道残留 %d 条"
			% [e["tag"], ap.get_animation_list().size(), hit])
		left += hit
	_check(left == 0, "基础层 + 两个叠加层里眼睑轨道残留 0 条（实测 %d）" % left)

	# ── 3. 真播两秒，四根骨不动 ──
	var idx := {}
	for b in PoseFix.BLINK_BONES:
		var i := sk.find_bone(String(b))
		if i >= 0:
			idx[String(b)] = i
	_check(idx.size() == PoseFix.BLINK_BONES.size(),
		"骨架里找到 %d/%d 根眼睑骨" % [idx.size(), PoseFix.BLINK_BONES.size()])

	var first := {}
	var moved := {}
	for b in idx:
		first[b] = sk.get_bone_pose_rotation(int(idx[b]))
		moved[b] = 0.0
	var t0 := Time.get_ticks_msec()
	var samples := 0
	while Time.get_ticks_msec() - t0 < WINDOW_MS:
		await process_frame
		samples += 1
		for b in idx:
			var q: Quaternion = sk.get_bone_pose_rotation(int(idx[b]))
			var d := rad_to_deg(first[b].angle_to(q))
			moved[b] = maxf(float(moved[b]), d)
	var worst := 0.0
	for b in moved:
		print("[blink] %-16s 2 秒内最大变化 %.4f°" % [b, moved[b]])
		worst = maxf(worst, float(moved[b]))
	print("[blink] 采样 %d 帧，最大变化 %.4f°（判据 < %.2f°）" % [samples, worst, STILL_TOL_DEG])
	_check(worst < STILL_TOL_DEG, "播两秒眼睑骨完全不动")

	# 顺带留一份数字给 README
	_m["tracks"] = int(rep.get("tracks", 0))
	_m["clips"] = (rep.get("clips", []) as Array).size()
	_m["worst_deg"] = worst
	print("[blink] summary %s" % str(_m))
	_quit()


func _bone_of(path: String) -> String:
	var i := path.rfind(":")
	return path.substr(i + 1) if i >= 0 else ""


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if cond:
		_pass += 1
	else:
		_fail += 1


func _quit() -> void:
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
