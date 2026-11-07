class_name RocketRide extends Node3D
## 一枚可骑乘的 SpaceX Falcon 9 —— 跑酷的「去程 / 回程」载具。
##
## ── 为什么需要这一层 ──
## 原来两个传送都是**瞬移**（`parkour.gd::_on_finish_portal_body` /
## `_on_return_pad_entered`）：一进触发盒，人就从 A 跳到 B，中间什么都没有。
## 用户 2026-11-06 要求「传送改成坐火箭」，所以这里把瞬移换成**分段飞行**：
##
##   ① 升空   火箭从地面垂直拔起 `lift_altitude` 米
##   ② 巡航   在 `lift_altitude` 高度横扫到目的地，机身在途中轻微前倾
##   ③ 降落   垂直落回地面
##   ④ 下舰   0.35 s 补间把人从座位挪到出舱点（不是硬瞬移）
##
## 全程玩家被 `player.set_ride_lock(true)` 锁住输入、不落重力，位置由本节点每帧写入。
##
## ── 落地后不回家 ──
## 飞完就**停在落点**（`_finish()`）。换边由 `parkour.gd` 派另一枚**空载摆渡**
## （`depart_to()`）飞过去补位 —— 两枚火箭在两头互换，玩家看到的永远是
## 「这头走一枚、那头来一枚」，没有任何瞬移。
##
## ── 尺度 ──
## GLB 原始高 70 m（真实 Falcon 9 尺寸）。实测跑道口 → 结算屋 **579 m**，
## 70 m 是赛道跨度的 12%。2026-11-06 先缩到 0.30（21 m），用户 2026-11-07 说
## 「感觉火箭不够大」，提到 `rocket_scale = 0.60`（**42 m**）——
## 参照旁边的柴关电脑城层高 5.99 m，42 m 是它的 7 倍，够压场。
## 还嫌小就往 0.8 调（56 m）；1.0 = 真实 70 m。想改大改小只动这一个数。
##
## ── 素材缺失要能降级 ──
## `models/rocket_falcon9/` 是第三方素材（CC BY-NC，Forest Katsch），按项目惯例
## 被 `.gitignore` 排除。克隆者没有这个文件时，本节点改用**程序化占位火箭**，
## 流程照常能跑完 —— 和 `gamedev_room` / `pc_wall_case` 一个套路。

## 骑乘结束（人已经落到出舱点、输入已解锁）
signal ride_finished()

## Falcon 9 的 GLB（真实高度 70 m）。没有就走占位火箭。
const GLB_PATH := "res://models/rocket_falcon9/falcon9.glb"
## GLB 的原始高度（米）—— 缩放系数的基准，改模型时同步改这里
const GLB_HEIGHT := 70.0

## 整体缩放。0.60 → 高 42 m。
##
## 用户 2026-11-07：「感觉火箭不够大」—— 从 0.30（21 m）提到 0.60（42 m）。
## 参照：旁边的柴关电脑城层高 5.99 m，42 m 的箭是它的 7 倍，够压场。
## 还嫌小就往 0.8 调（56 m）；1.0 = 真实 70 m。
@export var rocket_scale := 0.60
## 座位高度占全高的比例。0.80 ≈ 坐在二级/整流罩下方，视野能看见箭体
@export_range(0.1, 1.0) var seat_ratio := 0.80
## 升空 / 巡航高度（米，相对起点地面）
@export var lift_altitude := 45.0
## 三段时长（秒）
@export var t_liftoff := 1.10
@export var t_cruise := 2.60
@export var t_land := 1.30
## 下舰补间时长（秒）
@export var t_dismount := 0.35
## 巡航时机身最大前倾角（度）。0 = 全程笔直
@export var max_tilt_deg := 9.0
## 兜底：总时长超过「三段之和 + 这个余量」还没结束，就强制收尾，
## 免得某个 bug 把人永久锁在火箭上（玩家连 Esc 都按不了）
@export var watchdog_extra := 6.0

var _model: Node3D
## 旋转层：**只**承载飞行前倾，不碰缩放。
##
## ⚠️ 为什么非要这么一层（踩过）：`Node3D.basis` 的 setter 写的是「旋转+缩放」整体，
##    `_model.basis = Basis(axis, tilt)` 会把 `_model.scale` 的 0.30 一起冲成 1.0 ——
##    火箭瞬间从 21 m 变回 70 m，而出图取景怎么调都装不下。
##    `height()` 算的是 70×0.30 仍然正确，所以光看日志发现不了，必须量世界包围盒。
##    分成 _pivot(旋转) → _model(缩放) 两层之后，两者物理上不可能互相覆盖。
var _pivot: Node3D
var _player: Node3D
var _from := Vector3.ZERO          ## 火箭起点（也是它的 home）
var _to := Vector3.ZERO            ## 火箭落点
var _exit := Vector3.ZERO          ## 人的出舱点（可以和火箭落点不同）
var _dir := Vector3.FORWARD        ## 水平飞行方向（单位向量）
var _elapsed := 0.0
var _active := false
var _placeholder := false
## 这一趟的巡航高度。载人时 = `lift_altitude`；空载摆渡会更高（见 `depart_to()`）
var _lift := 45.0
## 这一趟是「空载摆渡」（换边），不载人、不发 `ride_finished`
var _ferry := false


func _ready() -> void:
	set_physics_process(false)
	_lift = lift_altitude
	_build()


## 造模型：优先真 GLB，缺文件就程序化占位
func _build() -> void:
	if _model != null:
		return
	if ResourceLoader.exists(GLB_PATH):
		var ps := load(GLB_PATH) as PackedScene
		if ps != null:
			_model = ps.instantiate() as Node3D
	if _model == null:
		_model = _build_placeholder()
		_placeholder = true
		push_warning("[Rocket] 缺 %s —— 用程序化占位火箭顶上" % GLB_PATH)
	_model.name = "Model"
	_model.scale = Vector3.ONE * rocket_scale
	# 旋转层与缩放层分开（原因见 `var _pivot` 上面那段）
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_pivot.add_child(_model)
	print("[Rocket] 模型 = %s，缩放 %.2f，高 %.1f m" % [
		"占位" if _placeholder else "Falcon9.glb", rocket_scale, height()])


## 缩放后的实际箭高（米）
func height() -> float:
	return GLB_HEIGHT * rocket_scale


## 是不是占位火箭（自检 / 调试用）
func is_placeholder() -> bool:
	return _placeholder


## 正在飞？（自检用：确认锁确实上过又解开了）
func is_riding() -> bool:
	return _active


## 停到某个点当「地标」——不飞，就杵在那儿
func park_at(p: Vector3) -> void:
	_from = p
	global_position = p
	_dir = Vector3.FORWARD
	_ferry = false
	_lift = lift_altitude
	if _pivot != null:
		_pivot.basis = Basis.IDENTITY
	set_physics_process(false)


## 空载摆渡：自己从当前位置飞到 `dest`，不载人，**不发 `ride_finished`**。
##
## ── 为什么需要它 ──
## 用户 2026-11-07 的三条反馈连起来是一件事：两头的火箭必须**一直在**，
## 而且落地要落在传送门脚下。但一个停机位同一时刻只能站一枚 ——
## 玩家坐 A 从这头飞向那头时，那头本来就站着 B，A 落地就会和 B 叠在一起。
##
## 所以让 B **同时起飞飞去 A 刚离开的那个点补位**：两头永远是「走一枚、来一枚」，
## 玩家落地时那头正好空出来，全程没有任何瞬移（瞬移会被看见凭空消失/出现）。
## 摆渡的巡航高度取 `FERRY_ALTITUDE`（95 m），比载人那趟（45 m）高一倍，
## 两枚对飞不会在半空中撞上。
func depart_to(dest: Vector3, altitude: float) -> void:
	if _active:
		push_warning("[Rocket] 摆渡被忽略：这枚正忙着（上一趟还没落地）")
		return
	_build()
	_from = global_position
	_to = dest
	_exit = dest
	_player = null
	_ferry = true
	_lift = maxf(altitude, lift_altitude)
	# 水平朝向。起落点重合时没有方向，退回单位 +Z，免得归一化出 NaN
	var flat := _to - _from
	flat.y = 0.0
	_dir = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	_elapsed = 0.0
	_active = true
	if _pivot != null:
		_pivot.basis = Basis.IDENTITY
	set_physics_process(true)
	print("[Rocket] 空载摆渡 %s → %s（alt %.0f m）" % [
		str(_from.snappedf(0.1)), str(_to.snappedf(0.1)), _lift])


## 起飞。`rocket_from` 也是飞完之后回归的 home。
func begin(rocket_from: Vector3, rocket_to: Vector3, player_exit: Vector3, player: Node3D) -> void:
	if _active:
		return
	if player == null or not is_instance_valid(player):
		push_warning("[Rocket] begin() 没给有效玩家，放弃")
		return
	_build()

	_from = rocket_from
	_to = rocket_to
	_exit = player_exit
	_player = player
	# 水平朝向。起落点重合时没有方向，退回单位 +Z，免得归一化出 NaN
	var flat := rocket_to - rocket_from
	flat.y = 0.0
	_dir = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD

	_elapsed = 0.0
	_active = true
	_ferry = false
	_lift = lift_altitude
	global_position = _from
	if _pivot != null:
		_pivot.basis = Basis.IDENTITY
	_carry_player()
	if _player.has_method("set_ride_lock"):
		_player.call("set_ride_lock", true)
	# 镜头朝向飞行方向（没有就保持原样）
	if _player.has_method("set_ride_yaw"):
		_player.call("set_ride_yaw", atan2(-_dir.x, -_dir.z))
	Sfx.play("ui_open", -2.0)
	set_physics_process(true)
	print("[Rocket] 起飞 %s → %s（水平 %.1f m，alt %.1f m，%s）" % [
		str(_from.snappedf(0.1)), str(_to.snappedf(0.1)),
		Vector3(_to.x - _from.x, 0.0, _to.z - _from.z).length(),
		lift_altitude, "占位" if _placeholder else "Falcon9"])


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta

	var t1 := t_liftoff
	var t2 := t1 + t_cruise
	var t3 := t2 + t_land

	# 兜底：卡住就强制收尾
	if _elapsed > t3 + watchdog_extra:
		push_warning("[Rocket] 超时兜底触发，强制降落收尾")
		global_position = _to
		_finish()
		return

	var pos := _to
	var tilt := 0.0

	if _elapsed < t1:
		# ① 升空：垂直拔起（ease-out，开始快后段收）
		var k := _elapsed / maxf(t1, 0.001)
		var e := 1.0 - pow(1.0 - k, 2.0)
		pos = _from + Vector3.UP * (_lift * e)
	elif _elapsed < t2:
		# ② 巡航：等高横扫，机身中途前倾最多 max_tilt_deg
		var k := (_elapsed - t1) / maxf(t_cruise, 0.001)
		var e := k * k * (3.0 - 2.0 * k)          # smoothstep
		var a := _from + Vector3.UP * _lift
		var b := _to + Vector3.UP * _lift
		pos = a.lerp(b, e)
		tilt = deg_to_rad(max_tilt_deg) * sin(k * PI)
	else:
		# ③ 降落：从巡航高度垂直落到地面（ease-in，越接近地面越慢）
		var k := (_elapsed - t2) / maxf(t_land, 0.001)
		var e := k * k
		var a := _to + Vector3.UP * _lift
		pos = a.lerp(_to, e)
		if _elapsed >= t3:
			pos = _to

	global_position = pos

	# 前倾：绕「上 × 飞行方向」这根水平轴转，箭尖朝飞行方向倒。
	# ⚠️ 写 `_pivot.basis` 而**不是** `_model.basis` —— 后者会把缩放冲掉（见 `var _pivot`）。
	if tilt > 0.0001 and _dir.length_squared() > 0.0001:
		var axis := Vector3.UP.cross(_dir)
		if axis.length_squared() > 0.0001:
			_pivot.basis = Basis(axis.normalized(), tilt)
		else:
			_pivot.basis = Basis.IDENTITY
	else:
		_pivot.basis = Basis.IDENTITY

	_carry_player()

	if _elapsed >= t3:
		_finish()


## 把人钉在座位上（座位点在箭体局部坐标里，跟着前倾一起转）
func _carry_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var seat := Vector3(0.0, height() * seat_ratio, 0.0)
	# 用 `_pivot` 的旋转（纯旋转、无缩放）算座位偏移
	var rot := _pivot.basis if _pivot != null else Basis.IDENTITY
	_player.global_position = global_position + rot * seat


## 落地收尾：停稳 → 0.35 s 把人挪到出舱点 → 解锁输入 → **就地停住**
##
## ⚠️ 2026-11-07 改：原来这里会把火箭瞬移回 `_from`（它的起点）。用户反馈
##    「火箭落地不是传送门那一块」「回来后又回去」—— 那个「又回去」就是这一行：
##    人刚站到出舱点，火箭就在眼前凭空消失、回到 570 m 外的老窝。
##    现在它**落在哪儿就停在哪儿**；换边交给 `parkour.gd` 派另一枚空载飞过来补位
##    （见 `depart_to()`），两头永远是「走一枚、来一枚」。
func _finish() -> void:
	if not _active:
		return
	_active = false
	set_physics_process(false)

	# 空载摆渡：落点即终点，停住就完事，不发信号
	if _ferry:
		_ferry = false
		_from = _to
		global_position = _to
		if _pivot != null:
			_pivot.basis = Basis.IDENTITY
		print("[Rocket] 摆渡到位 %s" % str(_to.snappedf(0.1)))
		return

	if _player == null or not is_instance_valid(_player):
		ride_finished.emit()
		return

	Sfx.play("ui_toggle")
	var tw := create_tween()
	tw.tween_property(_player, "global_position", _exit, t_dismount) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished

	if _player != null and is_instance_valid(_player):
		if _player.has_method("set_ride_lock"):
			_player.call("set_ride_lock", false)
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
		var moved := _player as Node3D
		if moved != null:
			moved.global_position = _exit

	# 就地停住：落点就是它新的停放点（原因见上面 `_finish()` 的注释）
	_from = _to
	global_position = _to
	if _pivot != null:
		_pivot.basis = Basis.IDENTITY
	print("[Rocket] 落地完成，人 → %s，火箭停在 %s" % [
		str(_exit.snappedf(0.1)), str(_to.snappedf(0.1))])
	ride_finished.emit()


# ── 占位火箭：没有 GLB 时的兜底 ─────────────────────────────────────────
## 白箭体 + 黑级间段 + 锥形整流罩 + 4 片格栅舵 + 9 个发动机喷口 + 4 条着陆腿。
## 全部用 `CylinderMesh` / `BoxMesh` 拼，约 600 面 —— 不追求还原，只求「一眼是火箭」。
func _build_placeholder() -> Node3D:
	var root := Node3D.new()

	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.90, 0.90, 0.92)
	white.roughness = 0.42
	white.metallic = 0.18

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.11, 0.11, 0.12)
	dark.roughness = 0.60
	dark.metallic = 0.35

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.32, 0.31, 0.30)
	metal.roughness = 0.50
	metal.metallic = 0.85

	var r := 1.83            # 真实 Falcon 9 半径
	# 一级箭体：0 → 42 m
	root.add_child(_cyl(r, 42.0, Vector3(0.0, 21.0, 0.0), white, "StageOne"))
	# 级间段（黑）：42 → 47 m
	root.add_child(_cyl(r + 0.02, 5.0, Vector3(0.0, 44.5, 0.0), dark, "Interstage"))
	# 二级：47 → 58 m
	root.add_child(_cyl(r, 11.0, Vector3(0.0, 52.5, 0.0), white, "StageTwo"))
	# 整流罩（锥）：58 → 70 m
	root.add_child(_cone(r, 0.30, 12.0, Vector3(0.0, 64.0, 0.0), white, "Fairing"))

	# 9 个发动机喷口（八边形一圈 + 中心 1 个）
	var engines := Node3D.new()
	engines.name = "Engines"
	for i in 8:
		var a := TAU * float(i) / 8.0
		var p := Vector3(cos(a) * 1.15, 0.35, sin(a) * 1.15)
		engines.add_child(_cone(0.42, 0.26, 0.7, p, metal, "Nozzle%d" % i))
	engines.add_child(_cone(0.42, 0.26, 0.7, Vector3(0.0, 0.35, 0.0), metal, "NozzleC"))
	root.add_child(engines)

	# 4 片格栅舵（顶部，十字分布）
	for i in 4:
		var a := TAU * float(i) / 4.0
		var fin := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.5, 1.7, 0.10)
		fin.mesh = bm
		fin.material_override = metal
		fin.name = "GridFin%d" % i
		fin.position = Vector3(cos(a) * (r + 0.7), 45.5, sin(a) * (r + 0.7))
		fin.rotation.y = -a
		root.add_child(fin)

	# 4 条着陆腿（底部，外撑）
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		var leg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.34, 6.0, 0.34)
		leg.mesh = bm
		leg.material_override = dark
		leg.name = "Leg%d" % i
		leg.position = Vector3(cos(a) * (r + 0.55), 3.0, sin(a) * (r + 0.55))
		leg.rotation.x = deg_to_rad(9.0) * sin(a)
		leg.rotation.z = deg_to_rad(-9.0) * cos(a)
		root.add_child(leg)

	return root


func _cyl(radius: float, h: float, at: Vector3, mat: Material, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = h
	cm.radial_segments = 24
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.name = nm
	mi.position = at
	return mi


func _cone(bottom: float, top: float, h: float, at: Vector3, mat: Material, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = 24
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.name = nm
	mi.position = at
	return mi
