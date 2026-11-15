@tool
extends RefCounted

## Scratch storage borrowed by sequential renders on one RenderingDevice.
## Capacities are immutable: a borrower never resizes another state's buffers.
## Output textures and source/instance data remain owned by each render state.
const Context := preload("res://addons/gdgs/runtime/render/compute/gaussian_rendering_device_context.gd")
const PARTITION_SIZE := 4096
const RADIX := 256

var context: GdgsRenderingDeviceContext
var descriptors: Dictionary = {}
var declared_bytes := 0


static func buffer_sizes(culled_entries: int, sort_elements: int) -> Dictionary:
	var partitions := ceili(sort_elements / float(PARTITION_SIZE))
	return {
		"culled_splats": maxi(1, culled_entries) * 48,
		"culled_counter": 4,
		"histogram": 4 + (1 + 4 * RADIX + partitions * RADIX) * 4,
		"sort_keys": maxi(1, sort_elements) * 8,
		"sort_values": maxi(1, sort_elements) * 8,
	}


func _init(device: RenderingDevice, culled_entries: int, sort_elements: int) -> void:
	context = Context.create(device)
	var sizes := buffer_sizes(culled_entries, sort_elements)
	for name in sizes:
		var bytes: int = sizes[name]
		descriptors[name] = context.create_storage_buffer(bytes)
		declared_bytes += bytes


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and context != null:
		context.free()
