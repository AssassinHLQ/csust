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

## Call from the main thread; the callback receives a Dictionary on that thread.
## Resource bytes are de-duplicated, not a measure of physical GPU residency.
func request_gpu_memory_stats(callback: Callable) -> void:
	var cache := _gpu_state_cache
	RenderingServer.call_on_render_thread(func():
		if callback.is_valid():
			callback.call_deferred(cache.get_memory_stats()))

## Main-thread tick. render_for_compositor() runs on the rendering thread, where
## walking the scene tree and reading node transforms would be unsafe, so every
## piece of relight state is gathered here and parked in the registry as bytes
## for the renderer to upload.
func _process(_delta: float) -> void:
	var rig := _resolve_light_rig()
	var light_bytes := PackedByteArray()
	var light_count := 0
	if rig != null:
		rig.update(self)
		light_bytes = rig.to_packed_floats().to_byte_array()
		light_count = rig.light_count
	if _scene_registry.refresh_relight(light_bytes, light_count):
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
	# Retire every cached resolution now, including viewports no longer rendered.
	# Keep the registry: a campus stream may still be registered after a room exits.
	RenderingServer.call_on_render_thread(_cleanup_on_render_thread)

func register_stream_node(node: Node) -> void:
	_apply_registry_result(_scene_registry.register_stream_node(node))

func unregister_stream_node(node: Node) -> void:
	_apply_registry_result(_scene_registry.unregister_stream_node(node))
	RenderingServer.call_on_render_thread(_cleanup_on_render_thread)

func mark_resource_dirty(node: Node) -> void:
	_apply_registry_result(_scene_registry.mark_resource_dirty(node))

func mark_transform_dirty(node: Node) -> void:
	_apply_registry_result(_scene_registry.mark_transform_dirty(node))

func shutdown() -> void:
	if not _gpu_state_cache.has_render_states():
		return
	RenderingServer.call_on_render_thread(_cleanup_on_render_thread)

## Called by SceneFlow after the old scene is freed. Replace the canonical
## and streaming registry together, then free render contexts and shared GPU
## workspaces. New render states always rebuild, including same-count reentry.
func purge_gpu() -> void:
	_scene_registry = SceneRegistryScript.new()
	RenderingServer.call_on_render_thread(_cleanup_on_render_thread)
	RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)

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
		# A hidden/compositor-free viewport never calls flush_pending_cleanup().
		RenderingServer.call_on_render_thread(_cleanup_on_render_thread)
	if result.has("require_gpu_rebuild") and bool(result["require_gpu_rebuild"]):
		_gpu_state_cache.mark_all_render_states_needs_gpu_rebuild()
	if result.has("require_splat_upload") and bool(result["require_splat_upload"]):
		_gpu_state_cache.mark_all_render_states_needs_splat_upload(true)
	if result.has("require_instance_upload") and bool(result["require_instance_upload"]):
		_gpu_state_cache.mark_all_render_states_needs_instance_upload(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _gpu_state_cache.has_render_states():
		RenderingServer.call_on_render_thread(_cleanup_on_render_thread)
