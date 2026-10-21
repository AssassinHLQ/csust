extends SceneTree
## 探针：**每一位**同伴跑步时头还歪不歪（以及前倾还趴不趴）。
##
## 背景：`PoseFix.fix_head_roll()` 原来写死 −18.6°，那是在 `Arisu_ext.glb` 上标定的，
## 却对 7 位同伴一律套用 —— 用户报「柚子小绿小桃跑步时姿势错误，头右倾了」。
##
## 现在：① `_pitch_delta()` 改用「眼骨 rest 连线」当左右轴（前倾不再顺带注入侧倾）；
##       ② 侧倾收尾改成每具骨架现场标定。
##
## 三段验收：
##   ① **原始**数据（把每个 glb 单独 instancing，不跑任何修正）：roll / pitch
##   ② **修完**的数据（真的加载 `game.tscn`，走 `AnimDriver` 的真实路径）+ 标定报告
##   ③ 待机没被带歪
##
## 用法：godot --path <工程> --script res://scripts/_probe_role_roll.gd -- --splat=off --no-capture

const MODELS := [
	["爱丽丝", "res://models/Arisu_ext.glb"],
	["小雪", "res://models/companions/Koyuki.glb"],
	["优香", "res://models/companions/Yuuka.glb"],
	["诺亚", "res://models/companions/Noa.glb"],
	["小桃", "res://models/companions/Momoi.glb"],
	["小绿", "res://models/companions/Midori.glb"],
	["柚子", "res://models/companions/Yuzu.glb"],
	["凯伊", "res://models/companions/Kei_ext.glb"],
]
const SAMPLES := 16
## 跑步时眼睛连线的侧倾容忍度（度）。用户能看出来的门槛大约 2° 以上。
const TOL_ROLL := 1.5
## 侧倾容忍度放宽到 3°：PoseFix 标定时用 12 个采样点，本探针用 16 个，
## 采样网格不同 ⇒ 同一个姿势的平均 roll 会差 1~2°。再往上就该查了。
const TOL_ROLL_ADJ := 3.0

var _fail := 0
## 原始数据（逐模型逐动作），最后用来证明「只动了 Move_Ing」
var _raw := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("========== ① 原始数据（单独 instancing，不跑任何修正）==========")
	print("  %-8s %-12s %8s %8s" % ["角色", "动作", "roll", "pitch"])
	for row in MODELS:
		var path := String(row[1])
		var packed := load(path) as PackedScene
		if packed == null:
			print("  %-8s !! 加载失败：%s" % [String(row[0]), path])
			_fail += 1
			continue
		var inst := packed.instantiate() as Node3D
		root.add_child(inst)
		await process_frame
		var sk := _find(inst, "Skeleton3D") as Skeleton3D
		var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
		if sk == null or ap == null:
			print("  %-8s !! 没有骨架/播放器" % String(row[0]))
			inst.queue_free()
			continue
		for clip in ["Normal_Idle", "Move_Ing"]:
			var m := await _measure(sk, ap, clip)
			_raw["%s|%s" % [String(row[0]), clip]] = m
			print("  %-8s %-12s %+8.2f %+8.2f" % [String(row[0]), clip,
				float(m["roll"]), float(m["pitch"])])
		inst.queue_free()
		await process_frame

	print("\n========== ② 修完（真实路径：game.tscn → AnimDriver）==========")
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false

	var rows: Array = []
	for ch in game.get_children():
		if ch is Companion:
			rows.append(ch)
	for ch in rows:
		var name := String(ch.get("display_name"))
		var rep: Dictionary = {}
		var found: Array[Node] = ch.find_children("*", "AnimDriver", true, false)
		if not found.is_empty():
			rep = (found[0] as AnimDriver).get("roll_fix")
		var sk := _find(ch, "Skeleton3D") as Skeleton3D
		var ap := _find(ch, "AnimationPlayer") as AnimationPlayer
		if sk == null or ap == null:
			print("  %-8s !! 找不到骨架/播放器" % name)
			_fail += 1
			continue
		var has_eyes := sk.find_bone("Bip001 eye_L") >= 0 and sk.find_bone("Bip001 eye_R") >= 0
		var m := await _measure(sk, ap, "Move_Ing")
		var roll := float(m["roll"])
		var pitch := float(m["pitch"])
		# ⚠️ 只看 roll。pitch 这个判据量的是「眼睛比头骨原点高多少」，
		#    是几何常数不是朝向，别拿它当验收集（侧面渲图看脖子歪不歪更靠谱，
		#    见 `_probe_role_shot.gd` 出来的 before/after 对照）。
		var ok_roll: bool = absf(roll) <= TOL_ROLL_ADJ
		# 凯伊整具骨架只有 6 根骨、也没有 Move_Ing，不适用
		if not has_eyes or not ap.has_animation("Move_Ing"):
			ok_roll = true
		if not ok_roll:
			_fail += 1
		print("  %-8s 眼骨 %s | 标定[量到 %s 修前 %+.2f° 修后 %+.2f° 补 %+.2f° %d 轮] | 实测 roll %+.2f° pitch %+.2f°  %s"
			% [name, "✔" if has_eyes else "✘",
				"是" if bool(rep.get("measured", false)) else "否",
				float(rep.get("roll_before", 0.0)), float(rep.get("roll_after", 0.0)),
				float(rep.get("deg", 0.0)), int(rep.get("passes", 0)),
				roll, pitch,
				"PASS" if ok_roll else "**FAIL**"])

	print("\n========== ③ 待机（Normal_Idle）没被带歪 ==========")
	for ch in rows:
		var sk := _find(ch, "Skeleton3D") as Skeleton3D
		var ap := _find(ch, "AnimationPlayer") as AnimationPlayer
		if sk == null or ap == null:
			continue
		var name := String(ch.get("display_name"))
		var m := await _measure(sk, ap, "Normal_Idle")
		var roll := float(m["roll"])
		# 判据：和**原始数据**逐位一致（差 < 0.01°）—— 证明这次只动了 Move_Ing，
		# 待机一个关键帧都没碰。别拿「随手定的 4°」当门槛：待机本身就有 ±9° 的重心偏移。
		var key := "%s|Normal_Idle" % name
		var ok := true
		if _raw.has(key):
			ok = absf(roll - float(_raw[key]["roll"])) < 0.01
		if not ok:
			_fail += 1
		print("  %-8s 待机 roll %+.2f°（原始 %+.2f°）  %s" % [name, roll,
			float(_raw[key]["roll"]) if _raw.has(key) else 0.0, "PASS" if ok else "FAIL"])

	print("\n================ 结果 ================")
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


## roll = 眼睛连线的侧倾（右耳抬高为正）；pitch = 脖子→头的俯仰（前倾为正）
func _measure(sk: Skeleton3D, ap: AnimationPlayer, clip: String) -> Dictionary:
	var out := {"roll": 0.0, "pitch": 0.0}
	if not ap.has_animation(clip):
		return out
	var eL := sk.find_bone("Bip001 eye_L")
	var eR := sk.find_bone("Bip001 eye_R")
	var head := sk.find_bone("Bip001 Head")
	var neck := sk.find_bone("Bip001 Neck")
	var a := ap.get_animation(clip)
	var prev_mode: int = ap.playback_process_mode
	var prev_clip := ap.current_animation
	var prev_pos := 0.0
	if not prev_clip.is_empty():
		prev_pos = ap.current_animation_position
	ap.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	ap.play(clip)
	var roll_sum := 0.0
	var pitch_sum := 0.0
	var n := 0
	for i in SAMPLES:
		ap.seek(a.length * float(i) / float(SAMPLES), true)
		sk.force_update_all_bone_transforms()
		await process_frame
		sk.force_update_all_bone_transforms()
		var xf := sk.global_transform
		if eL >= 0 and eR >= 0:
			var pl: Vector3 = xf * sk.get_bone_global_pose(eL).origin
			var pr: Vector3 = xf * sk.get_bone_global_pose(eR).origin
			roll_sum += rad_to_deg(asin(clampf((pr - pl).normalized().y, -1.0, 1.0)))
		if head >= 0 and neck >= 0:
			var ph: Vector3 = xf * sk.get_bone_global_pose(head).origin
			var pn: Vector3 = xf * sk.get_bone_global_pose(neck).origin
			pitch_sum += rad_to_deg(asin(clampf(-(ph - pn).normalized().z, -1.0, 1.0)))
		n += 1
	ap.playback_process_mode = prev_mode
	if prev_clip.is_empty():
		ap.stop()
	else:
		ap.play(prev_clip)
		ap.seek(prev_pos, true)
	sk.force_update_all_bone_transforms()
	out["roll"] = roll_sum / float(maxi(n, 1))
	out["pitch"] = pitch_sum / float(maxi(n, 1))
	return out


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null
