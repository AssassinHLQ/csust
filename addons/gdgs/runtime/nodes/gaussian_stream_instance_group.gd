@tool
extends "res://addons/gdgs/runtime/nodes/gaussian_stream_node.gd"
class_name GaussianStreamInstanceGroup

## Repeated worlds share one pack, worker queue, CPU mirror and GPU arena.
## budget_nodes is the TOTAL frontier budget across all visible copies.
const INSTANCE_RUNTIME := preload("res://addons/gdgs/runtime/stream/gaussian_stream_instance_runtime.gd")

@export_group("Instances")
## Local transforms relative to this group. Editing them never rewrites points.
@export var instance_transforms: Array[Transform3D] = [Transform3D.IDENTITY]
## Missing entries use white. Multiplied by the inherited color_tint.
@export var instance_colors := PackedColorArray()

var _last_transforms: Array[Transform3D] = []


func get_stream_instance_transforms() -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	for local in instance_transforms:
		transforms.append(global_transform * local)
	return transforms


func get_stream_instance_colors() -> PackedColorArray:
	var colors := PackedColorArray()
	for i in instance_transforms.size():
		colors.append(color_tint * (instance_colors[i] if i < instance_colors.size() else Color.WHITE))
	return colors


func _reconfigure_runtime() -> void:
	if _stream_pack == null or not _stream_pack.is_loaded():
		return
	if _runtime == null:
		_runtime = INSTANCE_RUNTIME.new()
	if not _runtime.is_running() or _runtime.pack != _stream_pack or _runtime.budget_nodes != budget_nodes:
		_runtime.configure(_stream_pack, budget_nodes)
	_runtime.max_sse = max_sse
	_runtime.max_loads_per_frame = max_loads_per_frame
	_runtime.select_interval = select_interval
	if is_inside_tree():
		_runtime.set_instances(get_stream_instance_transforms())


func _rebuild_aabb() -> void:
	_aabb_valid = false
	_local_aabb = AABB()
	if _stream_pack == null or not _stream_pack.is_loaded():
		return
	for local in instance_transforms:
		var bounds: AABB = local * _stream_pack.world_aabb
		_local_aabb = _local_aabb.merge(bounds) if _aabb_valid else bounds
		_aabb_valid = true


func _process(delta: float) -> void:
	var transforms := get_stream_instance_transforms()
	if _runtime != null:
		_runtime.set_instances(transforms, is_visible_in_tree())
	if transforms != _last_transforms:
		_last_transforms = transforms
		_rebuild_aabb()
		var backend := SELECTOR_SCRIPT.get_backend(self)
		if backend != null:
			backend.notify_transform_changed(self)
	if not auto_update or _runtime == null or not _runtime.is_running():
		return
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		return
	var projection := camera.get_camera_projection()
	_runtime.max_sse = max_sse
	_runtime.max_loads_per_frame = max_loads_per_frame
	_runtime.select_interval = select_interval
	_runtime.update(camera.global_position,
		projection * Projection(camera.global_transform.affine_inverse()),
		Lod.focal_pixels_from_projection(projection, viewport.size.y), delta)


func stats() -> Dictionary:
	var result := super.stats()
	if _runtime != null:
		result["instances"] = instance_transforms.size()
		result["logical_source_splats"] = _stream_pack.source_splats * instance_transforms.size()
		result["projected_splats"] = _runtime.projected_splats
		result["projected_nodes"] = _runtime.projected_nodes
		result["visible_instances"] = _runtime.visible_instances
	return result
