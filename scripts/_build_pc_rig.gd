extends SceneTree
## 生成 scenes/pc_5090_rig.tscn：八卡 5090 开放机架（编辑器可拖、可改）。
##   _tools/run_probe.sh res://scripts/_build_pc_rig.gd

const OUT := "res://scenes/pc_5090_rig.tscn"
const FONT := "res://assets/ui/gamedev_sign_12px.ttf"


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


func _fan(parent: Node3D, nm: String, pos: Vector3, silver: Material, black: Material) -> Node3D:
	var root := Node3D.new()
	root.name = nm
	root.position = pos
	root.rotation = Vector3(-PI * 0.5, 0, 0)
	parent.add_child(root)
	var c := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.055
	cm.bottom_radius = 0.055
	cm.height = 0.012
	cm.radial_segments = 20
	c.mesh = cm
	c.material_override = silver
	root.add_child(c)
	var blade := _box(root, "Blade", Vector3(0, 0.008, 0), Vector3(0.092, 0.006, 0.022), black)
	blade.rotation.y = 0.5
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.014
	hm.bottom_radius = 0.014
	hm.height = 0.018
	hub.mesh = hm
	hub.material_override = black
	hub.position = Vector3(0, 0.012, 0)
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
	parent.add_child(l)
	return l


func _own(n: Node, root_node: Node) -> void:
	for c in n.get_children():
		c.owner = root_node
		_own(c, root_node)


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "PC5090Rig"
	root.set_script(load("res://scripts/pc_rig.gd"))
	root.add_to_group("pc_rig", true)

	var black := _mat(Color(0.045, 0.048, 0.055), 0.55, 0.42)
	var dark := _mat(Color(0.025, 0.03, 0.035), 0.2, 0.55)
	var silver := _mat(Color(0.62, 0.64, 0.67), 0.85, 0.28)
	var pcb := _mat(Color(0.04, 0.07, 0.06), 0.15, 0.6)
	var cyan := _rgb(Color(0.1, 0.85, 1.0), 1.6)
	var magenta := _rgb(Color(1.0, 0.18, 0.55), 1.4)
	var cream := Color(0.95, 0.93, 0.86, 1.0)

	# 机架
	_box(root, "Base", Vector3(0, 0.025, 0), Vector3(1.22, 0.05, 0.66), black)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(root, "Post", Vector3(sx * 0.57, 0.75, sz * 0.30),
				Vector3(0.04, 1.45, 0.04), black)
	_box(root, "RailFrontTop", Vector3(0, 1.465, -0.30), Vector3(1.22, 0.04, 0.04), black)
	_box(root, "RailBackTop", Vector3(0, 1.465, 0.30), Vector3(1.22, 0.04, 0.04), black)
	for sx in [-1.0, 1.0]:
		_box(root, "RailSide", Vector3(sx * 0.57, 1.465, 0), Vector3(0.04, 0.04, 0.62), black)
	_box(root, "PSU", Vector3(0.36, 0.17, 0.05), Vector3(0.30, 0.22, 0.42), dark)
	_box(root, "Motherboard", Vector3(-0.20, 0.14, 0.08), Vector3(0.52, 0.03, 0.42), pcb)
	_box(root, "Riser", Vector3(0, 0.10, 0.02), Vector3(0.9, 0.02, 0.12), dark)

	# 8 张 5090：两列 × 四层
	var fans := Node3D.new()
	fans.name = "Fans"
	root.add_child(fans)
	var cards := [
		Vector3(-0.27, 0.40, 0), Vector3(0.27, 0.40, 0),
		Vector3(-0.27, 0.66, 0), Vector3(0.27, 0.66, 0),
		Vector3(-0.27, 0.92, 0), Vector3(0.27, 0.92, 0),
		Vector3(-0.27, 1.18, 0), Vector3(0.27, 1.18, 0),
	]
	for i in cards.size():
		var p: Vector3 = cards[i]
		_box(root, "GPU%d" % i, p, Vector3(0.46, 0.075, 0.26), black)
		_box(root, "GPU%d_Shroud" % i, p + Vector3(0, 0, -0.128),
			Vector3(0.44, 0.07, 0.015), dark)
		_box(root, "GPU%d_Glow" % i, p + Vector3(0, 0.045, -0.132),
			Vector3(0.40, 0.006, 0.008), cyan if i % 2 == 0 else magenta)
		_fan(fans, "Fan%d_A" % i, p + Vector3(-0.10, 0, -0.145), silver, black)
		_fan(fans, "Fan%d_B" % i, p + Vector3(0.10, 0, -0.145), silver, black)

	# 顶部铭牌
	_box(root, "Plate", Vector3(0, 1.35, -0.325), Vector3(1.05, 0.24, 0.02), black)
	_box(root, "PlateTrim", Vector3(0, 1.245, -0.337), Vector3(1.05, 0.012, 0.004), cyan)
	_label(root, "PlateText", "8x5090 工作站", Vector3(0, 1.35, -0.34), 0.0085, cream)

	# 交互提示 / 开机状态
	var hint := _label(root, "Hint", "按F开机", Vector3(0, 1.06, -0.40), 0.013, cream)
	hint.visible = false
	var status := _label(root, "Status", "已开机", Vector3(0, 1.60, -0.36), 0.011,
		Color(0.45, 1.0, 0.7, 1.0))
	status.visible = false

	# 碰撞
	var body := StaticBody3D.new()
	body.name = "Body"
	body.position = Vector3(0, 0.75, 0)
	body.collision_layer = 1
	body.collision_mask = 1
	root.add_child(body)
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.24, 1.5, 0.68)
	cs.shape = bs
	body.add_child(cs)

	# 开机灯
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, 1.0, -0.55)
	light.light_color = Color(0.2, 0.9, 1.0, 1.0)
	light.light_energy = 0.0
	light.omni_range = 2.2
	light.shadow_enabled = false
	root.add_child(light)

	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		print("[rig] pack failed ", err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT)
	print("[rig] saved ", OUT, " err=", err)
	root.queue_free()
	quit(0)
