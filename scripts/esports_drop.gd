extends Node3D
## 成交后的「天降电竞房」演出（用户 2026-11-07）。
##
## 用户原话：
##   「在成交后播放电竞房从天而降落地炸出大量灰尘动画视角要广一点，包括游戏开发部，
##     摄像机旋转环绕体现电竞房的震撼」
##
## 时间轴（总长 `total` ≈ 8.0 s，任意键可跳过）：
##   0.0 → 1.4   房子从 `DROP_HEIGHT` 高的地方砸下来（加速下落），天空光柱 + 影子跟着缩
##   1.4         着地：镜头重抖、`BIG_DUST` 大团灰尘炸开、冲击波圆环扩散、碎石飞溅、
##               低音轰鸣；这一下之后房子轻微"settle"（下沉 8 cm 再弹回）
##   1.4 → 7.6   镜头从**门口**起飞，绕整个东侧地块一圈（240°），半径 22 m、仰角 35°→18°，
##               把游戏开发部部室 + 电竞房 + 地块一起收进画面
##   7.6 → 8.0   淡出，把相机交还玩家
##
## 设计取舍：
##   · **不暂停世界**：`get_tree().paused` 一开，玩家的 `_apply_camera()` 也跟着停，
##     演出结束时镜头要"跳"回去一下。这里改为「独占相机 + 暂时收走玩家的鼠标捕获」，
##     结束后把 `cam.current` 还给玩家自己的相机，位置/朝向都没动，无缝衔接。
##   · **不写死朝向**：房子门在 +Z 那一头（`_probe_esports_door.gd` 量出来的：
##     +Z 端竖直墙面只有 3 m²，另一端 66.5 m²）。镜头从门口起飞。
##   · 灰尘用 `GPUParticles3D` + 程序化贴图（`_soft_dot()`，不依赖任何美术资源）；
##     冲击波是一块水平 QuadMesh + 着色器，按 `progress` 画圆环。

signal finished

## 房子下落多高（米）。再高就要等太久，再低看不出"从天而降"
const DROP_HEIGHT := 58.0
## 自由落体的感觉：用 `pow(t, 2.2)` 而不是真重力，前段慢一点、看得清
const FALL_TIME := 1.45
## 落地后的 settle：下沉再弹回
const SETTLE_DIP := 0.085
const SETTLE_TIME := 0.42
## 环绕
const ORBIT_TIME := 6.2
const ORBIT_RADIUS := 22.0
const ORBIT_START_DEG := 200.0     ## 0° = 门口正前方（+Z），顺时针绕
const ORBIT_SWEEP_DEG := 240.0
const ORBIT_PITCH_0 := 34.0
const ORBIT_PITCH_1 := 17.0
const ORBIT_LOOK_HEIGHT := 0.9     ## 视线落点离地多高（贴地一点才显得房子大）
## 总时长（跳过的窗口 = 全部）
const TOTAL := FALL_TIME + 0.25 + ORBIT_TIME + 0.35

var _room: Node3D
var _cam: Camera3D
var _prev_cam: Camera3D
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _t := 0.0
var _done := false
var _landed := false
var _base_y := 0.0
var _center := Vector3.ZERO
var _half_depth := 8.42
var _shake := 0.0

var _dust: Array[GPUParticles3D] = []
var _shock: MeshInstance3D
var _shock_mat: ShaderMaterial
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _rocks: GPUParticles3D
var _boom: AudioStreamPlayer3D


## 主入口：`room` 是整栋房子（`EsportsRoom` 节点），`center` 是它落地后的水平中心。
func play(room: Node3D, center: Vector3, half_depth := 8.42) -> void:
	_room = room
	_center = center
	_half_depth = half_depth
	_base_y = room.position.y

	_build_camera()
	_build_dust()
	_build_shock()
	_build_beam()
	_build_rocks()
	_build_sound()

	# 起手：房子在天上、看不见
	_room.visible = true
	_room.position.y = _base_y + DROP_HEIGHT
	_place_camera(0.0)
	_cam.current = true
	# 演出期间把鼠标还给人（玩家停手最稳），结束后原样恢复
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)
	print("[drop] 开演：房子从 %.1f m 高砸下来，环绕 %.0f°" % [DROP_HEIGHT, ORBIT_SWEEP_DEG])


func _process(delta: float) -> void:
	if _done:
		return
	# 任意键 / 任意鼠标键 = 跳过
	if _skip_pressed():
		_finish()
		return
	_t += delta

	# ── ① 下落 ──
	if _t < FALL_TIME:
		var k := clampf(_t / FALL_TIME, 0.0, 1.0)
		var e := pow(k, 2.2)  # 前段慢、后段砸下来
		_room.position.y = _base_y + DROP_HEIGHT * (1.0 - e)
		_update_beam(k)
	elif not _landed:
		_landed = true
		_room.position.y = _base_y
		_on_land()

	# ── ② settle（落地后轻微下沉再弹回）──
	if _landed:
		var st := _t - FALL_TIME
		if st < SETTLE_TIME:
			var k := st / SETTLE_TIME
			# 0 → 1 的下沉，再 sin 回弹一半
			_room.position.y = _base_y - SETTLE_DIP * sin(k * PI) * (1.0 - k * 0.35)

	# ── ③ 环绕 ──
	_place_camera(_t)

	# ── ④ 抖动衰减 ──
	if _shake > 0.001:
		_shake = maxf(0.0, _shake - delta * 2.4)
		var s := _shake * _shake
		_cam.h_offset = randf_range(-s, s) * 0.5
		_cam.v_offset = randf_range(-s, s) * 0.5

	if _t >= TOTAL:
		_finish()


## 落地那一帧：灰尘、冲击波、碎石、抖动、低音
func _on_land() -> void:
	_shake = 1.0
	for d in _dust:
		d.set_meta("drop_fired", true)   # 自检用：粒子只在落地这一下吐一次
		d.restart()
		d.emitting = true
	if _rocks != null:
		_rocks.restart()
		_rocks.emitting = true
	if _shock_mat != null:
		_shock_mat.set_shader_parameter("progress", 0.0)
		_shock.visible = true
		_tween_shock()
	if _boom != null:
		_boom.play()
	if _beam != null:
		_beam.visible = false
	print("[drop] 落地")


func _tween_shock() -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_shock_mat.set_shader_parameter("progress", v), 0.0, 1.0, 1.5)
	tw.tween_callback(func() -> void:
		if _shock != null:
			_shock.visible = false)


# ------------------------------------------------------------------ 相机

func _build_camera() -> void:
	_prev_cam = get_viewport().get_camera_3d() if is_inside_tree() else null
	_cam = Camera3D.new()
	_cam.name = "DropCam"
	_cam.fov = 74.0          # 广角（用户：「视角要广一点」）
	_cam.near = 0.05
	_cam.far = 600.0
	add_child(_cam)


## 门口正前方 = +Z（门在 +Z 那一头，见文件头）。0° 在门口，顺时针绕。
func _place_camera(t: float) -> void:
	var orbit_start := FALL_TIME + 0.25
	var k := clampf((t - orbit_start) / ORBIT_TIME, 0.0, 1.0)
	# 前摇阶段不动（就停在门口机位，看房子砸下来）
	var ease_k := k * k * (3.0 - 2.0 * k)  # smoothstep
	var ang := deg_to_rad(ORBIT_START_DEG + ORBIT_SWEEP_DEG * ease_k)
	var pitch := deg_to_rad(lerpf(ORBIT_PITCH_0, ORBIT_PITCH_1, ease_k))
	var r := lerpf(ORBIT_RADIUS * 0.92, ORBIT_RADIUS, ease_k)
	var dir := Vector3(sin(ang), 0.0, cos(ang))
	var pos := _center + dir * r + Vector3(0.0, sin(pitch) * r * 0.55 + 1.4, 0.0)
	var look := _center + Vector3(0.0, ORBIT_LOOK_HEIGHT, 0.0)
	# 下落阶段：镜头稍微俯低一点跟着房子
	if t < FALL_TIME:
		look.y += (_room.global_position.y - _base_y) * 0.42
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	if _shake <= 0.001:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	if _room != null:
		_room.position.y = _base_y
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.current = true
	Input.mouse_mode = _prev_mouse
	print("[drop] 收尾：相机交还玩家")
	# 让灰尘自然淡完再拆节点（拆早了画面上会"啪"地消失）
	get_tree().create_timer(3.0).timeout.connect(queue_free)
	finished.emit()


func _skip_pressed() -> bool:
	if _t < 0.35:
		return false  # 开场别被上一次按键误触
	return _has_fresh_key()


## 只在**这一帧有新按下**时跳过（用 `_input` 记的标记）
var _fresh_key := false


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


# ------------------------------------------------------------------ 灰尘 / 碎石 / 冲击波 / 光柱

## 一张 128×128 的软边圆点（程序化生成，不占仓库体积）。
## ⚠️ 粒子贴图要 `ALPHA` 通道 + `billboard`，所以这里只写白色 + 渐变 alpha。
static func _soft_dot(hard := 0.35) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n * 0.5, n * 0.5)
	var r := n * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c.x, y - c.y).length() / r
			var a := clampf(1.0 - (d - hard) / (1.0 - hard), 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _dust_material(tint: Color, size: float, life: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9.0, 0.35, 13.0)   # 沿房间长边铺开
	pm.direction = Vector3(1, 0.05, 0)
	pm.spread = 90.0
	pm.initial_velocity_min = 3.5
	pm.initial_velocity_max = 13.0
	pm.gravity = Vector3(0.0, 0.55, 0.0)                  # 轻微上飘
	pm.damping_min = 1.8
	pm.damping_max = 4.5
	pm.scale_min = size * 0.55
	pm.scale_max = size * 1.35
	pm.color = tint
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.hue_variation_min = -0.03
	pm.hue_variation_max = 0.03
	return pm


func _build_dust() -> void:
	# 三层：细尘（快、亮）、大团灰（慢、暗、大）、贴地扩散（低、宽）
	var specs := [
		{"n": 900, "life": 2.6, "size": 0.55, "tint": Color(0.78, 0.74, 0.68, 0.55)},
		{"n": 420, "life": 4.2, "size": 1.6, "tint": Color(0.55, 0.53, 0.50, 0.42)},
		{"n": 260, "life": 5.0, "size": 2.8, "tint": Color(0.62, 0.60, 0.57, 0.30)},
	]
	for sp in specs:
		var p := GPUParticles3D.new()
		p.amount = int(sp["n"])
		p.lifetime = float(sp["life"])
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 0.92
		p.fixed_fps = 0
		p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		p.visibility_aabb = AABB(Vector3(-40, -3, -40), Vector3(80, 30, 80))
		p.process_material = _dust_material(sp["tint"], float(sp["size"]), float(sp["life"]))
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = _soft_dot(0.25)
		mat.disable_receive_shadows = true
		quad.material = mat
		p.draw_pass_1 = quad
		p.position = Vector3(0.0, 0.25, 0.0)
		add_child(p)
		_dust.append(p)


func _build_rocks() -> void:
	# 碎石：小方块，初速往外+往上，重力拉回来
	var p := GPUParticles3D.new()
	p.amount = 220
	p.lifetime = 2.2
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.visibility_aabb = AABB(Vector3(-40, -3, -40), Vector3(80, 30, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(5.0, 0.2, 8.0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 16.0
	pm.gravity = Vector3(0, -22.0, 0)
	pm.scale_min = 0.06
	pm.scale_max = 0.22
	pm.color = Color(0.35, 0.34, 0.33, 1.0)
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


## 落地冲击波：一块水平 QuadMenu，着色器按 progress 画扩散的圆环
func _build_shock() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_shock_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ring_color : source_color = vec4(0.85, 0.88, 0.95, 1.0);
uniform float thickness = 0.055;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;          // 0 = 中心, 1 = 边缘
	float r = mix(0.08, 1.0, progress);              // 环半径随时间扩大
	float band = 1.0 - smoothstep(0.0, thickness, abs(d - r));
	float fade = 1.0 - smoothstep(0.35, 1.0, progress);
	float inner = (1.0 - smoothstep(0.0, r, d)) * 0.12 * (1.0 - progress);
	ALBEDO = ring_color.rgb;
	ALPHA = clamp((band * 0.85 + inner) * fade, 0.0, 1.0);
}
"""
	_shock_mat.shader = sh
	_shock_mat.set_shader_parameter("progress", 0.0)
	q.material = _shock_mat
	_shock = MeshInstance3D.new()
	_shock.name = "Shockwave"
	_shock.mesh = q
	_shock.scale = Vector3(30.0, 30.0, 1.0)   # 直径 30 m，罩住整个地块
	_shock.rotation_degrees = Vector3(-90, 0, 0)
	_shock.position = Vector3(0.0, 0.12, 0.0)
	_shock.visible = false
	add_child(_shock)


## 下落时的天空光柱：一个细长的圆柱（加色混合），落定后隐藏
func _build_beam() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 5.2
	cyl.bottom_radius = 6.4
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
	# 越接近地面越亮：0 → 0.10，1 → 0.28
	_beam_mat.albedo_color.a = lerpf(0.06, 0.26, k)


## 低音轰鸣：没有素材就程序化合成一段 2.5 s 的低频噪声包络
func _build_sound() -> void:
	var stream := _synth_boom()
	if stream == null:
		return
	_boom = AudioStreamPlayer3D.new()
	_boom.name = "DropBoom"
	_boom.stream = stream
	_boom.unit_size = 30.0
	_boom.max_distance = 400.0
	_boom.volume_db = 2.0
	add_child(_boom)


## 2.2 s / 22050 Hz 的单声道低音：60 Hz 正弦 × 噪声 × 快速衰减，再叠一层 34 Hz 低频。
static func _synth_boom() -> AudioStreamWAV:
	var rate := 22050
	var n := int(2.2 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261107
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * 2.6) * (1.0 - exp(-t * 90.0))   # 快起、缓落
		var body := sin(TAU * 58.0 * t) + 0.6 * sin(TAU * 34.0 * t)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.045)     # 一阶低通 → 闷响
		var s := clampf((body * 0.55 + lp * 1.4) * env, -1.0, 1.0)
		var v := int(s * 32000.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
