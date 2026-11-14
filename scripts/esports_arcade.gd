extends Node3D
## 电竞房里的**街机柜**：柜体 + 屏幕 + 摇杆按键，屏幕上跑「坦克动荡」小游戏。
##
## ── 由来 ──
## 用户 2026-11-14：「能不能内置到爱丽丝梦游长理的电竞房当小游戏」
## → 第一版先挂在小屋电脑上；当天改口「搬到电竞房」，于是有了这个文件。
##（小屋电脑那一版的代码已从 `hut_computer.gd` 里撤掉，只留终端。）
##
## ── 为什么自建柜体，而不是用房间里现成的显示器 ──
## 电竞房的 GLB 是**按材质合并的 533 个桶**：`M_集简空间h06_m21090344` 一个网格里
## 就同时装着 5 张桌子 + 椅子 + 显示器，没有「某一台显示器」这种节点可挑。
## 想往现成显示器上贴屏幕，只能靠肉眼估世界坐标 —— 差 2 cm 就穿模或悬空。
## 自建柜体则**完全可控**：尺寸、朝向、屏幕高度全是本文件里的常量。
##
## ── 位置怎么定的（实测，不是估的）──
## `scripts/_probe_esports_view.gd` 在游戏里实跑量到的：
##   · 地面 **y = 0.51**（网格顶面与烘焙碰撞一致）
##   · 房间世界范围 x 47.3~60.3、z 1.86~23.55
##   · 电竞桌一条长排：x 52.9~54.6、z 10.2~17.0（紧贴 x≈54.8 那道隔断）
##   · 上下铺 / 衣柜：x 47.2~50.0
##   · ⇒ 中间 **x 50~52.9** 是一条 2.9 m 宽的走道
## 柜子贴在走道**西侧**（上下铺那一边），正面朝 **+X** 对着走道；人站 x≈51.6 玩。
## 选这儿而不是门口：走道中段前后都通，玩家从门口（z≈9.3）进来走两步就看见它，
## 又不会堵门（`_probe_esports_view.gd` 的净空扫描：z 3~18 四周 0.9 m 全空）。
##
## ── ⚠️ 必须挂在 `game` 的**直接子节点**下，用世界坐标 ──
## `EsportsRoom` 挂着 `Transform3D(1.35375,0,0, 0,-1.5,0, 0,0,-1.35375, …)`：
## Y 轴是 **−1.5 的镜像**（整间屋上下翻过来了，玩家踩的其实是模型原来的天花板）。
## 把柜子挂进去会一起被镜像 —— 柜身倒立、屏幕朝地。所以只能挂平地。
## 代价：柜子的显隐要**自己跟房间同步**（见 `game.gd::_build_esports_arcade()`）。
##
## ── 画面 ──
## 小游戏的画面只有一份：`SubViewport`（1000×800，比例写死在它的 `W`/`H`）里那个
## `TankTurmoil`。柜体屏幕上是一块 `PlaneMesh`，`albedo_texture` 直接取这份
## ViewportTexture；按 F 之后另有一块全屏 `TextureRect` 读**同一张**纹理。
## 所以「贴着柜子看」和「全屏玩」是同一局，不会出现两份状态。
##
## ── 音乐 ──
## 用户 2026-11-14：「不用，小游戏音效，电竞房音乐」——小游戏自己一首曲子都不放，
## 全程用电竞房那首 BGM，只在开局时把它压到 45% 好让枪声听得见，退出还原。
##
## ── ⚠️ 为什么不用 `class_name` ──
## `class_name` 要靠**编辑器扫描**才注册进 `global_script_class_cache.cfg`；
## `--headless --script` 跑自检时不会重新扫，`game.gd` 里写 `EsportsArcade` 会直接
## 「Identifier not declared」解析失败。所以一律用 `preload(...).new()`，
## 类型注解退成 `Node3D`。

# ══════════════ 尺寸与位置 ══════════════

## 电竞房地面高度（实测，见文件头）
const FLOOR_Y := 0.51
## 柜子在世界里的落点（正面朝 +X）
const ARCADE_POS := Vector3(50.55, FLOOR_Y, 11.60)
## 绕 Y 转 90°：本地 +Z（正面）转到世界 +X
const YAW_DEG := 90.0

const BODY_W := 0.78          # 宽（沿 Z）
const BODY_D := 0.72          # 进深（沿 X）
const BODY_H := 1.80          # 总高（街机柜标准高度，不用抬头看也不用弯腰）

## 屏幕：**必须 5:4**（1000×800）。拉成 16:9 坦克和迷宫就扁了。
const SCREEN_SIZE := Vector2(0.62, 0.496)
const SCREEN_Y := 1.27
## 小游戏逻辑尺寸。改这里必须同步改 `tank_main.gd` 的 `W` / `H`。
const TANK_SIZE := Vector2i(1000, 800)
const TANK_SCENE := "res://scripts/tank_turmoil/tank_main_scene.tscn"

## 交互：人站在柜子正前方 1.9 m 内、高度差 1.6 m 内才能按 F
const USE_RADIUS := 1.9
const USE_DY_MAX := 1.6

## 小游戏开着时电竞房 BGM 压到原来的多少倍
const BGM_GAIN := 0.45

## 柜体配色：深色机身 + 青色灯带（和电竞房的蓝白冷调对得上）
const COLOR_BODY := Color(0.075, 0.085, 0.105)
const COLOR_PANEL := Color(0.13, 0.15, 0.19)
const COLOR_ACCENT := Color(0.32, 0.80, 0.96)
const COLOR_METAL := Color(0.55, 0.60, 0.66)

# ══════════════ 状态 ══════════════

var tank: Node2D
var tank_viewport: SubViewport

var _using := false
var _in_range := false
var _player: Node3D

var _layer: CanvasLayer
var _overlay: Control
var _wide: TextureRect
var _hint: Label
var _foot: Label
## 屏幕上那块材质（画面靠它显示，`_open()` 前后不用换）
var _screen_mat: StandardMaterial3D
## 待机时屏幕上那句「按 F 开始」
var _attract: Node2D
var _glow: OmniLight3D

## BGM 压低前的分贝（只在 `_open()`/`_close()` 各处一次，退出原样还原）
var _bgm_saved := false
var _bgm_db := 0.0


func _ready() -> void:
	add_to_group("esports_arcade")
	_build()
	# 兜底：设置菜单一开就把小游戏合上（层号差得远，宁可多合一次）
	var menu := _settings_menu()
	if menu != null and menu.has_signal("opened_changed") \
			and not menu.is_connected("opened_changed", _on_menu_opened):
		menu.opened_changed.connect(_on_menu_opened)
	print("[街机] 电竞房街机柜就位：%s（朝向 +X，屏幕 %.2f×%.2f m，交互半径 %.1f m）"
		% [str(ARCADE_POS), SCREEN_SIZE.x, SCREEN_SIZE.y, USE_RADIUS])


## 不用 `../../SettingsMenu` 这种硬路径：探针里单独 new 出来时那棵树是断的。
func _settings_menu() -> Node:
	var sc := get_tree().current_scene
	if sc != null:
		var m := sc.find_child("SettingsMenu", true, false)
		if m != null:
			return m
	return get_node_or_null("../../SettingsMenu")


func _on_menu_opened(open: bool) -> void:
	if open and _using:
		print("[小游戏] 设置菜单开了，坦克动荡让位（关掉小游戏）")
		_close()


# ══════════════ 建模 ══════════════

func _build() -> void:
	position = ARCADE_POS
	rotation_degrees = Vector3(0.0, YAW_DEG, 0.0)

	var body := _mat(COLOR_BODY, 0.55, 0.10)
	var panel := _mat(COLOR_PANEL, 0.42, 0.25)
	var metal := _mat(COLOR_METAL, 0.30, 0.85)
	var accent := _mat(COLOR_ACCENT, 0.30, 0.0)
	accent.emission_enabled = true
	accent.emission = COLOR_ACCENT
	accent.emission_energy_multiplier = 1.6

	var half_d := BODY_D * 0.5

	# ⚠️ 本地坐标约定（**别再改**）：+X = 宽、+Y = 高、+Z = **正面**。
	#    父节点再绕 Y 转 90°，让「正面」对上世界 +X（正对走道）。
	#
	#    第一版把「进深」放在本地 X 上，于是：
	#      · `PlaneMesh` 绕 X 转 90° 之后**宽度跑到进深轴**上 ⇒ 屏幕侧对着一窄条；
	#      · 操作台的 0.28 m 进深变成横向伸出 ⇒ 竖起来斜挡在屏幕前（实拍那块「黑板」）。
	#    实拍 `_tools/_tmp/esports_arcade2/` 一眼就能看出来，别再犯。

	# ── 柜身 ──
	_box("Body", Vector3(0.0, BODY_H * 0.5, 0.0), Vector3(BODY_W, BODY_H, BODY_D), body)
	# 踢脚线：底部收进去一点，看起来才不像一块砖
	_box("Kick", Vector3(0.0, 0.045, 0.0), Vector3(BODY_W - 0.06, 0.09, BODY_D - 0.06), panel)
	# 正面两侧的灯带（垂直，青色）
	for sx in [-1.0, 1.0]:
		_box("Strip%s" % ("L" if sx < 0.0 else "R"),
			Vector3(float(sx) * (BODY_W * 0.5 - 0.035), 1.05, half_d - 0.004),
			Vector3(0.020, 1.05, 0.010), accent)

	# ── 屏幕框 ──
	_box("Bezel", Vector3(0.0, SCREEN_Y, half_d - 0.006),
		Vector3(SCREEN_SIZE.x + 0.075, SCREEN_SIZE.y + 0.075, 0.026), panel)
	# 屏幕衬板：一圈比屏幕略大的深色板，屏幕贴在最外层
	_box("ScreenBack", Vector3(0.0, SCREEN_Y, half_d + 0.002),
		Vector3(SCREEN_SIZE.x + 0.010, SCREEN_SIZE.y + 0.010, 0.008), body)

	# ── 屏幕本体：SubViewport 贴到一块 PlaneMesh 上 ──
	tank_viewport = SubViewport.new()
	tank_viewport.name = "TankViewport"
	tank_viewport.size = TANK_SIZE
	tank_viewport.transparent_bg = false
	tank_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tank_viewport.handle_input_locally = false
	add_child(tank_viewport)

	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_texture = tank_viewport.get_texture()
	# 屏幕是自发光的，不该被房间灯影响
	_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_mat.emission_enabled = true
	_screen_mat.emission_texture = tank_viewport.get_texture()
	_screen_mat.emission_energy_multiplier = 0.75
	_screen_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

	# `PlaneMesh` 的 size 是 (x 沿本地 X, y 沿本地 Z)，法线 +Y。
	# 绕 X 转 +90° 后：法线 → +Z（正面 ✓）、size.y 那一维 → 本地 Y（高度 ✓）。
	# 所以 `plane.size = SCREEN_SIZE` 正好是「宽 0.62 × 高 0.496」。
	var plane := PlaneMesh.new()
	plane.size = SCREEN_SIZE
	var scr := MeshInstance3D.new()
	scr.name = "Screen"
	scr.mesh = plane
	scr.material_override = _screen_mat
	scr.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	scr.position = Vector3(0.0, SCREEN_Y, half_d + 0.008)
	add_child(scr)

	# 待机画面：还没按过 F 的时候屏幕上写一句提示（`_open()` 时藏掉）。
	# ⚠️ Control 直接挂进 SubViewport 时**锚点没有父 Control 可参照**，
	#    `PRESET_FULL_RECT` 算不出尺寸 ⇒ size 还是 0，文字被裁成半截
	#    （第一版实拍就是「开始 / 动荡」缺字）。所以下面**显式给 size**。
	# ⚠️ 用 `Node2D` 自绘，**不要**用 `Label`：`Control` 直接挂进 `SubViewport` 时
	#    没有父 `Control` 可参照，实测 `PRESET_FULL_RECT` 拿到的是 2000×1600 的父矩形
	#    （根窗口有 2× 内容缩放），文字被推到 1000×800 画布外面 —— 柜子屏幕上全黑。
	#    `Node2D._draw()` 走画布像素坐标，不受锚点影响。
	_attract = _AttractScreen.new()
	_attract.name = "Attract"
	_attract.font = _pixel_font()
	tank_viewport.add_child(_attract)

	# ── 招牌（屏幕上方那条会亮的灯箱）──
	_box("Marquee", Vector3(0.0, 1.695, half_d - 0.030),
		Vector3(BODY_W - 0.05, 0.215, 0.070), accent)
	var sgn := Label3D.new()
	sgn.name = "MarqueeLabel"
	sgn.text = "坦克动荡"
	sgn.font = _pixel_font()
	sgn.font_size = 48
	sgn.pixel_size = 0.0035
	sgn.modulate = Color(0.06, 0.09, 0.14)
	sgn.outline_size = 0
	# `Label3D` 默认就朝本地 +Z（= 正面），**不要再额外转 90°** ——
	# 第一版多转了那一下，实拍里招牌字是反的。
	sgn.position = Vector3(0.0, 1.695, half_d + 0.008)
	add_child(sgn)

	# ── 操作台：一块朝人这边下斜的台面 + 摇杆 + 三个按钮 ──
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(BODY_W - 0.08, 0.045, 0.30)
	deck.mesh = deck_mesh
	deck.material_override = panel
	deck.position = Vector3(0.0, 1.005, half_d + 0.070)
	# 绕 X 转 **正** 14°：本地 +Z（前缘）会往下掉，正好是街机台面的斜度
	deck.rotation_degrees = Vector3(14.0, 0.0, 0.0)
	add_child(deck)

	# 摇杆：底座 + 杆 + 球
	var stick_base := MeshInstance3D.new()
	stick_base.name = "StickBase"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.042
	cyl.bottom_radius = 0.048
	cyl.height = 0.026
	stick_base.mesh = cyl
	stick_base.material_override = metal
	stick_base.position = Vector3(-0.20, 1.048, half_d + 0.060)
	add_child(stick_base)
	var shaft := MeshInstance3D.new()
	shaft.name = "StickShaft"
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.011
	shaft_mesh.bottom_radius = 0.013
	shaft_mesh.height = 0.085
	shaft.mesh = shaft_mesh
	shaft.material_override = metal
	shaft.position = Vector3(-0.20, 1.090, half_d + 0.060)
	add_child(shaft)
	var knob := MeshInstance3D.new()
	knob.name = "StickKnob"
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.030
	knob_mesh.height = 0.060
	knob.mesh = knob_mesh
	knob.material_override = _mat(Color(0.85, 0.30, 0.35), 0.35, 0.0)
	knob.position = Vector3(-0.20, 1.138, half_d + 0.060)
	add_child(knob)

	# 三个按钮：红 / 黄 / 蓝，跟街机的感觉对上
	var btn_cols := [Color(0.88, 0.32, 0.34), Color(0.95, 0.76, 0.30), Color(0.34, 0.62, 0.92)]
	for i in 3:
		var btn := MeshInstance3D.new()
		btn.name = "Button%d" % i
		var bm := CylinderMesh.new()
		bm.top_radius = 0.024
		bm.bottom_radius = 0.026
		bm.height = 0.020
		btn.mesh = bm
		var bmat := _mat(btn_cols[i], 0.32, 0.0)
		bmat.emission_enabled = true
		bmat.emission = btn_cols[i]
		bmat.emission_energy_multiplier = 0.55
		btn.material_override = bmat
		btn.position = Vector3(0.02 + float(i) * 0.075, 1.048, half_d + 0.060)
		add_child(btn)

	# ── 投币口 ──
	_box("CoinPlate", Vector3(0.0, 0.66, half_d + 0.004),
		Vector3(0.20, 0.13, 0.012), metal)
	_box("CoinSlot", Vector3(0.0, 0.68, half_d + 0.012),
		Vector3(0.014, 0.045, 0.006), _mat(Color(0.05, 0.05, 0.06), 0.5, 0.2))

	# ── 屏幕冷光：让柜子附近有一点蓝白反光，远处也能看见这是什么 ──
	_glow = OmniLight3D.new()
	_glow.name = "ScreenGlow"
	_glow.position = Vector3(0.0, SCREEN_Y + 0.10, half_d + 0.55)
	_glow.light_color = Color(0.55, 0.78, 0.98)
	_glow.light_energy = 0.55
	_glow.omni_range = 2.6
	_glow.shadow_enabled = false
	add_child(_glow)

	_build_ui()


func _pixel_font() -> Font:
	# 工程自带的 Fusion Pixel 中文像素字体（7 MB，支持汉字）
	if ResourceLoader.exists("res://assets/ui/font.ttf"):
		return load("res://assets/ui/font.ttf") as Font
	return null


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


# ══════════════ 界面 ══════════════

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "ArcadeUI"
	# 45 层：压过 HUD（10）和设置菜单（10）；小屋电脑是 40，两边不会同时开，
	# 但万一真撞上，小游戏在上一层层叠观感更对。
	_layer.layer = 45
	add_child(_layer)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "按 F 玩「坦克动荡」"
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("shadow_offset_x", 2)
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-110, -150)
	_hint.visible = false
	_layer.add_child(_hint)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_layer.add_child(_overlay)

	# 黑底：画面是 5:4，窗口是 16:9，两边留黑边比拉伸好看
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color(0.015, 0.018, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(bg)

	_wide = TextureRect.new()
	_wide.name = "TankTexture"
	_wide.texture = tank_viewport.get_texture()
	# ⚠️ 1000×800 是 5:4，窗口 16:9 —— 必须 `KEEP_ASPECT_CENTERED` 留黑边。
	#    拉满会让坦克和迷宫全扁掉，手机触控那套坐标也全按 1000×800 写的。
	_wide.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wide.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_wide)

	_foot = Label.new()
	_foot.name = "Footer"
	_foot.text = "WASD 移动 · 空格/J 开火 · Esc 暂停 · G 退出小游戏"
	_foot.add_theme_font_size_override("font_size", 15)
	_foot.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	_foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_foot.offset_top = -40
	_foot.offset_left = -360
	_foot.offset_right = 360
	_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_foot)


# ══════════════ 交互 ══════════════

func _player_node() -> Node3D:
	if is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


## 人该站的位置：柜子正前方 0.55 m 处（本地 +Z 再往外一点）
func _use_point() -> Vector3:
	return to_global(Vector3(0.0, 0.0, BODY_D * 0.5 + 0.55))


func _physics_process(_delta: float) -> void:
	if _using:
		return
	var p := _player_node()
	if p == null:
		return
	var d := p.global_position - _use_point()
	var flat := Vector2(d.x, d.z).length()
	var near := flat <= USE_RADIUS and absf(d.y) <= USE_DY_MAX
	if near != _in_range:
		_in_range = near
		_hint.visible = near


func _input(event: InputEvent) -> void:
	# ── 小游戏开着：键盘 / 鼠标**全部**转给小游戏 ──
	# 退出键用 `G`：Esc 在小游戏里是暂停，而 G 不在它的键位表（WASD/空格/J/Z）里。
	if _using:
		var tk := event as InputEventKey
		if tk != null and tk.pressed and not tk.echo and tk.keycode == KEY_G:
			_close()
			get_viewport().set_input_as_handled()
			return
		if tank != null and is_instance_valid(tank):
			var tm := event as InputEventMouse
			if tm != null:
				# 鼠标坐标换算成 1000×800 画布坐标（覆盖层 16:9，画布 5:4 居中）
				var dup := event.duplicate() as InputEventMouse
				dup.position = _to_tank_canvas(tm.position)
				dup.global_position = dup.position
				tank.call("feed", dup)
			else:
				tank.call("feed", event)
		get_viewport().set_input_as_handled()
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F and _in_range:
		_open()
		get_viewport().set_input_as_handled()


## 窗口坐标 → 小游戏画布坐标（1000×800）。
## `_wide` 是 `KEEP_ASPECT_CENTERED`，先按「等比缩放 + 居中」求实际显示区再换算。
func _to_tank_canvas(p: Vector2) -> Vector2:
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


func is_open() -> bool:
	return _using


func in_range() -> bool:
	return _in_range


## 第一次按 F 才 load 那 3.4 MB（6 张立绘 + 85 KB 脚本），不给整局开机添负担。
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


func _open() -> void:
	if _using:
		return
	if not _ensure_tank():
		return
	_using = true
	_in_range = false
	_hint.visible = false
	_attract.visible = false
	_overlay.visible = true
	tank.call("release_all")
	var p := _player_node()
	if p != null:
		if p is CharacterBody3D:
			(p as CharacterBody3D).velocity = Vector3.ZERO
		p.set_physics_process(false)
		p.set_process(false)
		p.set_process_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_duck_room_music(true)
	Sfx.play("ui_open", -6.0)
	print("[小游戏] 打开坦克动荡（五人模式 · 音乐仍由电竞房播放，音量压到 %d%%）"
		% int(BGM_GAIN * 100.0))


func _close() -> void:
	if not _using:
		return
	_using = false
	if tank != null and is_instance_valid(tank) and tank.has_method("release_all"):
		tank.call("release_all")
	_overlay.visible = false
	_hint.visible = _in_range
	var p := _player_node()
	if p != null:
		p.set_physics_process(true)
		p.set_process(true)
		p.set_process_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_duck_room_music(false)
	Sfx.play("ui_close", -6.0)
	print("[小游戏] 关掉坦克动荡")


## 电竞房 BGM 让一让：只碰 `music.gd` 建在 `root/MusicHost/Bgm` 的那个播放器，
## 进出各改一次，关的时候原样还原。
##
## ⚠️ 不往 `music.gd` 里加 API：那个文件经常有别的会话在改（`git status` 里时不时是 M）。
## ⚠️ `Music` 是**静态类**，`Music.get("_player")` 会直接报
##    「Cannot call non-static function "get()" on the class "Music" directly」，
##    所以按节点树找。找不到就静默跳过 —— 压不了音量不影响玩。
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

func open_for_test() -> void:
	_open()


func close_for_test() -> void:
	_close()


func screen_mesh() -> MeshInstance3D:
	return get_node_or_null("Screen") as MeshInstance3D


func use_point() -> Vector3:
	return _use_point()


## 待机画面：屏幕上那句「坦克动荡 / 按 F 开始」。
##
## 单独写成内部类是因为它要 `_draw()` —— 见 `_build()` 里那段为什么不用 `Label`。
class _AttractScreen extends Node2D:
	var font: Font

	func _draw() -> void:
		var w := 1000.0
		var h := 800.0
		# 底色比柜身的黑略亮一点，屏幕才看得出「亮着」
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.045, 0.055, 0.085))
		var f: Font = font if font != null else ThemeDB.fallback_font
		if f == null:
			return
		# 标题
		draw_string(f, Vector2(0.0, 300.0), "坦克动荡",
			HORIZONTAL_ALIGNMENT_CENTER, w, 120, Color(0.82, 0.93, 1.0))
		# 提示
		draw_string(f, Vector2(0.0, 460.0), "按 F 开始",
			HORIZONTAL_ALIGNMENT_CENTER, w, 64, Color(0.55, 0.78, 0.98))
		# 底下一行操作说明
		draw_string(f, Vector2(0.0, 640.0), "WASD 移动 · 空格/J 开火",
			HORIZONTAL_ALIGNMENT_CENTER, w, 32, Color(0.40, 0.52, 0.66))
