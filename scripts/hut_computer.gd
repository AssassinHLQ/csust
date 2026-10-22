class_name HutComputer
extends Node3D
## 小屋桌子上的**电脑**：显示器 + 键盘 + 按 F 使用的假 Arch Linux 终端。
##
## 用户 2026-10-22：「现在先在那个召唤同伴屋子里面不是有桌子吗，上面放个显示器，
## 椅子可以坐上去，然后可以使用电脑，就是弹出这个 ARCH LINUX 主题，按 F 使用，
## 再按 F 退出」。
##
## ── 挂在哪 ──
## `game.gd::_build_computer()` 把它加成 `MeshHut` 的子节点，所以这里的坐标
## **就是小屋的局部坐标**（`scenes/mesh_hut.tscn` 里量的）：
##   桌面顶面 y = 0.75 + 0.05 = **0.80**，桌面中心 (-0.6, –, -2.2)；
##   凳子坐面 (-0.6, 0.60, -1.3) —— 桌子朝 **+Z**，人坐凳子面对 −Z 看屏幕。
##
## ── 画面为什么能同时出现在两个地方 ──
## 终端的画面只有一份：`SubViewport` 里那个 `ArchTerminal`。
##   · 桌上的显示器：一块 `PlaneMesh` 的 `albedo_texture` 直接取这份 ViewportTexture；
##   · 按 F 之后的全屏覆盖层：一个 `TextureRect`，读的还是同一张纹理。
## 所以「贴近看显示器」和「弹出大窗口」看到的是同一块屏幕，不会出现两份状态。
##
## ── 输入怎么进终端 ──
## 不做 `SubViewport` 的输入转发（那条路要处理鼠标坐标、焦点、`push_input` 一堆东西），
## 而是**电脑自己抓键盘**：`_input()` 里直接 `terminal.feed(event)`。
## 打开时把玩家的 `set_process_input/process/physics_process` 全关掉，
## 否则人物会在后台继续走动、R 键还在换弹。
##
## ⚠️ 椅子「坐上去」这一版**没做**：坐姿需要一条坐着的动画，现在只有 Idle/Walk/Run，
##    硬把人塞到凳子上会站着穿进凳子。等有坐姿动画（或允许掰骨）再加，
##    见文件末尾 `# TODO(坐姿)`。

## 桌面顶面（小屋局部）
const DESK_TOP_Y := 0.80
## 屏幕面板中心
const PANEL_POS := Vector3(-0.6, 1.10, -2.42)
const PANEL_SIZE := Vector2(0.66, 0.40)
const SCREEN_SIZE := Vector2(0.60, 0.34)

## 交互范围：人站在桌子前面（凳子附近）才能按 F
const USE_RADIUS := 1.7
const USE_DY_MAX := 1.6

## 终端画布尺寸：COLS×CELL + 两侧留白
const VP_SIZE := Vector2i(832, 664)

var terminal: ArchTerminal
var viewport: SubViewport

var _using := false
var _in_range := false
var _player: Node3D
var _layer: CanvasLayer
var _overlay: Control
var _screen: TextureRect
var _hint: Label
var _beam: OmniLight3D


func _ready() -> void:
	add_to_group("hut_computer")
	_build()


# ── 建模 ──────────────────────────────────────────────────────────────────────

func _build() -> void:
	var dark := _mat(Color(0.055, 0.06, 0.07), 0.35, 0.25)
	var plastic := _mat(Color(0.12, 0.13, 0.15), 0.65, 0.0)
	var metal := _mat(Color(0.45, 0.47, 0.50), 0.35, 0.85)

	# 显示器：底座 + 脖子 + 边框
	_box("Stand", Vector3(-0.6, DESK_TOP_Y + 0.008, -2.34),
		Vector3(0.30, 0.016, 0.18), metal)
	_box("Neck", Vector3(-0.6, DESK_TOP_Y + 0.06, -2.40),
		Vector3(0.05, 0.12, 0.04), metal)
	_box("Bezel", PANEL_POS, Vector3(PANEL_SIZE.x, PANEL_SIZE.y, 0.030), dark)

	# 屏幕：一个 SubViewport 贴在 PlaneMesh 上
	viewport = SubViewport.new()
	viewport.name = "ScreenViewport"
	viewport.size = VP_SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	add_child(viewport)

	terminal = ArchTerminal.new()
	terminal.name = "ArchTerminal"
	# PRESET_FULL_RECT 会让它跟着 SubViewport 的尺寸走（832×664），
	# 不要再手动设 size —— 锚点布局会覆盖掉，设了反而让人误以为是它在起作用。
	terminal.set_anchors_preset(Control.PRESET_FULL_RECT)
	terminal.exit_requested.connect(_close)
	viewport.add_child(terminal)

	var screen_mat := StandardMaterial3D.new()
	screen_mat.albedo_texture = viewport.get_texture()
	# 屏幕是自发光的显示器，不该被小屋的灯影响 —— 直接 UNSHADED + 一点自发光
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.emission_enabled = true
	screen_mat.emission_texture = viewport.get_texture()
	screen_mat.emission_energy_multiplier = 0.55
	screen_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

	var plane := PlaneMesh.new()
	plane.size = SCREEN_SIZE
	var scr := MeshInstance3D.new()
	scr.name = "Screen"
	scr.mesh = plane
	scr.material_override = screen_mat
	# ⚠️ `PlaneMesh` 是**水平**的（法线朝 +Y，像个地板），不转的话从正面只能看到
	#    一条边 —— 第一版就炸在这：屏幕只露出一条一像素高的字。绕 X 转 +90° 才是朝 +Z。
	scr.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	scr.position = PANEL_POS + Vector3(0.0, 0.0, 0.017)
	add_child(scr)

	# 键盘：一块矮板 + 一条空格键凹槽（够看得出是键盘就行）
	_box("Keyboard", Vector3(-0.6, DESK_TOP_Y + 0.012, -1.98),
		Vector3(0.42, 0.022, 0.15), plastic)
	_box("KeyboardLip", Vector3(-0.6, DESK_TOP_Y + 0.024, -1.905),
		Vector3(0.42, 0.006, 0.012), dark)

	# 屏幕的冷光：让桌子附近有一点蓝白反射（不影响玩法，关掉也行）
	_beam = OmniLight3D.new()
	_beam.name = "ScreenGlow"
	_beam.position = PANEL_POS + Vector3(0.0, -0.05, 0.55)
	_beam.light_color = Color(0.55, 0.72, 0.95)
	_beam.light_energy = 0.30
	_beam.omni_range = 1.4
	_beam.shadow_enabled = false
	add_child(_beam)

	_build_ui()
	print("[电脑] 小屋电脑就位：显示器 %s（屏幕 %.2f×%.2f m，终端画布 %s），交互半径 %.1f m"
		% [str(PANEL_POS), SCREEN_SIZE.x, SCREEN_SIZE.y, str(VP_SIZE), USE_RADIUS])


func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _box(nm: String, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.name = nm
	mi.position = center
	add_child(mi)
	return mi


# ── 界面 ──────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "ComputerUI"
	_layer.layer = 40          # 压在所有 HUD 之上（HUD 在 10 层）
	add_child(_layer)

	# 靠近时的提示（小、在屏幕下方）
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "按 F 使用电脑"
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("shadow_offset_x", 2)
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-90, -150)
	_hint.visible = false
	_layer.add_child(_hint)

	# 全屏覆盖层
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_layer.add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)

	# 显示器外框：一圈深灰边 + 里面是终端画面
	var frame := Panel.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 90
	frame.offset_top = 60
	frame.offset_right = -90
	frame.offset_bottom = -60
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.025, 0.035)
	sb.border_color = Color(0.22, 0.24, 0.28)
	sb.set_border_width_all(10)
	sb.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(frame)

	_screen = TextureRect.new()
	_screen.name = "ScreenTexture"
	_screen.texture = viewport.get_texture()
	_screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.offset_left = 10
	_screen.offset_top = 10
	_screen.offset_right = -10
	_screen.offset_bottom = -10
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_screen)

	var foot := Label.new()
	foot.text = "按 F（或 Esc、或输入 exit）退出电脑"
	foot.add_theme_font_size_override("font_size", 16)
	foot.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	foot.offset_top = -44
	foot.offset_left = -240
	foot.offset_right = 240
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(foot)


# ── 交互 ──────────────────────────────────────────────────────────────────────

func _player_node() -> Node3D:
	if is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func _nearest_point() -> Vector3:
	# 凳子前面那块地方（人站着看屏幕的位置）
	return to_global(Vector3(-0.6, 0.0, -1.30))


func _physics_process(_delta: float) -> void:
	if _using:
		return
	var p := _player_node()
	if p == null:
		return
	var here := _nearest_point()
	var d := p.global_position - here
	var flat := Vector2(d.x, d.z).length()
	var near := flat <= USE_RADIUS and absf(d.y) <= USE_DY_MAX
	if near != _in_range:
		_in_range = near
		_hint.visible = near


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if _using:
		# 鼠标之类的先吃掉，键盘全部转给终端；F / Esc 由终端和这里一起处理
		if k.keycode == KEY_F:
			_close()
			get_viewport().set_input_as_handled()
			return
		terminal.feed(event)
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_F and _in_range:
		_open()
		get_viewport().set_input_as_handled()


func _open() -> void:
	if _using:
		return
	_using = true
	_hint.visible = false
	_overlay.visible = true
	terminal.reset()
	var p := _player_node()
	if p != null:
		if p is CharacterBody3D:
			(p as CharacterBody3D).velocity = Vector3.ZERO
		p.set_physics_process(false)
		p.set_process(false)
		p.set_process_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("ui_open", -6.0)
	print("[电脑] 打开 Arch 终端（假终端，不接真实 shell）")


func _close() -> void:
	if not _using:
		return
	_using = false
	_overlay.visible = false
	_hint.visible = _in_range
	var p := _player_node()
	if p != null:
		p.set_physics_process(true)
		p.set_process(true)
		p.set_process_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sfx.play("ui_close", -6.0)
	print("[电脑] 合上电脑")


# ── 探针 / 自检用 ──────────────────────────────────────────────────────────────

func is_using() -> bool:
	return _using


func in_range() -> bool:
	return _in_range


func terminal_text() -> String:
	return terminal.screen_text() if terminal != null else ""


func use_for_test() -> void:
	## 探针用：不走距离判定，直接打开（省得在探针里把玩家瞬移过去）
	_open()


func close_for_test() -> void:
	_close()


func screen_mesh() -> MeshInstance3D:
	return get_node_or_null("Screen") as MeshInstance3D


# TODO(坐姿): 用户 2026-10-22 要求「椅子可以坐上去」。现在没有坐姿动画，
# 把人塞到凳子 (-0.6, 0.60, -1.3) 上会站着穿进凳子，所以这一版**只在桌子前面
# 站着按 F**。要真坐，得先有一条 sit 动画（或允许掰骨：大腿抬 ~90°、小腿垂下、
# 骨盆降 0.32 m），并且把 `Player/CameraRig` 的 y 从 1.35 降到 ~0.95。
