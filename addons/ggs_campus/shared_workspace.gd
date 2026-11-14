extends RefCounted
## Scratch memory for rasterizers submitted sequentially on one render thread.
## Source splats, output textures and per-layer tile bounds remain independent.
## The registry owns weak references only; the last context releases the buffers.

const Context := preload("res://addons/ggs_campus/render_context.gd")
const RADIX := 256
const PARTITION_SIZE := 4096
static var _groups: Dictionary = {}

var context
var descriptors: Dictionary = {}
var point_capacity := 0
var sort_capacity := 0
var last_writer_id := 0


static func acquire(device: RenderingDevice, group: String, points: int):
	var key := "%d:%s:%d" % [device.get_instance_id(), group, points]
	var entry = _groups.get(key)
	if entry != null:
		var existing = entry.get_ref()
		if existing != null:
			return existing
	# Drop expired keys as well as references, so repeated scene visits stay bounded.
	for old_key in _groups.keys():
		if _groups[old_key].get_ref() == null:
			_groups.erase(old_key)
	var workspace = load("res://addons/ggs_campus/shared_workspace.gd").new()
	workspace.point_capacity = points
	workspace.sort_capacity = points * 10
	workspace.context = Context.create(device)
	var partitions := ceili(float(workspace.sort_capacity) / PARTITION_SIZE)
	workspace.descriptors["culled_splats"] = workspace.context.create_storage_buffer(points * 48, [], 0, false)
	workspace.descriptors["histogram"] = workspace.context.create_storage_buffer(4 + (1 + 4 * RADIX + partitions * RADIX) * 4)
	workspace.descriptors["sort_keys"] = workspace.context.create_storage_buffer(workspace.sort_capacity * 8, [], 0, false)
	workspace.descriptors["sort_values"] = workspace.context.create_storage_buffer(workspace.sort_capacity * 8, [], 0, false)
	_groups[key] = weakref(workspace)
	return workspace


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and context != null:
		context.free()
		context = null
