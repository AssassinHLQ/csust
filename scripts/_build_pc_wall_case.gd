extends SceneTree
## 生成 scenes/pc_wall_case.tscn：白色机箱放大 2.6× 挂墙，内装 8×5090。
##   _tools/run_probe.sh res://scripts/_build_pc_wall_case.gd

const OUT := "res://scenes/pc_wall_case.tscn"
const SHELL := "res://models/pc_case/pc_case_shell.glb"
const CARD := "res://models/rtx5090_card/rtx5090_card.glb"
const MONITOR := "res://models/monitor/monitor.glb"
const FONT := "res://assets/ui/gamedev_sign_12px.ttf"
const SCALE := 2.6
const MON_X := -1.68


func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m


func _rgb(col: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(Color(0.08, 0.08, 0.09), 0.1, 0.5)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.16, 0.20, 0.14)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.22
	m.metallic = 0.0
	m.metallic_specular = 0.25
	return m


func _box(parent: Node3D, nm: String, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
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


func _fan(parent: Node3D, nm: String, pos: Vector3, silver: Material, black: Material) -> Node3D:
	var root := Node3D.new()
	root.name = nm
	root.position = pos
	root.rotation = Vector3(-PI * 0.5, 0, 0)
	parent.add_child(root)
	var c := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.050
	cm.bottom_radius = 0.050
	cm.height = 0.010
	cm.radial_segments = 20
	c.mesh = cm
	c.material_override = silver
	root.add_child(c)
	var blade := _box(root, "Blade", Vector3(0, 0.007, 0), Vector3(0.082, 0.005, 0.020), black)
	blade.rotation.y = 0.5
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.012
	hm.bottom_radius = 0.012
	hm.height = 0.016
	hub.mesh = hm
	hub.material_override = black
	hub.position = Vector3(0, 0.010, 0)
	root.add_child(hub)
	return root


func _label(parent: Node3D, nm: String, text: String, pos: Vector3, px: float,
		col: Color) -> Label3D:
	var l := Label3D.new()
	l.name = nm
	l.text = text
	l.font = load(FONT) as FontFile
	l.font_size = 12
	l.pixel_size = px
	l.position = pos
	l.rotation.y = PI
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
		# 实例化场景（外壳 / 显卡 / 显示器）只存引用，别把网格复制进 .tscn
		if not c.scene_file_path.is_empty():
			continue
		_own(c, root_node)


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "PC5090Rig"
	root.set_script(load("res://scripts/pc_rig.gd"))
	root.add_to_group("pc_rig", true)

	var white := _mat(Color(0.88, 0.90, 0.92), 0.32, 0.33)
	var black := _mat(Color(0.045, 0.048, 0.055), 0.55, 0.42)
	var dark := _mat(Color(0.022, 0.026, 0.032), 0.2, 0.55)
	var liner := _mat(Color(0.035, 0.040, 0.048), 0.15, 0.62)
	var silver := _mat(Color(0.62, 0.64, 0.67), 0.85, 0.28)
	var pcb := _mat(Color(0.035, 0.065, 0.055), 0.15, 0.6)
	var cyan := _rgb(Color(0.10, 0.85, 1.0), 1.8)
	var magenta := _rgb(Color(1.0, 0.18, 0.55), 1.6)
	var cream := Color(0.95, 0.93, 0.86, 1.0)

	# 机箱外壳：GLB 已按 0.1 比例居中，放大 2.6×，底面落在 y=0
	var shell_scene := load(SHELL) as PackedScene
	var shell := shell_scene.instantiate() as Node3D
	shell.name = "Shell"
	shell.position = Vector3(0, 0.6102, 0)
	shell.rotation.y = PI
	shell.scale = Vector3(SCALE, SCALE, SCALE)
	root.add_child(shell)
	for mi in shell.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = white

	# 内衬（背面 + 顶 + 底 + 两侧），挡住外壳背面的背面剔除
	_box(root, "LinerBack", Vector3(0, 0.61, 0.270), Vector3(1.22, 1.20, 0.02), liner)
	_box(root, "LinerTop", Vector3(0, 1.200, 0.0), Vector3(1.22, 0.02, 0.54), liner)
	_box(root, "LinerBottom", Vector3(0, 0.020, 0.0), Vector3(1.22, 0.02, 0.54), liner)
	_box(root, "LinerLeft", Vector3(-0.600, 0.61, 0.0), Vector3(0.02, 1.20, 0.54), liner)
	_box(root, "LinerRight", Vector3(0.600, 0.61, 0.0), Vector3(0.02, 1.20, 0.54), liner)

	# 背板 / 8 卡背板
	_box(root, "Backplane", Vector3(0, 0.60, -0.05), Vector3(1.12, 1.04, 0.02), pcb)

	# 8 张 5090：跑酷终点同款低模副本，长边 40 cm、风扇朝玻璃
	var fans := Node3D.new()
	fans.name = "Fans"
	root.add_child(fans)
	var card_scene := load(CARD) as PackedScene
	for i in 8:
		var col := i % 2
		var row := i / 2
		var p := Vector3(-0.22 + 0.44 * float(col), 0.24 + 0.21 * float(row), -0.12)
		var card := card_scene.instantiate() as Node3D
		card.name = "GPU%d" % i
		card.position = p
		card.rotation.y = PI
		root.add_child(card)
		_box(root, "GPU%d_Glow" % i, p + Vector3(0, 0.0904, -0.029),
			Vector3(0.36, 0.006, 0.006), cyan if i % 2 == 0 else magenta)

	# 电源仓（给四层卡让位，压矮）
	_box(root, "PSU", Vector3(0.33, 0.07, 0.0), Vector3(0.34, 0.12, 0.28), dark)
	_label(root, "PSUText", "1600", Vector3(0.33, 0.07, -0.143), 0.006, cream)

	# 顶部铭牌（柜内，卡片上方的窄条）
	_box(root, "Plate", Vector3(0, 1.06, -0.15), Vector3(1.08, 0.14, 0.02), black)
	_box(root, "PlateTrim", Vector3(0, 0.983, -0.164), Vector3(1.08, 0.008, 0.004), cyan)
	_label(root, "PlateText", "8x5090 工作站", Vector3(0, 1.06, -0.162), 0.0055, cream)

	# 显示器：门边到机箱之间的空墙，2×2 四屏（屏总高 0.463 m，排距 0.56）
	var mon_scene := load(MONITOR) as PackedScene
	const MON_ROW := 0.56
	for row in 2:
		for col in 2:
			var i := row * 2 + col
			var mon := mon_scene.instantiate() as Node3D
			mon.name = "Monitor%d" % i
			mon.position = Vector3(MON_X - 0.45 + 0.90 * float(col),
				MON_ROW * float(row), 0.0)
			mon.rotation.y = PI
			root.add_child(mon)
			# 曲面屏最前沿 z≈-0.116，字必须再往前，否则看到背面反字
			_label(root, "MonitorText%d" % i, "8x5090\n工作站",
				Vector3(mon.position.x, mon.position.y + 0.2744, -0.13), 0.0042,
				Color(0.55, 0.90, 1.0, 1.0))
	for row in 2:
		var sy := MON_ROW * float(row) - 0.02
		_box(root, "MonShelf%d" % row, Vector3(MON_X, sy, 0.085),
			Vector3(1.95, 0.04, 0.45), black)
		_box(root, "MonShelfLED%d" % row, Vector3(MON_X, sy + 0.018, -0.141),
			Vector3(1.80, 0.006, 0.006), cyan)
		_box(root, "MonWallPlate%d" % row, Vector3(MON_X, sy - 0.12, 0.30),
			Vector3(1.92, 0.10, 0.02), black)
		for sx in [-1.0, 1.0]:
			_box(root, "MonBracketV%d" % row, Vector3(MON_X + sx * 0.80, sy - 0.16, 0.30),
				Vector3(0.06, 0.30, 0.03), black)
			_box(root, "MonBracketH%d" % row, Vector3(MON_X + sx * 0.80, sy - 0.02, 0.10),
				Vector3(0.06, 0.04, 0.40), black)
			var mon_strut := _box(root, "MonBracketD%d" % row,
				Vector3(MON_X + sx * 0.80, sy - 0.175, 0.12),
				Vector3(0.04, 0.44, 0.04), black)
			mon_strut.rotation.x = -0.90

	# 前脸细节：三个黑色硬盘位（机箱正面朝向墙的右侧）
	for i in 3:
		_box(root, "Bay%d" % i, Vector3(-0.617, 0.38 + 0.15 * float(i), 0.02),
			Vector3(0.006, 0.10, 0.30), dark)

	# 玻璃 + 黑框
	var glass := _box(root, "Glass", Vector3(0, 0.61, -0.295),
		Vector3(1.09, 1.078, 0.006), _glass())
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(root, "FrameTop", Vector3(0, 1.167, -0.305), Vector3(1.24, 0.05, 0.04), white)
	_box(root, "FrameBottom", Vector3(0, 0.052, -0.305), Vector3(1.24, 0.05, 0.04), white)
	_box(root, "FrameLeft", Vector3(-0.564, 0.61, -0.305), Vector3(0.05, 1.165, 0.04), white)
	_box(root, "FrameRight", Vector3(0.564, 0.61, -0.305), Vector3(0.05, 1.165, 0.04), white)

	# 墙托板 + 支架
	_box(root, "Shelf", Vector3(0, -0.020, 0.0), Vector3(1.40, 0.04, 0.62), black)
	_box(root, "ShelfLED", Vector3(0, -0.002, -0.311), Vector3(1.30, 0.006, 0.006), cyan)
	_box(root, "WallPlate", Vector3(0, -0.14, 0.30), Vector3(1.36, 0.10, 0.02), black)
	for sx in [-1.0, 1.0]:
		_box(root, "BracketV", Vector3(sx * 0.55, -0.18, 0.30),
			Vector3(0.06, 0.30, 0.03), black)
		_box(root, "BracketH", Vector3(sx * 0.55, -0.04, 0.04),
			Vector3(0.06, 0.04, 0.52), black)
		var strut := _box(root, "BracketD", Vector3(sx * 0.55, -0.195, 0.06),
			Vector3(0.04, 0.53, 0.04), black)
		strut.rotation.x = -1.036
		var bolt := _cyl(root, "Bolt" + ("L" if sx < 0 else "R"),
			Vector3(sx * 0.55, -0.105, 0.285), 0.012, 0.02, silver)
		bolt.rotation.x = PI * 0.5

	# 交互提示 / 开机状态
	var hint := _label(root, "Hint", "按F开机", Vector3(0, 1.31, -0.30), 0.0095, cream)
	hint.visible = false
	var status := _label(root, "Status", "已开机", Vector3(0, 1.31, -0.30), 0.011,
		Color(0.45, 1.0, 0.7, 1.0))
	status.visible = false

	# 碰撞
	var body := StaticBody3D.new()
	body.name = "Body"
	body.position = Vector3(0, 0.62, 0)
	body.collision_layer = 1
	body.collision_mask = 1
	root.add_child(body)
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.40, 1.28, 0.66)
	cs.shape = bs
	body.add_child(cs)
	var mcs := CollisionShape3D.new()
	mcs.name = "CollisionMonitor"
	var mbs := BoxShape3D.new()
	mbs.size = Vector3(1.95, 1.28, 0.45)
	mcs.shape = mbs
	mcs.position = Vector3(MON_X, 0, 0)
	body.add_child(mcs)

	# 开机灯
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, 0.60, -0.05)
	light.light_color = Color(0.2, 0.9, 1.0, 1.0)
	light.light_energy = 0.0
	light.omni_range = 2.4
	light.shadow_enabled = false
	root.add_child(light)

	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		print("[wall] pack failed ", err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT)
	print("[wall] saved ", OUT, " err=", err)
	root.queue_free()
	quit(0)
