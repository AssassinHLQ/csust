@tool
extends "res://addons/gdgs/runtime/stream/gaussian_stream_runtime.gd"

## One disk source and one fixed arena for many transformed copies. Selection
## budgets count (instance, node) pairs; payload residency counts unique nodes.
## Slot directory word 6 redirects a draw to a shared physical payload slot.

var instance_transforms: Array[Transform3D] = []
var _instance_wanted: Array = []
var projected_splats := 0
var projected_nodes := 0
var visible_instances := 0
var instances_visible := true


func directory_slots() -> int:
	return maxi(_capacity_slots, mini(budget_nodes, instance_transforms.size() * pack.node_count))


func set_instances(transforms: Array[Transform3D], visible_: bool = true) -> void:
	if transforms == instance_transforms and instances_visible == visible_:
		return
	instance_transforms = transforms.duplicate()
	instances_visible = visible_
	_instance_wanted.clear()
	_has_selection = false
	_ops_dirty = true
	# Clear the previous draw list immediately, including with manual ticking.
	# Removing copies must never replay stale instance indices after a rebuild.
	if is_running():
		_publish()


func _select_wanted(camera_position: Vector3, view_projection: Projection, focal_pixels: float) -> Array[int]:
	_instance_wanted.clear()
	if not instances_visible:
		visible_instances = 0
		_ops_dirty = true
		return []
	var views: Array = []
	var weights := PackedFloat32Array()
	weights.resize(instance_transforms.size())
	weights.fill(0.0)
	var planes := Lod.extract_frustum_planes(view_projection)
	for i in instance_transforms.size():
		_instance_wanted.append([])
		var model := instance_transforms[i]
		if absf(model.basis.determinant()) < 0.000000000001:
			views.append({})
			continue
		var bounds: AABB = model * pack.world_aabb
		if not Lod.aabb_in_frustum(planes, bounds):
			views.append({})
			continue
		var inverse := model.affine_inverse()
		var scales := model.basis.get_scale().abs()
		var distortion := scales.max_axis_index()
		var min_axis := scales.min_axis_index()
		# Uniform scale cancels in error/distance. A non-uniform scale needs a
		# conservative correction to avoid under-refining its longest axis.
		var correction := scales[distortion] / maxf(scales[min_axis], 0.000001)
		views.append({"camera": inverse * camera_position,
			"projection": view_projection * Projection(model), "focal": focal_pixels * correction})
		var distance := maxf(Lod.distance_to_aabb(camera_position, bounds), 0.05)
		weights[i] = minf(bounds.size.length() / distance, 1000.0)
	var quotas := distribute_budget(weights, budget_nodes)
	var unique: Dictionary = {}
	visible_instances = 0
	for i in views.size():
		if quotas[i] <= 0 or views[i].is_empty():
			continue
		visible_instances += 1
		var view: Dictionary = views[i]
		var wanted := Lod.select(pack, view["camera"], view["projection"], view["focal"], max_sse, quotas[i])
		_instance_wanted[i] = wanted
		for node in wanted:
			unique[node] = true
	var result: Array[int] = []
	if not unique.is_empty():
		# Keep one shared coarse root for new views and camera teleports. It
		# uses fallback slack, never extra GPU storage or a per-instance copy.
		result.append(pack.root)
		unique.erase(pack.root)
	for node in unique:
		result.append(int(node))
	_ops_dirty = true
	return result


## Reserve one node per visible instance, then distribute remaining nodes by
## projected importance. The sum never exceeds total, including tiny budgets.
static func distribute_budget(weights: PackedFloat32Array, total: int) -> PackedInt32Array:
	var quotas := PackedInt32Array()
	quotas.resize(weights.size())
	quotas.fill(0)
	var order: Array[int] = []
	for i in weights.size():
		if weights[i] > 0.0:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return weights[a] > weights[b] or (weights[a] == weights[b] and a < b))
	var remaining := maxi(total, 0)
	var weight_sum := 0.0
	for index in order:
		if remaining <= 0:
			break
		quotas[index] = 1
		remaining -= 1
		weight_sum += weights[index]
	if remaining <= 0 or weight_sum <= 0.0:
		return quotas
	var remainders: Array = []
	var extra := remaining
	for index in order:
		if quotas[index] == 0:
			continue
		var share := float(extra) * weights[index] / weight_sum
		var whole := floori(share)
		quotas[index] += whole
		remaining -= whole
		remainders.append([index, share - whole])
	remainders.sort_custom(func(a: Array, b: Array) -> bool:
		return a[1] > b[1] or (a[1] == b[1] and a[0] < b[0]))
	for i in remaining:
		quotas[int(remainders[i][0])] += 1
	return quotas


func _build_slot_info() -> PackedInt32Array:
	var info := PackedInt32Array()
	info.resize(directory_slots() * SLOT_INFO_WORDS)
	info.fill(0)
	projected_splats = 0
	projected_nodes = 0
	for i in _instance_wanted.size():
		var draws: Dictionary = {}
		for desired in _instance_wanted[i]:
			var node := int(desired)
			while node >= 0 and not _node_slot.has(node):
				node = pack.parent[node]
			if node >= 0:
				draws[node] = true
		for node in draws:
			# A fallback parent covers its ready descendants too. Drawing both
			# would double opacity and waste projection/sort work.
			var ancestor: int = pack.parent[int(node)]
			var covered := false
			while ancestor >= 0:
				if draws.has(ancestor):
					covered = true
					break
				ancestor = pack.parent[ancestor]
			if covered:
				continue
			assert(projected_nodes < directory_slots())
			var base := projected_nodes * SLOT_INFO_WORDS
			info[base] = pack.splat_count[int(node)]
			info[base + 1] = instance_id + i
			info[base + 2] = _float_bits(pack.centre_x[int(node)])
			info[base + 3] = _float_bits(pack.centre_y[int(node)])
			info[base + 4] = _float_bits(pack.centre_z[int(node)])
			info[base + 5] = _float_bits(pack.half_size[int(node)])
			info[base + 6] = slot_base + int(_node_slot[node]) + 1
			projected_splats += info[base]
			projected_nodes += 1
	return info
