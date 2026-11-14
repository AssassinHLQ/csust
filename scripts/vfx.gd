class_name Vfx
extends RefCounted
## 通用特效工具箱（2026-11-14 用户：「怎么感觉效果不够震撼，加特效」）。
##
## 本地**没有**特效资源库；这里沿用 `esports_drop.gd` 里已经验证过的那一套：
##   · 粒子 = 程序化生成的软点贴图 + `GPUParticles3D`，零外部素材；
##   · 屏幕震动 = 相机 `h_offset / v_offset`（**不碰** `Engine.time_scale`，
##     那会把玩家相机和物理一起拖慢，`esports_drop.gd` 里已经写明这条）；
##   · 屏幕闪光 = 一个常驻 CanvasLayer 的 ColorRect。
##
## 全部 API 静态调用，宿主节点（负责 tick 抖动）在第一次用时懒建：
##     Vfx.impact(self, pos, Color(1,0.3,0.2), 1.0)
##     Vfx.shake(0.6, 0.5)
##     Vfx.flash(Color(1,0.9,0.85), 0.5, 0.35)

static var _host: _Ticker
static var _layer: CanvasLayer
static var _flash: ColorRect
static var _dot: ImageTexture


## 宿主：只干两件事 —— 每帧把抖动写进相机、衰减抖动。
## ⚠️ 注意：**不要**在内部类里引用 `Vfx`（`--script --check-only` 模式下
##    自己的 class_name 还没注册，会报 `Identifier not found: Vfx`）。
##    所以抖动状态放在这个宿主节点自己身上，`Vfx.shake()` 只往里写数。
class _Ticker extends Node:
	var amp := 0.0
	var t := 0.0
	var dur := 1.0

	func _process(delta: float) -> void:
		if t <= 0.0:
			if amp > 0.0:
				amp = 0.0
				_apply(0.0, 0.0)
			return
		t = maxf(t - delta, 0.0)
		var k := t / maxf(dur, 0.001)
		var s := amp * k * k
		_apply(randf_range(-s, s), randf_range(-s, s) * 0.7)

	func _apply(ox: float, oy: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		cam.h_offset = ox
		cam.v_offset = oy


static func _ensure_host() -> _Ticker:
	if _host != null and is_instance_valid(_host):
		return _host
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	_host = _Ticker.new()
	_host.name = "VfxHost"
	_host.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(_host)
	return _host


# ────────────────────────── 屏幕：震动 / 闪光 ──────────────────────────

## 屏幕震动。`amp` 是像素级偏移量（0.3 轻微 / 1.0 明显 / 2.5 重击），`dur` 秒。
static func shake(amp: float, dur := 0.4) -> void:
	var host := _ensure_host()
	if host == null:
		return
	var t := host as _Ticker
	if t == null:
		return
	t.amp = maxf(t.amp, amp)
	t.dur = maxf(t.dur, dur)
	t.t = maxf(t.t, dur)


## 全屏闪光（0~1 透明度）。颜色一般给暖白或技能色。
static func flash(col: Color, alpha := 0.5, dur := 0.3) -> void:
	var host := _ensure_host()
	if host == null:
		return
	if _layer == null or not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.name = "VfxFlash"
		_layer.layer = 120
		_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		host.add_child(_layer)
		_flash = ColorRect.new()
		_flash.name = "Flash"
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash.color = Color(1, 1, 1, 0)
		_layer.add_child(_flash)
	_flash.color = Color(col.r, col.g, col.b, 0.0)
	var tw := host.create_tween()
	tw.tween_property(_flash, "color:a", clampf(alpha, 0.0, 1.0), 0.06)
	tw.tween_property(_flash, "color:a", 0.0, maxf(dur, 0.05))


# ────────────────────────── 粒子 ──────────────────────────

## 一张程序化软点（白 → 透明），全工程共用
static func soft_dot() -> ImageTexture:
	if _dot != null:
		return _dot
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_dot = ImageTexture.create_from_image(img)
	return _dot


## 一团爆散粒子（加色发光）。`parent` 一般传 BOSS / 召唤物自己。
static func burst(parent: Node, pos: Vector3, col: Color, count := 40,
		size := 1.4, speed := 16.0, life := 0.6, gravity := -4.0) -> GPUParticles3D:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var p := GPUParticles3D.new()
	p.amount = maxi(count, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.fixed_fps = 0
	p.emitting = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = maxf(size, 0.2)
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.35
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0.0, gravity, 0.0)
	pm.damping_min = 1.0
	pm.damping_max = 4.0
	pm.scale_min = size * 0.45
	pm.scale_max = size * 1.4
	pm.color = col
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	# 颜色随寿命淡出
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = soft_dot()
	mat.albedo_color = Color(1, 1, 1, 1)
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.top_level = true
	p.global_position = pos
	# 播完自己回收（`emitting` 设 false 后粒子还会飞完寿命）
	var host := _ensure_host()
	if host != null:
		var tw := host.create_tween()
		tw.tween_interval(life + 0.5)
		tw.tween_callback(func() -> void:
			if is_instance_valid(p):
				p.queue_free())
	return p


## 冲击环：一个快速膨胀又淡出的圆环（地面/空中都行）
static func ring(parent: Node, pos: Vector3, col: Color, radius := 8.0,
		dur := 0.45, flat := true) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.94
	tm.outer_radius = 1.0
	tm.rings = 64
	tm.ring_segments = 5
	mi.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = col
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.top_level = true
	mi.global_position = pos
	mi.scale = Vector3(radius * 0.2, 2.0 if flat else 1.0, radius * 0.2)
	var tw := parent.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 2.0 if flat else 1.0, radius), dur) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur * 1.15)
	tw.chain().tween_callback(mi.queue_free)


## 一闪即灭的点光（让"打到了"有亮度）
static func flash_light(parent: Node, pos: Vector3, col: Color,
		energy := 6.0, dur := 0.35, light_range := 18.0) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.4
	parent.add_child(l)
	l.top_level = true
	l.global_position = pos
	var tw := parent.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(l.queue_free)


## 一次"打中了"的完整组合：粒子 + 环 + 点光 + 屏幕震动
## `scale` 控制分量（0.4 小 / 1.0 中 / 2.0 大），`dist` 用来按距离衰减震动。
static func impact(parent: Node, pos: Vector3, col: Color, scale_ := 1.0,
		dist := 0.0) -> void:
	burst(parent, pos, col, int(28 * scale_), 1.2 * scale_, 14.0 * sqrt(scale_),
		0.5 + 0.2 * scale_, -5.0)
	ring(parent, pos, Color(col.r, col.g, col.b, 0.85), 5.0 * scale_, 0.35 + 0.1 * scale_)
	flash_light(parent, pos, col, 4.0 * scale_, 0.3, 12.0 * scale_)
	var falloff := clampf(1.0 - dist / 70.0, 0.0, 1.0)
	if falloff > 0.05:
		shake(0.55 * scale_ * falloff, 0.28 + 0.12 * scale_)


## 原地炸开一大团（召唤 / 复活 / 死亡用）
static func big_burst(parent: Node, pos: Vector3, col: Color, scale_ := 2.0) -> void:
	burst(parent, pos, col, int(90 * scale_), 2.2 * scale_, 22.0 * scale_, 1.1, -3.0)
	ring(parent, pos, Color(col.r, col.g, col.b, 0.95), 14.0 * scale_, 0.6)
	ring(parent, pos + Vector3.UP * 2.0, Color(col.r * 0.8, col.g * 0.6, col.b, 0.6),
		22.0 * scale_, 0.9, false)
	flash_light(parent, pos + Vector3.UP * 4.0, col, 12.0 * scale_, 0.6, 40.0 * scale_)
	shake(1.6 * scale_ * 0.5, 0.6)
