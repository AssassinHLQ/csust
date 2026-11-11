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
## 玩家在这个世界空间盒子里时隐藏泼溅。室内场景用：GDGS 没有深度测试，
## 室外校园会直接糊在墙/天花板上；同时 615 万点的投影/排序也能省掉。
## 尺寸为 0 = 关闭。
@export var hide_inside_aabb := AABB()
## 场景门切换时，要不要在「载入中」黑屏里把它预载完。
## 小场地（画室 609，~700 MB）预载能消掉进场后那次上传卡顿；
## 长沙理工校园（615 万点、约 2.9 GiB）不行 —— 预载会把黑屏拖到几十秒，
## 所以它设成 false，进场后按 `start_delay` 自己在后台慢慢解。
@export var preload_on_gate := true
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

## ── 出房间就释放 GPU 显存（2026-11-06，2026-11-08 改成「门框判据」）──
##
## 用户原话：「只在609内部开，出去直接释放显存，设置可以开关这个选项，
##           如果打开就是显存很友好，但是每次进入609要加载」。
## 2026-11-08 追加：「换个思路，之前不是出门就隐藏高斯泼溅吗，
##                   把隐藏改成关闭就行了，进门再开」+「跨出门框就释放，零延迟」。
##
## 由设置项 `splat_unload_outside` 控制（2026-11-08 起**默认开启**）。
##
## 判据用**水平范围（XZ）**，不用 `content_world_aabb` 的 y：
## 那个盒是 8.29 m 高（含屋顶与地板下方），拿它判 y 会让「站在楼下/屋顶上」都算室内。
##
## ⚠️ 2026-11-08 实测教训：旧判据拿 `splat_aabb`（**点云整体**的源空间盒）算水平范围，
##    画室609 得到 x −18.0~16.4 / z −14.6~22.5（外扩 2 m 之后），
##    而真实房间的墙只到 x −5.85~4.86 / z −6.78~13.86 —— 范围大了三倍多。
##    人被墙挡着**永远走不到**那个边界，所以开关打开也从来不触发，看起来像「没释放」。
##    现在改成：优先用 `RoomCollision` 里**墙碰撞盒**的世界 AABB 当房间边界（那才是
##    玩家真的能走到的范围），没有墙碰撞盒时才退回点云范围。
##
## ⚠️ 这里必须**真的把节点释放掉**：`visible = false` 不还显存。
##    只有让 `GaussianSplatNode._exit_tree()` 走到
##    `unregister_splat_node()`，注册表才会在「一个泼溅节点都不剩」时返回
##    `request_cleanup`，`GaussianGpuStateCache.cleanup_all()` 才会把那一整套
##    1.28 GB 缓冲还掉（splats 665 + culled 177 + sort_keys/values 各 221 MB）。
@export var unload_outside_room := true
## 水平外扩余量（米）。**现在只作用于「退回点云范围」那条兜底路径**；
## 用墙碰撞盒时余量恒为 0 —— 用户要的是「跨出门框就释放」，多留余量就变成「走出去好几米才释放」。
@export var unload_pad := 2.0
## 走出范围多久之后才真的释放（秒）。2026-11-08 改为 0（零延迟），
## 因为判据已经收到门框内沿，再叠延迟会让「刚出门还挂着」看得很明显。
## 留一个极小的防抖量（见 `_UNLOAD_DEBOUNCE`），只在**同一帧内反复横跳**时兜底。
@export var unload_delay := 0.0
## 回到范围内之后多久才重载（秒）。同样归零：进门立刻开始后台解码。
@export var reload_delay := 0.0

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
## 这次加载失败了（`_finish` 里设）。场景门预载时用它判断「等完了没有」。
## 名字不能叫 `failed` —— 和上面的 `failed` 信号重名。
var load_failed := false
## 上一次展开（含裁剪）的结果，按「源文件 + 修改时间 + 裁剪参数」缓存。
## 场景来回切时同一个 .sogdata 会反复展开；缓存住这份 665 MB 的 CPU 数据，
## 回程就只剩 GDGS 的 GPU 上传（~2 s），不用再花 3 s 展开 + 裁剪。
## 只占内存、不占显存 —— 换场景时显存照常释放。
static var _res_cache := {}
var elapsed_seconds := 0.0

var _thread: Thread = null
var _mutex := Mutex.new()
var _result: Dictionary = {}
var _start_ms := 0
## ── 出房间释放（见 `unload_outside_room`）──
## 缓存的水平范围（点云释放之后 `content_world_aabb()` 就没了，所以必须存下来）
var _room_xz := Rect2()
## `_room_xz` 是不是由**墙碰撞盒**算出来的（true 时不允许被点云兜底覆盖）
var _room_xz_is_walls := false
## 房间的高度窗口（世界 y）。见 `_room_xz_from_walls()` 里那段「为什么上面也加载」。
## 相等 / 反序 = 没算出来，此时只按 XZ 判。
var _room_y_lo := 0.0
var _room_y_hi := 0.0
## 玩家在范围内的累计秒数 / 在范围外的累计秒数（去抖用）
var _inside_clock := 0.0
var _outside_clock := 0.0
## 连续在范围外 / 内的帧数（门框防抖，见 `_EDGE_FRAMES`）
var _inside_streak := 0
var _outside_streak := 0
## 被「出房间释放」卸掉过（用来区分「从没加载」和「加载过又被释放」）
var _unloaded_by_room_exit := false


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
	# 「出房间就释放泼溅显存」的设置：读一次 + 登记监听（面板改完立刻生效）
	unload_outside_room = bool(GameSettings.value("splat_unload_outside"))
	GameSettings.listen(_on_settings_changed)
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
	_update_inside_hide()
	_update_room_exit_unload(delta)


## 读设置：「出房间就释放泼溅显存」。设置面板改完立刻生效，不用重启。
func _apply_unload_setting() -> void:
	var want := bool(GameSettings.value("splat_unload_outside"))
	if want == unload_outside_room:
		return
	unload_outside_room = want
	if not want:
		# 关掉时如果正被卸着，立刻装回来；否则就继续常驻。
		_inside_clock = 0.0
		_outside_clock = 0.0
		if _unloaded_by_room_exit and splat_node == null and not loading:
			_reload_after_unload()
	elif splat_node != null:
		_remember_room_xz()


## 记住「房间」的水平范围，供 `_update_room_exit_unload()` 判内外用。
##
## 两条路，优先第一条：
##
## **① 墙碰撞盒（首选，2026-11-08 起）**：读 `RoomCollision` 下所有
##    `CollisionShape3D` 的世界 AABB，取它们围成的外框，再往里收 `_WALL_INSET`。
##    这才是**玩家真的能走到的范围** —— 用户要的「跨出门框就释放」，门框就在这儿。
##    实测画室609：框是 x −5.85~4.86 / z −6.78~13.86，和「一出门就释放」对得上。
##
## **② 点云范围（兜底）**：没有墙碰撞盒时退回 `splat_aabb`（点云整体）+ `unload_pad`。
##    ⚠️ 这个盒比真实房间大得多（609：x −16~14.4 / z −12.6~20.5），
##       拿它当判据会「永远走不出去」，只在没有手摆墙的场地里当粗略兜底。
##
## ⚠️ 变换要用 `global_transform × (_local_basis(), _resolve_offset())` —— 这是给
##    **源空间**点云盒换算**世界**坐标用的。碰撞盒已经在世界空间了，**不要**再过一遍，
##    否则会缩放两次。
##
## ⚠️ 2026-11-11 实测翻车：这里原来只乘 `_local_basis() * corner + _resolve_offset()`，
##    **漏了节点自己的 `global_transform`**，算出来的是「局部空间盒」。
##    画室 609 的节点摆在世界原点，所以这个错误一直没暴露；
##    校园节点带 `(0, 49.81, -316.7)` + 1.16°/0.43° 倾角，于是：
##      判据高度窗口 = y -110.6 ~ -71.4（真实世界点是 -29.1 ~ +31.7，玩家站 y=0）
##      ⇒ 玩家永远判成「屋外」，泼溅一显示就被 `_unload_for_vram()` 放掉 ——
##        用户看到的是「什么都看不见」。
##      XZ 也一起歪了（z -278~+274，把大厅都算进校园）。
##    `content_world_aabb()` 一直是**对的**（它乘了 `global_transform`），
##    所以探针量出来的盒子和判据对不上时，先怀疑这里。
func _remember_room_xz() -> void:
	var wall_rect := _room_xz_from_walls()
	if wall_rect.size != Vector2.ZERO:
		_room_xz = wall_rect
		_room_xz_is_walls = true
		print("[SplatScene] 房间水平范围（墙碰撞盒内沿）：x %.2f~%.2f，z %.2f~%.2f" % [
			_room_xz.position.x, _room_xz.position.x + _room_xz.size.x,
			_room_xz.position.y, _room_xz.position.y + _room_xz.size.y])
		return
	# 墙框已经算出来过就**不要**被兜底路径覆盖：手摆的墙在某些时机
	# （比如 reload 时节点还没挂回树）可能读不到，这时候退回大盒会让判据失效。
	if _room_xz_is_walls and _room_xz.size != Vector2.ZERO:
		return
	# ── 用哪一份盒？──
	# `splat_aabb` 是 `SogRuntime.load_sog()` 返回的 `aabb`，**已经过模型朝向校正**；
	# `content_min/content_max` 是**原始 SOG 空间**的内容盒（裁剪后）。
	# `use_default_orientation = true` 时两者差一个 180° 翻转，混用就会错一整个内容高度
	# （校园实测：splat_aabb 映射到 y −69.7~−29.1，content 盒映射到 y −29.1~+31.7，
	#  玩家站 y=0 —— 拿前者当判据必然判成「屋外」）。
	# 所以这里统一走 content 盒，和 `content_world_aabb()` 完全同一套坐标。
	var a := AABB()
	if content_max.y > content_min.y:
		a = AABB(content_min, content_max - content_min)
	if a.size == Vector3.ZERO:
		a = splat_aabb
	if a.size == Vector3.ZERO:
		return
	# 源空间 → 世界空间：先 `_local_basis()`/`_resolve_offset()` 出局部盒，
	# 再乘节点自己的 `global_transform`。两步都不能少（见上面 2026-11-11 那段）。
	var xf := global_transform * Transform3D(_local_basis(), _resolve_offset())
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in 8:
		var corner := a.position + Vector3(
			a.size.x * float(i & 1),
			a.size.y * float((i >> 1) & 1),
			a.size.z * float((i >> 2) & 1))
		var w := xf * corner
		lo = lo.min(w)
		hi = hi.max(w)
	_room_xz = Rect2(lo.x - unload_pad, lo.z - unload_pad,
		(hi.x - lo.x) + unload_pad * 2.0, (hi.z - lo.z) + unload_pad * 2.0)
	# 兜底路径也要给高度窗口，否则 `_room_y_lo == _room_y_hi == 0` 会被当成
	# 「没算出来」而只按 XZ 判 —— 那正是「站屋顶也加载」的老毛病。
	# 上面已经改用 content 盒，`hi.y` 就是**内容顶**（不含离群椭球），
	# 所以上限直接用它可以，不需要再从 `content_max` 单独换算一次
	# （2026-11-11：那次换算是按「splat_aabb + 原始 content_max」写的，
	#  朝向校正一介入就换错了轴，校园整片被判到地下）。
	_room_y_lo = lo.y
	_room_y_hi = hi.y
	print("[SplatScene] 房间水平范围（点云整体 + %.1f m 余量，无墙碰撞盒兜底）：x %.1f~%.1f，z %.1f~%.1f，y %.1f~%.1f" % [
		unload_pad,
		_room_xz.position.x, _room_xz.position.x + _room_xz.size.x,
		_room_xz.position.y, _room_xz.position.y + _room_xz.size.y,
		_room_y_lo, _room_y_hi])


## 房间边界往里收多少米。
##
## ── 2026-11-08 「我要进去才加载」──
## 用户原话：「为什么这个高斯泼溅在靠近门的地方就加载，**我要进去才加载**」，
## 实测位置 `(5.74, 0.00, 1.81)` —— 这在门那条墙的**外侧**，人还没进屋。
##
## 旧值 0.05 只把墙盒外框收 5 cm，但**墙有 0.30 m 厚**：
##   墙外表面 x=4.86 → 判据边界 4.81，而墙内表面在 4.56。
##   于是「站在墙里那一层」和「贴着墙根走」都算屋里，人还没迈过门槛就加载了。
##
## 现在改成**收满墙厚再多吃 0.10 m**，判据边界落在**墙内表面再往里**：
##   墙外 4.86 − 0.30（墙厚）− 0.10 = 4.46  →  跨过门槛才加载。
## 代价：门口那 10 cm 仍然算屋外，视觉上「进门」和「加载」差十几厘米，可接受。
##
## ⚠️ 墙厚是**逐面量**的（不是写死 0.30）：有的场地墙更厚，写死会误判。
##    见 `_wall_inset_xz()` 里按每面墙的实际厚度各收各的。
const _WALL_INSET := 0.10
## 门槛防抖：范围判定每帧都跑，脚踩在门框线上会左右横跳。
## 只有**连续两帧**都在同一侧才认账 —— 相当于 ~33 ms（60 fps），人感觉不到，
## 但能挡住一帧抖动引起的「释放→重载」循环。
const _EDGE_FRAMES := 2


## 从 `RoomCollision` 的墙碰撞盒算出房间水平矩形（世界空间）+ 高度窗口。
## 没有墙碰撞盒 / 尺寸为 0 时返回空 `Rect2()`，让调用方走兜底。
##
## ── 为什么要带高度（2026-11-08 用户：「为什么上面也加载?!」）──
## 只判 XZ 会把**屋顶上**当成屋里：用户实测站在屋顶 `y = 5.80`、
## 水平 `(x, z) = (-1.30, 3.84)`（在门框矩形内），609 的泼溅就被重新加载了，
## 显存又涨回 2299 MiB、FPS 掉到 4.0。屋顶本来就在房间正上方，XZ 判据分不出来。
##
## 高度窗口取**墙盒的 y 范围**（609 实测 −2.65~5.65）。墙盒从 −2.65 起是因为
## 它埋在平台下面防穿地 —— 玩家正常活动在 `y ≈ 0`（平台面），
## 所以下限用墙底、上限用墙顶，正好覆盖「人在屋里」的全部高度。
##
## ⚠️ 不能用墙盒**完整** y 范围而不留余量：玩家跳跃时头顶会短暂高过墙顶。
## ⚠️ 也不能把上限压到平台面（y=0）：二楼/攀爬类场地会误判。
##
## ── 上限为什么严格取「墙顶」（2026-11-08 第二版）──
## 第一版上限取了 `墙顶 + 0.30`（6.10），结果用户报的那个位置 `y = 5.80`
## （站屋顶板上）**还是落在窗口里**，照样加载。
## 实测 609：墙顶 **5.65**、屋顶板顶面 **5.80** —— 屋顶板比墙还高，
## 站在屋顶上时脚底就在 5.80。任何「墙顶 + 正余量」都会把它包进去。
## 所以上限**严格等于墙顶**，站在屋顶上必然判成「屋外」。
## 下限给 `_PLAYER_HEIGHT` 的宽限（人从屋顶边的墙里往下掉时才算进屋）。
## 估算用的玩家脚底到头顶高度（胶囊 y ≈ 1.8 m）。
const _PLAYER_HEIGHT := 1.8


func _room_xz_from_walls() -> Rect2:
	var col := get_node_or_null("RoomCollision")
	if col == null:
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var y_lo := INF
	var y_hi := -INF
	var found := false
	for c in col.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var raw: Vector3 = (cs.shape as BoxShape3D).size
		# ⚠️ 必须用 `Transform3D × AABB`，**不能**用 `size * 0.5 * basis.get_scale()`。
		#    实测教训（2026-11-08）：`WallZNegB` 这个盒子绕 Y 转了 90°，
		#    它的局部 X（size.x = 2.984）实际指向**世界 Z**。用 scale 相乘去算世界 X，
		#    得到 x 3.166~6.150；真实 AABB 只有 x 4.508~4.808 —— 右边界被撑大 1.3 m，
		#    于是「站在墙外还没进门」也被判成在屋里，泼溅照样加载（用户报的现象）。
		#    `global_transform * AABB(-size*0.5, size)` 会正确处理旋转，是正解。
		var b: AABB = cs.global_transform * AABB(-raw * 0.5, raw)
		lo = lo.min(Vector2(b.position.x, b.position.z))
		hi = hi.max(Vector2(b.position.x + b.size.x, b.position.z + b.size.z))
		# 高度只认**墙**（高盒子）：屋顶板/家具是扁的，它们会把 y 范围带歪。
		# 判据跟 `game.gd::ROOM_WALL_MIN_HEIGHT` 一致（2.0 m）。
		if raw.y > 2.0:
			y_lo = minf(y_lo, b.position.y)
			y_hi = maxf(y_hi, b.position.y + b.size.y)
		found = true
	if not found or hi.x <= lo.x or hi.y <= lo.y:
		return Rect2()
	# 高度窗口：墙底 → 墙顶。
	# 实测 609 墙顶 5.65、屋顶板顶面 5.80 —— 站在屋顶上时脚底在 5.80 > 5.65，
	# 一定判成「屋外」。这就是用户要的「上面不该加载」。
	#
	# ⚠️ 余量加在**上限之上**会很危险：加 0.30 就到 5.95，而用户站的是 5.80，
	#    又会被包进去（本喵第一版就是这么错的）。所以上限严格取墙顶。
	_room_y_lo = y_lo
	_room_y_hi = y_hi
	# ── 四个方向各收各的（按那一侧墙的真实厚度）──
	# 旧写法是「四边统一收 _WALL_INSET」，但墙厚是逐面变化的：
	# 只收 5 cm 的话，判据边界还停在墙**里面**，人站在墙外侧就已经算「进屋」了。
	# 正确做法：每一侧找**贴着那一侧**的墙，按它的厚度把边界推到墙内表面，
	# 再多收 `_WALL_INSET` 当门槛前的缓冲。
	var inset_x_min := _side_wall_thickness(col, "x", -1)
	var inset_x_max := _side_wall_thickness(col, "x", 1)
	var inset_z_min := _side_wall_thickness(col, "z", -1)
	var inset_z_max := _side_wall_thickness(col, "z", 1)
	return Rect2(lo.x + inset_x_min, lo.y + inset_z_min,
		(hi.x - lo.x) - inset_x_min - inset_x_max,
		(hi.y - lo.y) - inset_z_min - inset_z_max)


## 求「贴着某一侧的那面墙」有多厚（世界单位）。
##
## `axis` = "x" / "z"，`sign` = -1（负侧）/ +1（正侧）。
## 做法：在所有墙盒里，找**外表面正好贴着整体外框那一侧**的盒子，
## 取它在 `axis` 方向上的真实世界厚度（用旋转后的 AABB 量，不是 `size`）。
## 找不到（那一侧没有墙，比如开放式场地）就返回 0，让矩形保持原边界。
func _side_wall_thickness(col: Node, axis: String, sign: int) -> float:
	# 先求整体外框
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for c in col.get_children():
		var cs0 := c as CollisionShape3D
		if cs0 == null or not (cs0.shape is BoxShape3D):
			continue
		var raw0: Vector3 = (cs0.shape as BoxShape3D).size
		if raw0.y <= 2.0:
			continue
		var b0: AABB = cs0.global_transform * AABB(-raw0 * 0.5, raw0)
		lo = lo.min(b0.position)
		hi = hi.max(b0.position + b0.size)
	if lo.x == INF:
		return 0.0
	var edge: float = lo.x if sign < 0 else hi.x
	if axis == "z":
		edge = lo.z if sign < 0 else hi.z
	var thick := 0.0
	for c in col.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var raw: Vector3 = (cs.shape as BoxShape3D).size
		if raw.y <= 2.0:
			continue
		var b: AABB = cs.global_transform * AABB(-raw * 0.5, raw)
		var b_min: float = b.position.x if axis == "x" else b.position.z
		var b_max: float = b_min + (b.size.x if axis == "x" else b.size.z)
		# 这面墙的外表面是不是贴着整体外框？（容差 1 cm，浮点误差）
		var touches := absf((b_min if sign < 0 else b_max) - edge) < 0.01
		if touches:
			var t: float = b.size.x if axis == "x" else b.size.z
			thick = maxf(thick, t)
	return thick + _WALL_INSET


## 玩家位置算不算「在屋里」：XZ 在门框矩形内 **且** 高度在窗口内。
## 单独抽出来，是因为 `_update_room_exit_unload()` 里要用，别的地方也可能要。
func _is_inside_room(pos: Vector3) -> bool:
	if _room_xz.size == Vector2.ZERO:
		return true
	if not _room_xz.has_point(Vector2(pos.x, pos.z)):
		return false
	# 高度窗口没算出来（兜底路径）时只管 XZ
	if _room_y_hi <= _room_y_lo:
		return true
	# ⚠️ 用**脚底位置**判，不用头顶：玩家 `global_position` 是胶囊中心附近，
	#    站屋顶时 y=5.80 已经高于墙顶 5.65。这里比的是「脚有没有踩进屋里」，
	#    所以把脚下留一点余量 —— 人从屋顶往下掉时才会被判成进屋。
	return pos.y >= _room_y_lo - _PLAYER_HEIGHT and pos.y <= _room_y_hi


## 节点离开场景树：反注册设置监听（否则静态 `_listeners` 会越积越多，
## 换场景之后还拿着已经 free 的对象）。
func _exit_tree() -> void:
	GameSettings.unlisten(_on_settings_changed)


## ⚠️ 必须接受参数：`GameSettings._emit()` 广播时调的是 `cb.call(key, v)`，
##    零参回调会被判 `Invalid call ... Expected 0 argument(s)` 而**静默失效**
##    （本喵第一版就是这么错的：设置改了、`unload_outside_room` 一直是 false）。
func _on_settings_changed(_key: String = "", _value: Variant = null) -> void:
	_apply_unload_setting()


## 被「出房间释放」卸掉之后重新装回来。
func _reload_after_unload() -> void:
	if splat_node != null or loading:
		return
	_inside_clock = 0.0
	_outside_clock = 0.0
	_unloaded_by_room_exit = false
	# 重解码之后 `_finish()` 会再跑一遍「建节点 + 建碰撞」。碰撞对象若已存在，
	# 会叠出第二份 StaticBody3D —— 先清掉上次建的，避免重复。
	_clear_built_collision()
	print("[SplatScene] %s：回到范围，重新解码（缓存命中约 2.3 s）" % display_name)
	start()


## 删掉上一次 `_finish()` **自己建出来**的碰撞体（重载时用）。
##
## ⚠️ 只有 `build_box_collision = true` 的场地才该走这里 —— 那种场地的
##    `RoomCollision` 是 `_build_box_collision()` 在 `_finish()` 里 new 出来的，
##    重载会叠出第二份，必须清。
## ⚠️ 2026-11-08 修的 bug：以前这里**无条件**删 `RoomCollision`，但画室609 的
##    `RoomCollision` 是 `game.tscn` 里**手摆的静态节点**（`build_box_collision = false`），
##    删掉之后 `_room_xz_from_walls()` 找不到墙，判据悄悄退回「点云整体 + 2 m」，
##    人进门后就再也不触发了 —— 表现就是「开关开着却不释放」。
##    现在只清自己建的那份；手摆的墙绝不碰。
func _clear_built_collision() -> void:
	if not build_box_collision:
		# 手摆的墙：删了玩家就掉出房间，而且门框判据也跟着失效。
		return
	var n := get_node_or_null("RoomCollision")
	if n != null:
		remove_child(n)
		n.queue_free()


func _player_node() -> Node3D:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		return p
	var scene := get_tree().current_scene
	if scene != null:
		return scene.get_node_or_null("Player") as Node3D
	return null


## 出房间 → 真的释放泼溅节点（连带 GPU 缓冲）；回房间 → 后台重解码。
##
## 2026-11-08 改成「门框判据 + 零延迟」：只要判定玩家在房间墙框外，
## **同一帧就开始释放**（不再等 `unload_delay`），进门同理立刻重载。
## 唯一的缓冲是 `_EDGE_FRAMES` 那两帧防抖 —— 防止脚踩门框线上反复横跳。
func _update_room_exit_unload(delta: float) -> void:
	if not unload_outside_room:
		_outside_streak = 0
		_inside_streak = 0
		if _unloaded_by_room_exit and splat_node == null and not loading:
			# 刚在设置里关掉，但人已经在房间外：照样装回来，别让人看不到画面。
			_reload_after_unload()
		return
	if _room_xz.size == Vector2.ZERO:
		if splat_node != null:
			_remember_room_xz()
		return
	var p := _player_node()
	if p == null:
		return
	var pos := p.global_position
	var inside := _is_inside_room(pos)
	if inside:
		_inside_streak += 1
		_outside_streak = 0
		if splat_node != null:
			_inside_clock = 0.0
			return
		# 缺泼溅（从没载过 / 刚被卸掉）：进门就走重载
		_inside_clock += delta
		if _inside_streak >= _EDGE_FRAMES and _inside_clock >= reload_delay and not loading:
			if _unloaded_by_room_exit:
				_reload_after_unload()
			else:
				start()
		return
	_outside_streak += 1
	_inside_streak = 0
	_inside_clock = 0.0
	if splat_node == null:
		return
	_outside_clock += delta
	if _outside_streak >= _EDGE_FRAMES and _outside_clock >= unload_delay:
		_unload_for_vram()


## 释放泼溅节点，把 1.28 GB 左右的 GPU 缓冲还给驱动。
func _unload_for_vram() -> void:
	if splat_node == null:
		return
	# 有加载在跑就等它完 —— 中途放掉会留下半上传的缓冲。
	# ⚠️ 不要把 `_outside_clock` 清零：清了之后下次进来又会等满 `unload_delay`，
	#    而这里可能因为 loading 而提前返回，导致「一直等不到释放」。
	if loading or _thread != null:
		return
	_outside_clock = 0.0
	# ⚠️ 这里**不要**再调 `_remember_room_xz()`：墙碰撞盒是静态的，
	#    加载完成时已经记过；而这里每帧都会进（人还在外面），
	#    重复调用会把同一行日志刷屏、还白算一遍 8 个角点。
	#    兜底路径（`splat_aabb`）也不需要重算 —— 点云一放掉就没了。
	# 碰撞是照点云建的，但**要留着**：卸的只是显示，玩家还能站在房间里。
	# （`build_collision` 用 GLB、`build_box_collision` 用盒子，两者都不依赖
	#   泼溅节点的存在，所以这里什么都不用做。）
	var n := splat_node
	splat_node = null
	_unloaded_by_room_exit = true
	# ⚠️ `queue_free()` 而不是 `free()`：`_exit_tree()` 会登记给 GDGS 注销，
	#    注册表在「一个不剩」时会请 GPU 状态缓存整体清理。
	n.queue_free()
	print("[SplatScene] %s：离开范围，释放泼溅显存（下次进入要重新解码）" % display_name)


func _update_inside_hide() -> void:
	if splat_node == null or hide_inside_aabb.size == Vector3.ZERO:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		var scene := get_tree().current_scene
		if scene != null:
			p = scene.get_node_or_null("Player") as Node3D
	if p == null:
		return
	splat_node.visible = not hide_inside_aabb.has_point(p.global_position)


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


## 立刻开始，不管 start_delay / start_distance（场景门在黑屏期间预载用）。
func force_start() -> void:
	if loading or splat_node != null:
		return
	start()


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


func _cache_key(source: String) -> String:
	return "%s|%d|%s|%.3f|%.3f" % [source, FileAccess.get_modified_time(source),
		str(crop_enabled), crop_margin, crop_max_scale]


func _worker(source: String) -> void:
	var key := _cache_key(source)
	var hit: Variant = _res_cache.get(key)
	if hit is Dictionary:
		var cached: Dictionary = (hit as Dictionary).duplicate()
		cached["from_cache"] = true
		print("[SplatScene] %s：复用内存里的展开结果（跳过解码/裁剪）" % display_name)
		_mutex.lock()
		_result = cached
		_mutex.unlock()
		return
	var result: Dictionary = SogRuntime.load_sog(source, {
		"cache": cache_mode,
		"progress": Callable(self, "_on_progress_from_thread"),
	})
	# ⚠️ 内容盒 + 裁剪以前在 `_finish()`（主线程）里做。实测 2,769,851 点时
	#    这一段要 **2.79 s**，整整卡死一帧（用户报的「展开缓存这里总是卡」）。
	#    它们只读资源数据、不碰场景树，所以搬进工作线程：
	#    主线程只剩 `GaussianSplatNode.new()` + `add_child()`（实测 4 ms）。
	if bool(result.get("ok", false)):
		var t_prep := Time.get_ticks_msec()
		var res: Resource = result["resource"]
		var bounds := content_bounds(res)
		var cmin: Vector3 = bounds["min"]
		var cmax: Vector3 = bounds["max"]
		var bounds_ms := Time.get_ticks_msec() - t_prep
		var crop_ms := 0
		if crop_enabled:
			var t_crop := Time.get_ticks_msec()
			var cropped := _crop_resource(res, cmin, cmax)
			crop_ms = Time.get_ticks_msec() - t_crop
			if bool(cropped.get("ok", false)):
				result["crop"] = cropped
				res = cropped["resource"]
				result["resource"] = res
				var cb := content_bounds(res)
				cmin = cb["min"]
				cmax = cb["max"]
		result["content_min"] = cmin
		result["content_max"] = cmax
		result["prep_ms"] = Time.get_ticks_msec() - t_prep
		print("[SplatScene] 工作线程准备：内容盒 %d ms / 裁剪 %d ms（%s）" % [
			bounds_ms, crop_ms, "开" if crop_enabled else "关"])
		# 只留最后一份（同时只可能有一份场地在用），别让多份 665 MB 叠在内存里
		_res_cache.clear()
		_res_cache[key] = result.duplicate()
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
		load_failed = true
		failed.emit(String(result.get("message", result)))
		return

	var res: Resource = result["resource"]
	splat_center = result.get("center", Vector3.ZERO)
	splat_aabb = res.get("aabb")
	point_count = int(res.get("point_count"))
	content_min = result.get("content_min", Vector3.ZERO)
	content_max = result.get("content_max", Vector3.ZERO)
	crop_stats = result.get("crop", {})
	var t_node := Time.get_ticks_msec()
	# 逐高斯坍缩的收敛点（源坐标）。必须在建节点之前定好，否则第一帧的
	# _push_dynamic 会把 0 当成收敛点推下去。
	_content_center = (content_min + content_max) * 0.5
	splat_node = GaussianSplatNodeScript.new()
	splat_node.name = "Splat"
	splat_node.set("gaussian", res)
	add_child(splat_node)
	# 「出房间释放」要靠这个水平范围判断内外；点云一放掉 `content_world_aabb()`
	# 就没了，所以必须在这里（加载完成时）就记住。
	_remember_room_xz()
	print("[SplatScene] 主线程建节点（GDGS 合并点数据）%d ms" % (Time.get_ticks_msec() - t_node))
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
func _crop_resource(res: Resource, cmin: Vector3, cmax: Vector3) -> Dictionary:
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
		cmin - Vector3.ONE * crop_margin,
		(cmax - cmin) + Vector3.ONE * crop_margin * 2.0)
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
