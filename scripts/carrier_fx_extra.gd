extends Node3D
## 机甲飞行的**装饰性**特效层（2026-11-10）—— 专治「不够多不够炫丽」。
##
## ── 用户原话 ──
## 「总感觉不够多不够炫丽」
##
## ── 为什么单独开一个脚本，而不是继续往 `carrier_form.gd` 里塞 ──
## 那个文件已经 2000+ 行，再塞五套特效会彻底没法维护。
## 而且这五样东西的共同点是：**纯装饰、只管好看、不参与任何判定**，
## 集中放一处，出问题（掉帧/穿模）可以整体关掉，不影响飞行本身。
##
## ── 这五样（都在 `_build()` 里建一次，`tick()` 每帧驱动）──
##   ① 等离子光带（PlasmaRibbon）：推进器后方拖出的两条流动光带
##   ② 能量环阵列（EnergyRings）：环绕机体的多圈旋转发光环
##   ③ 速度气流线（SpeedLines）：高速时从四周掠过的小光条
##   ④ 翼尖光点（WingTips）：肩翼 8 个端点各一个脉动光点
##   ⑤ 加力尾焰（AfterburnerCones）：高速时主焰后面再套一层白色尖焰
##
## ── 全部用「加色混合 + 不投影」──
## 加色混合在深色背景上最亮、叠得越多越亮，这正是「炫丽」的来源；
## 不投影是因为发光体投影看起来很脏。

## 光带：每根多少个分段（越多越平滑，也越费）
const RIBBON_SEGMENTS := 14
## 能量环：几圈
const RING_COUNT := 3
## 气流线：多少条
const SPEED_LINE_COUNT := 18
## 翼尖光点：脉动速度
const TIP_PULSE_SPEED := 3.2

var _skel: Skeleton3D
var _carrier: Node3D
## 主机体（用来算朝向、绕中心转的环）
var _player: Node3D

var _ribbons: Array = []      ## [{mi, mat, bone}]
var _rings: Array = []        ## [{mi, mat, radius, speed, phase, axis}]
var _speed_lines: Array = []  ## [{mi, mat, dist, angle, height, speed}]
var _tips: Array = []         ## [{mi, mat, bone, phase}]
var _burners: Array = []      ## [{mi, mat, bone}]

var _built := false
var _time := 0.0
## 推力/速度（由 carrier_form 每帧写进来）
var thrust := 0.0
var speed01 := 0.0            ## 0..1 归一化速度
var boosting := false

const WING_TIP_BONES := [
	"bone_wing_LDL_01", "bone_wing_LUL_01", "bone_wing_LUR_01", "bone_wing_LU_01",
	"bone_wing_RDL_01", "bone_wing_RUL_01", "bone_wing_RUR_01", "bone_wing_RU_01",
]
const BOOST_BONES := ["bone_gearboost_L", "bone_gearboost_R"]


## 建全部装饰。`carrier` 是载具节点，`skel` 是它的骨架，`player` 是玩家根。
## 找不到骨头的项**静默跳过**（换模型时不至于崩）。
func build(carrier: Node3D, skel: Skeleton3D, player: Node3D) -> void:
	if _built:
		return
	_carrier = carrier
	_skel = skel
	_player = player
	if _carrier == null:
		return
	_build_ribbons()
	_build_rings()
	_build_speed_lines()
	_build_wing_tips()
	_build_afterburners()
	_built = true
	print("[FX+] 装饰特效就位：光带 %d / 能量环 %d / 气流线 %d / 翼尖 %d / 加力焰 %d" % [
		_ribbons.size(), _rings.size(), _speed_lines.size(), _tips.size(), _burners.size()])


func is_built() -> bool:
	return _built


# ═══════════════════════════════════════════════════════════════
#  材质小工具
# ═══════════════════════════════════════════════════════════════

func _add_mat(c: Color, energy := 4.0, billboard := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = energy
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = false
	return m


## 共享的软圆斑贴图（和 carrier_form 里那张同款，单独建一份免得跨脚本耦合）
static var _dot_tex: ImageTexture = null


func _dot_texture() -> ImageTexture:
	if _dot_tex != null:
		return _dot_tex
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var d := sqrt(u * u + v * v)
			var t := clampf(1.0 - d, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			img.set_pixel(x, y, Color(1, 1, 1, t))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


func _make_dot(size: float, c: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := _add_mat(c, energy, true)
	m.albedo_texture = _dot_texture()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1
	return mi


# ═══════════════════════════════════════════════════════════════
#  ① 等离子光带 —— 推进器后方拖出的流动光带
# ═══════════════════════════════════════════════════════════════
##
## 做法：一根由若干四边形串起来的**带状**网格，挂在推进器骨下、沿 −Y 垂下。
## 每个顶点带 alpha（根部亮、末端透明），并且**每帧用正弦波扰动宽度**，
## 读起来是「火焰在抖动、在拖」，比锥体多一层流动感。
##
## 为什么不用条带粒子：`GPUParticles3D` 的 trails 在 4.7 里配置繁琐且吃性能，
## 而这条带只要 14 段 = 56 个顶点，几乎不花钱。

func _build_ribbons() -> void:
	for bn in BOOST_BONES:
		var bi := _skel.find_bone(bn)
		if bi < 0:
			continue
		var holder := Node3D.new()
		holder.name = "Ribbon_%d" % bi
		_carrier.add_child(holder)

		# 两条：一条宽的淡蓝、一条窄的亮青，交叉一点角度
		for side in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = _make_ribbon_mesh()
			var c := Color(0.30, 0.62, 1.00, 0.42) if side < 0.0 \
				else Color(0.62, 0.92, 1.00, 0.55)
			var m := _add_mat(c, 3.4)
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.layers = 1
			mi.rotation.y = side * 0.55      # 两条错开，形成十字光带
			mi.visible = false
			holder.add_child(mi)
			_ribbons.append({"mi": mi, "mat": m, "bone": bi, "holder": holder, "side": side})


## 一条从原点沿 −Y 落下的带状网格，给每个顶点写 alpha（根部 1 → 末端 0）。
## 长度 1（靠 scale.y 拉长），宽度 1（靠 scale.x 拉宽）。
func _make_ribbon_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := RIBBON_SEGMENTS
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		# 宽度：中间略鼓（喷焰的形状），两端收
		var w0 := 0.5 * (1.0 - t0) * (0.55 + 0.45 * sin(t0 * PI))
		var w1 := 0.5 * (1.0 - t1) * (0.55 + 0.45 * sin(t1 * PI))
		var y0 := -t0
		var y1 := -t1
		# alpha：根部亮、末端透明
		var a0 := 1.0 - t0 * 0.95
		var a1 := 1.0 - t1 * 0.95
		var p00 := Vector3(-w0, y0, 0.0)
		var p10 := Vector3(w0, y0, 0.0)
		var p01 := Vector3(-w1, y1, 0.0)
		var p11 := Vector3(w1, y1, 0.0)
		# 两面都给（CULL_DISABLED 其实一面就够，这里保持简单）
		st.set_color(Color(1, 1, 1, a0))
		st.add_vertex(p00)
		st.set_color(Color(1, 1, 1, a1))
		st.add_vertex(p01)
		st.set_color(Color(1, 1, 1, a1))
		st.add_vertex(p11)
		st.set_color(Color(1, 1, 1, a0))
		st.add_vertex(p00)
		st.set_color(Color(1, 1, 1, a1))
		st.add_vertex(p11)
		st.set_color(Color(1, 1, 1, a0))
		st.add_vertex(p10)
	st.generate_normals()
	return st.commit()


# ═══════════════════════════════════════════════════════════════
#  ② 能量环阵列 —— 环绕机体旋转的发光环
# ═══════════════════════════════════════════════════════════════
##
## 三圈不同半径、不同轴向、不同转速的细环，绕机体中心转。
## 这是最便宜也最见效的「科技感」来源：静止时也能看出这是个高能装置。
##
## ⚠️ 环不挂在骨上、挂在 `_carrier` 下，位置每帧取「机体中心」——
##    挂在骨上会跟着动画抖，看起来像环在抽搐。

func _build_rings() -> void:
	var specs := [
		{"r": 1.05, "speed": 1.9, "axis": Vector3(0, 1, 0), "c": Color(0.40, 0.80, 1.00, 0.40)},
		{"r": 0.82, "speed": -2.7, "axis": Vector3(1, 0, 0.35), "c": Color(0.65, 0.95, 1.00, 0.32)},
		{"r": 1.30, "speed": 1.2, "axis": Vector3(0.2, 0.4, 1), "c": Color(0.30, 0.55, 1.00, 0.26)},
	]
	for i in RING_COUNT:
		var sp: Dictionary = specs[i % specs.size()]
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.985
		torus.outer_radius = 1.0
		torus.rings = 32
		torus.ring_segments = 6
		mi.mesh = torus
		var m := _add_mat(sp["c"], 4.2)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1
		mi.scale = Vector3.ONE * float(sp["r"])
		mi.visible = false
		_carrier.add_child(mi)
		_rings.append({
			"mi": mi, "mat": m,
			"radius": float(sp["r"]),
			"speed": float(sp["speed"]),
			"axis": (sp["axis"] as Vector3).normalized(),
			"phase": float(i) * 2.1,
		})


# ═══════════════════════════════════════════════════════════════
#  ③ 速度气流线 —— 高速时从四周掠过的小光条
# ═══════════════════════════════════════════════════════════════
##
## 一堆细长的小方块，在机体周围的一个圆筒里随机分布，
## 每帧朝**后方**移动，出界就从前方重生 —— 就是「风在往后刮」的感觉。
##
## 只在 `speed01 > 0.45` 时可见（低速飘着也能看到一堆线在飞，很怪）。

func _build_speed_lines() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xBEEF
	for i in SPEED_LINE_COUNT:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.018, 0.018, 1.0)
		mi.mesh = bm
		var m := _add_mat(Color(0.70, 0.92, 1.00, 0.5), 5.0)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1
		mi.visible = false
		_carrier.add_child(mi)
		_speed_lines.append({
			"mi": mi, "mat": m,
			"angles": rng.randf() * TAU,
			"radius": 1.4 + rng.randf() * 2.2,
			"height": rng.randf_range(-0.9, 1.5),
			"dist": rng.randf_range(-14.0, 2.0),
			"len": rng.randf_range(1.2, 3.6),
			"speed": rng.randf_range(18.0, 34.0),
		})


# ═══════════════════════════════════════════════════════════════
#  ④ 翼尖光点 —— 肩翼端点各一个脉动光点
# ═══════════════════════════════════════════════════════════════

func _build_wing_tips() -> void:
	for bn in WING_TIP_BONES:
		var bi := _skel.find_bone(bn)
		if bi < 0:
			continue
		var mi := _make_dot(0.42, Color(0.85, 0.97, 1.00, 0.75), 5.0)
		mi.visible = false
		_carrier.add_child(mi)
		_tips.append({"mi": mi, "bone": bi, "phase": float(_tips.size()) * 0.8})


# ═══════════════════════════════════════════════════════════════
#  ⑤ 加力尾焰 —— 高速时主焰后套一层白色尖焰
# ═══════════════════════════════════════════════════════════════
##
## `carrier_form` 的焰柱是蓝的、偏软。加力时在它**后面**再插一根更长更白的尖焰，
## 读起来就是「推背感」—— 这也是最常见的赛车/飞行游戏做法。

func _build_afterburners() -> void:
	for bn in BOOST_BONES:
		var bi := _skel.find_bone(bn)
		if bi < 0:
			continue
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 1.0
		cm.height = 1.0
		cm.radial_segments = 12
		cm.rings = 1
		mi.mesh = cm
		# CylinderMesh 的尖在 +Y，我们要尖朝 −Y ⇒ 转 180°
		mi.rotation.x = PI
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1
		var m := _add_mat(Color(1.00, 1.00, 1.00, 0.85), 8.0)
		mi.material_override = m
		mi.visible = false
		var holder := Node3D.new()
		holder.name = "Burner_%d" % bi
		_carrier.add_child(holder)
		holder.add_child(mi)
		_burners.append({"mi": mi, "mat": m, "bone": bi, "holder": holder})


# ═══════════════════════════════════════════════════════════════
#  每帧驱动
# ═══════════════════════════════════════════════════════════════

func tick(delta: float) -> void:
	if not _built or _skel == null or _carrier == null:
		return
	_time += delta
	var t := clampf(thrust, 0.0, 1.2)
	# 机体中心（环和气流线都围着它转）
	var center := _carrier.global_position
	if _player != null:
		center = _player.global_position + Vector3.UP * 1.0

	_drive_ribbons(t, delta)
	_drive_rings(t, center)
	_drive_speed_lines(delta)
	_drive_wing_tips(t)
	_drive_burners(t)


func _bone_xform(bi: int) -> Transform3D:
	if bi < 0 or bi >= _skel.get_bone_count():
		return Transform3D.IDENTITY
	return _skel.global_transform * _skel.get_bone_global_pose(bi)


func _drive_ribbons(t: float, _delta: float) -> void:
	for r in _ribbons:
		var mi := r["mi"] as MeshInstance3D
		var m := r["mat"] as StandardMaterial3D
		var bi: int = r["bone"]
		var xf := _bone_xform(bi)
		var holder: Node3D = r["holder"]
		holder.global_transform = Transform3D(xf.basis, xf.origin)
		var on := t > 0.12
		mi.visible = on
		if not on:
			continue
		# 抖动：两条相位相反，读起来是「火在扭」
		var side: float = r["side"]
		var wob := sin(_time * 5.0 + side * 2.2) * 0.18 * t
		mi.rotation.z = wob
		mi.rotation.x = cos(_time * 3.7 + side) * 0.12 * t
		var length := 1.6 * (0.4 + 0.9 * t) * (1.5 if boosting else 1.0)
		mi.scale = Vector3(0.55 * (0.5 + 0.7 * t), length, 1.0)
		m.albedo_color.a = clampf(0.12 + 0.42 * t, 0.0, 1.0) * (1.25 if boosting else 1.0)
		m.emission_energy_multiplier = lerpf(1.2, 4.6, t)


func _drive_rings(t: float, center: Vector3) -> void:
	for r in _rings:
		var mi := r["mi"] as MeshInstance3D
		var m := r["mat"] as StandardMaterial3D
		# 静止也显示 —— 这是「科技感」，不是「喷气」，不该随推力消失
		mi.visible = true
		mi.global_position = center
		var axis: Vector3 = r["axis"]
		var ang := _time * float(r["speed"]) + float(r["phase"])
		# 绕自身 axis 转：先把 axis 转到 −Z，转完再转回去
		var base := Basis.IDENTITY
		if absf(axis.dot(Vector3.UP)) < 0.99:
			var x := Vector3.UP.cross(axis).normalized()
			var z := x.cross(axis).normalized()
			base = Basis(x, axis, z)
		var spin := Basis(axis, ang)
		mi.global_basis = spin * base
		mi.scale = Vector3.ONE * float(r["radius"]) * (1.0 + 0.08 * t)
		# 速度越快越亮（飞行时环会"烧"起来）
		m.albedo_color.a = clampf(0.10 + 0.20 * t + 0.12 * speed01, 0.0, 0.85)
		m.emission_energy_multiplier = lerpf(2.0, 6.5, maxf(t, speed01))


func _drive_speed_lines(delta: float) -> void:
	var on := speed01 > 0.45
	for s in _speed_lines:
		var mi := s["mi"] as MeshInstance3D
		var m := s["mat"] as StandardMaterial3D
		mi.visible = on
		if not on:
			continue
		# 往后飞
		s["dist"] = float(s["dist"]) - float(s["speed"]) * delta * (0.4 + speed01)
		if float(s["dist"]) < -16.0:
			s["dist"] = 2.0
		var back: float = s["dist"]
		var rad: float = s["radius"]
		var ang: float = s["angles"]
		# 相对机体转向的「后方」偏移
		var basis := _carrier.global_transform.basis
		var off := basis.z * back + basis.x * (cos(ang) * rad) \
			+ basis.y * (float(s["height"]) + sin(ang) * rad * 0.3)
		mi.global_position = _carrier.global_position + off
		mi.global_basis = basis
		mi.scale = Vector3(1.0, 1.0, float(s["len"]) * (0.5 + speed01))
		m.albedo_color.a = clampf((0.10 + 0.45 * speed01) * (1.0 - absf(back) / 16.0), 0.0, 1.0)
		m.emission_energy_multiplier = lerpf(2.0, 7.0, speed01)


func _drive_wing_tips(t: float) -> void:
	for tip in _tips:
		var mi := tip["mi"] as MeshInstance3D
		var m := mi.material_override as StandardMaterial3D
		var xf := _bone_xform(int(tip["bone"]))
		mi.global_position = xf.origin
		# 呼吸式脉动，相位每个点不同（不然 8 个点一起闪，像故障）
		var pulse := 0.55 + 0.45 * sin(_time * TIP_PULSE_SPEED + float(tip["phase"]))
		# 飞行时更亮更明显
		var vis := clampf(0.25 + 0.75 * maxf(t, speed01), 0.0, 1.0)
		mi.visible = vis > 0.02
		mi.scale = Vector3.ONE * (0.7 + 0.5 * pulse) * (0.7 + 0.6 * vis)
		m.albedo_color.a = pulse * vis * 0.8
		m.emission_energy_multiplier = lerpf(2.0, 8.0, pulse * vis)


func _drive_burners(t: float) -> void:
	var on := boosting and t > 0.3
	for b in _burners:
		var mi := b["mi"] as MeshInstance3D
		var m := b["mat"] as StandardMaterial3D
		var xf := _bone_xform(int(b["bone"]))
		var holder: Node3D = b["holder"]
		holder.global_transform = Transform3D(xf.basis, xf.origin)
		mi.visible = on
		if not on:
			continue
		# 白色尖焰：又细又长，比主焰还长
		var len := 2.4 * (0.7 + 0.3 * sin(_time * 11.0))
		mi.scale = Vector3(0.055, len, 0.055)
		m.albedo_color.a = 0.55 + 0.35 * sin(_time * 17.0)
		m.emission_energy_multiplier = 7.0 + 3.0 * sin(_time * 13.0)


## 整层开关（调试/低配用）
func set_all_visible(on: bool) -> void:
	visible = on
