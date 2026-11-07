extends SceneTree
## 生成 scenes/esports_room.tscn：东侧地块南边的游戏开发部电竞房。
##   _tools/run_probe.sh res://scripts/_build_esports_room.gd
##
## 房间局部坐标：x ±8.2 / z ±5.0，门在西墙 x=-8.1；游戏场景里整体摆在 (52, 0.01, 13)。
## 东墙 4 个主力位（4 桌 4 屏 4 椅），北墙凯伊 1 桌 1 屏，南墙 8 卡 9995WX 开放架。

const OUT := "res://scenes/esports_room.tscn"
const MONITOR := "res://models/monitor/monitor.glb"
const CARD := "res://models/rtx5090_card/rtx5090_card.glb"
const FONT := "res://assets/ui/gamedev_sign_12px.ttf"
const POSTER_5090 := "res://assets/story/config_sheet_5090.png"
const POSTER_ROOM := "res://assets/story/gamedev_room.jpg"
## 贴图不进 .tscn 的 ext_resource，改成运行时按路径 load()。见 optional_texture.gd。
const OPTIONAL_TEX := preload("res://scripts/optional_texture.gd")
## 壁挂 8×5090 工作站（机箱 + 门边双屏）。2026-11-04 从部室 gamedev_room 搬来的。
const PC_RIG := "res://scenes/pc_wall_case.tscn"


func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m


func _rgb(col: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(Color(0.03, 0.035, 0.045), 0.05, 0.5)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.14, 0.18, 0.18)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.0
	m.metallic_specular = 0.3
	return m


func _box(parent: Node3D, nm: String, pos: Vector3, size: Vector3,
		mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.name = nm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, nm: String, pos: Vector3, radius: float, height: float,
		mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	mi.mesh = cm
	mi.name = nm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _label(parent: Node3D, nm: String, text: String, pos: Vector3, px: float,
		col: Color, rot_y: float = PI) -> Label3D:
	var l := Label3D.new()
	l.name = nm
	l.text = text
	l.font = load(FONT) as FontFile
	l.font_size = 12
	l.pixel_size = px
	l.position = pos
	l.rotation.y = rot_y
	l.modulate = col
	l.outline_size = 0
	l.alpha_cut = 1
	l.alpha_antialiasing_mode = 0
	l.texture_filter = 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _own(n: Node, root_node: Node) -> void:
	for c in n.get_children():
		c.owner = root_node
		if not c.scene_file_path.is_empty():
			continue
		_own(c, root_node)


func _shape(body: StaticBody3D, nm: String, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = nm
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)


func _monitor(root: Node3D, nm: String, pos: Vector3, rot_y: float,
		text: String, px: float) -> Node3D:
	# ⚠️ 显示器模型是爱给网素材、被 .gitignore 挡在仓外：缺文件时**只少这块屏**，
	#    字牌照摆（不然桌上光秃秃更难看），绝不能让 load() 返回 null 直接崩。
	var scene := load(MONITOR) as PackedScene
	var mon: Node3D = null
	if scene != null:
		mon = scene.instantiate() as Node3D
		mon.name = nm
		mon.position = pos
		mon.rotation.y = rot_y
		root.add_child(mon)
	else:
		push_warning("[esports] 没有 %s → 跳过显示器 %s" % [MONITOR, nm])
	# 屏面最前沿在局部 +z≈0.116；字放 0.13，跟着屏幕一起转
	var lx := pos.x + sin(rot_y) * 0.13
	var lz := pos.z + cos(rot_y) * 0.13
	_label(root, nm + "Text", text, Vector3(lx, pos.y + 0.2744, lz), px,
		Color(0.55, 0.90, 1.0, 1.0), rot_y)
	return mon


func _chair(root: Node3D, nm: String, pos: Vector3, rot_y: float,
		accent: Material, black: Material, dark: Material, metal: Material) -> Node3D:
	var c := Node3D.new()
	c.name = nm
	c.position = pos
	c.rotation.y = rot_y
	root.add_child(c)
	_cyl(c, "Lift", Vector3(0, 0.24, 0), 0.030, 0.30, metal)
	_cyl(c, "Hub", Vector3(0, 0.075, 0), 0.050, 0.10, dark)
	for i in 5:
		var ang := TAU * float(i) / 5.0
		var arm := _box(c, "Arm%d" % i,
			Vector3(cos(ang) * 0.13, 0.045, -sin(ang) * 0.13),
			Vector3(0.26, 0.035, 0.05), dark)
		arm.rotation.y = ang
		var caster := _cyl(c, "Caster%d" % i,
			Vector3(cos(ang) * 0.26, 0.030, -sin(ang) * 0.26), 0.026, 0.03, black)
		caster.rotation.z = PI * 0.5
	_box(c, "Seat", Vector3(0, 0.46, 0), Vector3(0.50, 0.10, 0.50), black)
	_box(c, "SeatL", Vector3(0, 0.49, -0.25), Vector3(0.50, 0.12, 0.06), black)
	_box(c, "SeatR", Vector3(0, 0.49, 0.25), Vector3(0.50, 0.12, 0.06), black)
	_box(c, "Back", Vector3(-0.23, 0.86, 0), Vector3(0.12, 0.72, 0.50), black)
	_box(c, "BackL", Vector3(-0.23, 0.90, -0.24), Vector3(0.15, 0.62, 0.06), black)
	_box(c, "BackR", Vector3(-0.23, 0.90, 0.24), Vector3(0.15, 0.62, 0.06), black)
	_box(c, "Headrest", Vector3(-0.25, 1.30, 0), Vector3(0.12, 0.18, 0.30), black)
	_box(c, "AccentBack", Vector3(-0.295, 0.90, 0), Vector3(0.012, 0.58, 0.04), accent)
	_box(c, "AccentSeat", Vector3(0.255, 0.47, 0), Vector3(0.012, 0.04, 0.36), accent)
	for sz in [-1.0, 1.0]:
		_box(c, "ArmPost", Vector3(-0.08, 0.58, sz * 0.30),
			Vector3(0.05, 0.20, 0.05), metal)
		_box(c, "ArmPad", Vector3(0.0, 0.69, sz * 0.30),
			Vector3(0.34, 0.05, 0.08), black)
	return c


func _desk(root: Node3D, nm: String, pos: Vector3, size: Vector3,
		black: Material, metal: Material, accent: Material) -> void:
	_box(root, nm, pos, size, black)
	var sx := size.x
	var sz := size.z
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			_box(root, nm + "Leg", Vector3(pos.x + dx * (sx * 0.5 - 0.05),
				pos.y - size.y * 0.5 - 0.35, pos.z + dz * (sz * 0.5 - 0.05)),
				Vector3(0.05, 0.70, 0.05), metal)
	if sz > sx:
		_box(root, nm + "LED", Vector3(pos.x - sx * 0.5, pos.y - 0.03, pos.z),
			Vector3(0.015, 0.012, sz * 0.94), accent)
	else:
		_box(root, nm + "LED", Vector3(pos.x, pos.y - 0.03, pos.z + sz * 0.5),
			Vector3(sx * 0.94, 0.012, 0.015), accent)


func _poster(root: Node3D, nm: String, pos: Vector3, size: Vector2, rot_y: float,
		tex_path: String, frame: Material) -> void:
	# 框厚 0.03（半厚 0.015）。框中心必须退到海报后面 0.015 以上，
	# 否则框的正面会盖住海报 —— 原来写的是 0.012，正好差 3 mm，
	# 结果两张海报一直是隐形的（2026-11-03 用 _probe_poster_shot.gd 对照查出）。
	_box(root, nm + "Frame", pos - Vector3(0, 0, cos(rot_y) * 0.020),
		Vector3(size.x + 0.10, size.y + 0.10, 0.03), frame)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	q.mesh = qm
	q.name = nm
	q.position = pos
	q.rotation.y = rot_y
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.10, 0.12)
	m.roughness = 0.8
	q.material_override = m
	# 贴图不写进 .tscn 的 ext_resource：有的图不允许随仓库分发（BA 游戏内截图），
	# 硬引用会让「缺图」变成「整个场景加载失败」。改成运行时按路径 load()，
	# 缺图时只是这张海报纯色，场景照常加载。见 scripts/optional_texture.gd。
	q.set_script(OPTIONAL_TEX)
	q.set("texture_path", tex_path)
	q.set("fallback_color", Color(0.10, 0.10, 0.12))
	root.add_child(q)


func _run() -> void:
	var root := Node3D.new()
	root.name = "EsportsRoom"

	var wall := _mat(Color(0.105, 0.120, 0.155), 0.05, 0.82)
	var wall_inner := _mat(Color(0.080, 0.093, 0.120), 0.05, 0.88)
	var floor_mat := _mat(Color(0.045, 0.050, 0.062), 0.0, 0.94)
	var ceil_mat := _mat(Color(0.028, 0.032, 0.042), 0.0, 0.96)
	var black := _mat(Color(0.022, 0.024, 0.030), 0.25, 0.45)
	var dark := _mat(Color(0.060, 0.070, 0.090), 0.30, 0.55)
	var metal := _mat(Color(0.34, 0.36, 0.41), 0.80, 0.30)
	var acoustic := _mat(Color(0.130, 0.150, 0.190), 0.0, 0.95)
	var cyan := _rgb(Color(0.10, 0.80, 1.0), 2.0)
	var magenta := _rgb(Color(1.0, 0.16, 0.62), 2.0)
	var white_glow := _rgb(Color(0.82, 0.91, 1.0), 1.5)
	var sign_mat := _mat(Color(0.04, 0.10, 0.28), 0.2, 0.45)
	sign_mat.emission_enabled = true
	sign_mat.emission = Color(0.04, 0.18, 0.50)
	sign_mat.emission_energy_multiplier = 0.7
	var pcb := _mat(Color(0.020, 0.075, 0.050), 0.35, 0.55)
	var ihs := _mat(Color(0.72, 0.74, 0.78), 0.90, 0.22)
	var ram_mat := _mat(Color(0.030, 0.050, 0.040), 0.30, 0.55)
	var glass := _glass()

	# ── 外壳 ──
	_box(root, "Floor", Vector3(0, -0.10, 0), Vector3(16.4, 0.20, 10.0), floor_mat)
	_box(root, "Ceiling", Vector3(0, 3.30, 0), Vector3(16.4, 0.20, 10.0), ceil_mat)
	_box(root, "WallEast", Vector3(8.1, 1.6, 0), Vector3(0.2, 3.2, 10.0), wall_inner)
	_box(root, "WallNorth", Vector3(0, 1.6, -4.9), Vector3(16.4, 3.2, 0.2), wall_inner)
	_box(root, "WallSouth", Vector3(0, 1.6, 4.9), Vector3(16.4, 3.2, 0.2), wall_inner)
	# 西墙：门洞 z ±1.0，两扇窗 z -3.4..-1.8 / 1.8..3.4
	for zc in [-2.9, 2.9]:
		_box(root, "WallWestLow", Vector3(-8.1, 0.45, zc), Vector3(0.2, 0.9, 3.8), wall)
	for zc in [-4.1, -1.4, 1.4, 4.1]:
		var wlen := 1.4 if absf(zc) > 2.0 else 0.8
		_box(root, "WallWestMid", Vector3(-8.1, 1.65, zc), Vector3(0.2, 1.5, wlen), wall)
	_box(root, "WallWestTop", Vector3(-8.1, 2.8, 0), Vector3(0.2, 0.8, 9.6), wall)
	for zc in [-2.6, 2.6]:
		_box(root, "WindowGlass", Vector3(-8.1, 1.65, zc), Vector3(0.02, 1.5, 1.6), glass)
		_box(root, "WindowTop", Vector3(-8.1, 2.42, zc), Vector3(0.24, 0.06, 1.72), black)
		_box(root, "WindowBot", Vector3(-8.1, 0.88, zc), Vector3(0.24, 0.06, 1.72), black)
		for ze in [-0.83, 0.83]:
			_box(root, "WindowSide", Vector3(-8.1, 1.65, zc + ze),
				Vector3(0.24, 1.5, 0.06), black)
	# 门框
	for ze in [-1.04, 1.04]:
		_box(root, "DoorFrameSide", Vector3(-8.06, 1.2, ze),
			Vector3(0.10, 2.4, 0.08), black)
	_box(root, "DoorFrameTop", Vector3(-8.06, 2.44, 0), Vector3(0.10, 0.08, 2.16), black)
	_box(root, "DoorMat", Vector3(-7.9, 0.012, 0), Vector3(0.5, 0.01, 1.6), dark)

	# 外用招牌
	_box(root, "EsportsSignBoard", Vector3(-8.3, 2.8, 0), Vector3(0.08, 0.7, 3.6), sign_mat)
	_label(root, "EsportsSign", "游戏开发部  电竞房", Vector3(-8.35, 2.8, 0),
		0.032, Color(0.72, 0.94, 1.0, 1.0), -PI * 0.5)

	# ── 灯光/吊顶 ──
	for p in [Vector3(-3.5, 2.9, -2.2), Vector3(3.5, 2.9, -2.2),
			Vector3(-3.5, 2.9, 2.2), Vector3(3.5, 2.9, 2.2)]:
		var l := OmniLight3D.new()
		l.position = p
		l.light_color = Color(0.72, 0.86, 1.0)
		l.light_energy = 1.15
		l.omni_range = 8.0
		l.shadow_enabled = false
		root.add_child(l)
	for p in [Vector3(-3.5, 3.17, -2.2), Vector3(3.5, 3.17, -2.2),
			Vector3(-3.5, 3.17, 2.2), Vector3(3.5, 3.17, 2.2)]:
		_box(root, "CeilPanel", p, Vector3(2.2, 0.03, 1.0), white_glow)
	var magenta_light := OmniLight3D.new()
	magenta_light.position = Vector3(-1.0, 2.35, -3.5)
	magenta_light.light_color = Color(1.0, 0.18, 0.62)
	magenta_light.light_energy = 0.55
	magenta_light.omni_range = 4.0
	magenta_light.shadow_enabled = false
	root.add_child(magenta_light)
	var cyan_light := OmniLight3D.new()
	cyan_light.position = Vector3(-3.6, 2.2, 3.9)
	cyan_light.light_color = Color(0.10, 0.78, 1.0)
	cyan_light.light_energy = 0.7
	cyan_light.omni_range = 4.5
	cyan_light.shadow_enabled = false
	root.add_child(cyan_light)

	# ── 地毯 + LED 边 ──
	_box(root, "RugEdge", Vector3(0, 0.004, 0.3), Vector3(8.4, 0.006, 6.4), cyan)
	_box(root, "Rug", Vector3(0, 0.008, 0.3), Vector3(8.2, 0.006, 6.2), black)

	# ── 墙面吸音板 / 灯带 ──
	for i in 8:
		var zc := -3.6 + 1.0 * float(i)
		_box(root, "AcousticE%d" % i, Vector3(7.97, 2.05, zc),
			Vector3(0.04, 1.25, 0.55), acoustic)
	for i in 6:
		var xc := -5.5 + 2.2 * float(i)
		_box(root, "AcousticN%d" % i, Vector3(xc, 1.95, -4.78),
			Vector3(0.55, 1.2, 0.04), acoustic)
	var neon := _box(root, "NeonBoard", Vector3(7.97, 2.70, 0),
		Vector3(0.05, 0.5, 2.0), black)
	neon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label(root, "NeonText", "电竞房", Vector3(7.92, 2.70, 0), 0.020,
		Color(0.35, 0.95, 1.0, 1.0), -PI * 0.5)
	_box(root, "StripE", Vector3(7.99, 3.02, 0), Vector3(0.02, 0.03, 9.4), cyan)
	_box(root, "StripN", Vector3(0, 3.02, -4.79), Vector3(15.4, 0.03, 0.02), cyan)
	_box(root, "StripS", Vector3(0, 3.02, 4.79), Vector3(15.4, 0.03, 0.02), magenta)

	# ── 东墙 4 个主力位 ──
	_desk(root, "MainDesk", Vector3(7.2, 0.725, 0), Vector3(0.75, 0.05, 5.8),
		black, metal, cyan)
	for i in 4:
		var zc := -2.1 + 1.4 * float(i)
		_monitor(root, "Monitor%d" % i, Vector3(7.25, 0.75, zc), -PI * 0.5,
			"8x5090\n工作站", 0.0036)
		_box(root, "Keypad%d" % i, Vector3(7.15, 0.762, zc),
			Vector3(0.16, 0.018, 0.44), black)
		_box(root, "KeyGlow%d" % i, Vector3(7.065, 0.752, zc),
			Vector3(0.006, 0.006, 0.38), cyan)
		_box(root, "MousePad%d" % i, Vector3(7.00, 0.753, zc + 0.30),
			Vector3(0.28, 0.004, 0.62), dark)
		_box(root, "Mouse%d" % i, Vector3(7.02, 0.766, zc + 0.38),
			Vector3(0.06, 0.024, 0.10), black)
		_box(root, "HeadsetStand%d" % i, Vector3(7.42, 0.87, zc - 0.48),
			Vector3(0.05, 0.24, 0.05), metal)
		_box(root, "Headset%d" % i, Vector3(7.38, 1.00, zc - 0.48),
			Vector3(0.16, 0.04, 0.10), black)
		_chair(root, "Chair%d" % i, Vector3(6.0, 0.0, zc), 0.0,
			cyan, black, dark, metal)

	# ── 北墙凯伊位 ──
	_desk(root, "KeiDesk", Vector3(-1.0, 0.725, -4.35), Vector3(2.2, 0.05, 0.75),
		black, metal, magenta)
	_monitor(root, "Monitor4", Vector3(-1.0, 0.75, -4.35), 0.0,
		"8x5090\n工作站", 0.0036)
	_box(root, "KeiKeypad", Vector3(-1.0, 0.762, -4.10),
		Vector3(0.44, 0.018, 0.16), black)
	_box(root, "KeiKeyGlow", Vector3(-1.0, 0.752, -4.175),
		Vector3(0.38, 0.006, 0.006), magenta)
	_box(root, "KeiMousePad", Vector3(-0.55, 0.753, -4.02),
		Vector3(0.50, 0.004, 0.30), dark)
	_box(root, "KeiMouse", Vector3(-0.55, 0.766, -4.0),
		Vector3(0.06, 0.024, 0.10), black)
	_box(root, "KeiNameBoard", Vector3(-1.0, 0.80, -3.95),
		Vector3(0.62, 0.16, 0.02), black)
	_label(root, "KeiName", "凯伊", Vector3(-1.0, 0.81, -3.935), 0.005,
		Color(1.0, 0.55, 0.85, 1.0), 0.0)
	_cyl(root, "KeiMicStand", Vector3(-0.25, 0.86, -4.5), 0.025, 0.22, metal)
	var mic_arm := _box(root, "KeiMicArm", Vector3(-0.12, 1.02, -4.35),
		Vector3(0.30, 0.025, 0.025), dark)
	mic_arm.rotation.y = -0.5
	_box(root, "KeiMic", Vector3(0.02, 1.08, -4.25), Vector3(0.05, 0.06, 0.05), black)
	_box(root, "KeiMug", Vector3(-1.7, 0.80, -4.15), Vector3(0.08, 0.10, 0.08),
		_mat(Color(0.8, 0.85, 0.9, 1), 0.1, 0.4))
	_chair(root, "KeiChair", Vector3(-1.0, 0.0, -3.35), -PI * 0.5,
		magenta, black, dark, metal)

	# ── 南墙 8 卡 9995WX 开放架 ──
	_desk(root, "FrameTable", Vector3(-3.6, 0.725, 4.35), Vector3(2.6, 0.05, 0.75),
		black, metal, cyan)
	_box(root, "FrameBack", Vector3(-3.6, 1.25, 4.46), Vector3(2.0, 1.0, 0.02), black)
	for xc in [-4.6, -2.6]:
		for zc in [4.05, 4.45]:
			_box(root, "FramePost", Vector3(xc, 1.25, zc), Vector3(0.04, 1.0, 0.04), black)
	_box(root, "FrameTopBeam", Vector3(-3.6, 1.75, 4.45), Vector3(2.0, 0.04, 0.04), black)
	_box(root, "FrameBotBeam", Vector3(-3.6, 0.77, 4.45), Vector3(2.0, 0.04, 0.04), black)
	var card_scene := load(CARD) as PackedScene
	if card_scene == null:
		# 显卡模型被 .gitignore 挡在仓外：缺文件时只少卡、框架和灯带照留
		push_warning("[esports] 没有 %s → 开放架上不摆显卡" % CARD)
	for i in 8:
		var col := i % 2
		var row := i / 2
		var p := Vector3(-4.05 + 0.42 * float(col), 0.95 + 0.21 * float(row), 4.20)
		if card_scene != null:
			var card := card_scene.instantiate() as Node3D
			card.name = "GPU%d" % i
			card.position = p
			root.add_child(card)
		_box(root, "GPU%dGlow" % i, p + Vector3(0, -0.092, -0.03),
			Vector3(0.36, 0.006, 0.006), cyan if i % 2 == 0 else magenta)
	# 4 个 120 mm 风扇（框架右侧）
	for i in 4:
		var yc := 0.98 + 0.19 * float(i)
		var ring := _cyl(root, "CaseFan%d" % i, Vector3(-2.72, yc, 4.28),
			0.06, 0.025, dark)
		ring.rotation.x = PI * 0.5
		var blade := _box(root, "CaseFanBlade%d" % i, Vector3(-2.72, yc, 4.30),
			Vector3(0.10, 0.012, 0.012), black)
		blade.rotation.z = 0.5 + float(i) * 0.4
	# 主板 / 9995WX / DDR5 ECC / 电源
	_box(root, "Mainboard", Vector3(-3.05, 1.22, 4.36), Vector3(0.50, 0.55, 0.02), pcb)
	_box(root, "CPU", Vector3(-2.95, 1.36, 4.33), Vector3(0.070, 0.055, 0.010), ihs)
	_box(root, "CPUCooler", Vector3(-2.95, 1.42, 4.31), Vector3(0.13, 0.10, 0.055),
		_mat(Color(0.05, 0.055, 0.07), 0.7, 0.35))
	_label(root, "CPUText", "9995WX", Vector3(-2.95, 1.42, 4.278), 0.0015,
		Color(0.92, 0.96, 1.0, 1.0), PI)
	for i in 8:
		var xc := -3.30 + 0.031 * float(i)
		_box(root, "RAM%d" % i, Vector3(xc, 1.01, 4.345),
			Vector3(0.030, 0.133, 0.012), ram_mat)
		_box(root, "RAMLed%d" % i, Vector3(xc, 1.085, 4.338),
			Vector3(0.024, 0.012, 0.004), cyan)
	_label(root, "RAMText", "DDR5 ECC", Vector3(-3.19, 0.93, 4.338), 0.0014,
		Color(0.62, 0.95, 1.0, 1.0), PI)
	for i in 2:
		var xc := -3.10 + 0.20 * float(i)
		_box(root, "PSU%d" % i, Vector3(xc, 0.793, 4.30),
			Vector3(0.15, 0.086, 0.18), black)
		_label(root, "PSUText%d" % i, "2000W", Vector3(xc, 0.81, 4.205), 0.0018,
			Color(0.92, 0.96, 1.0, 1.0), PI)
	_box(root, "FrameSignBoard", Vector3(-3.6, 2.05, 4.78), Vector3(1.9, 0.32, 0.02), black)
	_label(root, "FrameSign", "9995WX + 8x5090", Vector3(-3.6, 2.05, 4.765), 0.006,
		Color(0.55, 0.92, 1.0, 1.0), PI)

	# ── 海报 / 沙发 ──
	_poster(root, "Poster5090", Vector3(1.5, 1.72, 4.77), Vector2(1.40, 0.85), PI,
		POSTER_5090, black)
	_poster(root, "PosterRoom", Vector3(1.8, 1.82, -4.77), Vector2(1.10, 0.62), 0.0,
		POSTER_ROOM, black)
	_box(root, "CouchSeat", Vector3(-7.40, 0.42, 3.3), Vector3(0.75, 0.18, 1.8), dark)
	_box(root, "CouchBack", Vector3(-7.72, 0.75, 3.3), Vector3(0.22, 0.75, 1.8), dark)
	_box(root, "CouchL", Vector3(-7.55, 0.55, 2.45), Vector3(0.55, 0.45, 0.20), dark)
	_box(root, "CouchR", Vector3(-7.55, 0.55, 4.15), Vector3(0.55, 0.45, 0.20), dark)
	_box(root, "CouchTrim", Vector3(-7.40, 0.52, 3.3), Vector3(0.76, 0.012, 1.7), cyan)
	_box(root, "CoffeeTable", Vector3(-6.55, 0.36, 3.3), Vector3(0.75, 0.05, 0.55), black)
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			_box(root, "CoffeeLeg", Vector3(-6.55 + dx * 0.30, 0.17, 3.3 + dz * 0.20),
				Vector3(0.04, 0.34, 0.04), metal)

	# ── 壁挂 8×5090 工作站（2026-11-04 从部室搬过来）──
	# 北墙 x≈3.2 这段是空的：凯伊桌占到 x≈1.1、门口海报在 x=1.8、东墙主桌在 x≈7.2。
	# 整套（机箱 + 门边双屏托架）宽约 3.36 m、深 0.66 m，背面贴北墙内表面 z=-4.80，
	# 玻璃朝房间（局部 -z 是前脸，所以绕 Y 转 180°）。
	# 它自带 body / Collision / CollisionMonitor，不用再给 RoomBody 加盒子。
	var rig_scene := load(PC_RIG) as PackedScene
	if rig_scene != null:
		var rig := rig_scene.instantiate() as Node3D
		rig.name = "PC5090Rig"
		rig.position = Vector3(3.22, 0.94, -4.53)
		rig.rotation.y = PI
		root.add_child(rig)
	else:
		push_warning("[esports] 没有 %s → 跳过 5090 工作站" % PC_RIG)

	# ── 碰撞 ──
	var body := StaticBody3D.new()
	body.name = "RoomBody"
	body.collision_layer = 1
	body.collision_mask = 1
	root.add_child(body)
	_shape(body, "Floor", Vector3(0, -0.10, 0), Vector3(16.4, 0.20, 10.0))
	_shape(body, "Ceiling", Vector3(0, 3.30, 0), Vector3(16.4, 0.20, 10.0))
	_shape(body, "East", Vector3(8.1, 1.6, 0), Vector3(0.2, 3.2, 10.0))
	_shape(body, "North", Vector3(0, 1.6, -4.9), Vector3(16.4, 3.2, 0.2))
	_shape(body, "South", Vector3(0, 1.6, 4.9), Vector3(16.4, 3.2, 0.2))
	_shape(body, "WestL", Vector3(-8.1, 1.6, -2.9), Vector3(0.2, 3.2, 3.8))
	_shape(body, "WestR", Vector3(-8.1, 1.6, 2.9), Vector3(0.2, 3.2, 3.8))
	_shape(body, "WestTop", Vector3(-8.1, 2.8, 0), Vector3(0.2, 0.8, 2.0))
	_shape(body, "MainDesk", Vector3(7.2, 0.38, 0), Vector3(0.75, 0.75, 5.8))
	for i in 4:
		_shape(body, "Chair%d" % i, Vector3(6.0, 0.65, -2.1 + 1.4 * float(i)),
			Vector3(0.65, 1.30, 0.65))
	_shape(body, "KeiDesk", Vector3(-1.0, 0.38, -4.35), Vector3(2.2, 0.75, 0.75))
	_shape(body, "KeiChair", Vector3(-1.0, 0.65, -3.35), Vector3(0.65, 1.30, 0.65))
	_shape(body, "FrameTable", Vector3(-3.6, 0.38, 4.35), Vector3(2.6, 0.75, 0.75))
	_shape(body, "Frame", Vector3(-3.6, 1.28, 4.25), Vector3(2.0, 1.05, 0.45))
	_shape(body, "Couch", Vector3(-7.45, 0.55, 3.3), Vector3(0.95, 1.1, 1.9))
	_shape(body, "CoffeeTable", Vector3(-6.55, 0.20, 3.3), Vector3(0.75, 0.40, 0.55))

	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		print("[esports] pack failed ", err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT)
	print("[esports] saved ", OUT, " err=", err)
	quit(0)


func _initialize() -> void:
	_run.call_deferred()
