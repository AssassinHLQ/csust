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
			note = "   ← 游戏被暂停（Esc 设置菜单开着）"
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

	_hud.bind(_player, _weapon)

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


func _process(_delta: float) -> void:
	if _player and _player.global_position.y < FALL_LIMIT:
		_player.global_position = _spawn
		_player.velocity = Vector3.ZERO
		print("[game] 掉出平台，已送回出生点")


func _on_target_died(_by: float) -> void:
	_score += 1
	_hits += 1


## 只有 `venue == "room"` 的场地才和方盒地板共面（校园那份在平台下方 12 m）。
## `--splat=off` 时 SplatScene 会提前返回、绝不发 loaded，所以 11 套玩法自检不受影响。
func _on_splat_loaded(_info: Dictionary, scene: SplatScene) -> void:
	if scene == null or scene.venue != "room":
		return
	_room_scene = scene
	_carve_fallback_floor()


## 把 `Floor/Mesh` 这块方盒地板挖掉房间那一块：房间用扫描地面，四周照旧是平台。
## 见 FLOOR_MESH_PATH 上方那段长注释。
##
## 为什么用 CSG 而不是手摆四块盒子：房间是**斜的**（`yaw_degrees = 248.6`），
## 手摆的盒子只能轴对齐，洞会退化成世界包围盒（比房间大一圈，四角露真空）。
## CSG 布尔减法吃任意朝向，洞就是房间自己的旋转矩形。
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

	# 房间内容的世界变换（含 world_scale / yaw / 锚点偏移）—— 洞要跟着它走。
	var xf := _room_scene.global_transform * splat_node.transform
	var src_min := _room_scene.content_min
	var src_max := _room_scene.content_max
	var src_size := src_max - src_min
	if src_size.x <= 0.0 or src_size.z <= 0.0:
		push_warning("[Game] 房间内容盒是空的，跳过挖洞")
		return
	var world_scale := maxf(xf.basis.get_scale().y, 1e-4)
	# 洞的尺寸按**源坐标**给，缩放由 xf 承担，所以外扩量要除掉 world_scale。
	var margin_src := FLOOR_HOLE_MARGIN / world_scale
	# 厚度给世界 4 m，足够穿透这块 1 m 厚的平台板。
	var thickness_src := 4.0 / world_scale
	# 洞的竖向中心必须落在**平台顶面那一层**（世界 y = 0），否则切不到板子。
	var src_zero_y := (xf.affine_inverse() * Vector3.ZERO).y
	var center_src := Vector3(
		(src_min.x + src_max.x) * 0.5, src_zero_y, (src_min.z + src_max.z) * 0.5)

	var mat := mesh.get_active_material(0)
	var combiner := CSGCombiner3D.new()
	combiner.name = "FloorCarved"
	var slab := CSGBox3D.new()
	slab.name = "Slab"
	slab.size = box.size
	slab.position = mesh.position
	if mat != null:
		slab.material = mat
	combiner.add_child(slab)
	var cutter := CSGBox3D.new()
	cutter.name = "RoomHole"
	cutter.operation = CSGShape3D.OPERATION_SUBTRACTION
	cutter.size = Vector3(
		src_size.x + margin_src * 2.0, thickness_src, src_size.z + margin_src * 2.0)
	cutter.transform = xf * Transform3D(Basis.IDENTITY, center_src)
	combiner.add_child(cutter)
	mesh.get_parent().add_child(combiner)
	mesh.visible = false
	print("[Game] 房间泼溅就位：方盒地板挖掉房间那一块（CSG 减法，跟房间朝向对齐）；Floor/Collision 不动")
	print("[Game]   洞 世界尺寸 %.2f × %.2f m，外扩 %.2f m；板子 %s" % [
		(src_size.x + margin_src * 2.0) * world_scale,
		(src_size.z + margin_src * 2.0) * world_scale,
		FLOOR_HOLE_MARGIN, str(box.size)])


func stats() -> Dictionary:
	return {
		"score": _score,
		"shots": _shots,
		"hits": _hits,
		"accuracy": 0.0 if _shots == 0 else float(_hits) / float(_shots),
	}
