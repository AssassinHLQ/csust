class_name SplatScene
extends Node3D
## 高斯泼溅场景接入器：把 .sogdata 解码成 GDGS 的 GaussianSplatNode 挂进场景。
##
## ── 为什么不用 GDGS 的编辑器导入器 ──
##   导入器会把 SOG 展开成 GaussianResource 写进 res://.godot/imported/*.res，
##   615 万点约 2.89 GB，导出时整份塞进 PCK，exe 直接变 3 GB。
##   所以数据统一用 **.sogdata** 后缀（不是 .sog）绕开导入器，运行时现场解码。
##
## ── 开销（实测，RTX 4060 Laptop）──
##   6,150,154 点首次解码 ≈ 50 s，内存约 1.5 GB（point_data_byte = 点数 × 240 B）。
##   解码在工作线程里跑，主线程只显示进度；cache_mode="auto" 时第二次启动读
##   user://splat_cache，**1.0 s** 进场景。发行时建议 "off"。
##
## ── 摆放（本扫描是「俯拍航拍」薄饼，必须从上方看）──
##   内容稳健包围盒 ≈ 8.5 × 0.66 × 6.4（居中坐标系单位）。实测：
##     从上方 30° 看 → 干净清晰
##     贴地平视     → 高斯被拉成长条拖影（视角相关，跟缩放无关）
##   所以本节点提供「自动摆放」：水平把内容中心对到原点，竖向把内容顶面
##   沉到 top_gap 之下 —— 竞技场做成悬浮平台，校园铺在下面，玩家低头俯视。
##
## 节点自身 transform 留给场景摆放；缩放/旋转/平移施加在子节点 splat_node 上，
## 最终变换 = global_transform × splat_node.transform。

signal progress(phase: String, done: int, total: int)
signal loaded(info: Dictionary)
signal failed(message: String)

const SogRuntime := preload("res://scripts/sog_runtime.gd")
## ⚠️ 故意用 preload 而不是全局类名 `GaussianSplatNode`：
##    全局类名要靠 res://.godot/global_script_class_cache.cfg，插件刚加进工程时
##    如果编辑器缓存还是旧的（编辑器一直开着没重扫），`GaussianSplatNode.new()`
##    会直接解析失败、整个脚本加载不了。preload 走文件路径，不受类名缓存影响。
const GaussianSplatNodeScript := preload("res://addons/gdgs/runtime/nodes/gaussian_splat_node.gd")
const GaussianResourceScript := preload("res://addons/gdgs/runtime/resources/gaussian_resource.gd")
const STRUCT_SIZE := 60          # 每点 60 个 float
const BYTES_PER_SPLAT := 240     # = STRUCT_SIZE * 4

@export_file("*.sogdata", "*.sog") var sog_path := "res://splatdata/school_playable.sogdata"
## HUD 状态行上显示的名字（一场一行，前缀就是它）
@export var display_name := "泼溅场景"
## 场地标签：启动参数 `--venue=<标签>` 时**只加载标签相同的那几份**，空 = 永远加载。
## 为什么需要：两份泼溅同时常驻时，GDGS 是把所有节点的点合并成一个 GPU 缓冲的
## （见 gaussian_scene_registry.gd 的 merged_point_data），显存按**点数之和**涨。
## 校园 615 万 + 画室 277 万 ≈ 893 万点，光点数据就 2.04 GiB，加排序/裁剪缓冲
## 约 4 GiB —— 8 GB 显卡上必须能按场地拆开跑，这就是那个开关。
@export var venue := ""
## "off" 发行用；"auto" 开发期第二次启动秒进；"refresh" 强制重建缓存
@export_enum("off", "auto", "refresh") var cache_mode := "auto"
## 扫描是「模型尺度」，需要放大。×25 时内容约 211 × 160 m（真实校园尺度）
@export var world_scale := 25.0
@export var yaw_degrees := 0.0
## 手动平移（auto_place 打开时，水平/竖向会被自动摆放覆盖）
@export var offset := Vector3.ZERO
## 自动摆放：内容水平居中到原点，且顶面沉到 top_gap 之下
@export var auto_place := true
@export var top_gap := 12.0
## auto_place = false 时的第三种摆放方式：把**源坐标系**里的 anchor_source 点
## 对到节点局部空间的 anchor_world。适合「把房间地板摆到平台地面上」这类诉求 ——
## 源数据里「地板平面 + 房间中心」是量出来的常量，比手算 offset 稳。
@export var use_anchor := false
@export var anchor_source := Vector3.ZERO
@export var anchor_world := Vector3.ZERO
## 裁掉离群 floaters（俯拍重建里那些又大又远的椭球，放大后是糊满屏的白团）
@export var crop_enabled := false
## 裁剪盒 = 内容 1‰~99.9‰ 分位盒向外扩这么多（源坐标单位）
@export var crop_margin := 0.5
## > 0 时再丢弃椭球尺度超过它的点（同上单位）；0 = 只看位置
@export var crop_max_scale := 0.0
## 是否再乘 GDGS 自带的「绕 Z -180°」姿态修正。本数据自身 Y 朝上，默认关。
@export var use_default_orientation := false

## ── 加载节奏（2026-10-27 用户：「先不加载高斯泼溅…最后缓慢加载」）──
##
## 场景切进来时，泼溅是**最贵**的一项（解码 1~4 s + 主线程打包 + 几 GiB 显存）。
## 玩家刚进门时通常离它还有几十米，所以可以让它晚一点开始：
##   `start_delay`    场景就绪后至少等这么多秒再解码（0 = 立即）
##   `start_distance` >0 时，玩家一旦进入这个距离就**立刻**开始（不必等满 delay）
##   `low_priority`   解码线程降成低优先级，不和主线程抢 CPU（真正「缓慢加载」）
## 两个都为 0 时行为与以前完全一致。
@export var start_delay := 0.0
@export var start_distance := 0.0
@export var low_priority := false
## 是否挂上碰撞 GLB 的三角网格（本扫描的碰撞 GLB 与实际范围不符，默认关）
@export var build_collision := false
@export var collision_glb := "res://models/school.collision.glb"
## 按**房间矩形**生成盒碰撞（不需要碰撞 GLB）：四面墙。
## 适合「方方正正、已经轴对齐的房间」这类扫描 —— 墙厚向**内**长，所以外表面
## 正好落在内容包围盒上，站在房间外面贴着墙走不会被推出去。
@export var build_box_collision := false
## 墙的厚度（世界单位），从包围盒面往房间里长
@export var box_wall_thickness := 0.3
## 门留哪一面："none" = 四面封死；否则 `box_door_side` 那一面会在
## `box_door_center` 处开一个 `box_door_width` 宽的洞（沿该面方向的坐标）。
## ⚠️ 枚举里不能放空串（`@export_enum` 会报 "Argument 1 is empty"），所以用 "none"。
@export_enum("none", "x-", "x+", "z-", "z+") var box_door_side := "none"
@export var box_door_width := 1.6
@export var box_door_center := 0.0
@export var auto_start := true

@export_group("Collapse")
## 动态 3DGS「坍缩」：所有高斯同时等比变小，并向锚点收敛，最终在一点上塌掉。
##
## 实现只有一处：把系数乘进 _local_basis()。因为
##   位置 world_pos = basis * 源点 + offset   ⇒ basis 变小 ⇒ 点被拉向 offset
##   椭球 world_cov = object_linear * cov * object_linearᵀ ⇒ 吃 basis² ⇒ 同时变小
## 所以 Compute / Raster 两套后端**一行都不用改**，也天然兼容锚点：
## use_anchor 时 offset = anchor_world − basis * anchor_source，
## basis → 0 时所有点恰好收敛到 anchor_world 这个点。
@export var collapse_enabled := false
## 从 t=0 走到 t=1 的秒数。
@export_range(0.1, 120.0, 0.1) var collapse_duration := 6.0
## 开始前的停顿秒数。
@export_range(0.0, 60.0, 0.1) var collapse_delay := 0.0
@export_enum("linear", "in_quad", "in_cubic", "in_quart", "out_cubic", "in_out_cubic") var collapse_easing := "in_cubic"
## 到 1 之后自动倒放回 0（来回呼吸）；false 则停在坍缩状态。
@export var collapse_ping_pong := false
## 泼溅加载完成后自动开始播放。
@export var collapse_auto_play := false
## 坍缩到底时保留的缩放。不取 0：全 0 的基矩阵是奇异的，Godot 会报错。
@export_range(0.0, 0.1, 0.0001) var collapse_min_scale := 0.0004
## 收缩的同时让整体淡出（写内部 MultiMesh 的 transparency），
## 这样末帧不会剩一个死亮的白点。
@export var collapse_fade := false
## 淡出从 t 的哪个位置开始（1.0 = 到最后才淡）。
@export_range(0.0, 1.0, 0.01) var collapse_fade_from := 0.55
## 坍缩方式：
##   uniform   —— 缩放整个节点。所有高斯**同步**收缩并收敛；Compute/Raster 都能用。
##   staggered —— 在 Raster 着色器里逐高斯做，**可错峰**，且能和布朗漂移共存。
@export_enum("uniform", "staggered") var collapse_mode := "uniform"
## （staggered）错峰程度：0 = 同时动；0.6 = 起播时刻在 [0, 0.6] 内随机铺开，
## 但所有高斯仍在 collapse_t = 1 处收齐。
@export_range(0.0, 0.95, 0.01) var collapse_stagger := 0.6
## （staggered）着色器里的缓动档。独立于 collapse_easing —— 后者只给 uniform 用，
## 因为错峰必须逐高斯求值，只能放在着色器里。
@export_enum("linear", "in_cubic", "in_quad", "smoothstep") var collapse_shader_ease := "in_cubic"
## （staggered）随坍缩淡出到透明。0 = 亮度不变。
@export_range(0.0, 1.0, 0.01) var collapse_shader_fade := 0.0

@export_group("Brownian")
## 布朗漂移幅度，单位是**源坐标**。每个高斯在自己的原位置旁边小幅游走，
## 位移以原位置为中心，硬上界 = 1.5 × 本值（两段八度 amp + 0.5×amp）。
##
## 量纲提示：画室/村落这类扫描源尺寸约 6.8 单位，取 0.005 ~ 0.03 就是"小幅度"。
## ⚠️ 这项走的是逐高斯着色器路径，所以后端必须是 Raster。
@export_range(0.0, 5.0, 0.0001) var brownian_amp := 0.0
## 漂移频率（Hz）。越大抖得越快越碎。
@export_range(0.0, 20.0, 0.01) var brownian_freq := 1.0
## 换一批随机相位/频率。错峰顺序与它共用种子，所以也会一起变。
@export var brownian_seed := 0

@export_group("Rise")
## 第三个效果：**所有粒子随机向上**。每个高斯按自己的随机速度上升，
## 所以不是齐步走。0 = 关闭。单位是**源坐标/秒**。
@export_range(0.0, 20.0, 0.001) var rise_speed := 0.0
## 速度随机幅度：0 = 全部同速（齐步上升）；0.8 = 速度在 0.2 ~ 1.8 倍之间随机。
@export_range(0.0, 0.95, 0.01) var rise_jitter := 0.8
## 侧向随机偏移幅度（源坐标），让上升不是一条直线。
@export_range(0.0, 5.0, 0.0001) var rise_side := 0.0
## 循环：走完 rise_span 后从底部重新升起，形成源源不断的上升流。
## 关掉则是一次性升起（粒子会一直飞出画面）。建议开——上升流才是常态。
@export var rise_loop := false
## 一个循环的上升距离（源坐标）。
@export_range(0.001, 50.0, 0.001) var rise_span := 1.0
## 循环时两端各淡出多少（占一个循环的比例）。**必须 > 0**，否则回绕那一刻
## 粒子会从顶部"瞬移"回底部，看得见跳变。
@export_range(0.0, 0.5, 0.01) var rise_fade := 0.15

@export_group("Dynamic Clock")
## 动态时钟自动走。关掉则用手动的 dynamic_time，便于定格逐帧比对。
@export var dynamic_auto_time := true
## 手动时钟（秒），dynamic_auto_time = false 时生效。
## 布朗漂移与向上漂移**共用**这一个时钟。
@export var dynamic_time := 0.0

var splat_node: Node3D = null
## 坍缩进度：0 = 原始大小，1 = 完全坍缩。
var collapse_t := 0.0
var collapsing := false
var _collapse_clock := 0.0
var _collapse_dir := 1.0
## 内容中心（源坐标）。逐高斯坍缩的收敛点 —— 与 uniform 模式的锚点机制对齐：
## use_anchor 时内容中心被钉在 anchor_world 上，所以两种模式塌到同一个世界点。
var _content_center := Vector3.ZERO
var _dynamic_clock := 0.0
var splat_center := Vector3.ZERO
var splat_aabb := AABB()
## 内容稳健包围盒（1‰~99.9‰ 分位，排除 floaters）
var content_min := Vector3.ZERO
var content_max := Vector3.ZERO
var point_count := 0
## 裁剪结果（crop_enabled 时）：{"kept": int, "dropped": int, "box": AABB, "scale_dropped": int}
var crop_stats := {}
var loading := false
var elapsed_seconds := 0.0

var _thread: Thread = null
var _mutex := Mutex.new()
var _result: Dictionary = {}
var _start_ms := 0


func _ready() -> void:
	# ⚠️ 本节点的 `_process` 干两件性质不同的事：**后台解码线程的 join**（`_finish()`）
	#    和两个纯观赏用的动态效果（坍缩 / 粒子上升）。前者是**资源加载**，不该被
	#    「游戏暂停」卡住。
	#
	#    实测（开场剧情那一轮，正常启动、停在第一句）：剧情一播就
	#    `get_tree().paused = true`，而画室609 那份（276.9 万点、缓存命中 **1.6 s**）
	#    其实早就解码完了，日志里却**一条 `[SplatScene] 完成：…` 都没有**
	#    ——那句在 `_finish()` 里。也就是说舞台要等剧情**读完**才**突然**出现，
	#    而开场的旁白第一句就在讲「脚下的校园」。所以这里无视暂停。
	#
	#    代价：`play_collapse()` / 粒子上升这类效果在暂停期间也会继续走。
	#    目前没有任何地方在暂停时启动它们（只有 `_probe_collapse.gd` 用，而它不暂停），
	#    真要用了再单独拆一个「只跑 join」的开关。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 命令行覆盖：
	#   godot ... -- --splat-cache=off    不走展开缓存
	#   godot ... -- --splat=off          完全不加载泼溅
	#   godot ... -- --venue=room         只加载 venue 标签是 room 的那份（all = 全都要）
	# 加 --splat=off 是给玩法自检用的：615 万点的光栅化会拖慢每一条渲染相关的用例。
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--splat-cache="):
			cache_mode = a.substr(14)
		elif a.begins_with("--venue="):
			var want := a.substr(8)
			if want != "" and want != "all" and venue != "" and venue != want:
				print("[SplatScene] %s 不在 --venue=%s 里，跳过" % [display_name, want])
				_disable_placed_collision()
				return
		elif a == "--splat=off" or a == "--no-splat":
			print("[SplatScene] 命令行要求跳过泼溅加载")
			_disable_placed_collision()
			return
	if auto_start:
		if start_delay > 0.0 or start_distance > 0.0:
			_start_when_due()
		else:
			start()


## 按「延迟 / 距离」等一等再开始解码（见上面 `start_delay` 那段）。
## 两个条件**任意一个**满足就开：到点了，或者玩家自己走过来了。
func _start_when_due() -> void:
	print("[SplatScene] %s：延后加载（delay %.1f s / 距离 %.1f m / 低优先级 %s）"
		% [display_name, start_delay, start_distance, str(low_priority)])
	# ⚠️ 第一帧的检查必须等下一帧：从门进来时，玩家的落点是 `game.gd::_ready()`
	#    在**子节点 _ready 之后**才写的 —— 此刻玩家还站在场景的默认出生点
	#    （画室里面），按距离判会误判成「就在旁边」而立刻开始解码，
	#    结果整个换场景被泼溅打包拖到 7.6 s。等一帧，落点已经写好了。
	var t0 := Time.get_ticks_msec()
	while is_inside_tree() and not loading and splat_node == null:
		await get_tree().process_frame
		if _player_within_start_distance():
			print("[SplatScene] %s：玩家进入 %.1f m，开始解码"
				% [display_name, start_distance])
			break
		if start_delay > 0.0 \
				and float(Time.get_ticks_msec() - t0) / 1000.0 >= start_delay:
			print("[SplatScene] %s：等满 %.1f s，开始解码" % [display_name, start_delay])
			break
	if is_inside_tree() and not loading and splat_node == null:
		start()


func _player_within_start_distance() -> bool:
	if start_distance <= 0.0:
		return false
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		# 组是在 Player._ready() 里加的，而子节点的 _ready 顺序不保证它已经跑过 ——
		# 开局这一帧退回到按名字找（场景树里节点本身早就建好了）。
		var scene := get_tree().current_scene
		if scene != null:
			p = scene.get_node_or_null("Player") as Node3D
	return p != null and p.global_position.distance_to(global_position) <= start_distance


## 跳过加载时，把**预先摆在场景里**的碰撞一并关掉。
##
## ⚠️ 画室609 的四面墙现在是 game.tscn 里**手摆的静态节点**
## （`Room609/RoomCollision`，见 README §6.8），不再由 `_build_box_collision()`
## 在 `_finish()` 里生成 —— 也就是说它们**不受「加载没加载」影响**，一进场景
## 就在那儿挡人挡子弹。而一份没被加载的场地不该留下看不见的墙：不关的话，
## 带 `--splat=off` 的自检里子弹会被 z− 墙拦下（实测 `_verify_final` §6 靶子
## 100 → 100、`_verify_boss` 射线打不到本体、`_verify_mag` / `_verify_boss_pig`
## / `_verify_companion*` 会一起红）。
##
## 关法用 `collision_layer = 0`（而不是 `queue_free()`）：不改场景树结构、可逆，
## 也不影响自检去数节点。
func _disable_placed_collision() -> void:
	for child in get_children():
		if child is CollisionObject3D:
			var body := child as CollisionObject3D
			body.collision_layer = 0
			body.collision_mask = 0


func _process(delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
		_mutex.lock()
		var result := _result
		_mutex.unlock()
		_finish(result)
	_advance_collapse(delta)
	_advance_dynamic(delta)


# --- 对外接口 ---

## 后台开始解码；完成时发 loaded / failed
func start() -> void:
	if loading or splat_node != null:
		return
	var source := _resolve_source()
	if source == "":
		failed.emit("找不到 .sogdata：%s" % sog_path)
		return
	loading = true
	_start_ms = Time.get_ticks_msec()
	_thread = Thread.new()
	if low_priority:
		_thread.start(_worker.bind(source), Thread.PRIORITY_LOW)
	else:
		_thread.start(_worker.bind(source))


## 同步加载（探针 / 自检用；会冻住主线程几十秒）
func load_now(progress_cb: Callable = Callable()) -> Dictionary:
	var source := _resolve_source()
	if source == "":
		return {"ok": false, "message": "找不到 .sogdata"}
	_start_ms = Time.get_ticks_msec()
	var result: Dictionary = SogRuntime.load_sog(source, {
		"cache": cache_mode, "progress": progress_cb})
	_finish(result)
	return result


func is_ready() -> bool:
	return splat_node != null


## 内容（不含 floaters）在世界空间的包围盒
func content_world_aabb() -> AABB:
	var xf := global_transform * splat_node.transform if splat_node else global_transform
	return xf * AABB(content_min, content_max - content_min)


## 泼溅内容顶面在世界空间的 y（用于平台下沉校验）
func content_top_y() -> float:
	if not splat_node:
		return 0.0
	return (global_transform * splat_node.transform * content_max).y


## 按当前参数刷新子节点变换（运行时改 world_scale/yaw 后调用；auto_place 会重算偏移）
func apply_transform() -> void:
	if splat_node:
		splat_node.transform = Transform3D(_local_basis(), _resolve_offset())


# --- 坍缩 / 动态 3DGS ---------------------------------------------------------

## 当前缩放系数：1 = 原始大小，降到 collapse_min_scale = 塌成一点。
##
## staggered 模式下恒返回 1.0 —— 那条路的收缩是在着色器里逐高斯做的，
## 这里再乘一次就成了双重收缩。
func collapse_factor() -> float:
	if not collapse_enabled or collapse_mode == "staggered":
		return 1.0
	return maxf(1.0 - _collapse_ease(collapse_t), collapse_min_scale)


## 从 from_t 开始播放坍缩（默认从头）。
func play_collapse(from_t: float = 0.0) -> void:
	collapse_t = clampf(from_t, 0.0, 1.0)
	_collapse_clock = 0.0
	_collapse_dir = 1.0
	collapsing = true
	apply_transform()
	_apply_collapse_fade()
	_push_dynamic()


## 立刻回到原始大小。
func reset_collapse() -> void:
	collapsing = false
	collapse_t = 0.0
	_collapse_clock = 0.0
	_collapse_dir = 1.0
	apply_transform()
	_apply_collapse_fade()
	_push_dynamic()


## 直接切到某个进度，不启动时钟。给探针 / Sequencer / 外部驱动用。
func set_collapse(t: float) -> void:
	collapse_t = clampf(t, 0.0, 1.0)
	collapsing = false
	apply_transform()
	_apply_collapse_fade()
	_push_dynamic()


func _collapse_ease(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	match collapse_easing:
		"linear":
			return u
		"in_quad":
			return u * u
		"in_cubic":
			return u * u * u
		"in_quart":
			return u * u * u * u
		"out_cubic":
			return 1.0 - pow(1.0 - u, 3.0)
		"in_out_cubic":
			return 4.0 * u * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 3.0) * 0.5
		_:
			return u


## 每帧推进坍缩时钟。
##
## splat_node 还是 null 时直接不动 —— 画室 609 那档要解码 21 s，
## 若从 _ready 就开始计时，等画面出来时动画早跑完了。
func _advance_collapse(delta: float) -> void:
	if not collapsing or splat_node == null:
		return
	_collapse_clock += delta
	var t := 0.0
	if collapse_duration <= 0.0:
		t = 1.0
	else:
		# 停顿只在正向那一段生效，倒放（ping-pong）时不再等一次。
		var pause := collapse_delay if _collapse_dir > 0.0 else 0.0
		t = clampf((_collapse_clock - pause) / collapse_duration, 0.0, 1.0)
	if _collapse_dir < 0.0:
		t = 1.0 - t
	collapse_t = t
	apply_transform()
	_apply_collapse_fade()
	if t >= 1.0 or t <= 0.0:
		if collapse_ping_pong:
			_collapse_dir = -_collapse_dir
			_collapse_clock = 0.0
		else:
			collapsing = false


# --- 逐高斯路径（错峰坍缩 + 布朗漂移）---

## 把逐高斯参数推给泼溅节点；光栅后端每帧轮询它们并写进材质。
func _push_dynamic() -> void:
	if splat_node == null or not ("dynamic_active" in splat_node):
		return
	var active := collapse_enabled and collapse_mode == "staggered"
	splat_node.set("dynamic_active", active)
	splat_node.set("dynamic_t", collapse_t)
	splat_node.set("dynamic_center", _content_center)
	splat_node.set("dynamic_stagger", collapse_stagger)
	splat_node.set("dynamic_ease", collapse_shader_ease)
	splat_node.set("dynamic_min_scale", collapse_min_scale)
	splat_node.set("dynamic_fade", collapse_shader_fade)
	splat_node.set("dynamic_seed", brownian_seed)
	splat_node.set("dynamic_brownian_amp", brownian_amp)
	splat_node.set("dynamic_brownian_freq", brownian_freq)
	splat_node.set("dynamic_rise_speed", rise_speed)
	splat_node.set("dynamic_rise_jitter", rise_jitter)
	splat_node.set("dynamic_rise_side", rise_side)
	splat_node.set("dynamic_rise_loop", rise_loop)
	splat_node.set("dynamic_rise_span", rise_span)
	splat_node.set("dynamic_rise_fade", rise_fade)
	splat_node.set("dynamic_time", _dynamic_clock if dynamic_auto_time else dynamic_time)


## 推进动态时钟，并把逐高斯参数刷新到节点上。
##
## 为什么必须每帧推：着色器是无状态的，每个高斯的漂移/上升位置完全由
## anim_time 决定，而材质只能从节点属性里读到它 —— 所以得由这里持续刷。
## 既没开错峰坍缩、也没开布朗、也没开上升时直接返回，零开销。
func _advance_dynamic(delta: float) -> void:
	if splat_node == null:
		return
	var staggered := collapse_enabled and collapse_mode == "staggered"
	var needs_clock := brownian_amp > 0.0 or rise_speed > 0.0
	if not staggered and not needs_clock:
		return
	if needs_clock and dynamic_auto_time:
		_dynamic_clock += delta
	_push_dynamic()


var _fade_mesh: GeometryInstance3D = null


## 可选的整体淡出。后端把 MultiMeshInstance3D 当 INTERNAL 子节点挂在泼溅
## 节点下，所以这里写它的 transparency，不用碰插件一行代码。
func _apply_collapse_fade() -> void:
	# staggered 模式的淡出是着色器里逐高斯做的（透明度归零会把 quad 收到 0），
	# 这里再用节点 transparency 淡一次就是双重淡出。
	if not collapse_fade or collapse_mode == "staggered" or splat_node == null:
		return
	if _fade_mesh == null or not is_instance_valid(_fade_mesh):
		_fade_mesh = _find_render_mesh()
		if _fade_mesh == null:
			return
	var span := maxf(1.0 - collapse_fade_from, 0.0001)
	_fade_mesh.transparency = clampf((collapse_t - collapse_fade_from) / span, 0.0, 1.0)


## 按类型找后端的渲染网格，不依赖它的名字（_GdgsRasterSplat 属于插件内部约定）。
func _find_render_mesh() -> GeometryInstance3D:
	if splat_node == null:
		return null
	for child in splat_node.get_children(true):
		if child is GeometryInstance3D:
			return child
	return null


# --- 内部 ---

func _resolve_source() -> String:
	if FileAccess.file_exists(sog_path):
		return sog_path
	return SogRuntime.find_source(sog_path)


func _worker(source: String) -> void:
	var result: Dictionary = SogRuntime.load_sog(source, {
		"cache": cache_mode,
		"progress": Callable(self, "_on_progress_from_thread"),
	})
	_mutex.lock()
	_result = result
	_mutex.unlock()


## ⚠️ 这个回调在**工作线程**里执行：只能写变量 / 发延迟信号，绝不能碰场景树与 UI
func _on_progress_from_thread(phase: String, done: int, total: int) -> void:
	progress.emit.call_deferred(phase, done, total)


func _finish(result: Dictionary) -> void:
	loading = false
	elapsed_seconds = float(Time.get_ticks_msec() - _start_ms) / 1000.0
	if not bool(result.get("ok", false)):
		failed.emit(String(result.get("message", result)))
		return

	var res: Resource = result["resource"]
	splat_center = result.get("center", Vector3.ZERO)
	splat_aabb = res.get("aabb")
	point_count = int(res.get("point_count"))
	var bounds := content_bounds(res)
	content_min = bounds["min"]
	content_max = bounds["max"]

	# 裁掉离群 floaters（必须在算内容盒之后、建节点之前）
	crop_stats = {}
	if crop_enabled:
		var cropped := _crop_resource(res)
		if bool(cropped.get("ok", false)):
			crop_stats = cropped
			res = cropped["resource"]
			point_count = int(res.get("point_count"))
			splat_aabb = res.get("aabb")
			var cb := content_bounds(res)
			content_min = cb["min"]
			content_max = cb["max"]

	# 逐高斯坍缩的收敛点（源坐标）。必须在建节点之前定好，否则第一帧的
	# _push_dynamic 会把 0 当成收敛点推下去。
	_content_center = (content_min + content_max) * 0.5
	splat_node = GaussianSplatNodeScript.new()
	splat_node.name = "Splat"
	splat_node.set("gaussian", res)
	add_child(splat_node)
	apply_transform()
	if collapse_enabled and collapse_auto_play:
		play_collapse()
	if build_collision:
		_build_collision()
	if build_box_collision:
		_build_box_collision()

	var info := {
		"point_count": point_count,
		"aabb": splat_aabb,
		"content_min": content_min,
		"content_max": content_max,
		"content_world": content_world_aabb(),
		"center": splat_center,
		"elapsed": elapsed_seconds,
		"from_cache": bool(result.get("from_cache", false)),
		"source": String(result.get("source", sog_path)),
		"crop": crop_stats,
	}
	if crop_enabled and not crop_stats.is_empty():
		print("[SplatScene] 裁剪：留 %d 点，丢 %d 点（其中椭球过大 %d），盒 %s" % [
			int(crop_stats["kept"]), int(crop_stats["dropped"]),
			int(crop_stats["scale_dropped"]), str(crop_stats["box"])])
	print("[SplatScene] 完成：%d 点，耗时 %.1f s（缓存 %s）" % [
		point_count, elapsed_seconds, str(info["from_cache"])])
	print("[SplatScene] 内容源尺寸 %s → 世界尺寸 %s，顶面 y=%.2f" % [
		str((content_max - content_min).snappedf(0.01)),
		str(content_world_aabb().size.snappedf(0.1)),
		content_top_y()])
	loaded.emit(info)


func _local_basis() -> Basis:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_degrees)) \
		* Basis.from_scale(Vector3(world_scale, world_scale, world_scale))
	if use_default_orientation:
		b = b * GaussianSplatNodeScript.get_model_orientation_correction().basis
	# 坍缩系数。均匀缩放与旋转可交换，所以乘在最后即可，不影响 yaw 校正。
	return b * Basis.from_scale(Vector3.ONE * collapse_factor())


## 自动摆放：水平把内容中心对到原点，竖向把内容顶面沉到 -top_gap
func _resolve_offset() -> Vector3:
	if auto_place:
		var center := (content_min + content_max) * 0.5
		return Vector3(
			-center.x * world_scale,
			-top_gap - content_max.y * world_scale,
			-center.z * world_scale)
	if use_anchor:
		# 世界点 = 局部基 × 源点 + offset，所以把源锚点对到 anchor_world 就是
		# offset = anchor_world − 局部基 × anchor_source
		return anchor_world - _local_basis() * anchor_source
	return offset


## 按内容 1‰~99.9‰ 分位盒（外扩 crop_margin）+ 可选椭球尺度阈值裁剪点数据。
##
## 为什么要裁：俯拍重建里总有少量又大又远的离群椭球（本工程实测：0.2% 的点、
## 单个椭球尺度可达 15 源单位）。放大到场地尺度后它们就是几百米的大白团，
## 糊满半个屏幕 —— 校园那份只能靠 top_gap 把它们顶到平台上方，
## 而摆在地面上的房间没有这个余量，必须在数据层裁掉。
##
## 实现按「连续段」整段复制（slice + append_array），不是逐点拷贝 240 字节，
## 所以 277 万点只花 0.3 s 左右。
func _crop_resource(res: Resource) -> Dictionary:
	var bytes: PackedByteArray = res.get("point_data_byte")
	var xyz: PackedVector3Array = res.get("xyz")
	var count := int(res.get("point_count"))
	if bytes.size() < count * BYTES_PER_SPLAT:
		count = bytes.size() / BYTES_PER_SPLAT
	if count <= 0:
		return {"ok": false}
	if xyz.size() < count:
		xyz = PackedVector3Array()
		xyz.resize(count)
		for i in count:
			var o := i * BYTES_PER_SPLAT
			xyz[i] = Vector3(
				bytes.decode_float(o), bytes.decode_float(o + 4), bytes.decode_float(o + 8))

	var box := AABB(
		content_min - Vector3.ONE * crop_margin,
		(content_max - content_min) + Vector3.ONE * crop_margin * 2.0)
	var box_hi := box.position + box.size

	var out_bytes := PackedByteArray()
	var out_xyz := PackedVector3Array()
	var aabb_min := Vector3(INF, INF, INF)
	var aabb_max := Vector3(-INF, -INF, -INF)
	var kept := 0
	var dropped := 0
	var scale_dropped := 0
	var run_start := -1
	for i in count:
		var p: Vector3 = xyz[i]
		var keep := p.x >= box.position.x and p.x <= box_hi.x \
			and p.y >= box.position.y and p.y <= box_hi.y \
			and p.z >= box.position.z and p.z <= box_hi.z
		if keep and crop_max_scale > 0.0:
			var off := i * BYTES_PER_SPLAT
			var worst := 0.0
			for f in [4, 7, 9]:
				worst = maxf(worst, sqrt(maxf(bytes.decode_float(off + f * 4), 0.0)))
			if worst > crop_max_scale:
				keep = false
				scale_dropped += 1
		if keep:
			if run_start < 0:
				run_start = i
			kept += 1
			aabb_min = aabb_min.min(p)
			aabb_max = aabb_max.max(p)
		else:
			dropped += 1
			if run_start >= 0:
				out_bytes.append_array(bytes.slice(
					run_start * BYTES_PER_SPLAT, i * BYTES_PER_SPLAT))
				out_xyz.append_array(xyz.slice(run_start, i))
				run_start = -1
	if run_start >= 0:
		out_bytes.append_array(bytes.slice(
			run_start * BYTES_PER_SPLAT, count * BYTES_PER_SPLAT))
		out_xyz.append_array(xyz.slice(run_start, count))

	var cropped: Resource = GaussianResourceScript.new()
	cropped.set("point_count", kept)
	cropped.set("point_data_byte", out_bytes)
	cropped.set("xyz", out_xyz)
	cropped.set("aabb", AABB(aabb_min, aabb_max - aabb_min) if kept > 0 else AABB())
	return {
		"ok": true, "resource": cropped, "kept": kept, "dropped": dropped,
		"scale_dropped": scale_dropped, "box": box,
	}


## 抽样点数据算分位数包围盒。结构：每点 60 float，[0..2] = 已中心化的 xyz，
## 后面依次是 6 个协方差、透明度、48 个 SH 系数（见 gaussian_resource_builder.gd:82）。
## 为什么要分位数：原始 aabb 会被离群 floaters 撑大（实测 15.8×3.0×12.0 vs 内容 8.5×0.7×6.4）。
static func content_bounds(res: Resource, samples := 20000) -> Dictionary:
	var bytes: PackedByteArray = res.get("point_data_byte")
	var count := int(res.get("point_count"))
	if bytes.size() < count * BYTES_PER_SPLAT:
		count = bytes.size() / BYTES_PER_SPLAT
	var step := maxi(1, count / maxi(samples, 1))
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var i := 0
	while i < count:
		var off := i * BYTES_PER_SPLAT
		xs.append(bytes.decode_float(off))
		ys.append(bytes.decode_float(off + 4))
		zs.append(bytes.decode_float(off + 8))
		i += step
	xs.sort()
	ys.sort()
	zs.sort()
	var n := xs.size()
	if n == 0:
		return {"min": Vector3.ZERO, "max": Vector3.ZERO}
	var lo := int(n * 0.001)
	var hi := mini(int(n * 0.999), n - 1)
	return {
		"min": Vector3(xs[lo], ys[lo], zs[lo]),
		"max": Vector3(xs[hi], ys[hi], zs[hi]),
	}


## 房间碰撞：按内容包围盒做四面墙（可留一个门洞）。
##
## 为什么不用 GDGS 的碰撞管线从点云生成三角网：那条路要给 277 万点建体素索引
## 再 marching cubes，慢且结果不可控；这间房**已经轴对齐**、形状就是个矩形，
## 四面盒子又稳又快，而且哪面是门可以明确指定。
##
## 坐标：包围盒是世界空间，但碰撞体挂在**本节点**下，所以先用
## global_transform 的逆变换回本节点局部空间（本工程里节点是单位变换，等价）。
func _build_box_collision() -> void:
	var box := content_world_aabb()
	if box.size.length() <= 0.001:
		push_warning("[SplatScene] 内容包围盒是空的，不能生成房间碰撞")
		return
	var local_box: AABB = global_transform.affine_inverse() * box
	var body := StaticBody3D.new()
	body.name = "RoomCollision"
	add_child(body)
	var t := maxf(box_wall_thickness, 0.05)
	var lo := local_box.position
	var hi := local_box.position + local_box.size
	var made := 0
	made += _add_room_wall(body, local_box, 0, lo.x, lo.x + t, "x-")
	made += _add_room_wall(body, local_box, 0, hi.x - t, hi.x, "x+")
	made += _add_room_wall(body, local_box, 2, lo.z, lo.z + t, "z-")
	made += _add_room_wall(body, local_box, 2, hi.z - t, hi.z, "z+")
	var door := "（四面封死）" if (box_door_side == "none" or box_door_side == "") else \
		"门在 %s 面，宽 %.2f m，中心 %.2f" % [box_door_side, box_door_width, box_door_center]
	print("[SplatScene] 房间碰撞：%d 个盒，墙厚 %.2f m，%s" % [made, t, door])
	print("[SplatScene] 房间矩形（本节点局部）pos %s size %s" % [
		str(lo.snappedf(0.01)), str((hi - lo).snappedf(0.01))])


## 加一面墙：法线沿 `normal_axis`（0=x / 2=z），厚度占 [n_lo, n_hi]。
## 如果这面正是门那一面，就按 `box_door_center ± box_door_width/2` 切成两段。
## 返回实际加进去的盒子数。
func _add_room_wall(body: StaticBody3D, box: AABB, normal_axis: int,
		n_lo: float, n_hi: float, side_name: String) -> int:
	var along_axis := 2 if normal_axis == 0 else 0
	var lo := box.position
	var hi := box.position + box.size
	var a_lo: float = lo.x if along_axis == 0 else lo.z
	var a_hi: float = hi.x if along_axis == 0 else hi.z
	var segs: Array[Vector2] = []
	if box_door_side == side_name and box_door_width > 0.05:
		segs.append(Vector2(a_lo, clampf(box_door_center - box_door_width * 0.5, a_lo, a_hi)))
		segs.append(Vector2(clampf(box_door_center + box_door_width * 0.5, a_lo, a_hi), a_hi))
	else:
		segs.append(Vector2(a_lo, a_hi))
	var made := 0
	for s in segs:
		var length := s.y - s.x
		if length <= 0.05:
			continue
		var size := Vector3.ZERO
		var pos := Vector3.ZERO
		if normal_axis == 0:
			size = Vector3(n_hi - n_lo, hi.y - lo.y, length)
			pos = Vector3(n_lo, lo.y, s.x)
		else:
			size = Vector3(length, hi.y - lo.y, n_hi - n_lo)
			pos = Vector3(s.x, lo.y, n_lo)
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.name = "Wall%d" % made
		cs.shape = shape
		cs.position = pos + size * 0.5     # CollisionShape3D 的位置是盒中心
		body.add_child(cs)
		made += 1
	return made


## 把碰撞 GLB 包成三角网格碰撞体。GLB 在「源坐标系」，渲染是「减去中心」的，
## 所以整体平移 -center 后再跟随泼溅节点变换。
func _build_collision() -> void:
	var scene: PackedScene = load(collision_glb)
	if scene == null:
		push_warning("[SplatScene] 缺少碰撞 GLB：%s" % collision_glb)
		return
	var root_node := scene.instantiate()
	var body := StaticBody3D.new()
	body.name = "SplatCollision"
	body.transform = Transform3D(Basis.IDENTITY, -splat_center)
	splat_node.add_child(body)
	var shapes := 0
	for mi in _all_meshes(root_node):
		if mi.mesh == null:
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var cs := CollisionShape3D.new()
		cs.name = "Shape%d" % shapes
		cs.shape = shape
		cs.transform = mi.transform
		body.add_child(cs)
		shapes += 1
	root_node.queue_free()
	print("[SplatScene] 碰撞三角网格 %d 个" % shapes)


func _all_meshes(root_node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
