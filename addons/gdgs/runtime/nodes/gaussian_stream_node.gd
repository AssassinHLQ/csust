@tool
@icon("res://addons/gdgs/editor/icons/gaussian_splat_node.svg")
extends VisualInstance3D
class_name GaussianStreamNode

## A Gaussian cloud that is too large to keep resident, streamed from a disk LOD
## pack built by tools/build_stream_pack.py.
##
## By default the octree selects a bounded frontier rather than the whole cloud.
## A full-detail single-node pack can opt into persistent residency instead.
## The octree decides
## which nodes are worth their screen-space error, a worker thread reads just those
## payloads, and they land in a fixed-size GPU slot arena. VRAM therefore tracks
## `budget_nodes * node_cap`, not the size of the world: a 50M-splat pack and a 1M
## one cost the same at the same budget.

const SELECTOR_SCRIPT := preload("res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd")
const RUNTIME_SCRIPT := preload("res://addons/gdgs/runtime/stream/gaussian_stream_runtime.gd")
const Lod := preload("res://addons/gdgs/runtime/stream/gaussian_stream_lod.gd")

@export var stream_pack: GaussianStreamPack:
	set(value):
		_set_stream_pack(value)
	get:
		return _stream_pack

@export_group("Level of detail")
## Resident octree nodes. The splat budget is this times the pack's node_cap, so
## 96 nodes of a 32768-splat pack holds about 3.1M splats regardless of world size.
@export_range(1, 4096, 1) var budget_nodes: int = 96:
	set(value):
		if budget_nodes == maxi(1, value):
			return
		budget_nodes = maxi(1, value)
		_reconfigure_runtime()
		if is_inside_tree():
			var backend := SELECTOR_SCRIPT.get_backend(self)
			if backend != null:
				backend.notify_resource_changed(self)
## Refine while a node's projected error exceeds this many pixels. Lower is
## sharper and costs more nodes; the budget governor coarsens when it runs out.
@export_range(0.5, 128.0, 0.5) var max_sse: float = 16.0
## Nodes whose disk read may be started per frame. Keeps a refinement burst from
## saturating the IO queue and stalling the frame.
@export_range(1, 32, 1) var max_loads_per_frame: int = 4
## Seconds between small-movement/residency checks. Large moves, turns and zoom
## select immediately; converged static views reuse their selection. Zero
## explicitly forces selection on every tick.
@export_range(0.0, 1.0, 0.01) var select_interval: float = 0.08
## Drive the residency manager from this node's _process. Turn off to tick it
## yourself (a benchmark that wants a fixed camera path, for example).
@export var auto_update: bool = true
## Full-detail single-node packs can remain loaded across camera turns.
@export var keep_single_node_resident: bool = false
## Instance colour/opacity multiplier; never modifies the source pack.
@export var color_tint: Color = Color.WHITE

var _stream_pack: GaussianStreamPack = null
var _runtime: RefCounted = null
var _local_aabb := AABB()
var _aabb_valid := false


func _enter_tree() -> void:
	set_notify_transform(true)
	call_deferred("_register_with_backend")


func _ready() -> void:
	_rebuild_aabb()


func _exit_tree() -> void:
	_unregister_from_backend()
	if _runtime != null:
		_runtime.shutdown()


func _get_aabb() -> AABB:
	return _local_aabb if _aabb_valid else AABB()


## The residency manager. Exposed so a benchmark or a debug overlay can read the
## counters without reaching into private state.
func get_stream_runtime() -> RefCounted:
	return _runtime


func get_stream_instance_transforms() -> Array[Transform3D]:
	return [global_transform]


func get_stream_instance_colors() -> PackedColorArray:
	return PackedColorArray([color_tint])


func stats() -> Dictionary:
	if _runtime == null:
		return {}
	return {
		"active_slots": _runtime.active_slots(),
		"capacity_slots": _runtime.capacity_slots(),
		"resident_splats": _runtime.resident_splats(),
		"resident_bytes": _runtime.resident_bytes(),
		"loads_completed": _runtime.loads_completed,
		"evictions": _runtime.evictions,
		"moves": _runtime.moves,
		"covered_source_splats": _runtime.covered_source_splats,
		"peak_resident_splats": _runtime.peak_resident_splats,
		"io_failures": _runtime.io_failures,
	}


func _set_stream_pack(value: GaussianStreamPack) -> void:
	if _stream_pack == value:
		return
	var was_registered := _stream_pack != null and is_inside_tree()
	if was_registered:
		_unregister_from_backend()
	if _runtime != null:
		_runtime.shutdown()
		_runtime = null
	_stream_pack = value
	_rebuild_aabb()
	_reconfigure_runtime()
	if is_inside_tree():
		call_deferred("_register_with_backend")
	if Engine.is_editor_hint():
		update_gizmos()


func _reconfigure_runtime() -> void:
	if _stream_pack == null or not _stream_pack.is_loaded():
		return
	if _runtime == null:
		_runtime = RUNTIME_SCRIPT.new()
	if not _runtime.is_running() or _runtime.pack != _stream_pack or _runtime.budget_nodes != budget_nodes:
		_runtime.configure(_stream_pack, budget_nodes)
	_runtime.max_sse = max_sse
	_runtime.max_loads_per_frame = max_loads_per_frame
	_runtime.select_interval = select_interval
	_runtime.keep_single_node_resident = keep_single_node_resident


func _rebuild_aabb() -> void:
	_aabb_valid = false
	if _stream_pack == null or not _stream_pack.is_loaded():
		_local_aabb = AABB()
		return
	_local_aabb = _stream_pack.world_aabb
	_aabb_valid = true


## Main-thread residency tick. The camera is read here rather than on the render
## thread because walking the scene tree from the render thread is unsafe.
func _process(delta: float) -> void:
	if not auto_update or _runtime == null or not _runtime.is_running():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	var projection := camera.get_camera_projection()
	var view := Projection(camera.global_transform.affine_inverse())
	var to_pack := global_transform.affine_inverse()
	_runtime.max_sse = max_sse
	_runtime.max_loads_per_frame = max_loads_per_frame
	_runtime.select_interval = select_interval
	_runtime.keep_single_node_resident = keep_single_node_resident
	_runtime.update(
		to_pack * camera.global_position,
		projection * view * Projection(global_transform),
		Lod.focal_pixels_from_projection(projection, viewport.size.y),
		delta)


func _register_with_backend() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if _stream_pack == null or not _stream_pack.is_loaded():
		return
	_reconfigure_runtime()
	var backend := SELECTOR_SCRIPT.get_backend(self)
	if backend != null and backend.has_method("attach_stream_node"):
		backend.attach_stream_node(self)


func _unregister_from_backend() -> void:
	var backend := SELECTOR_SCRIPT.get_backend(self)
	if backend != null and backend.has_method("detach_stream_node"):
		backend.detach_stream_node(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		var backend := SELECTOR_SCRIPT.get_backend(self)
		if backend != null:
			backend.notify_transform_changed(self)
