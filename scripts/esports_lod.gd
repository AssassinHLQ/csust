extends Node3D
## 电竞房的三档 LOD（2026-11-08，2026-11-09 改成后台加载）
##
## 使用者原话：「总感觉减面后版本不好看了，试试放进去减面前版本，减面版本做lod回退」。
##
## ── 三档 ──
##   近（0 ~ 12 m）  高模 `esports_room_high.glb`  —— 减面前，757 万面
##   中（12 ~ 30 m） 中模 `esports_room_mid.glb`   —— ~280 万面
##   远（30 m+）    低模 `esports_room.glb`       —— 现有 105 万面
##
## ── 为什么用「整档切换」而不是逐网格 `visibility_range` ──
## `visibility_range` 是**按每个网格到相机的距离**判的，而**房间横跨 16.84 m**：
## 相机站在门口时，房间远端离相机 16 m > 8 m → **远端切中模、近端留高模**，
## 两档在同一个位置**重叠绘制**（实测 2 m 处图元 860 万 = 两档都在画），
## 既有 z-fighting 又白烧两倍面数。
##
## 所以改成**整间房同一时刻只用一档**：每帧按「相机到**房间中心**的距离」选档，
## 把那一档 `visible = true`、其余 `visible = false`。
##
## ⚠️ 切换距离（12 m / 30 m）**都小于房间对角线 19.7 m**，所以玩家在屋里时
##    距离房间中心最多 ~8 m → **永远只用近档**，根本不会切。
##    切档只发生在「玩家在屋外远处看这栋楼」时 —— 而那是**封闭外壳**，
##    看不见里面，所以切换的瞬间闪一下也无所谓。
##
## ⚠️ 为什么不用 Godot 的自动 LOD：`scripts/ryzen_9950x3d.gd` 已经踩过
##    （2026-11-04 实测）：`lod_bias` 从 1 扫到 64，图元数一直是 459,287~460,051
##    （全是噪声）—— **引擎根本没切低模**。
##
## ⚠️ 缺哪一档就退到下一档（high 缺 → 用 mid，mid 也缺 → 用当前的低模），
##    功能不受影响，只是画质降一级。
##
## ── 2026-11-09：改成**后台线程加载**（使用者：「现在开局很慢怎么办」）──
## 旧版在 `_ready` 里同步 `load()` 三档，实测开局被吃掉：
##     load high (233.9 MB) 1778 ms + mid (100.6 MB) 665 ms + low 274 ms
##     instantiate 整间房 + `_ready` 合计 **2471 ms**
## 而电竞房开局 `visible = false`（要在芹香那儿买完才现身）—— 白等。
##
## 现在：`_ready` 只做**不花钱的**事（找 Room、量房间中心），
## 高/中模用 `ResourceLoader.load_threaded_request()` 丢到后台线程，
## 每帧轮询，好了才 `instantiate` 挂上。
##
## 为什么不是「等房间现身再加载」：那样会把 2.5 s 的卡顿挪到**买完那一刻**，
## 正好撞上天降落地演出，动画会一顿。后台加载则是玩家还在逛/买东西时就流完了。

const MODEL_HIGH := "res://models/esports_room/esports_room_high.glb"
const MODEL_MID := "res://models/esports_room/esports_room_mid.glb"
const MODEL_LOW := "res://models/esports_room/esports_room.glb"

## 切换距离（米）
const NEAR_END := 12.0
const MID_END := 30.0

var _built := false
var _low: Node3D = null
var _mid: Node3D = null
var _high: Node3D = null
## 房间中心（世界坐标），用来算「相机到房间有多远」
var _center := Vector3.ZERO
## 当前正在显示哪一档：0 = 高模 / 1 = 中模 / 2 = 低模 / -1 = 还没定
var _current := -1
## 正在后台加载的档位：path -> 发起时刻（ms），只用来打印耗时
var _pending := {}


func _ready() -> void:
	# 等一帧：确保 GLB 实例（`Room` 节点）已经挂好
	await get_tree().process_frame
	_build_lod()


func _build_lod() -> void:
	if _built:
		return
	_built = true

	# 找到现有的低模实例（`esports_room.tscn` 里的 `Room`）。
	# ⚠️ 本脚本挂在 `Lod` 子节点下，而 `Room` 是它的**兄弟** —— 所以从父节点找。
	var host := get_parent()
	if host != null:
		_low = host.get_node_or_null("Room") as Node3D
	if _low == null:
		_low = get_node_or_null("../Room") as Node3D
	if _low == null:
		push_warning("[EsportsLOD] 没找到 Room 节点，跳过分档")
		return

	# 房间中心 = 整个房间的世界包围盒中心（用低模算，三档一致）。
	# 这一步只量 AABB，不加载任何模型，很便宜。
	var box := AABB()
	var first := true
	for m in _low.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	_center = box.position + box.size * 0.5

	# ★ 高/中模丢后台加载 —— 这一步**立即返回**，不阻塞开局
	_request(MODEL_HIGH)
	_request(MODEL_MID)

	set_process(true)
	print("[EsportsLOD] 分档就绪（低模在场景里，高/中模后台加载中）：近 %.0f m、中 %.0f m，房间中心 %s" % [
		NEAR_END, MID_END, str(_center.snappedf(0.01))])


## 发起后台加载。**不阻塞**：立刻返回，实际解码在 worker 线程上跑。
func _request(path: String) -> void:
	if not ResourceLoader.exists(path):
		print("[EsportsLOD] 没有 %s —— 跳过这一档（画质降一级，功能不受影响）"
			% path.get_file())
		return
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		push_warning("[EsportsLOD] %s 后台加载发起失败（错误 %d）" % [path.get_file(), err])
		return
	_pending[path] = Time.get_ticks_msec()
	print("[EsportsLOD] %s 开始后台加载" % path.get_file())


## 每帧轮询后台加载进度；好了就实例化挂上。
func _poll_threaded() -> void:
	if _pending.is_empty():
		return
	for path in _pending.keys():
		var st := ResourceLoader.load_threaded_get_status(path)
		match st:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue
			ResourceLoader.THREAD_LOAD_LOADED:
				var ps := ResourceLoader.load_threaded_get(path) as PackedScene
				var t0: int = _pending[path]
				_pending.erase(path)
				_attach(path, ps, Time.get_ticks_msec() - t0)
			_:
				# FAILED / INVALID_RESOURCE 等：丢掉，不重试（别每帧刷屏）
				_pending.erase(path)
				push_warning("[EsportsLOD] %s 后台加载失败（状态 %d），这一档不用了"
					% [path.get_file(), st])


## 后台加载完成后：实例化、挂到本节点下、**先设成不可见**，
## 然后 `_current = -1` 让下一帧重新选档（新档位才有机会被选中）。
func _attach(path: String, ps: PackedScene, cost_ms: int) -> void:
	if ps == null:
		return
	var n := ps.instantiate() as Node3D
	if n == null:
		return
	var is_high := path == MODEL_HIGH
	n.name = "HighModel" if is_high else "MidModel"
	n.visible = false          # 先藏起来，等 _process 选档
	add_child(n)
	if is_high:
		_high = n
	else:
		_mid = n
	_current = -1              # 重新判定，否则新档位永远轮不到
	print("[EsportsLOD] %s 后台加载完成（%d ms）：%s"
		% [n.name, cost_ms, path.get_file()])


## 每帧：轮询后台加载 + 按「相机到房间中心的距离」选一档，整间房只用那一档。
func _process(_delta: float) -> void:
	_poll_threaded()
	if _low == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(_center)
	var want := 0
	if d > MID_END:
		want = 2
	elif d > NEAR_END:
		want = 1
	# 缺档就往下降
	if want == 0 and _high == null:
		want = 1 if _mid != null else 2
	if want == 1 and _mid == null:
		want = 2
	if want == _current:
		return
	_current = want
	if _high != null:
		_high.visible = want == 0
	if _mid != null:
		_mid.visible = want == 1
	_low.visible = want == 2
