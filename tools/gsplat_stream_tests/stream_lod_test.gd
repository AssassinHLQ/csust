extends SceneTree

## Headless test for the streaming LOD pack loader and the selection maths.
##   godot --headless --path . --script tests/stream_lod_test.gd
##
## Pure geometry and policy: no RenderingDevice, no display server.

const Fixture := preload("res://tools/gsplat_stream_tests/stream_pack_fixture.gd")
const Lod := preload("res://addons/gdgs/runtime/stream/gaussian_stream_lod.gd")
const PackScript := preload("res://addons/gdgs/runtime/stream/gaussian_stream_pack.gd")

const DEPTH := 2
const NODE_CAP := 16
const HALF := 8.0


func _initialize() -> void:
	var failures: PackedStringArray = []
	var prefix := "user://stream_lod_test/pack"
	DirAccess.make_dir_recursive_absolute("user://stream_lod_test")
	var manifest := Fixture.build(prefix, DEPTH, NODE_CAP, HALF)
	if manifest.is_empty():
		failures.append("fixture failed to write a pack")
		_finish(failures)
		return

	var pack: GaussianStreamPack = PackScript.new()
	if pack.load_from(manifest) != OK:
		failures.append("pack.load_from failed")
		_finish(failures)
		return

	_test_loader(pack, failures)
	_test_frustum(failures)
	_test_error_maths(failures)
	_test_selection(pack, failures)
	_test_budget_governor(pack, failures)
	_test_extreme_budget(pack, failures)
	_test_stable_sort(failures)
	_test_retry_cache(pack, failures)

	DirAccess.remove_absolute(manifest)
	DirAccess.remove_absolute(prefix + ".nodes.bin")
	_finish(failures)


func _test_loader(pack: GaussianStreamPack, failures: PackedStringArray) -> void:
	# A full octree of depth 2 has 1 + 8 + 64 nodes.
	var expected_nodes := 1 + 8 + 64
	if pack.node_count != expected_nodes:
		failures.append("node_count %d, expected %d" % [pack.node_count, expected_nodes])
	if pack.root != 0:
		failures.append("root should be 0, got %d" % pack.root)
	if pack.node_cap != NODE_CAP:
		failures.append("node_cap %d, expected %d" % [pack.node_cap, NODE_CAP])

	# parent[] is derived from children[]; every non-root must have exactly one.
	var orphans := 0
	for node in pack.node_count:
		if node == pack.root:
			if pack.parent[node] != -1:
				failures.append("root should have no parent")
			continue
		var parent := pack.parent[node]
		if parent < 0 or parent >= pack.node_count:
			orphans += 1
			continue
		var found := false
		for slot in 8:
			if pack.children[parent * 8 + slot] == node:
				found = true
		if not found:
			failures.append("node %d claims parent %d which does not list it" % [node, parent])
	if orphans > 0:
		failures.append("%d nodes have no valid parent" % orphans)

	# is_leaf must look at all eight slots, not just the first.
	var leaves := 0
	for node in pack.node_count:
		if pack.is_leaf(node):
			leaves += 1
	if leaves != 64:
		failures.append("leaf count %d, expected 64" % leaves)

	# Leaves partition the source cloud: this is the invariant that lets the
	# runtime prove every source splat was streamed.
	var covered := 0
	for node in pack.node_count:
		if pack.is_leaf(node):
			covered += pack.source_count[node]
	if covered != pack.source_splats:
		failures.append("leaf source_count sums to %d, manifest says %d" % [covered, pack.source_splats])

	if not pack.world_aabb.is_equal_approx(AABB(Vector3(-HALF, -HALF, -HALF), Vector3.ONE * HALF * 2.0)):
		failures.append("world_aabb %s does not match the fixture" % str(pack.world_aabb))

	# Payload offsets must be strictly increasing and inside the file.
	var file := FileAccess.open(pack.nodes_bin_path, FileAccess.READ)
	if file == null:
		failures.append("nodes.bin not readable")
		return
	var length := file.get_length()
	file.close()
	for node in pack.node_count:
		var bytes := pack.payload_bytes(node)
		if bytes != NODE_CAP * pack.stride_bytes:
			failures.append("node %d payload %d bytes, expected %d" % [node, bytes, NODE_CAP * pack.stride_bytes])
		if pack.byte_offset[node] + bytes > length:
			failures.append("node %d payload runs past the end of nodes.bin" % node)


func _test_frustum(failures: PackedStringArray) -> void:
	var projection := Projection.create_perspective(60.0, 1.0, 0.1, 200.0)
	var planes := Lod.extract_frustum_planes(projection)
	if planes.size() != 6:
		failures.append("expected 6 frustum planes, got %d" % planes.size())

	var in_front := AABB(Vector3(-1, -1, -10), Vector3(2, 2, 2))
	var behind := AABB(Vector3(-1, -1, 8), Vector3(2, 2, 2))
	var far_left := AABB(Vector3(-400, -1, -10), Vector3(2, 2, 2))
	# A box straddling a plane is kept: the test is conservative, not exact.
	var straddling := AABB(Vector3(-1, -1, -0.2), Vector3(2, 2, 2))
	if not Lod.aabb_in_frustum(planes, in_front):
		failures.append("a box straight ahead was culled")
	if Lod.aabb_in_frustum(planes, behind):
		failures.append("a box behind the camera was kept")
	if Lod.aabb_in_frustum(planes, far_left):
		failures.append("a box far outside the horizontal FOV was kept")

	# Godot's renderer uses reverse-Z (0 <= z_clip <= w_clip) while
	# Projection.create_perspective uses OpenGL depth. Both must give the same
	# verdicts, or LOD selection would cull differently from what is drawn.
	var reversed := _reverse_z_perspective(60.0, 1.0, 0.1, 200.0)
	var reverse_planes := Lod.extract_frustum_planes(reversed)
	if reverse_planes.size() != 6:
		failures.append("reverse-Z gave %d planes, expected 6" % reverse_planes.size())
	for box in [in_front, behind, far_left, straddling]:
		if Lod.aabb_in_frustum(planes, box) != Lod.aabb_in_frustum(reverse_planes, box):
			failures.append("reverse-Z changed the culling verdict for %s" % str(box))

	# The near/far planes must land on the actual near/far distances under both
	# conventions; a swapped pair silently culls everything in front of the camera.
	for pair in [[planes, "opengl"], [reverse_planes, "reverse-z"]]:
		var depths: Array[float] = []
		for plane in pair[0]:
			if absf(plane.normal.z) > 0.99:
				depths.append(-plane.d / plane.normal.z)
		depths.sort()
		# float32 matrix entries round the far plane by a few thousandths.
		if depths.size() != 2 or absf(depths[0] + 200.0) > 0.01 or absf(depths[1] + 0.1) > 0.001:
			failures.append("%s depth planes at %s, expected [-200, -0.1]" % [pair[1], str(depths)])

	if not Lod.aabb_in_frustum(planes, straddling):
		failures.append("a box straddling the near plane was culled")


## A genuine reverse-Z perspective: z_clip in [0, w_clip], near -> 1, far -> 0.
## This is the convention Godot's renderer uses, so the selection has to handle it.
static func _reverse_z_perspective(fov_degrees: float, aspect: float, near: float, far: float) -> Projection:
	var cotangent := 1.0 / tan(deg_to_rad(fov_degrees) * 0.5)
	var matrix := Projection.IDENTITY
	matrix.x = Vector4(cotangent / aspect, 0, 0, 0)
	matrix.y = Vector4(0, cotangent, 0, 0)
	matrix.z = Vector4(0, 0, near / (far - near), -1)
	matrix.w = Vector4(0, 0, near * far / (far - near), 0)
	return matrix


func _test_error_maths(failures: PackedStringArray) -> void:
	if Lod.screen_space_error(0.0, 10.0, 500.0) != 0.0:
		failures.append("zero geometric error must give zero screen error")
	var near := Lod.screen_space_error(1.0, 10.0, 500.0)
	var far := Lod.screen_space_error(1.0, 20.0, 500.0)
	if not is_equal_approx(far, near * 0.5):
		failures.append("screen error should halve when distance doubles (%f vs %f)" % [far, near])
	# The distance floor keeps a camera inside a node from dividing by zero.
	var inside := Lod.screen_space_error(1.0, 0.0, 500.0)
	if not is_finite(inside) or inside <= 0.0:
		failures.append("zero distance must stay finite and positive, got %f" % inside)

	var projection := Projection.create_perspective(60.0, 16.0 / 9.0, 0.1, 200.0)
	var focal := Lod.focal_pixels_from_projection(projection, 1080.0)
	var expected := 1080.0 / (2.0 * tan(deg_to_rad(60.0) * 0.5))
	if not is_equal_approx(focal, expected):
		failures.append("focal_pixels %f, expected %f from the FOV" % [focal, expected])

	var box := AABB(Vector3(2, 0, 0), Vector3(2, 2, 2))
	if not is_equal_approx(Lod.distance_to_aabb(Vector3.ZERO, box), 2.0):
		failures.append("distance_to_aabb should clamp to the nearest face")
	if Lod.distance_to_aabb(Vector3(3, 1, 1), box) != 0.0:
		failures.append("a point inside the box must have distance 0")


func _test_selection(pack: GaussianStreamPack, failures: PackedStringArray) -> void:
	var projection := Projection.create_perspective(60.0, 1.0, 0.1, 200.0)
	var focal := Lod.focal_pixels_from_projection(projection, 1080.0)
	# Camera outside the cloud on +Z, looking back at the origin down -Z.
	var camera := Vector3(0, 0, HALF * 4.0)
	var view := Projection(Transform3D(Basis.looking_at(Vector3(0, 0, -1)), camera).affine_inverse())
	var vp := projection * view

	var wanted := Lod.select(pack, camera, vp, focal, 16.0, 512)
	if wanted.is_empty():
		failures.append("selection returned nothing for a camera looking at the cloud")
		return
	if wanted.size() > 512:
		failures.append("selection exceeded the budget")

	# Nearest first: the load queue truncates from the far end, so this ordering
	# is what makes a refinement burst fill in from the camera outwards.
	var previous := -1.0
	for node in wanted:
		var distance := Lod.distance_to_aabb(camera, pack.node_aabb(node))
		if distance < previous - 1e-4:
			failures.append("selection is not sorted nearest-first at node %d" % node)
			break
		previous = distance

	# Every emitted node must survive the frustum test.
	var planes := Lod.extract_frustum_planes(vp)
	for node in wanted:
		if not Lod.aabb_in_frustum(planes, pack.node_aabb(node)):
			failures.append("selected node %d is outside the frustum" % node)
			break

	# Refinement: a tight threshold near the cloud must emit more nodes than a
	# loose one far away, and both must stay inside the tree.
	var close := Lod.select(pack, Vector3(0, 0, HALF * 1.2), vp, focal, 0.5, 512)
	var distant := Lod.select(pack, Vector3(0, 0, HALF * 40.0), vp, focal, 64.0, 512)
	if close.size() <= distant.size():
		failures.append("close/tight view (%d nodes) should refine more than far/loose (%d)"
			% [close.size(), distant.size()])
	for node in close:
		if node < 0 or node >= pack.node_count:
			failures.append("selection emitted an out-of-range node %d" % node)
			break

	# A camera looking away must select nothing rather than the whole tree.
	var away_view := Projection(Transform3D(Basis.looking_at(Vector3(0, 0, 1)), camera).affine_inverse())
	var away := Lod.select(pack, camera, projection * away_view, focal, 16.0, 512)
	if not away.is_empty():
		failures.append("a camera facing away from the cloud selected %d nodes" % away.size())


func _test_budget_governor(pack: GaussianStreamPack, failures: PackedStringArray) -> void:
	var projection := Projection.create_perspective(60.0, 1.0, 0.1, 200.0)
	var focal := Lod.focal_pixels_from_projection(projection, 1080.0)
	var camera := Vector3(0, 0, HALF * 1.2)
	var view := Projection(Transform3D(Basis.looking_at(Vector3(0, 0, -1)), camera).affine_inverse())
	var vp := projection * view

	# A tight threshold wants the whole tree; the governor must coarsen until the
	# result fits, never return an over-budget set.
	for budget in [1, 2, 8, 32]:
		var wanted := Lod.select(pack, camera, vp, focal, 0.01, budget)
		if wanted.size() > budget:
			failures.append("budget %d returned %d nodes" % [budget, wanted.size()])
		if wanted.is_empty():
			failures.append("budget %d returned nothing" % budget)

	# Zero budget is a valid "render nothing" request, not a crash.
	if not Lod.select(pack, camera, vp, focal, 16.0, 0).is_empty():
		failures.append("a zero budget should select nothing")


## The final retry must actually traverse with INF, even when the finite ladder
## cannot coarsen a camera inside a node with very large geometric error.
func _test_extreme_budget(pack: GaussianStreamPack, failures: PackedStringArray) -> void:
	var original := pack.geometric_error.duplicate()
	for node in pack.node_count:
		if not pack.is_leaf(node):
			pack.geometric_error[node] = 1e20
	var projection := Projection.create_perspective(90.0, 1.0, 0.1, 200.0)
	var wanted := Lod.select(pack, Vector3.ZERO, projection, 540.0, 0.001, 1)
	if wanted != [pack.root]:
		failures.append("exhausted retry ladder must return the visible root, got %s" % str(wanted))
	if Lod.last_threshold != INF:
		failures.append("exhausted retry ladder did not report the infinite threshold")
	# Preserve all finite retries: a scene that fits on the last finite step
	# must not be forced to INF just because it reached the end of the ladder.
	var camera := Vector3(0, 0, HALF * 4.0)
	var finite_threshold := 0.001 * pow(Lod.THRESHOLD_GROWTH, Lod.MAX_ATTEMPTS - 1)
	pack.geometric_error[pack.root] = finite_threshold * 0.9 \
		* Lod.distance_to_aabb(camera, pack.node_aabb(pack.root)) / 540.0
	var view := Projection(Transform3D(Basis.IDENTITY, camera).affine_inverse())
	wanted = Lod.select(pack, camera, projection * view, 540.0, 0.001, 1)
	if wanted != [pack.root] or not is_equal_approx(Lod.last_threshold, finite_threshold):
		failures.append("last finite budget retry was replaced by the infinite fallback")
	pack.geometric_error = original


## Equal distances must preserve traversal order so tied nodes do not churn the
## IO priority from one selection to the next. Include the full exported budget.
func _test_stable_sort(failures: PackedStringArray) -> void:
	for count in [0, 1, 17, 64, 65, 192, 4096]:
		var values := PackedFloat32Array()
		values.resize(count)
		for i in count:
			values[i] = float((count - i) % 31)
		var order := Lod._sorted_indices(values)
		var seen: Dictionary = {}
		if order.size() != count:
			failures.append("sort returned %d indices for %d values" % [order.size(), count])
			continue
		for i in count:
			var index := order[i]
			if index < 0 or index >= count or seen.has(index):
				failures.append("sort result is not a permutation at size %d" % count)
				break
			seen[index] = true
			if i > 0:
				var previous := order[i - 1]
				if values[previous] > values[index] or (values[previous] == values[index] and previous > index):
					failures.append("sort is not stable nearest-first at size %d" % count)
					break


## Compare cached retries with a full iterative traversal. Every call changes
## camera/projection/policy so no cached visibility or SSE may leak to the next.
func _test_retry_cache(pack: GaussianStreamPack, failures: PackedStringArray) -> void:
	var cases := 0
	for eye in [Vector3(0, 0, 32), Vector3(0, 0, 4), Vector3(5, 4, 6), Vector3(-15, 2, -5)]:
		for fov in [50.0, 90.0]:
			var projection := Projection.create_perspective(fov, 16.0 / 9.0, 0.1, 200)
			var view := Transform3D(Basis.IDENTITY, eye).looking_at(Vector3.ZERO)
			var vp := projection * Projection(view.affine_inverse())
			var focal := Lod.focal_pixels_from_projection(projection, 1080)
			for budget in [1, 8, 32, 128]:
				for sse in [0.01, 1.0, 16.0, 256.0]:
					var expected := _reference_selection(pack, eye, vp, focal, sse, budget)
					var actual := Lod.select(pack, eye, vp, focal, sse, budget)
					cases += 1
					if actual != expected.nodes or Lod.last_threshold != expected.threshold:
						failures.append("retry cache changed frontier/threshold at case %d" % cases)
	print("LOD retry cache: %d reference cases" % cases)


func _reference_selection(pack: GaussianStreamPack, eye: Vector3, vp: Projection,
		focal: float, sse: float, budget: int) -> Dictionary:
	var planes := Lod.extract_frustum_planes(vp)
	var threshold := maxf(sse, 0.001)
	var wanted: Array[int] = []
	for attempt in range(Lod.MAX_ATTEMPTS + 1):
		wanted.clear()
		var stack: Array[int] = [pack.root]
		while not stack.is_empty():
			var node: int = stack.pop_back()
			var box := pack.node_aabb(node)
			if not Lod.aabb_in_frustum(planes, box):
				continue
			var error := Lod.screen_space_error(pack.geometric_error[node], Lod.distance_to_aabb(eye, box), focal)
			if error <= threshold or pack.is_leaf(node):
				wanted.append(node)
			else:
				for slot in range(7, -1, -1):
					var child := pack.children[node * 8 + slot]
					if child >= 0:
						stack.append(child)
		if wanted.size() <= budget:
			break
		threshold = INF if attempt == Lod.MAX_ATTEMPTS - 1 else threshold * Lod.THRESHOLD_GROWTH
	var distances := PackedFloat32Array()
	for node in wanted:
		distances.append(Lod.distance_to_aabb(eye, pack.node_aabb(node)))
	var result: Array[int] = []
	for index in Lod._sorted_indices(distances):
		result.append(wanted[index])
	return {"nodes": result, "threshold": threshold}


func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("stream_lod_test: PASS")
		quit(0)
		return
	for line in failures:
		printerr("  FAIL: %s" % line)
	printerr("stream_lod_test: %d failure(s)" % failures.size())
	quit(1)
