extends Node3D
## 成交后的「天降电竞房」演出（用户 2026-11-07）。
##
## ── 第一版被使用者打回 ──
## 原话（勾选的四条）：
##   「灰尘太小 / 不够炸（想满屏灰）」「落地没冲击感 / 抖音不够」
##   「下降看着像瞬移 / 轨迹太直」「每次都要等 8 秒太久」
## 第一版实测：整帧平均亮度 2.2~2.5（几乎全白）、9 宫格里全是 200+、
## 暗像素占比只有 0.5%~6.6% —— 天空压白、房子泛白，**灰尘根本糊不住画面**。
##
## ── 这一版怎么改 ──
## ① 灰尘：5 层、合计约 2600 颗，最外层单粒 6.5 m；再加一块**贴地尘毯**
##   （水平加色/Alpha 圆盘，按 progress 扩到 46 m），落地那一下整屏都是灰。
## ② 冲击：屏幕震动（整台相机 −fov 里 `h_offset/v_offset` 抖动，衰减 0.9 s）+
##   **落地白闪**（CanvasLayer 全屏 ColorRect，0.25 s 淡出）+ 一小段**时间冻结**
##   （0.9 s 内 delta ×0.35，街霸式 hitstop）+ 地砖碎屑 + 双同心冲击环。
## ③ 轨迹：下落时**拖尾**（竖直的细长加色柱跟着房子一起落，两段亮度递增）+
##   速度线（贴着房子四周的短线粒子，向下拉）。
## ④ 时长：8.0 s → **5.6 s**（下落 1.15 s、前摇 0.1 s、环绕 4.0 s、收尾 0.35 s）。
##
## 仍然不暂停世界：只独占相机 + 暂时交出鼠标；时间冻结是**给演出自己的 delta 打折扣**，
## 不碰 `Engine.time_scale`（那会把敌人的物理和玩家的 `_apply_camera()` 一起拖慢）。
##
## 门在 +Z 那一头（`_probe_esports_door.gd` 量出来的：+Z 端竖直墙面 3.0 m²，另一端 66.5 m²）。

signal finished

const DROP_HEIGHT := 48.0
const FALL_TIME := 1.15
const HOLD_BEFORE_ORBIT := 0.10
const SETTLE_DIP := 0.085
const SETTLE_TIME := 0.36

## 环绕：半径 26 m、仰角 30°→15°、fov 80、扫 260°（把部室那侧也带到画面里）
const ORBIT_TIME := 4.0
## 环绕半径。2026-11-10 实测 26 m 时房子只占画面一小块，烟看不清 —— 收到 19 m。
## 房间对角 19.7 m，19 m 半径 + fov 80° 正好让房子占满画面 2/3。
const ORBIT_RADIUS := 19.0
const ORBIT_START_DEG := 168.0
## 环绕总扫过的角度。2026-11-10 使用者：「直接转圈圈环绕运镜，上下颠倒雷霆显现」
## 540°（一圈半）实测下来画面**全程都在歪**，房子根本看不清 —— 收到 400°：
## 一圈多一点，既有「转满一圈」的体感，结尾又能自然收住。
const ORBIT_SWEEP_DEG := 400.0
## 俯仰三段：起 30°（俯看）→ 中 -8°（**压到地平线附近仰拍**）→ 收 12°
## ⚠️ 2026-11-10 实测：-22° 会让相机的**视平线落到平台边缘以下**，
##    画面里只剩「一块悬空的地板」，房子被挡在外面（用户看到的那两张就是）。
##    这个平台是**悬空**的（四周没有地面），所以相机不能低于平台。
##    -8° 已经能读出「从下往上看」的翻转感，但不会掉出平台。
const ORBIT_PITCH_0 := 22.0
const ORBIT_PITCH_MID := -8.0
const ORBIT_PITCH_1 := 12.0
## 相机横滚：环绕中后段自转。360° 实测会让人分不清上下，
## 收到 200° —— 转到「明显歪了」就回来，配合俯仰翻转足够「雷霆」。
const ORBIT_ROLL_DEG := 200.0
## 环绕半径：中途拉近一下再拉远，制造压迫感
const ORBIT_RADIUS_MID := 15.0
## 「翻转」的钟形包络宽度。1.0 = 整个环绕期间都带翻转；0.55 = 只在**中途**翻，
## 开头结尾都是稳的。使用者要的是「中间视角翻转」，所以收窄。
const FLIP_BELL_WIDTH := 0.55
const ORBIT_LOOK_HEIGHT := 0.75
const CAM_FOV := 80.0

const TOTAL := FALL_TIME + HOLD_BEFORE_ORBIT + ORBIT_TIME + 0.35

var _room: Node3D
var _cam: Camera3D
var _prev_cam: Camera3D
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _t := 0.0
var _done := false
var _landed := false
var _base_y := 0.0
## 门朝向（世界水平单位向量）；环绕的 0° 就落在这个方向上
var _door_dir := Vector3.FORWARD
var _center := Vector3.ZERO
var _half_depth := 8.42
## 开演前房间的**局部** position，收尾时原样放回。
## ⚠️ 不能记世界 Y 再写回 `position.y`：`position` 是相对父节点的，父节点一旦
## 不在原点（`EsportsRoom` 现在挂在 game 根下还好，以后嵌进别的节点就会下沉）。
## 使用者 2026-11-08：「游戏开发部怎么变成滚木了」——实测落地后 Y 变成 -0.054，
## 就是世界/局部混用的症状。
var _base_pos := Vector3.ZERO
var _shake := 0.0
var _hitstop := 0.0
## 落地抖动的横滚分量（弧度）。由 `_process` 算，`_place_camera` 叠到 basis 上。
var _roll_jitter := 0.0

var _dust: Array[GPUParticles3D] = []
var _rocks: GPUParticles3D
var _streaks: GPUParticles3D
var _trail_near: MeshInstance3D
var _trail_far: MeshInstance3D
var _shock: MeshInstance3D
var _shock2: MeshInstance3D
var _shock_mats: Array[ShaderMaterial] = []
var _dust_sheet: MeshInstance3D
var _dust_sheet_mat: ShaderMaterial
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _boom: AudioStreamPlayer3D
var _flash: ColorRect


## 主入口。`room` 是整栋房子（`EsportsRoom`），`center` 是它落地后的水平中心。
## door_dir = 门朝向（世界水平方向，已归一化）。使用者会在编辑器里随手转房子，
## 所以机位不能写死「0° = +Z」—— 见 _dir_from_deg()。
func play(room: Node3D, center: Vector3, half_depth := 8.42,
		floor_y := -1.0, door_dir := Vector3.FORWARD) -> void:
	_room = room
	_center = center
	_half_depth = half_depth
	# 记下原始局部位置，收尾原样放回（别用世界坐标硬写 position.y）
	_base_pos = room.position
	print("[drop] play() 记录基准 position=%s（此时的设计高度）" % str(_base_pos))
	# `floor_y` 是**世界**高度，换成本地高度才算得出正确的下降距离
	var parent_y := 0.0
	if room.get_parent() is Node3D:
		parent_y = (room.get_parent() as Node3D).global_position.y
	_base_y = floor_y - parent_y if floor_y != -1.0 else _base_pos.y
	_door_dir = door_dir.normalized()
	if _door_dir.length_squared() < 0.0001:
		_door_dir = Vector3.FORWARD

	# ⚠️ 2026-11-10 严重 bug：所有特效（尘毯 / 冲击环 / 碎石 / 拖尾 / 光柱）
	#    都是按 `Vector3(0, y, 0)` 这种**局部坐标**摆的，而这个演出节点挂在
	#    `game` 根下、原点在 (0,0,0) —— 房间却在 (48~53, 0, 5~13)。
	#    结果：**特效生成在世界的原点，房子在 48 米外**，玩家看到地上一块
	#    莫名其妙的平板，房子孤零零在最边上（使用者截图里那张就是）。
	#    修法：把这个节点整体搬到房间中心，之后所有局部坐标就都对上了。
	global_position = Vector3(_center.x, floor_y if floor_y != -1.0 else 0.0, _center.z)

	_build_camera()
	_build_flash()
	_build_dust()
	_build_dust_sheet()
	_build_rocks()
	_build_streaks()
	_build_trails()
	_build_shock()
	_build_beam()
	_build_sound()

	_room.visible = true
	_room.position.y = _base_y + DROP_HEIGHT
	_place_camera(0.0)
	_cam.current = true
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)
	print("[drop] 开演：%.0f m 天降，全程 %.1f s，环绕 %.0f°" % [
		DROP_HEIGHT, TOTAL, ORBIT_SWEEP_DEG])


func _process(delta: float) -> void:
	if _done:
		return
	if _skip_pressed():
		_finish()
		return
	# ── 时间冻结：落地后 0.9 s 内把 delta 打折（街霸式 hitstop）──
	var dt := delta
	if _hitstop > 0.0:
		_hitstop = maxf(0.0, _hitstop - delta)
		dt = delta * 0.35
	_t += dt

	# ① 下落
	if _t < FALL_TIME:
		var k := clampf(_t / FALL_TIME, 0.0, 1.0)
		var e := pow(k, 2.4)              # 前段慢、后段砸下来
		var y_off := DROP_HEIGHT * (1.0 - e)
		_room.position.y = _base_y + y_off
		_update_beam(k)
		_update_trails(y_off)
	elif not _landed:
		_landed = true
		_room.position.y = _base_y
		_on_land()

	# ② settle
	if _landed:
		var st := _t - FALL_TIME
		if st < SETTLE_TIME:
			var k := st / SETTLE_TIME
			_room.position.y = _base_y - SETTLE_DIP * sin(k * PI) * (1.0 - k * 0.35)

	# ③ 镜头
	_place_camera(_t)

	# ④ 抖动衰减：前段满幅，之后按平方衰减
	# ⚠️ 2026-11-10 使用者「还要加入镜头抖动」——
	#    旧版振幅 0.75 / 旋转 0.012 rad 实测几乎看不出来。现在：
	#      · 位置振幅 0.75 → 2.2 m
	#      · 横滚抖动 0.012 → 0.055 rad（3.2°）
	#      · 衰减时间 0.9 s → 1.6 s（抖得久一点）
	#      · 加一条同频率的「呼吸」正弦，纯随机会像噪点，叠上正弦才像「震」
	#
	# ⚠️ 横滚不能写 `_cam.rotation.z` —— `_place_camera()` 每帧都把整个 basis 重设一遍，
	#    再写 rotation.z 会互相打架（表现为抖动时有时无）。这里统一在 `_place_camera()`
	#    里把 `_roll_jitter` 叠到 basis 上。
	if _shake > 0.001:
		_shake = maxf(0.0, _shake - delta / 1.6)
		var s := _shake * _shake
		var wob := sin(_t * 61.0) * 0.35 + sin(_t * 103.0) * 0.2
		_cam.h_offset = (randf_range(-s, s) + wob * s) * 2.2
		_cam.v_offset = (randf_range(-s, s) + wob * s) * 2.2
		_roll_jitter = randf_range(-s, s) * 0.055
	elif _cam != null:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0
		_roll_jitter = 0.0

	if _t >= TOTAL:
		_finish()


# ------------------------------------------------------------------ 落地那一下

func _on_land() -> void:
	_shake = 1.0
	_hitstop = 0.9
	# ⚠️ 2026-11-10 实测 bug：`one_shot = true` 的粒子在**同一帧**里
	#    `restart()` 之后立刻 `emitting = true`，会被内部状态机覆盖回 false ——
	#    探针量到的结果是 7 层全部 `emitting=false`，烟一颗都没放出来。
	#    修法：先 `restart()`，**等一帧**再 `emitting = true`。
	for d in _dust:
		d.set_meta("drop_fired", true)
		d.restart()
	for p in [_rocks, _streaks]:
		if p != null:
			p.restart()
	_fire_after_frame()
	for m in _shock_mats:
		m.set_shader_parameter("progress", 0.0)
	for s in [_shock, _shock2]:
		if s != null:
			s.visible = true
	_tween_shock()
	if _dust_sheet != null and _dust_sheet_mat != null:
		_dust_sheet.visible = true
		_dust_sheet_mat.set_shader_parameter("progress", 0.0)
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			if _dust_sheet_mat != null:
				_dust_sheet_mat.set_shader_parameter("progress", v), 0.0, 1.0, 1.8)
		tw.tween_callback(func() -> void:
			if _dust_sheet != null:
				_dust_sheet.visible = false)
	if _flash != null:
		_flash.modulate.a = 0.92
		var tf := create_tween()
		tf.tween_property(_flash, "modulate:a", 0.0, 0.28)
	if _boom != null:
		_boom.play()
	for m in [_trail_near, _trail_far, _beam]:
		if m != null:
			m.visible = false
	print("[drop] 落地")


## 落地后等一帧，再把粒子真正打开（见 `_on_land()` 里那段实测说明）。
func _fire_after_frame() -> void:
	await get_tree().process_frame
	for d in _dust:
		if d != null:
			d.emitting = true
	for p in [_rocks, _streaks]:
		if p != null:
			p.emitting = true
	# 二次爆开（第 ⑥ 层）：让它晚 0.18 s 再炸，制造「余波」
	if _dust.size() > 5:
		var f := _dust[5]
		f.emitting = false
		var tw := create_tween()
		tw.tween_interval(0.18)
		tw.tween_callback(func() -> void:
			if f != null and is_instance_valid(f):
				f.restart()
				f.emitting = true)
	print("[drop] 灰尘已开火（%d 层）" % _dust.size())


func _tween_shock() -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		for m in _shock_mats:
			if m != null:
				m.set_shader_parameter("progress", v), 0.0, 1.0, 1.25)
	tw.tween_callback(func() -> void:
		for s in [_shock, _shock2]:
			if s != null:
				s.visible = false)


# ------------------------------------------------------------------ 相机

func _build_camera() -> void:
	_prev_cam = get_viewport().get_camera_3d() if is_inside_tree() else null
	_cam = Camera3D.new()
	_cam.name = "DropCam"
	_cam.fov = CAM_FOV
	_cam.near = 0.05
	_cam.far = 600.0
	add_child(_cam)


## ⚠️ 不能用 `look_at()`：相机在「正上方俯视」附近时，`look_at` 的 up 向量会退化成
##    零向量 → 视线翻滚（使用者 2026-11-07 反馈的「房子上下反了」就是这一种：
##    模型本身是对的 —— 地板朝上、天花板朝下、y=0 是地面，`_probe_esports_flip.gd` 量过 ——
##    是镜头绕着自身 Z 轴翻了半圈）。这里直接给 `basis`：-Z 指向目标，
##    X 轴固定为「水平面内与视线垂直」的方向，Y 轴永远是「屏幕上」。
## 把「相对门朝向的角度」转成世界水平方向。
## 使用者在编辑器里把房子转个向，环绕也跟着转 —— 本喵不用改任何常量。
func _dir_from_deg(deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	# 以门朝向为 0°、顺时针：先取「门朝向」的垂直方向当 +90°
	var fwd := _door_dir
	var right := Vector3.UP.cross(fwd).normalized()   # 注意：这是**左手**侧的垂直方向
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	return (fwd * cos(a) + right * sin(a)).normalized()


## 收窄的钟形包络：k=0/1 时为 0，k=0.5 时为 1，但只在 `width` 这一段里鼓起。
## `width = 1.0` 退化成 `sin(πk)`；`0.55` 表示「中间 55% 的时间才翻」。
static func _bell(k: float, width: float) -> float:
	if width >= 0.999:
		return sin(PI * k)
	# 把 k 映射到「中间 width 段」，外面拉平到 0
	var lo := (1.0 - width) * 0.5
	var hi := 1.0 - lo
	if k <= lo or k >= hi:
		return 0.0
	var u := (k - lo) / (hi - lo)      # 0..1
	return sin(PI * u)


func _place_camera(t: float) -> void:
	var orbit_start := FALL_TIME + HOLD_BEFORE_ORBIT
	var k := clampf((t - orbit_start) / ORBIT_TIME, 0.0, 1.0)
	var ease_k := k * k * (3.0 - 2.0 * k)
	var ang := deg_to_rad(ORBIT_START_DEG + ORBIT_SWEEP_DEG * ease_k)

	# ── 俯仰：三段插值（30° 俯看 → -22° 翻转仰拍 → 12° 收）──
	# 用**收窄的**钟形：只在环绕中途翻，开头结尾都在正常视角。
	# 旧版用 `sin(πk)`（全程钟形）实测下来「画面大半时间都是歪的，房子看不清」。
	var bell := _bell(k, FLIP_BELL_WIDTH)
	var pitch_lerp := lerpf(ORBIT_PITCH_0, ORBIT_PITCH_1, ease_k)
	var pitch := pitch_lerp + (ORBIT_PITCH_MID - pitch_lerp) * bell
	var pitch_r := deg_to_rad(pitch)

	# ── 半径：中途收近（压迫感），两头放远 ──
	var r := lerpf(ORBIT_RADIUS * 0.92, ORBIT_RADIUS, ease_k)
	r -= (ORBIT_RADIUS - ORBIT_RADIUS_MID) * bell * 0.55

	# ang 的 0° = 门朝向（你摆在哪就绕哪），正值顺时针扫
	var horiz := _dir_from_deg(rad_to_deg(ang))
	# 标准球坐标：r 是**到房间中心的真实距离**，
	# pitch 决定「多高」—— 负 pitch 时相机跑到地面以下，画面就是仰拍颠倒的。
	var pos := _center + horiz * (cos(pitch_r) * r) \
		+ Vector3(0.0, sin(pitch_r) * r + ORBIT_LOOK_HEIGHT, 0.0)
	# 视线目标：稍高于房间中心，让房子落在画面正中偏下（上方留天空，下坠感更好）
	var look := _center + Vector3(0.0, ORBIT_LOOK_HEIGHT, 0.0)
	if t < FALL_TIME:
		look.y += (_room.global_position.y - _base_y) * 0.38
	_cam.global_position = pos
	# 手动正交化：永远「头朝上」
	var to_target := (look - pos).normalized()
	if to_target.length_squared() < 0.0001:
		return
	var right := Vector3.UP.cross(to_target)
	if right.length_squared() < 0.0001:
		# 视线几乎垂直于地面（正俯视）—— 用扫掠方向当右轴，免得退化成零
		right = horiz.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := to_target.cross(right).normalized()

	# ── 横滚（「转圈圈」）：中途绕视线轴自转 ──
	# 同样用收窄钟形，两头不滚、中间滚满 —— 结束时画面自然回正。
	# 再叠上落地抖动的横滚分量 `_roll_jitter`（见 `_process` 的 ④）。
	var roll := deg_to_rad(ORBIT_ROLL_DEG) * bell + _roll_jitter
	if absf(roll) > 0.0001:
		var q := Quaternion(to_target, roll)
		right = (q * right).normalized()
		up = (q * up).normalized()

	_cam.global_transform = Transform3D(Basis(right, up, -to_target), pos)


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	if _room != null:
		# 原样放回开演前记下的局部位置（不是世界坐标）
		_room.position = _base_pos
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.current = true
	Input.mouse_mode = _prev_mouse
	print("[drop] 收尾：相机交还玩家")
	get_tree().create_timer(3.0).timeout.connect(queue_free)
	finished.emit()


var _fresh_key := false


func _skip_pressed() -> bool:
	if _t < 0.3:
		return false
	return _has_fresh_key()


func _input(event: InputEvent) -> void:
	if _done:
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		_fresh_key = true
		return
	var m := event as InputEventMouseButton
	if m != null and m.pressed:
		_fresh_key = true


func _has_fresh_key() -> bool:
	if _fresh_key:
		_fresh_key = false
		return true
	return false


# ------------------------------------------------------------------ 贴图 / 材质

## 128×128 软边圆点（程序化，不占仓库体积）
static func _soft_dot(hard := 0.28) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n * 0.5, n * 0.5)
	var r := n * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c.x, y - c.y).length() / r
			var a := clampf(1.0 - (d - hard) / (1.0 - hard), 0.0, 1.0)
			# ⚠️ 2026-11-10 原来是 `a * a`，把中心 1.0 之外全压扁了，
			#    再乘 tint.a（0.26~0.62）→ 实际 alpha 只剩 0.06~0.14，看不见。
			#    现在用 `pow(a, 0.65)`：中心保持实，边缘柔，整体密度上来。
			img.set_pixel(x, y, Color(1, 1, 1, pow(a, 0.65)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## 32×128 竖直拖尾（越往下越亮），给下落轨迹用
static func _trail_grad() -> ImageTexture:
	var w := 16
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var v := float(y) / float(h - 1)          # 0 = 顶（远）, 1 = 底（近）
		var a := pow(v, 1.7)
		for x in w:
			var u := absf(float(x) / float(w - 1) - 0.5) * 2.0
			var a2 := a * (1.0 - u * u)
			img.set_pixel(x, y, Color(0.75, 0.85, 1.0, clampf(a2, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _dust_layer(amount: int, life: float, size: float, tint: Color,
		box: Vector3, vmin: float, vmax: float, grav: float, spread := 90.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.fixed_fps = 0
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-70, -4, -70), Vector3(140, 60, 140))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3(1, 0.08, 0)
	pm.spread = spread
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3(0.0, grav, 0.0)
	# ⚠️ 2026-11-10 使用者「怎么没看见烟雾了」——
	#    旧值 damping 1.6~5.0 会让粒子一出生就刹死，灰还没散开就停在原地，
	#    加上贴图中心只有 0.22 不透明度 → 整片看不见。现在阻尼降下来、让它飞出去。
	pm.damping_min = 0.25
	pm.damping_max = 1.10
	pm.scale_min = size * 0.55
	pm.scale_max = size * 1.5
	pm.color = tint
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	# ⚠️ 这一行 2026-11-10 被误删过一次 —— 没有它粒子**根本没有发射参数**，
	#    `emitting=true` 也一颗不飞（探针量到「7 层全 fired=true 但画面没烟」就是这个）。
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot(0.42)
	mat.disable_receive_shadows = true
	# ⚠️ 2026-11-10：`vertex_color_use_as_albedo = true` 时，粒子的 `color` 会乘到
	#    **ALBEDO（颜色）**上，而不是 ALPHA —— 所以 tint 的 alpha 被当成了亮度，
	#    画面里出现一片「发光的白点」而不是灰。
	#    解法：给贴图一个真正的灰，并让粒子颜色走 `color`（含 alpha）。
	mat.albedo_color = Color(1, 1, 1, 1)
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	_dust.append(p)
	return p


func _build_dust() -> void:
	# ⚠️ 2026-11-10 使用者「怎么没看见烟雾了，加回来」——
	#    旧版 5 层合计 2600 颗、alpha 0.26~0.62，配合那张中心 0.22 的软点，
	#    实际不透明度只剩个位数，等于没有。现在：
	#      · 层数 5 → 7（补两层贴地大团 + 一层高空飘）
	#      · 颗粒数 2600 → 4600
	#      · alpha 全线提到 0.45~0.82
	#      · 速度拉开差距，让灰飞得出去
	# ① 贴地尘毯：低、宽、快，落地瞬间糊住地面
	var a := _dust_layer(1400, 3.2, 3.0, Color(0.62, 0.58, 0.52, 0.80),
		Vector3(10.0, 0.30, 14.0), 11.0, 26.0, 0.30, 88.0)
	a.position = Vector3(0, 0.2, 0)
	# ② 中环：往外扩的主力
	var b := _dust_layer(1100, 4.0, 5.0, Color(0.55, 0.52, 0.47, 0.72),
		Vector3(7.5, 0.70, 11.0), 7.0, 18.0, 0.45, 90.0)
	b.position = Vector3(0, 0.8, 0)
	# ③ 大团灰：慢、暗、大，撑体积感
	var c := _dust_layer(700, 5.6, 7.5, Color(0.44, 0.42, 0.39, 0.60),
		Vector3(6.0, 1.00, 9.0), 3.5, 10.0, 0.70, 90.0)
	c.position = Vector3(0, 1.4, 0)
	# ④ 冲天柱：往上蹿，把"砸下来"的高度感拉满
	var d := _dust_layer(520, 3.6, 3.8, Color(0.60, 0.57, 0.52, 0.70),
		Vector3(4.5, 0.25, 6.5), 6.0, 16.0, 1.05, 42.0)
	d.process_material.gravity = Vector3(0, 2.2, 0)
	d.process_material.direction = Vector3(0, 1, 0)
	d.process_material.spread = 55.0
	d.position = Vector3(0, 0.4, 0)
	# ⑤ 高空散尘：慢速飘、寿命最长，让灰一直留在画面里
	var e := _dust_layer(480, 7.5, 10.0, Color(0.52, 0.50, 0.46, 0.45),
		Vector3(9.0, 1.4, 12.0), 1.2, 5.0, 0.20, 90.0)
	e.position = Vector3(0, 2.4, 0)
	# ⑥ 二次爆开：落地 0.18 s 后再从中心炸一次，制造「余波」
	var f := _dust_layer(600, 3.0, 4.4, Color(0.58, 0.55, 0.50, 0.62),
		Vector3(3.0, 0.4, 4.0), 14.0, 30.0, 0.15, 90.0)
	f.position = Vector3(0, 0.5, 0)
	# ⑦ 贴近镜头的碎尘：让灰从画面里「冲出来」
	var g := _dust_layer(300, 2.4, 2.2, Color(0.68, 0.65, 0.60, 0.55),
		Vector3(12.0, 0.6, 12.0), 16.0, 34.0, 0.10, 90.0)
	g.position = Vector3(0, 1.0, 0)


## 贴地尘毯：一块水平圆盘，着色器按 progress 从中心扩到 ~46 m，同时淡出
func _build_dust_sheet() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_dust_sheet_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dust_color : source_color = vec4(0.44, 0.42, 0.39, 0.55);
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float grow = mix(0.05, 1.0, sqrt(progress));
	float body = 1.0 - smoothstep(grow * 0.55, grow, d);
	float noise = fract(sin(dot(floor(UV * 220.0), vec2(12.9898, 78.233))) * 43758.5453);
	float fade = (1.0 - smoothstep(0.25, 1.0, progress)) * 0.85;
	ALBEDO = dust_color.rgb;
	// ⚠️ 2026-11-10：旧版 alpha 最高到 0.85 且整块 46 m 铺满 —— 实测从演出机位看
	//    就是地上一块**不透明的塑料布**，把刚砸下来的房子整个盖住。
	//    现在压到 0.42 上限，并且**中间挖空**（房子本体那一块不画），
	//    让它读起来像「贴着地面的扬尘」而不是「一块板」。
	float hole = smoothstep(0.10, 0.42, d);   // 中心 10% 全空、42% 外全实
	ALPHA = clamp(body * fade * hole * (0.60 + noise * 0.40), 0.0, 0.42);
}
"""
	_dust_sheet_mat.shader = sh
	_dust_sheet_mat.set_shader_parameter("progress", 0.0)
	q.material = _dust_sheet_mat
	_dust_sheet = MeshInstance3D.new()
	_dust_sheet.name = "DustSheet"
	_dust_sheet.mesh = q
	# 46 m → 30 m：房间对角 19.7 m，30 m 已经能盖到外圈，又不至于铺满整个平台
	_dust_sheet.scale = Vector3(30.0, 30.0, 1.0)
	_dust_sheet.rotation_degrees = Vector3(-90, 0, 0)
	# 抬高到 0.55 m：原先 0.18 m 几乎贴在地砖上，和地板 z-fighting，看着像块补丁
	_dust_sheet.position = Vector3(0.0, 0.55, 0.0)
	_dust_sheet.visible = false
	add_child(_dust_sheet)


func _build_rocks() -> void:
	var p := GPUParticles3D.new()
	p.amount = 320
	p.lifetime = 2.4
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.visibility_aabb = AABB(Vector3(-70, -4, -70), Vector3(140, 60, 140))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(5.5, 0.25, 9.0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 72.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 19.0
	pm.gravity = Vector3(0, -26.0, 0)
	pm.scale_min = 0.07
	pm.scale_max = 0.26
	pm.color = Color(0.33, 0.32, 0.31, 1.0)
	p.process_material = pm
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	box.material = mat
	p.draw_pass_1 = box
	add_child(p)
	_rocks = p


## 下落速度线：短线粒子，向下拉，看着像"砸下来带风"
func _build_streaks() -> void:
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 1.1
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.55
	p.visibility_aabb = AABB(Vector3(-70, -4, -70), Vector3(140, 80, 140))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(4.6, 12.0, 8.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 42.0
	pm.gravity = Vector3(0, -30.0, 0)
	pm.scale_min = 1.0
	pm.scale_max = 2.4
	pm.color = Color(0.82, 0.88, 1.0, 0.55)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 2.4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	q.material = mat
	p.draw_pass_1 = q
	add_child(p)
	_streaks = p


## 下落拖尾：两根竖直圆柱，从房子顶一直往上连到它"来处"，亮度随高度递减
func _build_trails() -> void:
	for i in 2:
		var near := i == 0
		var cyl := CylinderMesh.new()
		cyl.top_radius = 6.6 if near else 4.2
		cyl.bottom_radius = 5.4 if near else 7.2
		cyl.height = 1.0
		cyl.radial_segments = 20
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(0.72, 0.84, 1.0, 0.22 if near else 0.09)
		cyl.material = mat
		var mi := MeshInstance3D.new()
		mi.name = "TrailNear" if near else "TrailFar"
		mi.mesh = cyl
		add_child(mi)
		if near:
			_trail_near = mi
		else:
			_trail_far = mi


## 拖尾长度 = 当前离地高度；越接近地面越亮（"压缩空气"的观感）
func _update_trails(y_off: float) -> void:
	if _trail_near == null or _trail_far == null:
		return
	var k := 1.0 - clampf(y_off / DROP_HEIGHT, 0.0, 1.0)   # 0 = 在高处, 1 = 落地
	for pair in [[_trail_near, 0.18, 0.42], [_trail_far, 0.06, 0.20]]:
		var mi: MeshInstance3D = pair[0]
		var a0: float = pair[1]
		var a1: float = pair[2]
		mi.visible = y_off > 0.5
		mi.scale = Vector3(1.0, maxf(y_off, 0.05), 1.0)
		mi.position = Vector3(0.0, y_off * 0.5, 0.0)   # 底端 = 房子顶（房子已抬到 y_off）
		var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = lerpf(a0, a1, k)


## 双同心冲击环
func _build_shock() -> void:
	var code := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ring_color : source_color = vec4(0.90, 0.93, 1.0, 1.0);
uniform float thickness = 0.045;
uniform float radius_scale = 1.0;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float r = mix(0.05, 1.0, progress) * radius_scale;
	float band = 1.0 - smoothstep(0.0, thickness, abs(d - r));
	float fade = 1.0 - smoothstep(0.30, 1.0, progress);
	float inner = (1.0 - smoothstep(0.0, r, d)) * 0.10 * (1.0 - progress);
	ALBEDO = ring_color.rgb;
	ALPHA = clamp((band * 1.1 + inner) * fade, 0.0, 1.0);
}
"""
	for i in 2:
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		var mat := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = code
		mat.shader = sh
		mat.set_shader_parameter("progress", 0.0)
		mat.set_shader_parameter("radius_scale", 1.0 if i == 0 else 0.62)
		q.material = mat
		var mi := MeshInstance3D.new()
		mi.name = "Shockwave%d" % i
		mi.mesh = q
		mi.scale = Vector3(34.0 if i == 0 else 26.0, 34.0 if i == 0 else 26.0, 1.0)
		mi.rotation_degrees = Vector3(-90, 0, 0)
		mi.position = Vector3(0.0, 0.1 + i * 0.05, 0.0)
		mi.visible = false
		add_child(mi)
		_shock_mats.append(mat)
		if i == 0:
			_shock = mi
		else:
			_shock2 = mi


## 下落时的天空光柱（保留第一版的，落地后隐藏）
func _build_beam() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 5.2
	cyl.bottom_radius = 6.6
	cyl.height = DROP_HEIGHT
	cyl.radial_segments = 24
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(0.62, 0.80, 1.0, 0.10)
	cyl.material = _beam_mat
	_beam = MeshInstance3D.new()
	_beam.name = "DropBeam"
	_beam.mesh = cyl
	_beam.position = Vector3(0.0, DROP_HEIGHT * 0.5, 0.0)
	add_child(_beam)


func _update_beam(k: float) -> void:
	if _beam == null:
		return
	_beam.visible = true
	_beam_mat.albedo_color.a = lerpf(0.05, 0.30, k)


## 落地白闪：全屏 ColorRect（CanvasLayer，跟游戏 HUD 同一个渲染层）
func _build_flash() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DropFlashLayer"
	layer.layer = 90          # 压在 HUD 上面，但比设置菜单低
	add_child(layer)
	_flash = ColorRect.new()
	_flash.name = "DropFlash"
	_flash.color = Color(1, 0.97, 0.92, 1)
	_flash.modulate.a = 0.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_flash)


# ------------------------------------------------------------------ 声音

func _build_sound() -> void:
	var stream := _synth_boom()
	if stream == null:
		return
	_boom = AudioStreamPlayer3D.new()
	_boom.name = "DropBoom"
	_boom.stream = stream
	_boom.unit_size = 30.0
	_boom.max_distance = 400.0
	_boom.volume_db = 4.0
	add_child(_boom)


## 2.4 s / 22050 Hz 低音：58 Hz + 34 Hz 正弦 × 低通噪声 × 快速衰减，再叠一记高频"啪"
static func _synth_boom() -> AudioStreamWAV:
	var rate := 22050
	var n := int(2.4 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261107
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * 2.4) * (1.0 - exp(-t * 110.0))
		var body := sin(TAU * 58.0 * t) + 0.6 * sin(TAU * 34.0 * t)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.045)
		var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 42.0)
		var s := clampf((body * 0.55 + lp * 1.5) * env + crack * 0.35, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
