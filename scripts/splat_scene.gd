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
const STRUCT_SIZE := 60          # 每点 60 个 float
const BYTES_PER_SPLAT := 240     # = STRUCT_SIZE * 4

@export_file("*.sogdata", "*.sog") var sog_path := "res://splatdata/school_playable.sogdata"
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
## 是否再乘 GDGS 自带的「绕 Z -180°」姿态修正。本数据自身 Y 朝上，默认关。
@export var use_default_orientation := false
## 是否挂上碰撞 GLB 的三角网格（本扫描的碰撞 GLB 与实际范围不符，默认关）
@export var build_collision := false
@export var collision_glb := "res://models/school.collision.glb"
@export var auto_start := true

var splat_node: Node3D = null
var splat_center := Vector3.ZERO
var splat_aabb := AABB()
## 内容稳健包围盒（1‰~99.9‰ 分位，排除 floaters）
var content_min := Vector3.ZERO
var content_max := Vector3.ZERO
var point_count := 0
var loading := false
var elapsed_seconds := 0.0

var _thread: Thread = null
var _mutex := Mutex.new()
var _result: Dictionary = {}
var _start_ms := 0


func _ready() -> void:
	# 命令行覆盖：
	#   godot ... -- --splat-cache=off    不走展开缓存
	#   godot ... -- --splat=off          完全不加载泼溅
	# 加 --splat=off 是给玩法自检用的：615 万点的光栅化会拖慢每一条渲染相关的用例。
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--splat-cache="):
			cache_mode = a.substr(14)
		elif a == "--splat=off" or a == "--no-splat":
			print("[SplatScene] 命令行要求跳过泼溅加载")
			return
	if auto_start:
		start()


func _process(_delta: float) -> void:
	if _thread == null or _thread.is_alive():
		return
	_thread.wait_to_finish()
	_thread = null
	_mutex.lock()
	var result := _result
	_mutex.unlock()
	_finish(result)


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

	splat_node = GaussianSplatNodeScript.new()
	splat_node.name = "Splat"
	splat_node.set("gaussian", res)
	add_child(splat_node)
	apply_transform()
	if build_collision:
		_build_collision()

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
	}
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
	return b


## 自动摆放：水平把内容中心对到原点，竖向把内容顶面沉到 -top_gap
func _resolve_offset() -> Vector3:
	if not auto_place:
		return offset
	var center := (content_min + content_max) * 0.5
	return Vector3(
		-center.x * world_scale,
		-top_gap - content_max.y * world_scale,
		-center.z * world_scale)


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
