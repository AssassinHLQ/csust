@tool
extends Node
class_name GaussianRenderManager

const SceneRegistryScript := preload("res://addons/gdgs/runtime/render/compute/gaussian_scene_registry.gd")
const GpuStateCacheScript := preload("res://addons/gdgs/runtime/render/compute/gaussian_gpu_state_cache.gd")
const RendererScript := preload("res://addons/gdgs/runtime/render/compute/gaussian_renderer.gd")
# Guarded load, not preload: runtime/lighting/ is deletable and losing it must
# only cost relighting, leaving splats rendering unlit.
const LIGHT_RIG_PATH := "res://addons/gdgs/runtime/lighting/gaussian_light_rig.gd"

static var _instance

var _scene_registry: GaussianSceneRegistry = SceneRegistryScript.new()
var _gpu_state_cache: GaussianGpuStateCache = GpuStateCacheScript.new()
var _renderer: GaussianRenderer = RendererScript.new()
var _light_rig: RefCounted = null
var _light_rig_checked := false

static func get_instance():
	if _instance != null and is_instance_valid(_instance):
		return _instance
	return null

func _enter_tree() -> void:
	_instance = self

## Main-thread tick. render_for_compositor() runs on the rendering thread, where
## walking the scene tree and reading node transforms would be unsafe, so every
## piece of relight state is gathered here and parked in the registry as bytes
## for the renderer to upload.
func _process(_delta: float) -> void:
	var rig := _resolve_light_rig()
	if rig == null:
		return
	rig.update(self)
	if _scene_registry.refresh_relight(rig.to_packed_floats().to_byte_array(), rig.light_count):
		_gpu_state_cache.mark_all_render_states_needs_relight_upload(true)

func _resolve_light_rig() -> RefCounted:
	if _light_rig_checked:
		return _light_rig
	_light_rig_checked = true
	if not ResourceLoader.exists(LIGHT_RIG_PATH, "Script"):
		return null
	var script: Variant = load(LIGHT_RIG_PATH)
	if script == null or not (script is GDScript) or not (script as GDScript).can_instantiate():
		push_warning("[gdgs] compute: light rig failed to load; splats render unlit")
		return null
	var instance: Variant = (script as GDScript).new()
	if instance is RefCounted:
		_light_rig = instance
	return _light_rig

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

func register_splat_node(node: Node) -> void:
	_apply_registry_result(_scene_registry.register_splat_node(node))

func unregister_splat_node(node: Node) -> void:
	_apply_registry_result(_scene_registry.unregister_splat_node(node))

func mark_resource_dirty(node: Node) -> void:
	_apply_registry_result(_scene_registry.mark_resource_dirty(node))

func mark_transform_dirty(node: Node) -> void:
	_apply_registry_result(_scene_registry.mark_transform_dirty(node))

func shutdown() -> void:
	if not _gpu_state_cache.has_render_states():
		return
	RenderingServer.call_on_render_thread(_cleanup_on_render_thread)

## 切场景专用：把 GPU 状态**当帧**放干净，而不是等 GC 回收 context。
##
## 为什么需要（2026-11-07 用户：「进入第二场景不释放第一场景的显存」）：
## 换场景时旧的 `GaussianSplatNode` 会 `queue_free()`，注册表跟着清空，
## 于是 `gaussian_renderer.gd` 里那条「注册表没有点数据 ⇒ `cleanup_all()`」的
## 兜底会触发。但 `cleanup_all()` 只是把 `state.context` 丢掉，RID 还攒在
## `GdgsRenderingDeviceContext.deletion_queue` 里等 `NOTIFICATION_PREDELETE` ——
## 实测日志里「缓冲」一栏跨场景纹丝不动（1285 MiB 一路不变），就是这段没落下来。
##
## 这里按三步做，顺序不能换：
##   ① 主线程：清空注册表（`_splat_nodes` 已经空了，顺带把合并出来的
##      `_point_data_byte` 等大 `PackedByteArray` 也放掉）；
##   ② 渲染线程：`release_gpu_now()` 显式 `free_rid` 所有缓冲/纹理/RID；
##   ③ 下一帧第一次渲染：`request_rearm()` 让注册表**整份重注入**
##      （不重注入的话，`_sync_scene_resources` 会认为「点数据没变」而跳过上传，
##      新场景的泼溅就永远不显示）。
##
## ⚠️ 只能在「旧场景已经 free、新场景还没加载」的空档调（见 `scene_flow.gd`）。
##
## ⚠️ 这里**不能**用 `RenderingServer.rendering_device_sync()` —— 4.7.1 的
##    RenderingServer 上根本没有这个方法（本喵踩过：`Parse Error: Static function
##    "rendering_device_sync()" not found`，整个后端脚本连带编译失败）。
##    改成「提交一次真活再读回」：`call_on_render_thread` 后面紧跟一次
##    `get_rendering_info()` 读回，RID 的释放一定已经排在它前面执行完。
func purge_gpu() -> void:
	_scene_registry.forget_all()
	_renderer.request_rearm()
	if not _gpu_state_cache.has_render_states():
		return
	RenderingServer.call_on_render_thread(_release_gpu_on_render_thread)
	# 同步屏障：`call_on_render_thread` 是异步投递，读一次渲染信息把队列排空，
	# 保证 RID 真的还掉了才继续往下走（否则紧接着 load 新场景时峰值又叠一起）。
	RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	# ⚠️ 兜底：上面那两条路径都没能在这帧内把 `GdgsRenderingDeviceContext`
	#    的引用清零时（实测：投递到渲染线程的 Callable 会多按住一会儿），
	#    主线程这边再显式 `free()` 一次。RID 队列已被 `release_gpu_now()` 清空，
	#    所以这次 flush 是空操作，不会重复还 RID。
	_reap_leftover_contexts()

func _release_gpu_on_render_thread() -> void:
	_gpu_state_cache.release_gpu_now()


## 把「已经被 `release_gpu_now()` 清空、但引用计数还没归零」的 context 收掉。
##
## 场景：`release_gpu_now()` 在渲染线程把 RID 全还了并把 `state.context` 置 null，
## 但那份 `GdgsRenderingDeviceContext` 可能还被渲染线程队列里的临时引用按着，
## 等到进程退出才被回收 —— 退出时报
##   `Resource still in use: .../gaussian_rendering_device_context.gd`
##   `Leaked instance: GDScript ... - Reference count: 1`
## 这是**符号层面**的报错，不是显存问题（RID 早还了）；但既然能确定它已经
## 没有可用的 device、也没有待释放的 RID，主线程直接 `free()` 掉最干净。
##
## ⚠️ 两个前提都必须成立才 free，否则会误伤正在用的 context：
##   ① `device == null`（`release_all()` 里最后一步就是置 null）：说明已经放过；
##   ② `deletion_queue` 为空：说明没有待还的 RID，free 不会触发第二次释放。
func _reap_leftover_contexts() -> void:
	for ctx in _gpu_state_cache.take_released_contexts():
		if ctx == null:
			continue
		if ctx.get("device") != null:
			continue
		var q: Array = ctx.get("deletion_queue").queue
		if not q.is_empty():
			continue
		ctx.free()

func render_for_compositor(
	texture_size: Vector2i,
	camera_transform: Transform3D,
	camera_projection: Projection,
	camera_world_position: Vector3,
	depth_capture_alpha: float = 0.5
) -> Dictionary:
	return _renderer.render_for_compositor(
		_gpu_state_cache,
		_scene_registry,
		texture_size,
		camera_transform,
		camera_projection,
		camera_world_position,
		depth_capture_alpha
	)

func _cleanup_on_render_thread() -> void:
	_gpu_state_cache.cleanup_all()

func _apply_registry_result(result: Dictionary) -> void:
	if result.is_empty():
		return
	if result.get("request_cleanup", false):
		_gpu_state_cache.request_cleanup()
	if result.has("require_gpu_rebuild") and bool(result["require_gpu_rebuild"]):
		_gpu_state_cache.mark_all_render_states_needs_gpu_rebuild()
	if result.has("require_splat_upload") and bool(result["require_splat_upload"]):
		_gpu_state_cache.mark_all_render_states_needs_splat_upload(true)
	if result.has("require_instance_upload") and bool(result["require_instance_upload"]):
		_gpu_state_cache.mark_all_render_states_needs_instance_upload(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _gpu_state_cache.has_render_states():
		RenderingServer.call_on_render_thread(_cleanup_on_render_thread)
