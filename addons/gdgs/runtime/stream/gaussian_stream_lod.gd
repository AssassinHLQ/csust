@tool
extends RefCounted
class_name GaussianStreamLod

## Pure LOD selection for a GaussianStreamPack: frustum culling, screen-space
## error and the node-budget governor. No RenderingDevice, no scene tree, so it
## is headless-testable (tests/stream_lod_test.gd).
##
## The traversal descends while a node's screen-space error exceeds a threshold.
## Because every node stores the same fixed-capacity sample, the number of
## emitted nodes is directly the number of GPU slots, so a node budget is a
## splat budget: `budget * pack.node_cap` splats resident, whatever the world
## size. When the ideal set is over budget the threshold is raised and the tree
## re-walked, which coarsens the whole view uniformly instead of punching holes
## in it.

## Threshold growth per retry. The geometric phase coarsens the view uniformly;
## an infinite-threshold fallback follows exhausted finite retries and always
## collapses to the root, honouring any budget and any pack error scale.
const THRESHOLD_GROWTH := 1.7
const MAX_ATTEMPTS := 32
## Distance floor so a camera inside a node does not divide by zero.
const MIN_DISTANCE := 0.05

## Effective SSE threshold of the last select(), after budget retries. When the
## ideal set is over budget the threshold grows by THRESHOLD_GROWTH per retry,
## so the picture can be coarser than max_sse; diagnostics report this value.
static var last_threshold: float = 0.0


## Six frustum half-spaces from a world->clip matrix.
##
## Gribb-Hartmann: row3 +/- rowN for the sides, and a depth pair that depends on
## the clip convention. Projection.create_perspective uses OpenGL depth
## (-w <= z <= w, pair row3+row2 / row3-row2); Godot's renderer uses reverse-Z
## (0 <= z <= w, pair row2 / row3-row2). The two are told apart geometrically:
## a near/far pair always faces opposite ways, so when the OpenGL pair's normals
## agree instead, the matrix is reverse-Z. This works on a combined
## projection*view matrix, where the depth scale is no longer readable directly.
static func extract_frustum_planes(matrix: Projection) -> Array[Plane]:
	var row0 := Vector4(matrix.x[0], matrix.y[0], matrix.z[0], matrix.w[0])
	var row1 := Vector4(matrix.x[1], matrix.y[1], matrix.z[1], matrix.w[1])
	var row2 := Vector4(matrix.x[2], matrix.y[2], matrix.z[2], matrix.w[2])
	var row3 := Vector4(matrix.x[3], matrix.y[3], matrix.z[3], matrix.w[3])
	var candidates := [
		row3 + row0, row3 - row0,
		row3 + row1, row3 - row1,
	]
	var depth_a := row3 + row2
	var depth_b := row3 - row2
	var normal_a := Vector3(depth_a.x, depth_a.y, depth_a.z)
	var normal_b := Vector3(depth_b.x, depth_b.y, depth_b.z)
	var reverse_z := false
	if normal_a.length() > 1e-12 and normal_b.length() > 1e-12:
		reverse_z = normal_a.normalized().dot(normal_b.normalized()) > 0.0
	if reverse_z:
		candidates.append_array([row2, depth_b])
	else:
		candidates.append_array([depth_a, depth_b])
	var planes: Array[Plane] = []
	for candidate in candidates:
		var normal := Vector3(candidate.x, candidate.y, candidate.z)
		var length := normal.length()
		if length < 1e-12:
			continue
		planes.append(Plane(normal / length, candidate.w / length))
	return planes


## Conservative AABB/frustum test: the box is rejected only when its corner
## furthest along a plane normal is still behind that plane.
static func aabb_in_frustum(planes: Array[Plane], box: AABB) -> bool:
	var end := box.position + box.size
	for plane in planes:
		var normal := plane.normal
		var corner := Vector3(
			end.x if normal.x >= 0.0 else box.position.x,
			end.y if normal.y >= 0.0 else box.position.y,
			end.z if normal.z >= 0.0 else box.position.z)
		if normal.dot(corner) + plane.d < 0.0:
			return false
	return true


static func distance_to_aabb(point: Vector3, box: AABB) -> float:
	var closest := point.clamp(box.position, box.position + box.size)
	return point.distance_to(closest)


## Pixels of world-space error a node projects to at `distance`.
## `focal_pixels` is viewport_height / (2 * tan(fov_y / 2)).
static func screen_space_error(geometric_error: float, distance: float, focal_pixels: float) -> float:
	if geometric_error <= 0.0:
		return 0.0
	return geometric_error * focal_pixels / maxf(distance, MIN_DISTANCE)


## Vertical focal length in pixels, taken from the projection matrix so the
## selection matches whatever FOV/aspect the camera actually renders with.
static func focal_pixels_from_projection(projection: Projection, viewport_height: float) -> float:
	return absf(projection.y[1]) * maxf(viewport_height, 1.0) * 0.5


## Nodes the viewer wants resident, nearest first.
##
## `camera_position` and the pack share a coordinate space (the stream node's
## local space). `budget` caps the node count; the returned array never exceeds
## it.
static func select(
	pack: GaussianStreamPack,
	camera_position: Vector3,
	view_projection: Projection,
	focal_pixels: float,
	max_sse: float,
	budget: int
) -> Array[int]:
	var result: Array[int] = []
	if pack == null or not pack.is_loaded() or budget <= 0:
		return result
	var planes := extract_frustum_planes(view_projection)
	var threshold := maxf(max_sse, 0.001)
	var wanted: Array[int] = []
	# Retries change only the threshold. After a budget miss, cache each visited
	# node's exact SSE (or a negative frustum rejection) for this call only.
	# A fitting first traversal pays no per-node dictionary cost. Sparse storage
	# follows visited nodes instead of allocating for the world.
	var node_errors: Variant = null
	for attempt in MAX_ATTEMPTS:
		wanted.clear()
		_traverse(pack, pack.root, camera_position, planes, focal_pixels, threshold, budget, wanted, node_errors)
		if wanted.size() <= budget:
			break
		if node_errors == null:
			node_errors = {}
		# Preserve every finite step. Only an exhausted ladder uses the infinite
		# fallback, and it must actually traverse with that threshold.
		if attempt == MAX_ATTEMPTS - 1:
			threshold = INF
			wanted.clear()
			_traverse(pack, pack.root, camera_position, planes, focal_pixels, threshold, budget, wanted, node_errors)
			break
		threshold *= THRESHOLD_GROWTH
	last_threshold = threshold

	# Nearest first: the picture fills in from the camera outwards, and when a
	# load queue has to be truncated the far end is what waits.
	var distances := PackedFloat32Array()
	distances.resize(wanted.size())
	for i in wanted.size():
		distances[i] = distance_to_aabb(camera_position, pack.node_aabb(wanted[i]))
	var order := _sorted_indices(distances)
	result.resize(wanted.size())
	for i in wanted.size():
		result[i] = wanted[order[i]]
	return result


static func _traverse(
	pack: GaussianStreamPack,
	node: int,
	camera_position: Vector3,
	planes: Array[Plane],
	focal_pixels: float,
	threshold: float,
	budget: int,
	out: Array[int],
	node_errors: Variant
) -> void:
	var sse: float = node_errors.get(node, -2.0) if node_errors != null else -2.0
	if sse == -2.0:
		var box := pack.node_aabb(node)
		sse = screen_space_error(pack.geometric_error[node], distance_to_aabb(camera_position, box), focal_pixels) \
			if aabb_in_frustum(planes, box) else -1.0
		if node_errors != null:
			node_errors[node] = sse
	if sse < 0.0:
		return
	if sse <= threshold or pack.is_leaf(node):
		out.append(node)
		return
	var descended := false
	for slot in 8:
		var child := pack.children[node * 8 + slot]
		if child >= 0:
			descended = true
			_traverse(pack, child, camera_position, planes, focal_pixels, threshold, budget, out, node_errors)
			# An over-budget frontier is discarded in its entirety. Once the
			# (budget + 1)th node is visible, visiting the rest cannot make this
			# attempt fit; retry at the same next threshold as the full walk.
			if out.size() > budget:
				return
	if not descended:
		out.append(node)


## Short lists keep insertion sort's low overhead; larger frontiers use the
## native O(n log n) sort. Ties retain the original traversal/IO priority.
static func _sorted_indices(values: PackedFloat32Array) -> PackedInt32Array:
	if values.size() <= 64:
		var small := PackedInt32Array()
		small.resize(values.size())
		for i in values.size():
			small[i] = i
		for i in range(1, small.size()):
			var key := small[i]
			var j := i - 1
			while j >= 0 and values[small[j]] > values[key]:
				small[j + 1] = small[j]
				j -= 1
			small[j + 1] = key
		return small
	var order: Array[int] = []
	order.resize(values.size())
	for i in values.size():
		order[i] = i
	order.sort_custom(func(a: int, b: int) -> bool:
		return values[a] < values[b] or (values[a] == values[b] and a < b))
	return PackedInt32Array(order)
