extends SceneTree
## 量机甲/本体的**头**相对机体歪了多少：pitch(前后仰) / yaw(左右拧) / roll(侧倒)。
##
##   & <godot> --headless --path . --script res://scripts/_diag_carrier_head_tilt.gd
##
## 做法：头的世界基相对「载具节点」的世界基求相对旋转，再按 Godot 的 YXZ 欧拉
## 分解成 (pitch, yaw, roll)。头骨的绑定朝向与机体轴并不对齐（本体在地面待机时
## local Y 与模型正面就差 33°），所以**单看绝对值没有意义** ——
## 本探针拿「机甲自己那条 `Idle`」当基准，打印每条动作**相对基准**歪了多少。
##
## 两轮测量：
##   ① 裸动作：把 `_process` 关掉，直接指定动作 —— 看动画本身把头摆成什么样
##   ② 实机：`_process` 开着、强制 `_airborne` —— 看**玩家实际看到的**
##      （`_update_lean` 与 `_fix_head_face` 都在这条路径里）

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")

const HEAD := ["Bip001 Head", "Bip001_Head"]
const CLIPS := ["Idle", "Walk", "Normal_Idle", "Move_Ing", "Normal_Attack_Ing"]

var _skel: Skeleton3D
var _ap: AnimationPlayer
var _carrier: Node3D
var _form: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("========== 头姿态（相对机体）==========")
	MechState.set_carrier_for_test(true)
	var stage := Node3D.new()
	root.add_child(stage)
	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame
	_form = player.get_node_or_null("Arisu/CarrierForm")
	if _form == null or not _form.call("set_form", true):
		push_error("[tilt] 变形失败")
		quit(1)
		return
	await process_frame
	_skel = _form.get("_skel") as Skeleton3D
	_ap = _form.get("_ap") as AnimationPlayer
	_carrier = _form.get("_carrier") as Node3D
	if _skel == null or _ap == null or _carrier == null:
		push_error("[tilt] 拿不到骨架/动画器/载具节点")
		quit(1)
		return
	var hi := _head_index()
	if hi < 0:
		push_error("[tilt] 找不到头骨")
		quit(1)
		return
	print("头骨 index=%d｜载具节点 %s" % [hi, _carrier.name])

	# 先看一眼：机甲自己那两条动作（头是正的）下，头骨三根轴在机体系里指向哪
	_form.call("set_process", false)
	_form.call("set_physics_process", false)
	player.set_physics_process(false)
	player.call("set_flight_lock", true)
	await _play("Idle", 0.5)
	print("")
	print("③ 机甲自己的 `Idle`（基准，头是正的）—— 头骨三轴在机体系里：")
	var d0 := _dirs(hi)
	var names := ["local Y = 脸", "local X = 上", "local Z = 右"]
	for k in 3:
		var v: Vector3 = d0[k]
		print("   %-8s (%+.3f, %+.3f, %+.3f)   与机体上方点积 %+.3f｜与机体前方 %+.3f"
			% [names[k], v.x, v.y, v.z, v.dot(Vector3.UP), v.dot(Vector3.FORWARD)])

	# ---------- ① 裸动作 ----------
	_form.call("set_process", false)
	_form.call("set_physics_process", false)
	player.set_physics_process(false)
	player.call("set_flight_lock", true)
	var base_face := Vector3.ZERO
	var base_up := Vector3.ZERO
	var have_base := false
	print("")
	print("① 裸动作（`_process` 关掉，看动画本身）。基准 = 机甲自己的 `Idle`")
	print("   %-20s %10s %10s   %s" % ["clip", "脸偏角°", "上轴偏角°", "脸方向(机体系)"])
	for clip in CLIPS:
		if not _ap.has_animation(clip):
			continue
		await _play(clip, 0.5)
		var dr := _dirs(hi)
		var face: Vector3 = dr[0]
		var up: Vector3 = dr[1]
		if clip == "Idle":
			base_face = face
			base_up = up
			have_base = true
		var a_face := rad_to_deg(face.angle_to(base_face)) if have_base else 0.0
		var a_up := rad_to_deg(up.angle_to(base_up)) if have_base else 0.0
		print("   %-20s %+10.2f %+10.2f   (%.2f, %.2f, %.2f)"
			% [clip, a_face, a_up, face.x, face.y, face.z])
	# ---------- ② 实机 ----------
	print("")
	print("② 实机（`_process` 开着，玩家真正看到的）")
	_form.call("set_process", true)
	_form.call("set_physics_process", true)
	for airborne in [false, true]:
		_form.set("_airborne", airborne)
		_form.set("_hold_y", 20.0)
		for _i in 60:
			await process_frame
		var dr2 := _dirs(hi)
		var face2: Vector3 = dr2[0]
		var up2: Vector3 = dr2[1]
		print("   %-6s 动作 %-16s 脸偏 %+7.2f°  上轴偏 %+7.2f°   脸(%.2f, %.2f, %.2f)"
			% ["空中" if airborne else "地面", _ap.current_animation,
				rad_to_deg(face2.angle_to(base_face)), rad_to_deg(up2.angle_to(base_up)),
				face2.x, face2.y, face2.z])

	quit(0)


## 头在**机体坐标系**里的三个方向：脸(=local Y)、上(=local X)、右(=local Z)。
## 轴序是**实测**定的（基准姿态下 local Y 与机体前方点积 +1.000、local X 与上方 +0.999）——
## ⚠️ 2026-11-11 本喵一度按「local X = 脸」去改 `_fix_head_face()`，
##    结果实机偏差从 29° 涨到 84°。下面 `③` 段会把三根轴的实测指向打出来，改错了一眼能看见。
## 用向量夹角判断歪没歪 —— 比在这里做欧拉分解可靠：头骨绑定朝向与机体轴差约 90°，
## 那种姿态下机体系里的 YXZ 分解会把物理俯仰显示成 roll，读数会骗人。
func _dirs(hi: int) -> Array:
	var inv := _carrier.global_transform.basis.inverse()
	var b := (_skel.global_transform * _skel.get_bone_global_pose(hi)).basis.orthonormalized()
	return [(inv * b.y).normalized(), (inv * b.x).normalized(), (inv * b.z).normalized()]


func _head_index() -> int:
	for n in HEAD:
		var i := _skel.find_bone(String(n))
		if i >= 0:
			return i
	return -1


func _play(clip: String, frac: float) -> void:
	var anim := _ap.get_animation(clip)
	_ap.play(clip)
	_ap.seek(anim.length * frac, true)
	for _i in 8:
		await process_frame
