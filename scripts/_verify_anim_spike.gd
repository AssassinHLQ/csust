extends SceneTree
## 验证「孤点关键帧」修好了没有。
##
##   _tools/run_probe.sh res://scripts/_verify_anim_spike.gd
##
## 判据：`player.tscn` 装载并跑过 `anim_driver.gd::_ready()` 之后，
## `Normal_Attack_Ing` 里剩下的孤点必须是 **0**；同时动作长度不能变。
##
## 「修之前」的数字由 `tools/glb_curve.py` 直接从 GLB 量（真渲染无关），
## 本探针只管「修之后」。

const PLAYER_SCENE := "res://scenes/player.tscn"
const CLIP := "Normal_Attack_Ing"
const ASF := preload("res://scripts/anim_spike_fix.gd")

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps := load(PLAYER_SCENE) as PackedScene
	if ps == null:
		print("[spike] FAIL: 玩家场景加载失败")
		quit(1)
		return
	var p := ps.instantiate()
	root.add_child(p)
	await process_frame
	await process_frame

	var driver := _find_driver(p)
	if driver == null:
		print("[spike] FAIL: 找不到 AnimDriver")
		quit(1)
		return

	var ap := p.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		print("[spike] FAIL: 找不到 AnimationPlayer")
		quit(1)
		return

	var rep: Dictionary = driver.get("spike_fix")
	print("[spike] 修复报告：%s" % str(rep))

	var stats: Dictionary = ASF.count_spikes(ap, CLIP)
	print("[spike] %s 剩余孤点 %d 个，最大绕路 %.1f°（%s）" % [
		CLIP, int(stats["spikes"]), float(stats["worst_deg"]), str(stats["worst_bone"])])

	if int(stats["spikes"]) != 0:
		print("[spike] FAIL: 还有 %d 个孤点没消掉" % int(stats["spikes"]))
		_fail += 1

	# 动作长度不能被改
	var a := ap.get_animation(CLIP)
	var len_s := a.length
	print("[spike] 动作长度 %.3f s（原始 2.667 s）" % len_s)
	if absf(len_s - 2.667) > 0.01:
		print("[spike] FAIL: 动作长度变了")
		_fail += 1

	# 关键帧数：确认 Godot 导入后仍然是 24 fps 的 65 个 key（否则「第 25 帧」对不上）
	var key_n := 0
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			key_n = maxi(key_n, a.track_get_key_count(t))
	print("[spike] 旋转轨道最多 %d 个 key（GLB 里是 65 → 24 fps）" % key_n)

	# 抽查：两只上臂在 **t = 25/24 s（Blender 第 25 帧）** 的绕路。
	# ⚠️ 不能直接用 key 下标：Godot 是按 30 fps 重采样导入的（81 个 key），
	#    它的第 25 个 key 是 t=0.833 s，不是 Blender 的第 25 帧（t=1.042 s）。
	const T_SPIKE := 25.0 / 24.0
	for bone in ["Bip001 R UpperArm", "Bip001 L UpperArm", "Bip001 R Forearm"]:
		var d := _detour_at_time(a, bone, T_SPIKE)
		print("[spike] %-18s t=%.3fs 处绕路 %.1f°（修前 60~142°）" % [bone, T_SPIKE, d])
		if d > 15.0:
			print("[spike] FAIL: %s 在 %.3fs 还在绕路" % [bone, T_SPIKE])
			_fail += 1

	print("[spike] 结果：%s" % ("OK" if _fail == 0 else "FAIL %d" % _fail))
	quit(1 if _fail > 0 else 0)


## 某根骨在**某一时刻**的「绕路 − 直连」度数（同一根骨有多条轨道时取最大）。
## 按时间找最近的 key —— Godot 导入后会重采样，key 下标和源文件的帧号对不上。
func _detour_at_time(a: Animation, bone: String, at: float) -> float:
	var best := -1.0
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		if String(a.track_get_path(t).get_concatenated_subnames()) != bone:
			continue
		var n := a.track_get_key_count(t)
		if n < 3:
			continue
		var k := 0
		var best_dt := INF
		for i in range(1, n - 1):
			var dt := absf(a.track_get_key_time(t, i) - at)
			if dt < best_dt:
				best_dt = dt
				k = i
		if k < 1 or k > n - 2:
			continue
		var qa: Quaternion = a.track_get_key_value(t, k - 1)
		var qb: Quaternion = a.track_get_key_value(t, k)
		var qc: Quaternion = a.track_get_key_value(t, k + 1)
		best = maxf(best, rad_to_deg(qa.angle_to(qb) + qb.angle_to(qc) - qa.angle_to(qc)))
	return best


func _find_driver(n: Node) -> Node:
	var s: Script = n.get_script()
	if s != null and String(s.resource_path).ends_with("anim_driver.gd"):
		return n
	for c in n.get_children():
		var r := _find_driver(c)
		if r != null:
			return r
	return null
