extends SceneTree
## 探针：**真玩家 + 真武器链**，量「走打右倾」和「攻击后变螃蟹」。
##
## 用户 2026-10-18（改了第七轮之后仍然报）：
##   「走打还是右倾，攻击一下后再开始走路会变成爱丽丝右转螃蟹平移仍然没有修复」
##
## 与前几个探针的区别（重要）：
##   · 不关 `_physics_process`、不手动调 `anim.set_locomotion()` —— 走真输入
##     （`Input.action_press`），朝向逻辑、`_fire_held`、武器冷却全程都在跑；
##   · 开火走 `Weapon.trigger_down()` / `trigger_up()`（**玩家鼠标就是转给它**），
##     这样才验得到「松手 → `cancel_fire()`」这条链真的接通了没有；
##   · 量的是**模型空间**的量，不受相机怎么转影响。
##
## 四个量（每个都直接对应一句用户原话）：
##   1. **肩线倾角** `asin(Δy / |肩线|)`：左右肩连线的仰角。正 = 左肩高。
##      人「右倾」时它就是个十几度以上的常值 —— 这是「右倾」最直白的机器判据。
##   2. **头相对骨盆的侧偏** `asin(Δright / |髋→头|)`：整条脊柱往右歪多少度。
##   3. **脚的横/纵位移比**：脚在模型空间里每帧位移，`Σ|lateral| / Σ|forward|`。
##      正常走路脚是**前后**迈的（比 < 0.5）；「螃蟹平移」时脚在**横着**迈（比 → 1+）。
##   4. **模型朝向 vs 速度方向**的夹角：螃蟹也可能是「人朝右、却往前走」。
##
## 用法：
##   godot --path <工程> --headless --script res://scripts/_probe_live_fire.gd -- --splat=off

const SPOT := Vector3(-14.0, 0.1, -12.0)
## 每个状态每多少帧打一行
const ROW_EVERY := 15

var _p: Player
var _anim: AnimDriver
var _wpn: Weapon
var _sk: Skeleton3D
var _names := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 14:
		await process_frame
	paused = false                      # 开场剧情会暂停整棵树（见 §9.5 坑 12）
	_p = game.get_node_or_null("Player") as Player
	if _p == null or _p.anim == null:
		print("!! 没有 Player/AnimDriver")
		quit(1)
		return
	_anim = _p.anim as AnimDriver
	_sk = _anim.skeleton
	_wpn = game.get_node_or_null("Player/Weapon") as Weapon
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_p.global_position = SPOT
	_p.velocity = Vector3.ZERO
	await _frames(6)
	_resolve()

	print("=== 骨名解析 ===")
	for k in _names.keys():
		print("  %-10s → %s" % [String(k), String(_names[k])])

	print("\n=== 1. 走路（按住 W，不开火）===")
	Input.action_press("move_forward")
	await _frames(90)
	await _table("只走", 60)

	print("\n=== 2. 走打（点击一次开火，仍按住 W）===")
	_wpn.trigger_down()
	await _frames(30)
	await _table("走打", 45)
	_wpn.trigger_up()
	print("  ↑ trigger_up() 已调用（= 松开鼠标）")

	print("\n=== 3. 松手后继续走（看有没有变螃蟹 / 右倾）===")
	for i in 120:
		await process_frame
		_pin()
		if i % ROW_EVERY == ROW_EVERY - 1:
			_row(i + 1, "松手后")
	Input.action_release("move_forward")
	await _frames(30)
	await _table("停下", 40)

	# ── 对照：跑起来（跑打开火本来就是跑步姿势，不是螃蟹）──
	print("\n=== 4. 对照：跑（Shift+W）===")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(60)
	await _table("只跑", 45)
	_wpn.trigger_down()
	await _frames(30)
	await _table("跑打", 45)
	_wpn.trigger_up()
	Input.action_release("move_forward")
	Input.action_release("sprint")
	quit(0)


## 在一个窗口里累计「脚在模型空间的横/纵位移」，并打平均肩线倾角 / 头侧偏
func _table(tag: String, frames: int) -> void:
	var lat := 0.0
	var fwd := 0.0
	var sh := 0.0
	var hd := 0.0
	var hip := 0.0
	var yaw := 0.0
	var prev := _model_pos(String(_names["toe"]))
	var tag_state := "%s/%s" % [_anim.current_clip(), _anim.current_state_name()]
	var tag_ss := _anim.player.speed_scale
	for i in frames:
		await process_frame
		_pin()
		var cur := _model_pos(String(_names["toe"]))
		var d := cur - prev
		lat += absf(d.x)
		fwd += absf(d.z)
		prev = cur
		sh += _shoulder_tilt()
		hd += _head_lateral()
		hip += _hip_tilt()
		yaw += _yaw_error()
	var n := float(maxi(frames, 1))
	print("  [%s] clip=%-13s ss=%.2f  肩线 %+5.1f°  髋线 %+5.1f°  头侧偏 %+5.1f°  "
		% [tag, tag_state, tag_ss,
		sh / n, hip / n, hd / n] +
		"脚横/纵 %.2f  朝向差 %+5.1f°  速度 %.2f" % [
		lat / maxf(fwd, 0.0001), yaw / n, _speed()])


func _row(f: int, tag: String) -> void:
	print("  [%3d 帧] %-8s clip=%-13s state=%-10s 肩线 %+5.1f°  头侧偏 %+5.1f°  朝向差 %+5.1f°"
		% [f, tag, _anim.current_clip(), _anim.current_state_name(),
		_shoulder_tilt(), _head_lateral(), _yaw_error()])


## 肩线仰角：左右上臂骨连线在**模型空间**里相对水平面的角度（正 = 左肩高）
func _shoulder_tilt() -> float:
	var l := _model_pos(String(_names["arm_l"]))
	var r := _model_pos(String(_names["arm_r"]))
	var v := l - r
	var h := Vector2(v.x, v.z).length()
	return rad_to_deg(atan2(v.y, maxf(h, 0.0001)))


## 髋线仰角：左右大腿骨连线（正 = 左髋高）
func _hip_tilt() -> float:
	var l := _model_pos(String(_names["thigh_l"]))
	var r := _model_pos(String(_names["thigh_r"]))
	var v := l - r
	var h := Vector2(v.x, v.z).length()
	return rad_to_deg(atan2(v.y, maxf(h, 0.0001)))


## 头相对骨盆的侧偏角（模型空间，正 = 往右歪）
func _head_lateral() -> float:
	var h := _model_pos(String(_names["head"]))
	var p := _model_pos(String(_names["pelvis"]))
	var v := h - p
	var len := v.length()
	if len < 0.001:
		return 0.0
	return rad_to_deg(asin(clampf(v.x / len, -1.0, 1.0)))


## 模型朝向与**速度方向**的夹角（度）。人朝右走 = 螃蟹
func _yaw_error() -> float:
	var v := Vector3(_p.velocity.x, 0.0, _p.velocity.z)
	if v.length() < 0.3:
		return 0.0
	var vel_yaw := atan2(v.x, v.z)
	var face_yaw := atan2(sin(_p.model_root.rotation.y), cos(_p.model_root.rotation.y))
	return rad_to_deg(angle_difference(vel_yaw, face_yaw))


## 把玩家钉在原地（只保位置、不动速度）：跑出平台会触发跑酷的摔落/回站，
## 位置一跳，量出来的脚位移就全是假的。
func _pin() -> void:
	if _p == null or not _p.is_inside_tree():
		return
	if _p.global_position.y < SPOT.y:
		_p.global_position = SPOT
	else:
		_p.global_position = Vector3(SPOT.x, _p.global_position.y, SPOT.z)


func _speed() -> float:
	return Vector2(_p.velocity.x, _p.velocity.z).length()


## 骨的世界位置 → 模型空间（去掉角色自己的旋转/位移）
func _model_pos(bone: String) -> Vector3:
	var i := _sk.find_bone(bone)
	if i < 0:
		return Vector3.ZERO
	var w: Vector3 = _sk.global_transform * _sk.get_bone_global_pose(i).origin
	return _p.model_root.global_transform.affine_inverse() * w


func _resolve() -> void:
	_names["toe"] = _like("L Toe")
	_names["head"] = _like("Head")
	_names["pelvis"] = _like("Pelvis")
	_names["thigh_l"] = _like("L Thigh")
	_names["thigh_r"] = _like("R Thigh")
	_names["arm_l"] = _like("L UpperArm")
	_names["arm_r"] = _like("R UpperArm")


func _like(kw: String) -> String:
	for i in _sk.get_bone_count():
		var nm := _sk.get_bone_name(i)
		if nm.to_lower().contains(kw.to_lower()):
			return nm
	return ""


func _frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
