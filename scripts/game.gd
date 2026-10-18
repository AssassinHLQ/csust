extends Node3D
## 玩法场景总控：把 Player / Weapon / HUD / 高斯泼溅校园接起来，记账击杀。

## 掉到这个高度以下就判定「掉出悬浮平台」，送回出生点（护栏之外的保险）
const FALL_LIMIT := -60.0

## 设计分辨率（project.godot 的 window/size/viewport_*）。见 _fit_render_scale()。
const DESIGN_VIEWPORT := Vector2(1600, 900)

## ── 为什么要把兜底方盒地板挖掉房间那一块 ──
##
## `Floor/Mesh` 的顶面正好在 **y ≈ 0**，而画室609 扫描出来的地面在 **y ≈ 0.03**
## —— 两者**共面**。Compute 后端靠 `depth_rejected = gsplat_depth >
## scene_depth + depth_bias` 决定一个泼溅是不是"在场景不透明几何后面"，
## 共面就意味着扫描地面会被判成"在后面"而**整片剔掉**，露出深色方盒：
## 实测地板上是一片黑洞（`_arisu_captures/_backend_ab/compute.png`）。
##
## 试过并且**否掉**的五条路（前四条有实测图）：
##   1. `depth_bias` 0.05 → 0.5：黑洞没了，但 0.5 m 以内的泼溅会盖住角色腿脚。
##      偏置是**全局一个数**，地板要的和角色要的差一个数量级，调不拢。
##   2. 关掉深度剔除：地板干净了，角色被泼溅整个盖住。
##   3. `Floor/Mesh` 改 `DEPTH_DRAW_DISABLED`：**没用** —— Godot 的不透明深度
##      **预通道**照样把它写进深度缓冲，`scene_depth` 里仍有它；彩色通道还糊住下半屏。
##   4. 整块藏掉 `Floor/Mesh`：房间里的地面完美，**但房间外那片平台没影了**。
##      碰撞体还在，于是玩家走出那扇门之后**站在看不见的地板上**，人又钻进扫描
##      墙壁的背面，画面糊成一坨。这一版就是这样翻的车。
##   5. 整体下压：要让 20 m 外的掠射角也不冲突得压到接近 1 m，门外就成了悬空平台。
##
## 所以只能**挖洞**：保留整块方盒地板，只把房间占位的那一块切掉。
## 房间里靠扫描地面，房间外照旧是方盒平台，两边都不动位置、不悬空、不露馅。
##
## ⚠️ 洞必须跟着房间的**真实朝向**。第一版用房间的**世界轴对齐包围盒**挖，
##    而房间是斜的（`yaw_degrees = 248.6`）：包围盒 23.9 × 27.2 m，房间实际
##    只有 22.6 × 16.8 m —— 包围盒那四个角落在房间外面，既没扫描地面也没方盒
##    地板，于是平台中间破出一大片**真空**（实测图：`_arisu_captures/_gameplay/`
##    里那条"中间空了"的边界）。所以改用 **CSG 布尔减法**，洞是房间自己的
##    那个旋转矩形，和扫描地面严丝合缝。
##
## 场景里的方盒地板（**只是没加载泼溅时的兜底**；碰撞体 Floor/Collision 另算）。
const FLOOR_MESH_PATH := "Floor/Mesh"
## 洞相对房间footprint 的外扩量（米）。**负数 = 洞略小于房间**，让平台和扫描
## 地面重叠一点点：宁可重叠一条 15 cm 的窄边（在墙根，基本看不见），
## 也不要留一条头发丝宽的缝 —— 缝下面就是几百米高的天空。
const FLOOR_HOLE_MARGIN := -0.15
## 想回到"一整块方盒地板"（例如排查别的问题）就把这里改成 false，
## 或启动时加 `-- --solid-floor`。
const CARVE_FALLBACK_FLOOR := true

## ── 「空地」铺地砖（2026-10-18）──
## 用户：「平台中间，高斯泼溅下面很大一片空的地方」→ 又补一句
## **「场地最外面不要填上，因为会有影响跑酷」**。
##
## 现场量到的是：40×40 的平台只有 `albedo_color = (0.21,0.23,0.27)` 一个纯色、
## 没有任何贴图。所以这里**只给平台这一块换材质**，平台外一律不铺 ——
## 掉出平台就该继续往下掉（跑酷的失败判定靠这个），别在外面加地面。
const LOT_TEX := "res://assets/tex/lot_paver.png"
const LOT_TEX_N := "res://assets/tex/lot_paver_n.png"
## 平台贴图重复次数：平台 40 m ÷ 16 = 2.5 m 一次重复，图里是 2×2 块 → 一块砖 1.25 m
const LOT_UV_SCALE := 16.0

## ── 开场剧情（第七节 `story_script.gd` / `dialogue_box.gd`）──
## 剧本文件。想换一段就改这里；也可以只改文件名不管这里 ——
## 找不到它会自动退回 `story/` 目录里**排序第一份**，并打印用了哪一份。
const OPENING_STORY := "res://story/开场.txt"
const STORY_DIR := "res://story/"

## 进关卡要不要自动播开场剧情。
##
## ⚠️ `--script` 模式下**一律不播**（见 `_play_opening()`）：13 套自检各自
##    instantiate 这个场景，一播就把整棵树暂停了，`_verify_settings` 的
##    「初始没有暂停」当场就红。想「进关卡直接开打」用 `-- --story=off`。
const PLAY_OPENING := true

var _floor_carved := false
## 加载成功的房间场地（挖地板洞要用它的世界包围盒）
var _room_scene: SplatScene = null
## `_fit_render_scale` 算出来的**自动上限**（只看窗口尺寸，默认 1.0）
var _auto_scale := 1.0
## 当前画质档位的参数表（`GameSettings.QUALITY` 的一项）。见 `_apply_quality()`。
var _quality: Dictionary = {}

var _player: Player
var _weapon: Weapon
var _hud: CanvasLayer
## 场上所有泼溅场地（现在是校园 + 画室609 两份；按类型收，不写死节点名）
var _splats: Array[SplatScene] = []
## 场上所有 Boss「木桩」（现在是霸王龙优香 + 飞猪优香两位）
var _bosses: Array[Boss] = []
var _companions: Array[Companion] = []
var _spawn := Vector3.ZERO
var _score := 0
var _shots := 0
var _hits := 0
## 输入自检用：累计收到的真实键盘按下事件数（见 _input）。一直 0 就说明
## 按键事件压根没进 Godot，而不是 InputMap 没匹配上。
var _keys_seen := 0


## 输入自检：把「窗口到底有没有拿到前台焦点」打出来，并尽力抢一次前台。
##
## ⚠️ 为什么必须由**游戏自己**报，而不是写个探针去测：
## `Input.action_press()` 与 `Input.parse_input_event()` 都是**直接往 Godot 的
## Input 单例里塞事件**，绕过「操作系统 → 窗口 → Godot」这一整段。所以完全可能
## 「探针里 WASD 走得飞起、真人按下去毫无反应」—— 缺的正是这一段。
## 本喵为此误判过两轮。
##
## 症状特征（用来和别的病因区分）：
##   场上其它角色照常走动/播动画，**只有键鼠没反应**，鼠标也没被捕获
##   ⇒ 游戏逻辑和帧率都正常，纯粹是窗口收不到操作系统的输入事件。
##   对照：物理时间被稀释时（见 _fit_render_scale 的注释）是**所有东西一起变慢**。
##
## 自检运行（`--script`）时不抢前台、也不打印：13 套自检各自开一个窗口，
## 抢前台会互相干扰，而且它们自己会注入事件、不需要焦点。
func _watch_input() -> void:
	if OS.get_cmdline_args().has("--script"):
		return
	_report_input.call_deferred()


## 数「收到的真实按键事件」。
##
## ⚠️ 这是唯一能回答「键盘到底有没有到 Godot」的办法：
## `Input.is_action_pressed()` 为 false 有两种完全不同的原因 ——
##   ① 按键事件压根没进 Godot（操作系统/焦点层面的问题）
##   ② 事件进来了，但 InputMap 没匹配上动作（映射问题）
## 看这个计数就知道是哪种：一直 0 就是①，在涨就是②。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		_keys_seen += 1


func _report_input() -> void:
	for i in 12:
		await get_tree().create_timer(1.0).timeout
		var focus := DisplayServer.window_is_focused()
		var note := ""
		if not focus:
			note = "   ← ⚠️ **窗口没有前台焦点：键鼠都收不到，点一下游戏窗口即可**"
		elif get_tree().paused:
			note = "   ← 游戏被暂停（Esc 设置菜单开着，或正在播剧情对话）"
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			# 自愈：有焦点、没暂停、鼠标却没被捕获 ⇒ 自己收回来。
			# （焦点丢失时 Godot 会把鼠标放出来且**不会自动收回**；player.gd 的
			#   _notification 只在「重新获得焦点」那一刻收，漏了就一直是 VISIBLE。）
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			note = "   ← 有焦点却没捕获，已自动收回 mouse_mode=%d" % Input.mouse_mode
		print("[Game] 输入自检 第 %2d 秒：focused=%s  mouse_mode=%d  paused=%s  累计按键事件=%d" % [
			i + 1, str(focus), Input.mouse_mode, str(get_tree().paused), _keys_seen])
		print("[Game]            └─ Player：%s%s" % [_player_state(), note])


## Player 节点还活不活 —— 这是把「两个症状是不是同一个原因」分开的关键。
##
## 如果 `player.gd` 的 `_ready()` 根本没跑，那么「没捕获鼠标」和「WASD 不动」
## 就是**同一个原因**（脚本没执行）；而如果它活得好好的，两个症状就得分开查。
## 只看鼠标模式是分不出来的 —— 默认值本来就是 0（VISIBLE）。
func _player_state() -> String:
	var pl := get_node_or_null("Player")
	if pl == null:
		return "**节点不存在**"
	var s := "script=%s  is_physics_processing=%s  is_processing_input=%s  vel=%s  pos=%s" % [
		"有" if pl.get_script() != null else "**无**",
		str(pl.is_physics_processing()), str(pl.is_processing_input()),
		str((pl as CharacterBody3D).velocity.snappedf(0.01)),
		str((pl as Node3D).global_position.snappedf(0.01))]
	return s


## 全屏帧率护栏：只有视口面积**远大于**设计分辨率时才缩小 3D 渲染分辨率。
##
## ── 病根订正 ──
## 最初把「全屏后掉到 2 fps → 物理时间被稀释 → WASD 按了不动」归咎于**分辨率**，
## 于是加了「按面积开方缩小 3D 分辨率」这个补丁。后来用
## scripts/_probe_splat_perf.gd（关垂直同步、每档预热 15 帧再连测 40 帧、
## 三档交错重复 3 轮）重测，真凶是 **MSAA 4×**：
##     2560×1334，scale 0.649 + MSAA 4× + 全套后处理 → 54.0 fps（中位）
##     2560×1334，scale 1.000 + 无 MSAA  + 全套后处理 → 43.2 fps（中位）
##     2560×1334，scale 1.000 + 无 MSAA  + 只留 ACES    → 44.0 fps（中位）
## 关键读数：关掉 MSAA、后处理一套不动，锐度就已经和「全关后处理」持平
## （同一视角裁黑板算拉普拉斯方差：363 vs 370，而降分辨率那一档只有 100）。
## 原因是 MSAA 4× 即使在 0.649 下也要生成 1662×866×4 = 576 万采样，比原生
## 无 MSAA 的 341 万还多 —— 分辨率一直是被 MSAA 挤掉的，不是它自己太贵；
## 而 MSAA 对泼溅只在 quad 的几何边缘起作用（高斯的柔边来自 alpha 衰减），
## 实测锐度贡献约 2%。
## 所以 `project.godot` 已把 `msaa_3d` 关掉，这里相应放开原生分辨率：
## 同一取景下黑板那块的高频能量涨 4.06 倍（右墙海报 2.14 倍），只付 −20% 帧率。
##
## ── 保留护栏的依据：物理时间稀释是真实机制 ──
## Godot 每帧最多跑 `max_physics_steps_per_frame`（默认 8）步物理 —— 渲染一慢，
## **物理时间就被稀释**：fps < 7.5 时物理步数掉到 60 以下，玩家真实速度同比例
## 变慢，症状和「输入坏了」一模一样（本喵先用 `Input.action_press` 测出能走
## 1.93 m 就误判过一轮 —— 可那次是**窗口化**跑的，换成全屏才暴露）。
## 诊断办法见 scripts/_probe_gameplay_input.gd：**位移必须和帧率、物理帧数一起报**。
## 实测 2560×1334（面积比 0.42）在无 MSAA 下有 43 fps，离 7.5 还差 5.7 倍余量，
## 所以阈值放到 `RENDER_SCALE_AREA_RATIO_MIN`：只有 6 倍设计面积（≈4K 及以上）
## 才会触发，避免在 8K 屏上重演那场事故。
##
## ⚠️ 两个仍然适用的坑：
##   1. 不能只在 `_ready()` 里算一次 —— 那一刻窗口还没变成全屏尺寸（实测还没
##      2560×1440），算出来是「不用缩放」。所以挂在 `Viewport.size_changed` 上，
##      尺寸一变就重算。自检会事后 `root.size = 1600×900`，正好也走这条信号。
##   2. 尺寸回到设计分辨率时必须**显式设回 1.0**，不能「提前 return 什么都不做」——
##      否则触发过护栏的那次缩放会一直留着，自检拿到的就是被降过分辨率的画面。
##
## 视口面积 / 设计面积 低于这个比值（即窗口大于约 6 倍设计分辨率）才降分辨率。
## 1600×900 × 6 ≈ 2938×1653。2560×1334 的比值是 0.42，远在阈值之上。
const RENDER_SCALE_AREA_RATIO_MIN := 0.16

func _fit_render_scale() -> void:
	var vp := get_viewport()
	# ⚠️ 必须用 `vp.size`（= Window.size，就是**渲染目标**的像素数），
	#    **不能**用 `vp.get_visible_rect().size` —— 在 `canvas_items` 拉伸模式下
	#    后者返回的是**画布矩形**（= 设计分辨率 1600×900），跟真实渲染尺寸无关。
	#    本喵第一版就是用它，于是在 2560×1440 全屏下算出「不用缩放」，白改一轮。
	var size := Vector2(vp.size)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var ratio := (DESIGN_VIEWPORT.x * DESIGN_VIEWPORT.y) / (size.x * size.y)
	var s := 1.0
	if ratio < RENDER_SCALE_AREA_RATIO_MIN:
		s = clampf(sqrt(ratio), 0.5, 1.0)
	# 这里算出来的只是**上限**（窗口别太大）；真正的档位由设置里的「画质」决定，
	# 两者在 _apply_quality() 里相乘。
	_auto_scale = s
	print("[Game] _fit_render_scale：渲染尺寸 %s → 自动上限 %.3f" % [str(size), s])
	_apply_quality()


## 画质档位 → 实际渲染参数。设置界面一改就立刻生效（走 `GameSettings.listen`）。
##
## 为什么把「省电」做成档位而不是写死：GPU 占用几乎只由**每帧画多少像素**决定。
## 实测 2560×1440 + 原生 + Compute 后端时 GPU 恒在 100%（每帧 16.2 ms / 预算
## 16.67 ms，刚好追得上 60 fps），所以降一档能直接换回一大截功耗。旋钮见
## `GameSettings.QUALITY`。
func _apply_quality() -> void:
	var q := GameSettings.quality_spec()
	_quality = q
	var vp := get_viewport()
	# ⚠️ 只**乘**、不放大过 1.0：窗口极大时 _auto_scale 会小于 1，两者取小
	var target := clampf(_auto_scale * float(q["scale"]), 0.25, 1.0)
	if not is_equal_approx(vp.scaling_3d_scale, target):
		vp.scaling_3d_scale = target
	Engine.max_fps = int(q["fps"])
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.ssao_enabled = bool(q["ssao"])
		we.environment.glow_enabled = bool(q["glow"])
	# 打一行：GPU 占用直接跟这个数走，排查「怎么突然很烫」时先看它
	print("[Game] 画质 = %s：3D 缩放 %.2f（自动上限 %.2f × 档位 %.2f）  SSAO %s  辉光 %s  限帧 %s" % [
		GameSettings.choice_label("render_quality", GameSettings.value("render_quality")),
		target, _auto_scale, float(q["scale"]),
		"开" if q["ssao"] else "关", "开" if q["glow"] else "关",
		"垂直同步" if int(q["fps"]) <= 0 else "%d fps" % int(q["fps"])])


## 设置变了：只有画质需要在这里落地（其余设置由各自的系统自己 listen）。
func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "render_quality":
		_apply_quality()


func _ready() -> void:
	var vp := get_viewport()
	if not vp.size_changed.is_connected(_fit_render_scale):
		vp.size_changed.connect(_fit_render_scale)
	# 画质档位（设置界面里可调）：先注册监听，再走一次 _fit_render_scale ——
	# 它会算出自动上限并顺带调 _apply_quality()，两条路径共用同一处落地逻辑。
	GameSettings.listen(_on_setting_changed)
	_fit_render_scale()
	_watch_input()
	_player = $Player
	_weapon = $Player/Weapon
	_hud = $HUD
	_spawn = _player.global_position
	_build_room_proxy()
	# 「空地」铺地砖：只换平台这一块的材质，平台外什么都不加（见 LOT_TEX 上面那段）。
	# ⚠️ 必须在房间泼溅挖洞**之前**做 —— `_carve_fallback_floor()` 会复制
	#    `mesh.get_active_material(0)`，晚一步挖出来的洞就是没贴图的那块。
	_dress_empty_lot()

	_hud.bind(_player, _weapon)

	# 备用 Boss（见 scenes/bosses_standby.tscn）。必须在下面「按类型收 Boss」之前，
	# 否则它们进不了 `_bosses`、也不会被 HUD 绑血条。
	_spawn_standby_bosses()

	# 泼溅场地也是一场一行：两份（校园 / 画室609）同时解码时，玩家得分清
	# 是哪一份在等。HUD 侧 bind_splats() 按传入顺序从上往下排。
	for child in get_children():
		if child is SplatScene:
			var room := child as SplatScene
			_splats.append(room)
			# 房间泼溅一就位就把共面的方盒地板改成不写深度（见 FLOOR_MESH_PATH 的注释）。
			room.loaded.connect(_on_splat_loaded.bind(room))
			if room.is_ready():
				_on_splat_loaded({}, room)
	if not _splats.is_empty():
		if _hud.has_method("bind_splats"):
			_hud.bind_splats(_splats)
		elif _hud.has_method("bind_splat"):
			_hud.bind_splat(_splats[0])

	# Boss 与同伴都是场景里的直接子节点，按类型收一遍（不写死节点名，
	# 以后再加一位 Boss / 一名同伴只要往场景里摆就行）
	for child in get_children():
		if child is Boss:
			var boss := child as Boss
			_bosses.append(boss)
			boss.died.connect(_on_target_died)
		elif child is Companion:
			_companions.append(child as Companion)
	# ⚠️ Boss 不一定在 game 的**直接子节点**下：第 8 段的比纳挂在
	#    `Parkour/Route/DarkBoss`（生成器摆进去的）。`Boss._ready()` 会把自己加进
	#    `bosses` 组，而且子节点的 `_ready` 先跑，所以这里按组再收一遍就齐了。
	#    少了这一段：比纳**没有血条**、`died` 也没接上（用户：「怎么没有血条呀」）。
	for node in get_tree().get_nodes_in_group("bosses"):
		var b := node as Boss
		if b == null or _bosses.has(b) or not is_ancestor_of(b):
			continue
		_bosses.append(b)
		b.died.connect(_on_target_died)
	if not _bosses.is_empty() and _hud.has_method("bind_bosses"):
		_hud.bind_bosses(_bosses)
	_weapon.fired.connect(func(_i: int) -> void: _shots += 1)

	for target in get_tree().get_nodes_in_group("targets"):
		if target.has_signal("died"):
			target.died.connect(_on_target_died)
	# 场景里的靶子没进组也接一下
	for child in get_children():
		if child is Target and not child.is_in_group("targets"):
			child.died.connect(_on_target_died)

	# 开场剧情放**最后**：HUD / Boss / 同伴都接好了再演，
	# 这样对话框一结束世界就是完整可玩的（暂停期间 `splat_scene.gd` 的解码线程
	# 照常在后台跑，只是 `_process` 里的收尾被推迟到恢复之后）。
	_play_opening()


## 备用 Boss：`scenes/bosses_standby.tscn` 里躺着 6 位（霸王龙 / 倭瓜 / 霍德 /
## 佩洛洛斯拉 / 比纳 / 哥利亚），主场景里**只留飞猪优香** —— 全摆上去太挤。
##
## 命令行（写在 `--` 之后）：
##     -- --bosses=all            六位全部上场
##     -- --bosses=hod,peroro     只上场点名的（按节点名做包含匹配，不分大小写）
##     -- --bosses=off            什么都不加（等同不传）
## 自检 / 探针也用它：节点名和以前完全一致，所以 `get_node("Boss")` 之类一行都不用改。
const STANDBY_SCENE := "res://scenes/bosses_standby.tscn"


## 解析 `--bosses=`：返回空数组 = 不加。
func _wanted_standby() -> PackedStringArray:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--bosses="):
			continue
		var v := a.substr(9).strip_edges()
		if v.is_empty() or v == "off" or v == "none":
			return PackedStringArray()
		return v.split(",", false)
	return PackedStringArray()


func _spawn_standby_bosses() -> void:
	var want := _wanted_standby()
	if want.is_empty():
		return
	if not ResourceLoader.exists(STANDBY_SCENE):
		push_warning("[Game] 找不到 %s，备用 Boss 不上场" % STANDBY_SCENE)
		return
	var ps := load(STANDBY_SCENE) as PackedScene
	if ps == null:
		push_warning("[Game] %s 不是 PackedScene" % STANDBY_SCENE)
		return
	var holder := ps.instantiate()
	if holder == null:
		push_warning("[Game] %s 实例化失败" % STANDBY_SCENE)
		return
	var all := want.size() == 1 and String(want[0]).to_lower() == "all"
	var picked: Array[Node] = []
	for child in holder.get_children():
		var keep := all
		if not keep:
			var key := String(child.name).to_lower()
			for w in want:
				var q := String(w).strip_edges().to_lower()
				if q != "" and key.contains(q):
					keep = true
					break
		if keep:
			picked.append(child)
	# ⚠️ 先摘出来再加：直接 add_child 会改 `holder.get_children()`，遍历会漏人。
	# 另外要把 `owner` 清掉，否则 Godot 会警告「owner 不一致」（它们原本属于
	# `BossesStandby` 这棵场景树，现在要挂到 Game 下）。
	for child in picked:
		child.owner = null
		holder.remove_child(child)
		add_child(child)
	holder.queue_free()
	print("[Game] --bosses=%s：备用 Boss 上场 %d 位（%s）" % [
		",".join(want), picked.size(),
		", ".join(picked.map(func(n): return String(n.name)))])


## 播开场剧情。见 `OPENING_STORY` / `PLAY_OPENING`。
## 命令行覆盖（都写在 `--` 之后）：
##     -- --story=off                不播开场，直接开打
##     -- --story=res://story/x.txt  改播指定的那一份（调某一段剧情用）
func _play_opening() -> void:
	if not PLAY_OPENING:
		return
	# ⚠️ `--script`（自检 / 探针）不自动播。自检里凡是 instantiate 场景的用例
	#    都会断言「没被暂停」，自动播会一起带红；探针要自己显式调 `play_file`。
	if OS.get_cmdline_args().has("--script"):
		return
	var path := OPENING_STORY
	var explicit := false
	for a in OS.get_cmdline_user_args():
		if a == "--story=off":
			print("[Game] --story=off：跳过开场剧情")
			return
		if a.begins_with("--story="):
			path = a.substr(8)
			explicit = true
	var box := get_node_or_null("DialogueBox")
	if box == null:
		push_warning("[Game] 场景里没有 DialogueBox，跳过开场剧情")
		return
	if not FileAccess.file_exists(path):
		if explicit:
			push_warning("[Game] --story 指定的剧本不存在：%s" % path)
			return
		var alt := StoryScript.first_in_dir(STORY_DIR)
		if alt.is_empty():
			print("[Game] %s 不存在，%s 里也没有剧本，跳过开场剧情"
				% [OPENING_STORY, STORY_DIR])
			return
		print("[Game] %s 不存在，改用目录里排序第一份：%s" % [OPENING_STORY, alt])
		path = alt
	# 别在这一帧就开演 —— 等画面真的出来（见 `_wait_world_then_play()`）
	_wait_world_then_play(box, path)


## 等「画面真的出来了」再开演。
##
## 用户 2026-10-18：「语音在刚开游戏就开始播放了，应该等到看见游戏画面才播放」。
## 病根：`_play_opening()` 是在 `_ready()` 里直接调的，而那一刻**第一帧还没画出来**
## —— 房间泼溅要解码 2.1 s（缓存命中）、着色器还在编译，屏幕上可能只有代理网格
## 甚至黑色；配音却已经从第 0 秒开始放了，等玩家看见画面时第一句已经过半。
##
## 所以这里等两件事，然后才 `play_file()`：
##   ① 泼溅就绪（`--splat=off` 或没有泼溅时直接算就绪）；
##   ② 至少画过几帧（`frame_post_draw` 保证这一帧真的上了屏）。
## 上限 `OPENING_WAIT_MAX` 秒：冷缓存解 615 万点要 50 s，不能让开场一直等下去
## —— 超时就照常开演，最多回到「边加载边念」的老样子，不会卡死。
const OPENING_WAIT_MAX := 10.0

func _wait_world_then_play(box: Node, path: String) -> void:
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while true:
		await get_tree().process_frame
		frames += 1
		var waited := float(Time.get_ticks_msec() - t0) / 1000.0
		if frames >= 3 and (_splats_ready() or waited >= OPENING_WAIT_MAX):
			break
		if frames >= 3000:
			break
	var waited := float(Time.get_ticks_msec() - t0) / 1000.0
	# 再等一帧**真的画完**：这时屏幕上一定已经有世界了。
	await RenderingServer.frame_post_draw
	print("[Game] 开场剧情：等画面 %.1f s / %d 帧（泼溅 %s）→ 开演" % [
		waited, frames, "就绪" if _splats_ready() else "还没就绪（等超时了）"])
	box.call("play_file", path)


## 场上所有泼溅都**解码完了**？（没有泼溅 / `--splat=off` / 解码失败也算）
##
## 用 `loading` 而不是 `is_ready()`：`--splat=off` 时 SplatScene 在 `_ready()` 里
## 提前返回、永远不 `is_ready()`，用它当判据会让每一次 `--splat=off` 的启动都白等
## 满 `OPENING_WAIT_MAX` 秒。
func _splats_ready() -> bool:
	for s in _splats:
		if s != null and s.loading:
			return false
	return true


func _process(_delta: float) -> void:
	_update_room_swap()
	if _player and _player.global_position.y < FALL_LIMIT:
		_player.global_position = _spawn
		_player.velocity = Vector3.ZERO
		print("[game] 掉出平台，已送回出生点")


func _on_target_died(_by: float) -> void:
	_score += 1
	_hits += 1


## ── 画室609：门内看泼溅、门外看普通网格 ──
##
## 用户要的：「走出 609 门就隐藏高斯泼溅，外部看起来从高斯泼溅变成普通网格，
## 走回去又隐藏普通网格、显示高斯泼溅」。**位置就是碰撞网格**（用户原话）。
##
## 所以代理网格的每一个盒子都**照着 `Room609/RoomCollision` 的 `CollisionShape3D`
## 原样复制**（尺寸取 `BoxShape3D.size`、位置取它的全局变换），不估、不缩、不对齐
## 到别的东西上 —— 碰撞在哪儿，看起来的墙就在哪儿。
## 再补一块盖在墙顶的**顶板**：碰撞里没有顶，但站在外面从高处看，没有顶就一眼
## 看进空房间里。
##
## 判定：墙体的世界包围盒（`_room_box`）收缩 `ROOM_SWAP_HYSTERESIS` 之后
## `has_point(player)` 就是「在屋里」。进/出各用一条边界（滞回），
## 免得贴着门框走的时候每帧来回闪。
const ROOM_COLLISION_PATH := "Room609/RoomCollision"
const ROOM_PROXY_NAME := "RoomProxy"
const ROOM_SWAP_HYSTERESIS := 0.25
## 配色照 `scenes/mesh_hut.tscn` 那间手工小屋的调子（用户说的「你之前做的这样子」）
const ROOM_WALL_COLOR := Color(0.86, 0.83, 0.76)
## 门板：淡黄色。门洞可能是整面全高切出来的（只剩左右两段墙），所以门板也是
## 一整块板；**没有碰撞**，人照常穿过去 —— 只是从门外看，屋里不再一览无余。
const ROOM_DOOR_COLOR := Color(0.96, 0.90, 0.62)
## 门板比洞口每边多出多少（盖住软边，别在缝里漏光）
const ROOM_DOOR_OVERLAP := 0.12
## 门洞扫描：沿墙心线每 5 cm 打点；比 0.8 m 窄的空段不当门
const ROOM_DOOR_SCAN_STEP := 0.05
const ROOM_DOOR_MIN_WIDTH := 0.80
## 门板高度（到平台面算起）。门洞本身是全高的，上面那截用墙材质补成「门楣」
const ROOM_DOOR_HEIGHT := 2.6
const ROOM_ROOF_COLOR := Color(0.27, 0.28, 0.30)
const ROOM_ROOF_THICKNESS := 0.3

var _room_proxy: Node3D
## 墙体的世界包围盒（= 房间占位）。空 AABB 表示没建代理。
var _room_box := AABB()
var _room_inside := true


## 照碰撞盒建出「门外看到的网格」。放在 `_ready()`，因为碰撞盒在场景里就有，
## 不必等泼溅加载完 —— 加载那几秒里如果什么都不显示，房间就是一个黑洞。
func _build_room_proxy() -> void:
	var body := get_node_or_null(ROOM_COLLISION_PATH)
	if body == null:
		return
	var proxy := Node3D.new()
	proxy.name = ROOM_PROXY_NAME
	add_child(proxy)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = ROOM_WALL_COLOR
	wall_mat.roughness = 0.95

	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var walls := 0
	var wall_boxes: Array[AABB] = []
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var size: Vector3 = (cs.shape as BoxShape3D).size
		var mi := MeshInstance3D.new()
		mi.name = "Wall%d" % walls
		var m := BoxMesh.new()
		m.size = size
		mi.mesh = m
		mi.material_override = wall_mat
		proxy.add_child(mi)
		# ⚠️ 先 add_child 再写 global_transform：不在树里时 global == local。
		mi.global_transform = cs.global_transform
		var b: AABB = cs.global_transform * AABB(-size * 0.5, size)
		lo = lo.min(b.position)
		hi = hi.max(b.position + b.size)
		wall_boxes.append(b)
		walls += 1
	if walls == 0:
		proxy.queue_free()
		return

	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var rm := BoxMesh.new()
	rm.size = Vector3(hi.x - lo.x, ROOM_ROOF_THICKNESS, hi.z - lo.z)
	roof.mesh = rm
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = ROOM_ROOF_COLOR
	roof_mat.roughness = 0.9
	roof.material_override = roof_mat
	proxy.add_child(roof)
	roof.global_position = Vector3((lo.x + hi.x) * 0.5,
		hi.y + ROOM_ROOF_THICKNESS * 0.5, (lo.z + hi.z) * 0.5)

	_build_room_door(proxy, wall_boxes, AABB(lo, hi - lo), wall_mat)
	_room_proxy = proxy
	_room_box = AABB(lo, hi - lo)
	print("[Game] 609 门内外切换：代理网格 %d 面墙 + 顶板；房间矩形 %s，中心 %s" % [
		walls, str(_room_box.size.snappedf(0.01)),
		str((_room_box.position + _room_box.size * 0.5).snappedf(0.01))])


## 门板：把门洞糊上一块**淡黄色**的板。
##
## 用户原话：「这里可以做个淡黄色的门吗，把门填满，不要漏出破绽，当然这个门没有碰撞
## 正常穿过，只是视觉上遮住房内」。
##
## ⚠️ **门洞的位置是扫出来的，不是拿 `box_door_*` 猜的。**
## 第一版照 `box_door_side`（"z-"）建，门板就贴在了 z− 那面墙上 —— 可那面被
## `WallZNegA` 一整条封死，真正「没有碰撞箱」的缺口在 **x+ 面**：`WallXPos` 的
## 下沿 `z = −1.65` 与 `WallZNegB` 的上沿 `z = −3.76` 之间那 2.11 m。
## 用户一眼看穿：「做错地方了，是放在没有碰撞箱的地方不是放在墙那里」。
##
## 三个要点：
##  1. **比洞口每边大 0.12 m**：门洞是碰撞盒切出来的，而泼溅墙有软边、代理墙也有
##     接缝，严丝合缝的板一定会在边上漏出屋里的黑；压过墙 0.12 m 就看不出来了。
##  2. **门扇缩在墙厚中间**（离外表面 0.15 m），四周用一圈比墙厚的门框收口 ——
##     门扇四条边全藏在门洞里，从门外看不到「一块飘在墙面上的黄板子」。
##  3. **无碰撞**：它只是个 `MeshInstance3D`，挂在 `RoomProxy` 下面 —— 于是
##     「走出门 → 代理网格亮起来」时门板一起出现、「走回屋里 → 代理网格隐藏」时
##     门板一起消失，不用单独写开关。


## 门洞 = 墙环上**没有碰撞盒**的那一段。
##
## 做法：沿四面墙的**墙心线**（离外表面 0.15 m）每 5 cm 打一个点，落在任何一个
## 碰撞盒里就算「有墙」；取最长的一段「连续没墙、且两端都有墙」的区间。
## 只认两端都有墙的 —— 房间四角的开口（墙本来就到边）不算门。
func _room_doorway(walls: Array[AABB], room: AABB) -> Dictionary:
	const HALF_WALL := 0.15
	const EDGE := 0.20
	var lo := room.position
	var hi := room.position + room.size
	var faces := [
		{"side": "x-", "axis": 0, "plane": lo.x + HALF_WALL, "outer": lo.x},
		{"side": "x+", "axis": 0, "plane": hi.x - HALF_WALL, "outer": hi.x},
		{"side": "z-", "axis": 2, "plane": lo.z + HALF_WALL, "outer": lo.z},
		{"side": "z+", "axis": 2, "plane": hi.z - HALF_WALL, "outer": hi.z},
	]
	var best := {}
	var best_w := 0.0
	for f in faces:
		var axis: int = int(f["axis"])
		var plane: float = float(f["plane"])
		var t_lo: float = (lo.z if axis == 0 else lo.x) + EDGE
		var t_hi: float = (hi.z if axis == 0 else hi.x) - EDGE
		var n := int(round((t_hi - t_lo) / ROOM_DOOR_SCAN_STEP)) + 1
		var hit := PackedByteArray()
		hit.resize(n)
		for i in n:
			var t := t_lo + float(i) * ROOM_DOOR_SCAN_STEP
			var p := Vector3(plane, 1.6, t) if axis == 0 else Vector3(t, 1.6, plane)
			for b in walls:
				if b.has_point(p):
					hit[i] = 1
					break
		var i2 := 0
		while i2 < n:
			if hit[i2] != 0:
				i2 += 1
				continue
			var a := i2
			while i2 < n and hit[i2] == 0:
				i2 += 1
			if a == 0 or i2 >= n:
				continue
			var w := float(i2 - a) * ROOM_DOOR_SCAN_STEP
			if w > best_w:
				best_w = w
				best = {
					"side": String(f["side"]), "axis": axis, "plane": plane,
					"outer": float(f["outer"]),
					"lo": t_lo + float(a) * ROOM_DOOR_SCAN_STEP,
					"hi": t_lo + float(i2) * ROOM_DOOR_SCAN_STEP,
					"width": w,
				}
	return best if best_w >= ROOM_DOOR_MIN_WIDTH else {}


func _build_room_door(proxy: Node3D, walls: Array[AABB], room: AABB, wall_mat: Material) -> void:
	var door := _room_doorway(walls, room)
	if door.is_empty():
		print("[Game] 609 代理墙环上没有找到「没有碰撞」的缺口 —— 不做门板")
		return
	var axis := int(door["axis"])            # 0 = 洞开在 x± 面（法向 x），2 = z± 面
	var plane := float(door["plane"])        # 墙心线的法向坐标
	var outer := float(door["outer"])        # 墙外表面的法向坐标
	var t_lo := float(door["lo"])
	var t_hi := float(door["hi"])
	var center := (t_lo + t_hi) * 0.5
	var gap := t_hi - t_lo
	# 「往屋外」是法向的哪一边：x+ / z+ 是 +1，x− / z− 是 −1
	var out_sign := 1.0 if outer > plane else -1.0
	# 人在平台面上走（y = 0），所以门从**平台面**起，而不是从埋在地下的碰撞盒底部起
	var floor_y := maxf(room.position.y, 0.0)
	var top_y := room.position.y + room.size.y
	var door_top := floor_y + ROOM_DOOR_HEIGHT
	var w := gap + ROOM_DOOR_OVERLAP * 2.0
	var thick := 0.08
	# 门洞是全高切出来的，但门只做到 2.6 m：上面那截拿**墙的材质**填平，
	# 看上去就是「门 + 门楣」，一点缝都不漏（比一整条 5.4 m 的黄漆自然得多）
	_put_door_box(proxy, "DoorPanel", axis, plane, floor_y, door_top, center, w, thick,
		_door_mat(ROOM_DOOR_COLOR, false, 0.45))
	if door_top < top_y:
		# 门楣比门扇**靠外**，只往里缩 4 cm：缩得太深（11 cm）会在门框上方留一道
		# 一直拉到屋顶的暗缝，斜看像墙没接上。也不能齐平 —— 齐平会和代理墙面
		# 共面打架（z-fighting），而且超过墙顶会露出屋顶轮廓外一小截。
		_put_door_box(proxy, "DoorLintel", axis,
			outer - out_sign * (0.04 + thick * 0.5), door_top,
			top_y + ROOM_DOOR_OVERLAP, center, w, thick, wall_mat)
	# 门框：四根比墙厚的条，贴在墙外表面上收口（门扇缩在墙里，四条边全靠它遮住）
	var bar := 0.14
	var bar_d := 0.12
	var n_face := outer
	var frame_mat := _door_mat(ROOM_DOOR_COLOR.darkened(0.35), false, 0.15)
	_put_door_box(proxy, "DoorFrameL", axis, n_face, floor_y - 0.02, door_top + 0.07,
		t_lo, bar, bar_d, frame_mat)
	_put_door_box(proxy, "DoorFrameR", axis, n_face, floor_y - 0.02, door_top + 0.07,
		t_hi, bar, bar_d, frame_mat)
	_put_door_box(proxy, "DoorFrameT", axis, n_face, door_top, door_top + bar,
		center, gap + bar + 0.02, bar_d, frame_mat)
	# 把手：一颗小圆柱，让这块黄板一眼看得出是「门」而不是刷了漆的墙
	var knob := MeshInstance3D.new()
	knob.name = "DoorKnob"
	var km := CylinderMesh.new()
	km.top_radius = 0.045
	km.bottom_radius = 0.045
	km.height = 0.16
	km.radial_segments = 10
	knob.mesh = km
	var kmat := StandardMaterial3D.new()
	kmat.albedo_color = Color(0.32, 0.24, 0.16)
	kmat.metallic = 0.5
	kmat.roughness = 0.45
	knob.material_override = kmat
	proxy.add_child(knob)
	knob.global_position = _door_point(axis, outer + out_sign * 0.10, floor_y + 1.05,
		center + w * 0.30)
	knob.global_rotation = Vector3(0, 0, PI * 0.5) if axis == 0 else Vector3(PI * 0.5, 0, 0)
	print("[Game] 609 门洞（没有碰撞盒的那一段）：%s 面 %.2f ~ %.2f，宽 %.2f m，中心 %.2f" % [
		String(door["side"]), t_lo, t_hi, gap, center])
	print("[Game] 609 门板：%.2f × %.2f m（门楣补齐到墙顶，比洞口每边多 %.2f m，无碰撞）"
		% [w, ROOM_DOOR_HEIGHT, ROOM_DOOR_OVERLAP])


## 门板 / 门框的通用放置。`axis` = 0 时洞在 x± 面（法向 x、沿墙 z），= 2 时反过来。
func _put_door_box(proxy: Node3D, nm: String, axis: int, n: float, y0: float, y1: float,
		t: float, w: float, thick: float, mat: Material) -> void:
	var h := y1 - y0
	if h <= 0.01:
		return
	var mi := MeshInstance3D.new()
	mi.name = nm
	var m := BoxMesh.new()
	m.size = Vector3(thick, h, w) if axis == 0 else Vector3(w, h, thick)
	mi.mesh = m
	mi.material_override = mat
	proxy.add_child(mi)
	mi.global_position = _door_point(axis, n, (y0 + y1) * 0.5, t)


## 门板坐标系 → 世界坐标：`axis` = 0 时（法向 = x，沿墙 = z），= 2 时（法向 = z，沿墙 = x）
func _door_point(axis: int, n: float, y: float, t: float) -> Vector3:
	return Vector3(n, y, t) if axis == 0 else Vector3(t, y, n)


## 门板 / 门框的材质。`unshaded` = 完全不吃光（会变成一块纯色贴纸），
## 一般不要开；背光那一面靠 `glow`（自发光）提亮就够了 —— 纯 PBR 在逆光时是黑的。
func _door_mat(col: Color, unshaded: bool, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## 给 40×40 平台铺地砖（见 `LOT_TEX` 上面那段）。
##
## **只动平台本身，平台外一格都不铺**：跑酷的失败判定是「掉下去」，
## 外面补了地面就掉不下去了（用户 2026-10-18 专门交代过）。
##
## ⚠️ 必须在 `_carve_fallback_floor()` 之前调用：挖洞那一步复制的是
##    `mesh.get_active_material(0)`，晚一步挖出来的洞就是没贴图的那块。
func _dress_empty_lot() -> void:
	var mesh := get_node_or_null(FLOOR_MESH_PATH) as MeshInstance3D
	if mesh == null:
		return
	var tex := load(LOT_TEX) as Texture2D
	if tex == null:
		push_warning("[Game] 没有地面贴图 %s（先跑 tools/make_lot_paver.py）" % LOT_TEX)
		return
	var src = mesh.get_active_material(0)
	var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate() \
		if src is StandardMaterial3D else StandardMaterial3D.new()
	m.albedo_texture = tex
	# 原来的 (0.21,0.23,0.27) 会把贴图压暗一倍；但也不能全白 ——
	# 这是黄昏/阴天的场景，铺成亮白瓷砖会跟墙、天空打架。
	m.albedo_color = Color(0.58, 0.62, 0.68)
	m.uv1_scale = Vector3(LOT_UV_SCALE, LOT_UV_SCALE, LOT_UV_SCALE)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var nmap := load(LOT_TEX_N) as Texture2D
	if nmap != null:
		m.normal_enabled = true
		m.normal_texture = nmap
		m.normal_scale = 0.7
	m.roughness = 0.95
	m.metallic = 0.0
	mesh.set_surface_override_material(0, m)
	print("[Game] 空地铺地砖：%s（UV %.0f×，平台 40×40 m，平台外不铺）" % [LOT_TEX, LOT_UV_SCALE])


## 每帧：在屋里 → 泼溅显示、代理藏；出屋 → 反过来。
## 泼溅**没就位之前**代理一直显示（宁可先看到一个实心房间，也别看到黑洞）。
func _update_room_swap() -> void:
	if _room_proxy == null or _player == null:
		return
	var p := _player.global_position
	if _room_box.grow(-ROOM_SWAP_HYSTERESIS).has_point(p):
		_room_inside = true
	elif not _room_box.grow(ROOM_SWAP_HYSTERESIS).has_point(p):
		_room_inside = false

	var ready := _room_scene != null and _room_scene.is_ready()
	_room_proxy.visible = not _room_inside or not ready
	if _room_scene != null and _room_scene.splat_node != null:
		_room_scene.splat_node.visible = _room_inside and ready


## 只有 `venue == "room"` 的场地才和方盒地板共面（校园那份在平台下方 12 m）。
## `--splat=off` 时 SplatScene 会提前返回、绝不发 loaded，所以 11 套玩法自检不受影响。
func _on_splat_loaded(_info: Dictionary, scene: SplatScene) -> void:
	if scene == null or scene.venue != "room":
		return
	_room_scene = scene
	_carve_fallback_floor()
	# ⚠️ 立刻换一次代理/泼溅：开场剧情一开就 `get_tree().paused = true`，
	#    `_process` 里的 `_update_room_swap()` **不会跑** —— 而房间这份泼溅
	#    是 2.1 s 才解码完、往往正好落在剧情里。不在这里换，代理网格（米色墙 +
	#    深色顶板）会一直盖在泼溅上面，用户看到的就是「高斯泼溅根本没加载」。
	_update_room_swap()


## 把 `Floor/Mesh` 这块方盒地板挖掉房间那一块：房间用扫描地面，四周照旧是平台。
## 见 FLOOR_MESH_PATH 上方那段长注释。
##
## ── 洞的形状：**房间自己的矩形**，不是泼溅的内容盒（2026-10-18 订正）──
## 第一版拿 `content_min/max`（源坐标系的内容盒）当洞，被 yaw 一旋就成了
## 22.34 × 16.50 m 的斜矩形。而那个内容盒里**装的不只是房间**：从窗户看出去的
## 校园、拍摄时的离群点都在里面，房间本身只有 10.7 × 20.6 m。于是平台中间被
## 挖掉一大圈**没有地板、也没有扫描地面**的真空 —— 用户报的「地板中间没填满」。
##
## 现在直接量 `Room609/RoomCollision`（= 房间四面墙）的世界包围盒来挖：
## 洞里只剩房间本身（扫描地面铺满它），洞外一直到平台边沿全是地砖。
## 墙根的 15 cm 重叠靠 `FLOOR_HOLE_MARGIN`（负数 = 洞略小）保证，那里被墙挡着看不见。
func _carve_fallback_floor() -> void:
	if _floor_carved:
		return
	_floor_carved = true
	var mesh := get_node_or_null(FLOOR_MESH_PATH) as MeshInstance3D
	if mesh == null:
		return
	if not CARVE_FALLBACK_FLOOR or OS.get_cmdline_user_args().has("--solid-floor"):
		print("[Game] --solid-floor / CARVE_FALLBACK_FLOOR=false：方盒地板保持整块不动")
		return
	var box := mesh.mesh as BoxMesh
	var splat_node := _room_scene.splat_node if _room_scene != null else null
	if box == null or splat_node == null:
		push_warning("[Game] 方盒地板不是 BoxMesh 或房间未就绪，跳过挖洞")
		return

	# 洞 = 房间墙体的世界矩形（`_build_room_proxy()` 里量好的那个）。
	var hole := _room_box
	if hole.size.x <= 0.01 or hole.size.z <= 0.01:
		push_warning("[Game] 房间矩形是空的（代理网格没建出来），跳过挖洞")
		return
	# 厚度给世界 4 m，足够穿透这块 1 m 厚的平台板；竖向中心压在平台顶面（y = 0）。
	var hole_size := Vector3(
		hole.size.x + FLOOR_HOLE_MARGIN * 2.0, 4.0, hole.size.z + FLOOR_HOLE_MARGIN * 2.0)
	var hole_center := Vector3(
		hole.position.x + hole.size.x * 0.5, 0.0, hole.position.z + hole.size.z * 0.5)

	var mat := mesh.get_active_material(0)
	var combiner := CSGCombiner3D.new()
	combiner.name = "FloorCarved"
	var slab := CSGBox3D.new()
	slab.name = "Slab"
	slab.size = box.size
	if mat != null:
		slab.material = mat
	combiner.add_child(slab)
	var cutter := CSGBox3D.new()
	cutter.name = "RoomHole"
	cutter.operation = CSGShape3D.OPERATION_SUBTRACTION
	cutter.size = hole_size
	combiner.add_child(cutter)
	mesh.get_parent().add_child(combiner)
	# ⚠️ 先进树再写 global_transform：不在树里时 global == local，
	#    而这里要的是「跟 `Floor/Mesh` 在同一处、同一朝向」。
	slab.global_transform = mesh.global_transform
	cutter.global_transform = Transform3D(Basis.IDENTITY, hole_center)
	mesh.visible = false
	print("[Game] 房间泼溅就位：方盒地板挖掉房间那一块（CSG 减法，洞 = 房间墙体矩形）；Floor/Collision 不动")
	print("[Game]   洞 世界尺寸 %.2f × %.2f m（房间 %.2f × %.2f m，外扩 %.2f m），中心 %s；板子 %s" % [
		hole_size.x, hole_size.z, hole.size.x, hole.size.z,
		FLOOR_HOLE_MARGIN, str(hole_center.snappedf(0.01)), str(box.size)])


func stats() -> Dictionary:
	return {
		"score": _score,
		"shots": _shots,
		"hits": _hits,
		"accuracy": 0.0 if _shots == 0 else float(_hits) / float(_shots),
	}
