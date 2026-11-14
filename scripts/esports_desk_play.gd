extends Node3D
## 电竞房「坐下开黑」过场：五人主角团坐上五把电竞椅 → 五台电脑亮起游戏开发部标
## → 玩家窗口切进坦克动荡 → 按 Esc 退出 → 五人从椅子上跳下来。
##
## ── 用户 2026-11-14 的原话 ──
## 「现在加开始玩游戏动画，五人主角团全部坐上椅子，这里不动骨骼，直接平移上去，
##   快速平移就可以，就是爱丽丝在自己椅子旁边按 f 触发动画，她们坐上去，然后五个电脑
##   全部亮起发光图片，图片就是游戏开发部的标，玩家这边显示的是，窗口全部变成了小游戏，
##   按 esc 退出，像 arch 一样。结束游戏后所有人从椅子跳下来也是不动骨骼。」
##
## ── 五个位置是实测的，不是摆拍 ──
## `models/esports_room/esports_parts.json` 是 GLB **合并材质之前**的逐物件数据，
## 所以椅子/显示器能一个个挑出来（GLB 本身是按材质合并的 533 个桶，挑不出单台）。
## 换算：world = EsportsRoom 的变换（X +1.35375、Y −1.5、Z −1.35375）+ 原点 (53.265, 5.415, 13.257)
##
##   椅子（`tris=39340` 的贴地星形底座）：x 52.96~53.67（中心 **53.32**），z 中心
##     10.68 / 12.17 / 13.69 / 15.16 / 16.66 —— 人朝 **+X** 坐。
##   显示器（`tris=5387` 的薄板）：x 54.36~54.40（厚 0.05）、y 1.66~2.06、z 宽 0.60，
##     屏面朝 **−X**（对着椅子），z 中心 10.59 / 12.08 / 13.57 / 15.07 / 16.56。
##   走道在 x 50~52.9（上下铺与电竞桌之间），所以玩家只能站在**椅子前走道**上按 F。
##
##   ⚠️ 第一版把「桌子」当成了「椅子」（椅子其实更靠走道、桌子在它后面），
##      结果人浮在显示器前面、五把椅子全空着 —— 实拍 `ws0_front.png` 一眼看穿。
##
## ── 为什么「坐下」只是平移 ──
## 用户明确「不动骨骼」。三条路都试过的取舍：
##   ① 掰骨做坐姿 —— 要另做一条 Sit 动作，且这些模型是 glTF 带骨骼的，掰了会和
##      动画驱动打架（`anim_driver.gd` 每帧在写骨骼）。
##   ② 把脚放到**地板**上、人往前贴椅子 —— 人会和椅子穿模，且位置说不清在椅子上还是椅子前。
##   ③（本实现）把人整体平移到**座面上**，脚踩座面（y=1.00）。远处看是「五个人在位子上」，
##      近看是「站在椅子上」—— 和小屋电脑那套 `_seat()`（站着塞进凳子）是同一个取舍。
## 想升级成真坐姿：给五个角色各做一条 `Sit` 动作，把 `SEAT_Y` 换成「髋高」再调 `anim`。
##
## ── 显示器和玩家窗口 ──
##   · 五台电脑亮的是 `assets/story/gamedev_logo.png`（本仓库自己画的像素标，
##     不引外部版权素材；和工程里其它像素招牌同一套字体）；
##   · 玩家自己那块：一块全屏 5:4 覆盖层放坦克动荡（`SubViewport` 1000×800），
##     按 Esc 退出 —— 和 `hut_computer.gd` 的 Arch 终端一个用法。

# ══════════════ 实测坐标 ══════════════

## 电竞房地面（网格与烘焙碰撞一致）
const FLOOR_Y := 0.51
## 椅心 X（五把椅子同一条线）
## ⚠️ 是 `tris=39340` 那个「贴地星形底座」的 x 中心（53.32），不是桌子下面那块板；
##    实际落座点再往 +X 让 13 cm（53.45），否则人和椅背会叠在一起。
const SEAT_X := 53.45
## 座面顶：人物「站」在座面上时脚底就是这里
const SEAT_Y := 1.00
## 五把椅子的 Z（门 → 里，间距约 1.49 m）
const SEAT_Z: Array[float] = [10.68, 12.17, 13.69, 15.16, 16.66]
## 爱丽丝坐中间那把（门口进来正对的那台），触发点也在它前面
const ALICE_SEAT := 2

## 显示器面板：x 54.36~54.40 的薄板（厚 0.05 m）、y 1.66~2.06、z 宽 0.60。
## 面板**朝 −X**（对着椅子那侧），所以亮标的 QuadMesh 贴在 x=54.28、绕 Y 转 −90°。
## ⚠️ 贴片离面板前脸（x=54.36）留 **0.08 m** —— 只留 0.02 m 时远处几台会和面板
##    在深度缓冲里打平，实拍只有最近那台看得到标，其余还露着原来的白屏。
const SCREEN_X := 54.28
const SCREEN_Y := 1.86
const SCREEN_SIZE := Vector2(0.60, 0.40)
const SCREEN_Z: Array[float] = [10.59, 12.08, 13.57, 15.07, 16.56]

## 按 F 的位置：爱丽丝座位正前方的走道（椅子前沿 x≈52.96，人站 52.30 不会挤进椅子）
const TRIGGER_POS := Vector3(52.30, FLOOR_Y, 13.69)
const USE_RADIUS := 1.7
const USE_DY_MAX := 1.6

## 朝向：模型脸朝 +Z（见 `player.gd` 第 956 行的注释「脸朝世界 +Z」），
## 要朝 **+X**（面向桌上的显示器，显示器在 x≈54.38）就是 atan2(1, 0) = +π/2。
const FACE_YAW := PI * 0.5

# ══════════════ 动画节奏 ══════════════

## 单人位移时长 / 相邻两人错开多久（用户要「快速平移」）
const SIT_TIME := 0.22
const SIT_STAGGER := 0.07
## 平移时抬一点点的弧线高度，纯位移也有「跳上去」的感觉
const SIT_HOP := 0.18
## 亮屏时长
const GLOW_TIME := 0.42
## 跳下来时长 / 错开 / 弧高（比坐上去夸张一点，像真跳）
const STAND_TIME := 0.30
const STAND_STAGGER := 0.05
const STAND_HOP := 0.34

## 超过这个距离就不做位移动画、直接瞬移到位（同伴可能被落在别的场景）
const TELEPORT_DIST := 8.0

## ── 过场相机 ──
## ⚠️ 必须换成固定机位，不能沿用玩家自己的第三人称相机：
##    椅子在 x=54.28、隔断墙在 x≈54.8，人一坐下（面朝 −X 的显示器），
##    `SpringArm3D` 把相机甩到人**背后 +X** 一侧 —— 正好插进墙里，
##    实拍出来半屏白墙（`_tools/_tmp/esports_play/lit.png` 第一版就是这个）。
## 机位放在桌前走道靠门口那一头，斜着看整排工位，五个人和五块屏都在画面里。
## ⚠️ 别把机位往走道外侧挪（试过 x=50.85、y=2.55）：那个位置在窗边窗帘里面，
##    实拍整屏都是布。这组数值是实拍试出来的，动之前先出图看一眼。
const CUTSCENE_EYE := Vector3(52.05, 1.98, 9.35)
const CUTSCENE_LOOK := Vector3(54.10, 1.55, 14.10)

# ══════════════ 小游戏 ══════════════

const TANK_SIZE := Vector2i(1000, 800)
const TANK_SCENE := "res://scripts/tank_turmoil/tank_main_scene.tscn"
const LOGO_PATH := "res://assets/story/gamedev_logo.png"
## 小游戏开着时电竞房 BGM 压到原来的多少倍
const BGM_GAIN := 0.45

enum Phase { IDLE, SIT, GLOW, PLAY, STAND }

# ══════════════ 状态 ══════════════

var tank: Node2D
var tank_viewport: SubViewport
var _phase: Phase = Phase.IDLE
var _t := 0.0
## [{node, is_player, from_pos, from_yaw, seat_pos, seat_yaw}]
var _actors: Array = []
var _screens: Array[MeshInstance3D] = []
var _screen_mats: Array[StandardMaterial3D] = []
var _glow_light: OmniLight3D
## 过场相机 + 玩家原来的相机（收尾要还回去）
var _cutscene_cam: Camera3D
var _player_cam: Camera3D

var _in_range := false
var _player: Node3D
var _layer: CanvasLayer
var _hint: Label
var _overlay: Control
var _wide: TextureRect
var _foot: Label

var _bgm_saved := false
var _bgm_db := 0.0


func _ready() -> void:
	add_to_group("esports_desk_play")
	_build_screens()
	_build_ui()
	_build_cutscene_camera()
	_set_screen_level(0.0)   # 一开始屏幕是灭的（材质默认 albedo 是白的，不显式压黑的话亮度会读成 1）
	var menu := _settings_menu()
	if menu != null and menu.has_signal("opened_changed") \
			and not menu.is_connected("opened_changed", _on_menu_opened):
		menu.opened_changed.connect(_on_menu_opened)
	print("[开黑] 电竞房「坐下开黑」就位：触发点 %s（爱丽丝第 %d 把椅子），交互半径 %.1f m"
		% [str(TRIGGER_POS), ALICE_SEAT, USE_RADIUS])


func _settings_menu() -> Node:
	var sc := get_tree().current_scene
	if sc != null:
		var m := sc.find_child("SettingsMenu", true, false)
		if m != null:
			return m
	return get_node_or_null("../../SettingsMenu")


## 设置菜单一开就把小游戏合上（层号差得远，宁可多合一次）
func _on_menu_opened(open: bool) -> void:
	if open and _phase == Phase.PLAY:
		print("[小游戏] 设置菜单开了，坦克动荡让位")
		_end_play()


# ══════════════ 建模：五块会亮的「显示器」 ══════════════

func _build_screens() -> void:
	var logo := _load_logo()
	if logo == null:
		push_warning("[开黑] 载不到 %s，显示器只能亮纯色" % LOGO_PATH)

	var quad := QuadMesh.new()
	quad.size = SCREEN_SIZE

	for i in SEAT_Z.size():
		var mat := StandardMaterial3D.new()
		# 屏幕自己是发光体，不吃房间灯
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = logo
		mat.emission_enabled = true
		mat.emission_texture = logo
		mat.emission_energy_multiplier = 1.8
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		mat.albedo_color = Color(1, 1, 1)

		var mi := MeshInstance3D.new()
		mi.name = "DeskScreen%d" % i
		mi.mesh = quad
		mi.material_override = mat
		# 面板朝 −X（椅子在 −X 侧）：QuadMesh 法线是 +Z，绕 Y 转 −90° 就朝 −X
		mi.rotation_degrees = Vector3(0.0, -90.0, 0.0)
		mi.position = Vector3(SCREEN_X, SCREEN_Y, SCREEN_Z[i])
		mi.visible = false
		add_child(mi)
		_screens.append(mi)
		_screen_mats.append(mat)

	# 五块屏幕一起亮，给房间补一点冷光
	_glow_light = OmniLight3D.new()
	_glow_light.name = "DeskGlow"
	_glow_light.position = Vector3(SCREEN_X + 0.9, SCREEN_Y + 0.35, SEAT_Z[ALICE_SEAT])
	_glow_light.light_color = Color(0.55, 0.78, 1.0)
	_glow_light.light_energy = 0.0
	_glow_light.omni_range = 4.5
	_glow_light.shadow_enabled = false
	add_child(_glow_light)


## 载「游戏开发部标」。
##
## 优先走导入后的资源（`load()`）；只有**还没被 Godot 导入**时（新加的图第一次跑、
## 编辑器没打开过）才退回 `Image.load_from_file()` 直接读原始 PNG —— 那条路在
## 导出包里不好使，所以它是兜底，不是主路。踩过：加了 PNG 但没 import，
## `ResourceLoader.exists()` 直接 false，五台电脑全黑。
func _load_logo() -> Texture2D:
	if ResourceLoader.exists(LOGO_PATH):
		return load(LOGO_PATH) as Texture2D
	var img := Image.load_from_file(LOGO_PATH)
	if img != null and not img.is_empty():
		push_warning("[开黑] %s 还没导入，先用原始图片顶上（打开一次编辑器让 Godot 导入）" % LOGO_PATH)
		return ImageTexture.create_from_image(img)
	return null


## 过场机位：建好但**不设为 current**，等开场才接管。
func _build_cutscene_camera() -> void:
	_cutscene_cam = Camera3D.new()
	_cutscene_cam.name = "CutsceneCam"
	_cutscene_cam.fov = 68.0
	_cutscene_cam.near = 0.05
	_cutscene_cam.far = 220.0
	_cutscene_cam.position = CUTSCENE_EYE
	add_child(_cutscene_cam)
	_cutscene_cam.look_at(CUTSCENE_LOOK, Vector3.UP)


## 接管画面：过场期间用固定机位，结束还给玩家。
func _take_camera() -> void:
	var p := _player_node()
	if p != null:
		_player_cam = p.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
		if _player_cam == null:
			_player_cam = p.find_child("Camera3D", true, false) as Camera3D
	if _cutscene_cam != null:
		_cutscene_cam.make_current()


func _release_camera() -> void:
	if _player_cam != null and is_instance_valid(_player_cam):
		_player_cam.make_current()
	_player_cam = null


## 屏幕亮度 0→1（用 albedo/emission 乘系数，不用 visible 硬切，才有「亮起来」的过程）
func _set_screen_level(k: float) -> void:
	for i in _screens.size():
		var mi := _screens[i]
		mi.visible = k > 0.001
		var mat := _screen_mats[i]
		var c := clampf(k, 0.0, 1.0)
		mat.albedo_color = Color(c, c, c)
		mat.emission_energy_multiplier = 1.8 * c
	_glow_light.light_energy = 1.35 * clampf(k, 0.0, 1.0)


# ══════════════ 界面 ══════════════

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "DeskPlayUI"
	_layer.layer = 45
	add_child(_layer)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "按 F 和她们一起坐下开黑"
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("shadow_offset_x", 2)
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-150, -150)
	_hint.visible = false
	_layer.add_child(_hint)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_layer.add_child(_overlay)

	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color(0.015, 0.018, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(bg)

	# 小游戏画布：第一次按下才建（3.4 MB 立绘 + 85 KB 脚本，别给开机添负担）
	tank_viewport = SubViewport.new()
	tank_viewport.name = "TankViewport"
	tank_viewport.size = TANK_SIZE
	tank_viewport.transparent_bg = false
	tank_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tank_viewport.handle_input_locally = false
	add_child(tank_viewport)

	_wide = TextureRect.new()
	_wide.name = "TankTexture"
	_wide.texture = tank_viewport.get_texture()
	# 1000×800 是 5:4，窗口 16:9 —— 必须留黑边，拉满会把坦克压扁
	_wide.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wide.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_wide)

	_foot = Label.new()
	_foot.name = "Footer"
	_foot.text = "WASD 移动 · 空格/J 开火 · P 暂停 · Esc 结束开黑"
	_foot.add_theme_font_size_override("font_size", 15)
	_foot.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	_foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_foot.offset_top = -40
	_foot.offset_left = -380
	_foot.offset_right = 380
	_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_foot)


# ══════════════ 交互 ══════════════

func _player_node() -> Node3D:
	if is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func _use_point() -> Vector3:
	return TRIGGER_POS


## 过场时钟。**只有过场在跑时才有事做**，常态下直接返回（不占帧）。
##
## ⚠️ 少了这个分发器，`_tick_sit/_tick_glow/_tick_stand` 全是死代码 ——
##    表现就是「按了 F 人不动、屏幕不亮」。第一版真忘了写，自检里才发现。
func _process(delta: float) -> void:
	match _phase:
		Phase.SIT:
			_tick_sit(delta)
		Phase.GLOW:
			_tick_glow(delta)
		Phase.STAND:
			_tick_stand(delta)
		_:
			pass


func _physics_process(_delta: float) -> void:
	if _phase != Phase.IDLE:
		return
	var p := _player_node()
	if p == null:
		return
	var d := p.global_position - _use_point()
	var near := Vector2(d.x, d.z).length() <= USE_RADIUS and absf(d.y) <= USE_DY_MAX
	if near != _in_range:
		_in_range = near
		_hint.visible = near


func _input(event: InputEvent) -> void:
	if _phase == Phase.PLAY:
		var k := event as InputEventKey
		# Esc 退出（用户要「像 arch 一样」）。`G` 留作备用，手柄 / 误按都能退。
		if k != null and k.pressed and not k.echo \
				and (k.keycode == KEY_ESCAPE or k.keycode == KEY_G):
			_end_play()
			get_viewport().set_input_as_handled()
			return
		if tank != null and is_instance_valid(tank):
			var tm := event as InputEventMouse
			if tm != null:
				var dup := event.duplicate() as InputEventMouse
				dup.position = _to_canvas(tm.position)
				dup.global_position = dup.position
				_feed_tank(dup)
			else:
				_feed_tank(event)
		get_viewport().set_input_as_handled()
		return
	if _phase != Phase.IDLE:
		# 过场动画期间不吃键，但要挡一下，免得同时触发别的东西
		return
	var k2 := event as InputEventKey
	if k2 != null and k2.pressed and not k2.echo and k2.keycode == KEY_F and _in_range:
		begin()
		get_viewport().set_input_as_handled()


## 窗口坐标 → 小游戏画布坐标（1000×800，等比缩放 + 居中留黑边）
func _to_canvas(p: Vector2) -> Vector2:
	if _wide == null:
		return p
	var r := _wide.get_global_rect()
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return p
	var sc := minf(r.size.x / float(TANK_SIZE.x), r.size.y / float(TANK_SIZE.y))
	if sc <= 0.0:
		return p
	var shown := Vector2(TANK_SIZE) * sc
	var origin := r.position + (r.size - shown) * 0.5
	return (p - origin) / sc


## 事件同时喂两条路：
##   · `feed()` —— 键位表 / 鼠标左键，给**玩法**用；
##   · `ui_event()` —— 菜单点击 / 暂停菜单 / 设置滑块，给**界面**用。
## ⚠️ 只喂 `feed()` 是不够的：菜单按键走 `_handle_menu_keys`、按钮点击走
##    `_handle_gameplay_mouse`，它们原本挂在 `_unhandled_input` 上；本节点在
##    `SubViewport` 里、`handle_input_locally = false`，那两个回调**根本不会被触发**，
##    表现就是「菜单点不动、开始不了游戏」。
func _feed_tank(event: InputEvent) -> void:
	if tank == null or not is_instance_valid(tank):
		return
	tank.call("feed", event)
	if tank.has_method("ui_event"):
		tank.call("ui_event", event)


# ══════════════ 过场：坐下 ══════════════

func is_playing() -> bool:
	return _phase == Phase.PLAY


func phase_name() -> String:
	return ["IDLE", "SIT", "GLOW", "PLAY", "STAND"][int(_phase)]


func in_range() -> bool:
	return _in_range


## 开始过场：收集五个角色 → 快速平移上椅子
func begin() -> void:
	if _phase != Phase.IDLE:
		return
	_collect_actors()
	if _actors.is_empty():
		push_warning("[开黑] 一个角色都没找到，过场取消")
		return
	_phase = Phase.SIT
	_t = 0.0
	_in_range = false
	_hint.visible = false
	# 人都挪走了，先把输入系统让出来（否则人还在原地走）
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_take_camera()
	_duck_room_music(true)
	Sfx.play("ui_open", -6.0)
	print("[开黑] 开始：%d 人依次坐上电竞椅" % _actors.size())


## 收集玩家 + 四位队友，记下「原来站哪」
func _collect_actors() -> void:
	_actors.clear()
	var p := _player_node()
	if p == null:
		return
	_actors.append(_make_actor(p, ALICE_SEAT, true))
	# 四位队友是 game 的直接子节点（`CompanionMomoi` / `Midori` / `Yuzu` / `Kei`），
	# 按场景里的顺序取，依次安排在爱丽丝左右两侧的椅子上。
	var seats := [1, 0, 3, 4]
	var k := 0
	var parent := get_parent()
	if parent != null:
		for c in parent.get_children():
			if not (c is Companion) or k >= seats.size():
				continue
			_actors.append(_make_actor(c as Node3D, int(seats[k]), false))
			k += 1


func _make_actor(node: Node3D, seat: int, is_player: bool) -> Dictionary:
	var a := {
		"node": node,
		"is_player": is_player,
		"from_pos": node.global_position,
		"from_yaw": node.rotation.y,
		"from_model_yaw": 0.0,
		"seat_pos": Vector3(SEAT_X, SEAT_Y, SEAT_Z[seat]),
		"seat_yaw": FACE_YAW,
		# 太远（被落在别处）就别演位移动画，直接落座
		"instant": node.global_position.distance_to(Vector3(SEAT_X, SEAT_Y, SEAT_Z[seat])) > TELEPORT_DIST,
	}
	if is_player:
		var mr := node.get("model_root") as Node3D
		if mr != null:
			a["from_model_yaw"] = mr.rotation.y
	# 冻结：真人用 set_process_input，同伴是 CharacterBody3D 有重力，
	# 不关掉 `_physics_process` 的话「把人放到座面」下一帧就会被重力拽下去。
	node.set_physics_process(false)
	node.set_process(false)
	if node is CharacterBody3D:
		(node as CharacterBody3D).velocity = Vector3.ZERO
	if not is_player and node.has_method("set_standby"):
		node.call("set_standby", true)
	return a


func _apply_pose(a: Dictionary, pos: Vector3, yaw: float) -> void:
	var node := a["node"] as Node3D
	node.global_position = pos
	node.rotation.y = yaw
	if bool(a["is_player"]):
		var mr := node.get("model_root") as Node3D
		if mr != null:
			mr.rotation.y = yaw
		# 相机也跟着转，坐下去那一下是「面朝桌上的显示器」
		var rig := node.get_node_or_null("CameraRig") as Node3D
		if rig != null:
			rig.rotation.y = yaw


func _tick_sit(delta: float) -> void:
	_t += delta
	var total := SIT_TIME + SIT_STAGGER * float(maxi(_actors.size() - 1, 0))
	for i in _actors.size():
		var a: Dictionary = _actors[i]
		var u := 1.0 if bool(a["instant"]) else \
			clampf((_t - SIT_STAGGER * float(i)) / SIT_TIME, 0.0, 1.0)
		var e := _ease_out(u)
		var from: Vector3 = a["from_pos"]
		var seat: Vector3 = a["seat_pos"]
		var pos := from.lerp(seat, e) + Vector3.UP * (sin(PI * e) * SIT_HOP)
		_apply_pose(a, pos, _lerp_yaw(float(a["from_yaw"]), float(a["seat_yaw"]), e))
	if _t >= total + 0.05:
		# 全部落座，进入「电脑亮起来」
		for a in _actors:
			_apply_pose(a, a["seat_pos"], float(a["seat_yaw"]))
		_phase = Phase.GLOW
		_t = 0.0
		Sfx.play("ui_open", -8.0)
		print("[开黑] 五人就位，电脑开始亮屏")


func _tick_glow(delta: float) -> void:
	_t += delta
	_set_screen_level(clampf(_t / GLOW_TIME, 0.0, 1.0))
	if _t >= GLOW_TIME + 0.12:
		_begin_play()


# ══════════════ 小游戏 ══════════════

func _begin_play() -> void:
	if not _ensure_tank():
		return
	_phase = Phase.PLAY
	_overlay.visible = true
	if tank.has_method("release_all"):
		tank.call("release_all")
	print("[小游戏] 窗口切进坦克动荡（五人混战 · 音乐仍由电竞房播放，压到 %d%%）"
		% int(BGM_GAIN * 100.0))


func _ensure_tank() -> bool:
	if tank != null and is_instance_valid(tank):
		return true
	var packed := load(TANK_SCENE) as PackedScene
	if packed == null:
		push_warning("[小游戏] 载不到 %s" % TANK_SCENE)
		return false
	tank = packed.instantiate() as Node2D
	if tank == null:
		return false
	tank.name = "TankTurmoil"
	tank_viewport.add_child(tank)
	return true


func _end_play() -> void:
	if _phase != Phase.PLAY:
		return
	_overlay.visible = false
	if tank != null and is_instance_valid(tank) and tank.has_method("release_all"):
		tank.call("release_all")
	_begin_stand()


# ══════════════ 过场：跳下来 ══════════════

func _begin_stand() -> void:
	_phase = Phase.STAND
	_t = 0.0
	_set_screen_level(1.0)
	Sfx.play("ui_close", -6.0)
	print("[开黑] 结束：五人从椅子上跳下来")


func _tick_stand(delta: float) -> void:
	_t += delta
	var total := STAND_TIME + STAND_STAGGER * float(maxi(_actors.size() - 1, 0))
	for i in _actors.size():
		var a: Dictionary = _actors[i]
		var u := 1.0 if bool(a["instant"]) else \
			clampf((_t - STAND_STAGGER * float(i)) / STAND_TIME, 0.0, 1.0)
		var e := _ease_out(u)
		var seat: Vector3 = a["seat_pos"]
		var to: Vector3 = a["from_pos"]
		var pos := seat.lerp(to, e) + Vector3.UP * (sin(PI * e) * STAND_HOP)
		_apply_pose(a, pos, _lerp_yaw(float(a["seat_yaw"]), float(a["from_yaw"]), e))
	# 屏幕在「跳下来」的过程中灭掉（人走屏灭）
	_set_screen_level(clampf(1.0 - _t / maxf(STAND_TIME, 0.01), 0.0, 1.0))
	if _t >= total + 0.05:
		_finish_stand()


func _finish_stand() -> void:
	for a in _actors:
		var node := a["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		_apply_pose(a, a["from_pos"], float(a["from_yaw"]))
		if bool(a["is_player"]):
			var mr := node.get("model_root") as Node3D
			if mr != null:
				mr.rotation.y = float(a["from_model_yaw"])
		if not bool(a["is_player"]) and node.has_method("set_standby"):
			node.call("set_standby", false)
		node.set_physics_process(true)
		node.set_process(true)
	_actors.clear()
	_set_screen_level(0.0)
	_phase = Phase.IDLE
	_t = 0.0
	_release_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_duck_room_music(false)
	print("[开黑] 回到常态")


func _ease_out(u: float) -> float:
	# 先快后慢：用户要「快速平移」，起步就得冲出去
	return 1.0 - pow(1.0 - u, 3.0)


func _lerp_yaw(from: float, to: float, u: float) -> float:
	return lerp_angle(from, to, u)


# ══════════════ BGM 让位 ══════════════

## 只碰 `music.gd` 建在 `root/MusicHost/Bgm` 的那个播放器，进出各改一次，退出原样还原。
## ⚠️ 不往 `music.gd` 加 API（那个文件常有别的会话在改）；`Music` 是静态类，
##    `Music.get("_player")` 会直接报错，所以按节点树找。
func _room_music_player() -> AudioStreamPlayer:
	return get_tree().root.get_node_or_null("MusicHost/Bgm") as AudioStreamPlayer


func _duck_room_music(on: bool) -> void:
	var player := _room_music_player()
	if player == null:
		return
	if on:
		if not _bgm_saved:
			_bgm_db = player.volume_db
			_bgm_saved = true
		player.volume_db = _bgm_db + linear_to_db(BGM_GAIN)
	elif _bgm_saved:
		player.volume_db = _bgm_db
		_bgm_saved = false


# ══════════════ 探针 / 自检用 ══════════════

func screens() -> Array[MeshInstance3D]:
	return _screens


func screen_level() -> float:
	if _screen_mats.is_empty():
		return 0.0
	var c := _screen_mats[0].albedo_color
	return c.r


func actors() -> Array:
	return _actors


## 探针：跳过距离判定直接开始过场
func begin_for_test() -> void:
	begin()


## 自检用：手动推一帧。
##
## ⚠️ 不能 `host.call("_process", dt)` —— 引擎的生命周期方法**不是**普通脚本方法，
##    直接 call 会报「Nonexistent function '_process'」。所以包一层。
func tick_for_test(delta: float) -> void:
	_process(delta)


## 自检用：手动推一帧物理（`in_range` 是 `_physics_process` 里算的）。
func tick_physics_for_test(delta: float) -> void:
	_physics_process(delta)


## 探针：把过场快进到「窗口已经是小游戏」
func jump_to_play_for_test() -> void:
	if _phase == Phase.IDLE:
		begin()
	var guard := 0
	while _phase != Phase.PLAY and guard < 600:
		_process(1.0 / 60.0)
		guard += 1
