class_name HutComputer
extends Node3D
## 小屋桌子上的**电脑**：显示器 + 键盘 + 按 F 使用的假 Arch Linux 终端。
##
## 用户 2026-10-22：「现在先在那个召唤同伴屋子里面不是有桌子吗，上面放个显示器，
## 椅子可以坐上去，然后可以使用电脑，就是弹出这个 ARCH LINUX 主题，按 F 使用，
## 再按 F 退出」。
##
## ⚠️ 「再按 F 退出」这条**2026-11-12 已废**：用户当天反馈「不能用 F 取消，因为输入
##    不了命令」—— F 在把按键转给终端之前就把电脑关了，等于**字母 f 打不进终端**，
##    `neofetch`/`df`/`sudo` 全废。所以现在**打开**还是 F（人没在用时），
##    **退出**改成 `Esc` / `Ctrl+Q` / `exit` 命令，见 `_input()` 里那段注释。
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

## 坐姿：人挪到凳子上（小屋局部坐标），摄像机降到这个高度。
## 凳子坐面 (-0.6, 0.60, -1.3)；摄像机从站姿 1.35 降到 1.05。
const SEAT_LOCAL := Vector3(-0.6, 0.0, -1.30)
const SEAT_EYE_Y := 1.05

## 终端画布尺寸。
##
## ⚠️ **必须是 16:9**（2026-11-13 用户实测：「现在的 ARCH LINUX 太胖了」）。
##    原来是 832×664（1.25:1），而窗口/全屏是 1.75~1.78:1，`STRETCH_SCALE`
##    把它横向拉宽约 40% —— 字被拉扁成「胖字」。现在画布跟窗口同比例，
##    而且**屏幕直接铺满整个窗口**（外框已去掉），拉伸几乎为 1。
##
## 100 列 × 8 px = 800 px 的正文只占 1280 里的 63%，
## 右边 37% 是**留给阿洛娜 / 普拉娜的立绘区**（见 `arch_terminal.gd` 的同伴一节）。
const VP_SIZE := Vector2i(1280, 720)

## ── 坦克动荡 ──
## 逻辑尺寸（它的 `W` / `H`）。改这里必须同步改 `tank_main.gd` 的同名常量。
const TANK_SIZE := Vector2i(1000, 800)
const TANK_SCENE := "res://scripts/tank_turmoil/tank_main_scene.tscn"
## 小游戏开着时，电竞房 BGM 压到原来的多少倍（用户 2026-11-14：「小游戏音效，电竞房音乐」——
## 音乐继续放、音量让一点，好让枪声 / 爆炸听得见）。
const TANK_BGM_GAIN := 0.45

var terminal: ArchTerminal
var viewport: SubViewport
## 假 B 站窗口（终端敲 `bilibili` 打开）
var bili: BiliBrowser
## 假浏览器（终端敲 `archlinux` 打开，画的是 archlinux.org 首页）
var web: ArchWeb

## ── 坦克动荡小游戏（2026-11-14）──
## 用户：「能不能内置到爱丽丝梦游长理的电竞房当小游戏」→ 做在**小屋这台电脑**上。
##
## 为什么不开独立窗口：它自己的 `project.godot` 带 `window/size/mode=2`（最大化），
## 一旦当成独立场景跑就会弹一个全屏窗口抢前台。塞进 `SubViewport` 之后
## **一行窗口代码都不需要**，画面直接贴到桌上显示器 + 全屏覆盖层。
##
## 资源：`scripts/tank_turmoil/`（代码 85 KB）+ `assets/tank_turmoil/`（立绘 + 音效 3.4 MB）。
## **37.9 MB 的曲库、3.2 MB 的开场视频、284 MB 的导出产物全都没搬进来。**
var tank: Node2D
## 坦克动荡专用 viewport。尺寸必须是 **1000 × 800**（游戏逻辑尺寸写死在这个比例），
## 和终端那个 1280 × 720 分开 —— 混用一个会把小游戏拉变形。
var tank_viewport: SubViewport
## ⚠️ 阿洛娜 / 普拉娜 **不再挂在这里**。
##
## 用户 2026-11-12 中途改了设计：「arona 这个，**不是新开一个界面**，
## 而是**直接在 arch 右半部分显现，遮住系统**，她的对话也通过终端发送」。
## 所以她们现在是 `arch_terminal.gd` 里「屏幕里的同伴」那一节（`summon()`），
## 由终端自己画 —— 不再是盖在终端上面的独立页面。
##
## `arona_stage.gd`（3D 版）/ `arona_page.gd` / `plana_page.gd` 三个文件**留在仓库里**，
## 只是**不再实例化**（3D 舞台还会载入 arona.glb、多占一份显存）。
## 哪天想回到「整屏 3D」的版本，把 `_build()` 里那几行接回来即可。

var _using := false
var _in_range := false
var _player: Node3D
var _seated := false
var _saved_xform := Transform3D()
var _saved_rig_y := 1.35
var _layer: CanvasLayer
var _overlay: Control
var _screen: TextureRect
var _hint: Label
## 底部那行「Esc 或 Ctrl+Q 退出电脑…」。页面（B 站 / 浏览器）开着的时候要藏起来：
## 那时候 Esc 是「退出这个页面」而不是「退出电脑」，两句话放一起会互相矛盾，
## 而且它会压在页面内容上（实拍图里正好盖住包名那几行）。
var _foot: Label
var _beam: OmniLight3D
## 坦克动荡的状态
var _tank_wide: Control
var _tank_foot: Label
var _tank_using := false
## 打开小游戏前显示器那块材质（关掉时要换回去）
var _screen_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("hut_computer")
	_build()
	# 兜底：设置菜单一开就把电脑合上（正常路径下永远不会触发，理由见 `_on_menu_opened`）。
	var menu := _settings_menu()
	if menu != null and menu.has_signal("opened_changed") \
			and not menu.is_connected("opened_changed", _on_menu_opened):
		menu.opened_changed.connect(_on_menu_opened)


## 找设置菜单。**不用 `../../SettingsMenu` 这种硬路径** —— 探针里单独 instance
## 小屋时那棵树是断的。先找当前场景，再退回按树干往上数两级。
func _settings_menu() -> Node:
	var sc := get_tree().current_scene
	if sc != null:
		var m := sc.find_child("SettingsMenu", true, false)
		if m != null:
			return m
	return get_node_or_null("../../SettingsMenu")


## 设置菜单开了 ⇒ 立刻合上电脑。
##
## 正常路径下这条**不会触发**：终端开着时 Esc 由设置菜单主动让给终端
## （见 `settings_menu.gd::_input()` 里那段），菜单根本开不起来。
## 留着是因为层号差得太远 —— 电脑这层 CanvasLayer 是 **40**、设置菜单是 **10**，
## 万一以后菜单能从别的入口打开（快捷键、脚本、剧情演出），终端就会**盖在菜单上面**，
## 用户 2026-10-26 实拍到的正是这个画面。宁可多合一次电脑，也不要那种画面。
func _on_menu_opened(open: bool) -> void:
	if open and _tank_using:
		print("[小游戏] 设置菜单开了，坦克动荡让位（关掉小游戏）")
		_close_tank()
	elif open and _using:
		print("[电脑] 设置菜单开了，终端让位（合上电脑）")
		_close()


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
	# ⚠️ **必须给屏幕一个独立 World3D**：`SubViewport` 默认共用父场景的世界，
	#    而阿洛娜那台 3D 相机就挂在这个 viewport 里 —— 不隔离的话，
	#    屏幕上会把整个校园/小屋一起渲染出来（终端那些 Control 只是盖在上面）。
	viewport.own_world_3d = true
	add_child(viewport)

	terminal = ArchTerminal.new()
	terminal.name = "ArchTerminal"
	# PRESET_FULL_RECT 会让它跟着 SubViewport 的尺寸走（832×664），
	# 不要再手动设 size —— 锚点布局会覆盖掉，设了反而让人误以为是它在起作用。
	terminal.set_anchors_preset(Control.PRESET_FULL_RECT)
	terminal.exit_requested.connect(_close)
	terminal.open_bili_requested.connect(_open_bili)
	viewport.add_child(terminal)

	# 假 B 站（`bilibili` 命令打开）。**必须放同一个 SubViewport** ——
	# 终端画面是「一份内容、两处显示」（桌上显示器的材质 + 全屏覆盖层），
	# 放外面就只有覆盖层看得到、桌上那台显示器还是终端。
	bili = BiliBrowser.new()
	bili.name = "BiliBrowser"
	bili.set_anchors_preset(Control.PRESET_FULL_RECT)
	bili.visible = false
	bili.close_requested.connect(_close_bili)
	viewport.add_child(bili)

	# 假浏览器（`archlinux` 命令打开）。也放同一个 SubViewport、盖在 bili 之上：
	# 两个页面同一时刻只会开一个，谁在上都不要紧，但层级要稳定。
	terminal.open_web_requested.connect(_open_web)
	web = ArchWeb.new()
	web.name = "ArchWeb"
	web.set_anchors_preset(Control.PRESET_FULL_RECT)
	web.visible = false
	web.close_requested.connect(_close_web)
	viewport.add_child(web)

	# 坦克动荡（2026-11-14）：自己一个 1000×800 的 SubViewport。
	# 开关**懒做** —— 第一次按 G 才把 85 KB 的脚本 + 6 张立绘 load 进来，
	# 不给整局开机时间添负担（`PLAN.md` 第 1 条就是嫌启动慢）。
	tank_viewport = SubViewport.new()
	tank_viewport.name = "TankViewport"
	tank_viewport.size = TANK_SIZE
	tank_viewport.transparent_bg = false
	tank_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tank_viewport.handle_input_locally = false
	add_child(tank_viewport)

	# 阿洛娜 / 普拉娜：**不在这里建**。她们由终端自己画在右半屏
	# （见本文件 `bili` 变量上面那段说明，以及 `arch_terminal.gd` 的
	#  「屏幕里的同伴」一节）。这里只保证 bili 之后没有别的全屏层。

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
	_hint.text = "按 F 使用电脑 · 按 G 玩坦克动荡"
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

	# 屏幕：**直接铺满整个窗口，不要外框**
	#
	# ⚠️ 2026-11-13 用户（附实拍图）：「还要扩大，占满整个窗口，不要屏幕旁边那个框了，
	#    直接就是屏幕满占窗口」。所以原来那圈 8 px 深灰边 + 16 px 内缩 + 圆角
	#    **整块删掉**，`ScreenTexture` 直接贴在 Overlay 上、offset 全 0。
	#    画布本身也换成 16:9（见 `VP_SIZE`），否则会被横向拉宽成「胖字」。
	_screen = TextureRect.new()
	_screen.name = "ScreenTexture"
	_screen.texture = viewport.get_texture()
	# `STRETCH_SCALE` 铺满；画布已是 16:9，和窗口比例基本一致，几乎没有拉伸
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_screen)

	# 底部提示行：**用终端那套等宽字体**（用户 2026-11-12：
	# 「退出提示也在下面用 arch 风格字体」）。原来走的是默认 UI 字体，和终端不一套。
	var foot := Label.new()
	_foot = foot
	foot.name = "Footer"
	foot.text = "Esc 或 Ctrl+Q 退出电脑（也可以直接输入 exit）· 键盘可以正常打字"
	foot.add_theme_font_size_override("font_size", 15)
	foot.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	# 终端字体（等宽，ASCII 干净）；找得到就换成它，中文靠系统字体回退
	var term_font := _terminal_font()
	if term_font != null:
		foot.add_theme_font_override("font", term_font)
	foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	foot.offset_top = -40
	foot.offset_left = -320
	foot.offset_right = 320
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(foot)

	# ── 坦克动荡的全屏画面（2026-11-14）──
	# 和终端用同一套「一份画布、两处显示」：这里这块只负责全屏覆盖，
	# 桌上那台显示器在 `_open_tank()` 里临时换成这块纹理。
	# ⚠️ 1000 × 800 是 5:4，窗口是 16:9 —— 用 `STRETCH_KEEP_ASPECT_CENTERED` 留黑边，
	#    不能拉满，否则坦克和迷宫全被拉扁（手机触控那套坐标也全是按 1000×800 写的）。
	var wide := TextureRect.new()
	_tank_wide = wide
	wide.name = "TankTexture"
	wide.texture = tank_viewport.get_texture()
	wide.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wide.set_anchors_preset(Control.PRESET_FULL_RECT)
	wide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wide.visible = false
	_overlay.add_child(wide)

	# 坦克动荡的底部提示（盖在终端那行上面，两个不会同时可见）
	var tank_foot := Label.new()
	_tank_foot = tank_foot
	tank_foot.name = "TankFooter"
	tank_foot.text = "WASD 移动 · 空格/J 开火 · Esc 暂停 · G 退出小游戏"
	tank_foot.add_theme_font_size_override("font_size", 15)
	tank_foot.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	if term_font != null:
		tank_foot.add_theme_font_override("font", term_font)
	tank_foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tank_foot.offset_top = -40
	tank_foot.offset_left = -360
	tank_foot.offset_right = 360
	tank_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tank_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tank_foot.visible = false
	_overlay.add_child(tank_foot)


## 终端用的等宽字体。和 `arch_terminal.gd::_pick_font()` 同一套优先级：
## 优先找真正的等宽字体（Arch 风格界面就该等宽），找不到再退回 CJK 字体。
##
## ⚠️ 这就是用户说的「arch 的字体是不是有一点点乱了」的根源：
##    原来两边都拿 `assets/ui/font.ttf`（Fusion Pixel 中文像素字体）——
##    它的**西文字宽不是等宽的**，和终端里 8 px 的字符格对不上，
##    画一行 ASCII 就会东倒西歪；中文倒是没问题。
##    所以先找 `assets/ui/mono.ttf`（往这儿丢任何等宽字体即可），
##    没有才退回原来的 CJK 字体（中文照常显示，只是西文会略歪）。
const MONO_CANDIDATES := [
	"res://assets/ui/mono.ttf",
	"res://assets/ui/LiberationMono-Regular.ttf",
	"res://assets/ui/JetBrainsMono-Regular.ttf",
]


func _terminal_font() -> Font:
	for p in MONO_CANDIDATES:
		if ResourceLoader.exists(p):
			return load(p) as Font
	# 退回终端现在实际在用的那一份（保持两边一致）
	var t := terminal
	if t != null and t.has_method("terminal_font"):
		return t.call("terminal_font")
	return null


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
	# ── 坦克动荡开着：键盘 / 鼠标**全部**转给小游戏，这里一个键都不留 ──
	# ⚠️ 退出键用 `G`（不是 Esc）：Esc 在小游戏里是「暂停」。
	#    `G` 在小游戏的键位表里没有（`P1_KEYS` 只有 WASD/空格/J/Z），所以不会误伤。
	if _tank_using:
		var tk := event as InputEventKey
		if tk != null and tk.pressed and not tk.echo and tk.keycode == KEY_G:
			_close_tank()
			get_viewport().set_input_as_handled()
			return
		if tank != null and is_instance_valid(tank):
			# 鼠标坐标要换算成 1000×800 画布坐标（覆盖层是 16:9，画布是 5:4 居中留黑边）
			var tm := event as InputEventMouse
			if tm != null:
				var dup := event.duplicate() as InputEventMouse
				dup.position = _to_tank_canvas(tm.position)
				dup.global_position = dup.position
				tank.call("feed", dup)
			else:
				tank.call("feed", event)
		get_viewport().set_input_as_handled()
		return
	# ── 鼠标滚轮：转给终端翻历史 ──
	# 用户 2026-11-13：「怎么不能滚轮滑动」。原来这段第一句就是
	# `event as InputEventKey`，鼠标事件当场被判成 null 丢掉，滚轮永远到不了终端。
	# 现在先单独接滚轮（终端里是 `_scroll_by()`）。
	if _using:
		# ── 鼠标 ──
		# 假浏览器要能**点链接**，可 `SubViewport` 的 `handle_input_locally = false`
		# （GUI 事件根本送不进去），所以这里手动把窗口坐标换算成画布坐标再转给页面。
		# 顺带把滚轮也交给它（翻页面 / 翻终端历史）。
		var me := event as InputEventMouse
		if me != null:
			if web != null and web.visible:
				var c := event.duplicate() as InputEventMouse
				c.position = _to_canvas(me.position)
				c.global_position = c.position
				web.feed(c)
				get_viewport().set_input_as_handled()
				return
			var mb := event as InputEventMouseButton
			if mb != null and mb.pressed and not (bili != null and bili.visible) \
					and (mb.button_index == MOUSE_BUTTON_WHEEL_UP
						or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
				terminal.feed(event)      # B 站页面不吃滚轮，终端才要
				get_viewport().set_input_as_handled()
				return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if _using:
		# 鼠标之类的先吃掉，键盘全部转给终端
		#
		# ⚠️⚠️ 2026-11-12 用户：「电脑取消，不能用 F 取消因为输入不了命令」——
		#    原来这里有一句 `if k.keycode == KEY_F: _close()`，而且**在转给终端之前**就
		#    把电脑关了。后果不是「退出不方便」，而是**字母 f 根本打不进终端**：
		#    `neofetch` / `df` / `sudo` / `clear` 里凡是带 f 的，敲到 f 就整台电脑被关掉。
		#    所以这里**不再用单个字母当退出键**（任何可打印字符都会有同样的毛病）。
		#
		# 现在退出电脑的三条路（都不占可打印字符）：
		#   · `Esc`      —— 终端自己 `exit_requested`；页面里先退一层
		#   · `Ctrl+Q`   —— 任何页面下直接关（这里处理）
		#   · `exit` / `logout` 命令
		if k.ctrl_pressed and k.keycode == KEY_Q:
			_close()
			get_viewport().set_input_as_handled()
			return
		# 页面开着的时候，按键归页面 —— 否则方向键会被终端当成输入字符。
		# 顺序按**层级**来：假浏览器盖在 B 站上面，所以先问它。
		if web != null and web.visible:
			web.feed(event)
		elif bili != null and bili.visible:
			bili.feed(event)
		else:
			terminal.feed(event)
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_F and _in_range:
		_open()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_G and _in_range:
		_open_tank()
		get_viewport().set_input_as_handled()


## 窗口坐标 → 小游戏画布坐标（1000×800）。
## 覆盖层里那块 `TankTexture` 是 `STRETCH_KEEP_ASPECT_CENTERED`（留黑边），
## 所以要先按「等比缩放 + 居中」求实际显示区，再换算。
func _to_tank_canvas(p: Vector2) -> Vector2:
	if _tank_wide == null:
		return p
	var r := _tank_wide.get_global_rect()
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return p
	var scale := minf(r.size.x / float(TANK_SIZE.x), r.size.y / float(TANK_SIZE.y))
	if scale <= 0.0:
		return p
	var shown := Vector2(TANK_SIZE) * scale
	var origin := r.position + (r.size - shown) * 0.5
	return (p - origin) / scale


## 窗口/画布坐标 → 终端画布坐标（1280×720）。
## 屏幕那块 `TextureRect` 是铺满整个覆盖层的，所以按它的 rect 等比换算即可。
func _to_canvas(p: Vector2) -> Vector2:
	if _screen == null:
		return p
	var r := _screen.get_global_rect()
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return p
	return (p - r.position) / r.size * Vector2(VP_SIZE)


# ══════════════════ 坦克动荡（2026-11-14）══════════════════
#
# 用户：「能不能内置到爱丽丝梦游长理的电竞房当小游戏」→
#      「不并入音乐，全程同步电竞房音乐，五人模式大地图，主角爱丽丝」。
#
# ── 为什么做在**小屋**这台电脑上，而不是电竞房 ──
# 电竞房工位那排显示器是 GLB 里的纯网格（`models/esports_room/esports_room.glb`
# 合并出来的材质桶），**没有控制器**：想在上面跑小游戏得先挑一台显示器、量出它的
# 世界包围盒、再挂 `SubViewport`，而且整间屋是 `Y=-1` 翻转 + 1.5 倍缩放的，
# 坐标要重新算。小屋这台电脑现成有「靠近提示 + 按 F 坐下 + 输入让位」三条通路，
# 复用它们风险最低。**以后想搬进电竞房**：把 `_open_tank()` / `_close_tank()` 整段
# 搬进 `esports_collision.gd` 或新写一个 `esports_arcade.gd`，逻辑不用改。

func is_tank_open() -> bool:
	return _tank_using


## 第一次按 G 才 load 这 3.4 MB 资源（不给整局开机添负担）。
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


## 打开小游戏：和打开终端一样要「坐下 + 让出输入 + 放出鼠标」，但画面换一块。
func _open_tank() -> void:
	if _tank_using or _using:
		return
	if not _ensure_tank():
		return
	_tank_using = true
	_hint.visible = false
	_overlay.visible = true
	_screen.visible = false
	_foot.visible = false
	_tank_wide.visible = true
	_tank_foot.visible = true
	# 桌上那台显示器也切成小游戏画面（不然贴着看还是终端）
	var scr := get_node_or_null("Screen") as MeshInstance3D
	if scr != null:
		_screen_mat = scr.material_override as StandardMaterial3D
		if _screen_mat != null:
			# ⚠️ 复制一份再改：`material_override` 是共享资源，直接改会把终端那块也换掉
			var m: StandardMaterial3D = _screen_mat.duplicate()
			m.albedo_texture = tank_viewport.get_texture()
			m.emission_texture = tank_viewport.get_texture()
			scr.material_override = m
	tank.call("release_all")
	_seat()
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
		% int(TANK_BGM_GAIN * 100.0))


## 关掉小游戏：恢复终端那套画面 + 把人和音乐都还回去。
func _close_tank() -> void:
	if not _tank_using:
		return
	_tank_using = false
	if tank != null and is_instance_valid(tank) and tank.has_method("release_all"):
		tank.call("release_all")
	_tank_wide.visible = false
	_tank_foot.visible = false
	_screen.visible = true
	_foot.visible = true
	_overlay.visible = false
	var scr := get_node_or_null("Screen") as MeshInstance3D
	if scr != null and _screen_mat != null:
		scr.material_override = _screen_mat
		_screen_mat = null
	_hint.visible = _in_range
	_stand()
	var p := _player_node()
	if p != null:
		p.set_physics_process(true)
		p.set_process(true)
		p.set_process_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_duck_room_music(false)
	Sfx.play("ui_close", -6.0)
	print("[小游戏] 关掉坦克动荡")


## 电竞房 BGM 让一让（用户 2026-11-14：「小游戏音效，电竞房音乐」）。
##
## **刻意做得很保守**：只碰 `Music` 内部那个播放器的 `volume_db`，进出各改一次，
## 关的时候原样还原。`Music.play()` 在同一首正在放时直接 return，所以下一帧
## `esports_collision.gd::_refresh_music()` 不会把音量顶回去；真换曲了也无所谓 ——
## 那说明玩家已经出了房间，小游戏的声音本来就该更大。
##
## ⚠️ 不往 `music.gd` 里加任何 API：那个文件 2026-11-14 有另一个会话在改
##    （`git status` 里是 M），加东西会撞车。
##
## ⚠️ `Music` 是**静态类**，`Music.get("_player")` 在 GDScript 里会直接报
##    「Cannot call non-static function "get()" on the class "Music" directly」——
##    所以这里**不从 `Music` 里偷播放器**，而是按节点树找它建出来的那个：
##    `music.gd::_ensure_host()` 在 `tree.root` 下挂了 `MusicHost`，子节点叫 `Bgm`。
##    找不到就静默跳过：压不了音量不影响玩，只是枪效会小一点。
var _bgm_saved := false
var _bgm_db := 0.0


func _room_music_player() -> AudioStreamPlayer:
	var player := get_tree().root.get_node_or_null("MusicHost/Bgm") as AudioStreamPlayer
	return player


func _duck_room_music(on: bool) -> void:
	var player := _room_music_player()
	if player == null:
		return
	if on:
		if not _bgm_saved:
			_bgm_db = player.volume_db
			_bgm_saved = true
		player.volume_db = _bgm_db + linear_to_db(TANK_BGM_GAIN)
	elif _bgm_saved:
		player.volume_db = _bgm_db
		_bgm_saved = false


## 终端敲 `bilibili` → 盖上一层假 B 站（终端画面留着，回来还在）

func _open_bili() -> void:
	if bili == null:
		return
	bili.open()
	_sync_footer()
	Sfx.play("ui_open", -8.0)
	print("[电脑] 打开假 B 站（离线 demo，不联网）")


## B 站里按 Esc 退回终端
func _close_bili() -> void:
	if bili == null:
		return
	bili.close()
	_sync_footer()
	Sfx.play("ui_close", -8.0)


## 终端敲 `archlinux` → 盖上假浏览器（画出来的 archlinux.org 首页）
func _open_web() -> void:
	if web == null:
		return
	web.open()
	_sync_footer()
	Sfx.play("ui_open", -8.0)
	print("[电脑] 打开假浏览器（archlinux.org 首页，纯手绘，不联网）")


## 浏览器里按 Esc 退回终端
func _close_web() -> void:
	if web == null:
		return
	web.close()
	_sync_footer()
	Sfx.play("ui_close", -8.0)


## 底部提示行：有页面开着就藏（页面自己底部有说明），回到终端再显示
func _sync_footer() -> void:
	if _foot == null:
		return
	var page_open := (web != null and web.visible) or (bili != null and bili.visible)
	_foot.visible = not page_open


## ⚠️ 2026-11-13：原来的 `_open_arona()` / `_close_arona()` / `_open_plana()` /
##    `_close_plana()` **整组删掉了**。用户当天改的需求是
##    「arona 这个，不是新开一个界面，而是**直接在 arch 右半部分显现**，遮住系统，
##    她的对话也通过终端发送」，所以「切页面 + 把终端藏起来」这套做法不再适用。
##    现在两个人都由 `arch_terminal.gd` 的「屏幕里的同伴」一节就地画
##    （入口 `summon()` / `dismiss()`）。
##
##    想恢复「整屏 3D」：`arona_stage.gd` / `arona_page.gd` / `plana_page.gd`
##    三个文件都还在，重新 `new()` 出来加进 viewport、把信号接上即可。


func _open() -> void:
	if _using:
		return
	_using = true
	_hint.visible = false
	_overlay.visible = true
	_sync_footer()
	terminal.reset()
	_seat()
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


## 把人挪到凳子上。
##
## ⚠️ 用户 2026-10-22 明确「即使是待机动画生硬移动到椅子上也没事」——
##    所以这里**不掰骨、不换动画**，就是把人平移过去 + 摄像机降到坐姿高度。
##    代价：人是站着塞进凳子的（腿会穿模、身体穿靠背），这是用户接受的取舍。
func _seat() -> void:
	var p := _player_node()
	if p == null or _seated:
		return
	_seated = true
	_saved_xform = p.global_transform
	var rig := p.get_node_or_null("CameraRig") as Node3D
	if rig != null:
		_saved_rig_y = rig.position.y
		rig.position.y = SEAT_EYE_Y
	p.global_position = to_global(SEAT_LOCAL)
	p.rotation = Vector3(0.0, 0.0, 0.0)     # 朝 −Z，正对桌子


func _stand() -> void:
	if not _seated:
		return
	_seated = false
	var p := _player_node()
	if p == null:
		return
	p.global_transform = _saved_xform
	var rig := p.get_node_or_null("CameraRig") as Node3D
	if rig != null:
		rig.position.y = _saved_rig_y


func _close() -> void:
	if not _using:
		return
	_using = false
	# 合上电脑时把假 B 站 / 假浏览器收掉、把同伴请走 —— 不然下次开机会直接看到上次的画面
	if bili != null:
		bili.close()
	_close_web()
	if terminal != null and terminal.companion_active():
		terminal.dismiss()
	_overlay.visible = false
	_hint.visible = _in_range
	_stand()
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


## 坦克动荡：探针用（不走距离判定）
func open_tank_for_test() -> void:
	_open_tank()


func close_tank_for_test() -> void:
	_close_tank()


func screen_mesh() -> MeshInstance3D:
	return get_node_or_null("Screen") as MeshInstance3D


# 坐姿说明见 `_seat()`：2026-10-22 用户拍板「即使是待机动画生硬移动到椅子上也没事」，
# 所以是**站着塞进凳子**（腿会穿模），不掰骨、不做 sit 动画。
# 想做得好看，需要真的一条 `Sit` 动画（或允许掰骨：大腿 ~90°、小腿垂下、骨盆降 0.32 m）。
