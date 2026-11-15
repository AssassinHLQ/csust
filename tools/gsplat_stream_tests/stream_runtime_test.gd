extends SceneTree

## Headless test for the streaming residency manager: slot density, eviction
## swaps, snapshot/full agreement and source coverage.
##   godot --headless --path . --script tests/stream_runtime_test.gd
##
## Uses WorkerThreadPool (available headless) but no RenderingDevice.

const Fixture := preload("res://tools/gsplat_stream_tests/stream_pack_fixture.gd")
const Lod := preload("res://addons/gdgs/runtime/stream/gaussian_stream_lod.gd")
const PackScript := preload("res://addons/gdgs/runtime/stream/gaussian_stream_pack.gd")
const RuntimeScript := preload("res://addons/gdgs/runtime/stream/gaussian_stream_runtime.gd")

const DEPTH := 2
const NODE_CAP := 16
const HALF := 8.0
const BUDGET := 8
## Must match GaussianStreamRuntime.SLOT_INFO_WORDS.
const SLOT_INFO_WORDS := 8

var _failures: PackedStringArray = []
var _pack: GaussianStreamPack
var _runtime: RefCounted
var _prefix := "user://stream_runtime_test/pack"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("user://stream_runtime_test")
	var manifest := Fixture.build(_prefix, DEPTH, NODE_CAP, HALF)
	if manifest.is_empty():
		_failures.append("fixture failed to write a pack")
		_finish()
		return
	_pack = PackScript.new()
	if _pack.load_from(manifest) != OK:
		_failures.append("pack.load_from failed")
		_finish()
		return

	_runtime = RuntimeScript.new()
	_runtime.configure(_pack, BUDGET)
	_runtime.max_sse = 0.5
	_runtime.select_interval = 0.0
	_runtime.max_loads_per_frame = 8
	_runtime.max_inflight = 8

	# Phase A: from inside the cloud looking towards +X, only the +X octants are
	# in frustum, so the wanted set is a strict subset of the tree.
	var inside := Vector3(0, 0, HALF * 0.5)
	_drive(inside, Vector3(1, 0, 0), 400)
	_check_density("after first fill")
	_check_budget()
	var first_slots: int = _runtime.active_slots()
	if first_slots == 0:
		_failures.append("nothing became resident")
	if _runtime.io_failures != 0:
		_failures.append("unexpected IO failures: %d" % _runtime.io_failures)

	# Phase B: turn around. The wanted set is now the disjoint -X octants, so
	# every resident node is evicted and the arena has to swap slots to stay dense.
	_drive(inside, Vector3(-1, 0, 0), 400)
	_check_density("after camera turn")
	_check_budget()
	if _runtime.evictions == 0:
		_failures.append("turning to the opposite octants evicted nothing")
	if _runtime.moves == 0:
		_failures.append("eviction never produced a swap move")

	# Phase C: a budget large enough to reach the leaves. Only leaves carry
	# source_count, so this is what proves the coverage counter means anything.
	_runtime.configure(_pack, 256)
	_runtime.max_sse = 0.5
	_runtime.select_interval = 0.0
	_drive(inside, Vector3(1, 0, 0), 600)
	_check_density("after leaf refinement")
	var covered: int = _runtime.covered_source_splats
	if covered <= 0 or covered > _pack.source_splats:
		_failures.append("covered_source_splats %d out of range (source %d)"
			% [covered, _pack.source_splats])
	var leaves := 0
	for slot in _runtime.active_slots():
		if _pack.is_leaf(_runtime._slot_node[slot]):
			leaves += 1
	if leaves == 0:
		_failures.append("a 256-node budget never refined down to a leaf")

	# Phase D: the delta snapshots and the full mirror must agree.
	_check_snapshots()

	# Phase E: a truncated payload file must be counted, not crash or corrupt.
	_test_short_read()

	# Phase F: the q24 layout loads with its own stride and publishes the node
	# centre/half-size word the projection shader decodes positions against.
	_test_quantized_layout()
	_test_selection_cache()
	_test_fallback_retirement()
	_test_full_detail_residency()

	# Phase G: shutdown drains the workers and drops the CPU mirror.
	_runtime.shutdown()
	if not _runtime._cpu_payload.is_empty():
		_failures.append("shutdown left %d CPU payloads behind" % _runtime._cpu_payload.size())
	if _runtime.inflight_count() != 0:
		_failures.append("shutdown left %d reads in flight" % _runtime.inflight_count())
	if _runtime.is_running():
		_failures.append("runtime still reports running after shutdown")

	DirAccess.remove_absolute(_prefix + ".manifest.json")
	DirAccess.remove_absolute(_prefix + ".nodes.bin")
	_finish()


## A full-detail pack must not reload its whole payload after looking at the sky.
## Hierarchical packs and the default streaming policy still cull normally.
func _test_full_detail_residency() -> void:
	var prefix := "user://stream_runtime_test/full_detail"
	var manifest := Fixture.build(prefix, 0, NODE_CAP, HALF)
	var pack: GaussianStreamPack = PackScript.new()
	if pack.load_from(manifest) != OK:
		_failures.append("full-detail fixture failed to load")
		return
	var runtime := RuntimeScript.new()
	runtime.configure(pack, 1)
	var camera := Vector3(0, 0, HALF * 3)
	_drive_runtime(runtime, camera, Vector3.FORWARD, 200)
	if runtime.resident_splats() != NODE_CAP:
		_failures.append("full-detail pack did not become resident")
	_drive_runtime(runtime, camera, Vector3.BACK, 100)
	if runtime.active_slots() != 0:
		_failures.append("default policy did not evict an out-of-view pack")
	runtime.keep_single_node_resident = true
	_drive_runtime(runtime, camera, Vector3.BACK, 200)
	var loads: int = runtime.loads_completed
	var evictions: int = runtime.evictions
	for direction in [Vector3.FORWARD, Vector3.BACK, Vector3(0, 1, -.01)]:
		_drive_runtime(runtime, camera, direction, 100)
		if runtime.resident_splats() != NODE_CAP or runtime.wanted_count() != 1:
			_failures.append("pinned full-detail pack evicted during camera turn")
	if runtime.loads_completed != loads or runtime.evictions != evictions:
		_failures.append("camera turns reloaded pinned full-detail payload")
	runtime.keep_single_node_resident = false
	_drive_runtime(runtime, camera, Vector3.BACK, 100)
	if runtime.active_slots() != 0:
		_failures.append("disabling retention did not restore frustum eviction")
	runtime.configure(_pack, BUDGET)
	runtime.keep_single_node_resident = true
	_drive_runtime(runtime, Vector3(0, 0, HALF * 3), Vector3.BACK, 100)
	if runtime.active_slots() != 0:
		_failures.append("retention incorrectly pinned a hierarchical LOD pack")
	runtime.shutdown()
	if runtime.resident_splats() != 0 or not runtime._cpu_payload.is_empty():
		_failures.append("retained full-detail payload survived shutdown")
	DirAccess.remove_absolute(prefix + ".manifest.json")
	DirAccess.remove_absolute(prefix + ".nodes.bin")


## Tick the manager until the IO queue drains. WorkerThreadPool runs on its own
## threads, so a short main-thread delay is enough to let reads land.
func _drive(camera: Vector3, direction: Vector3, ticks: int) -> void:
	_drive_runtime(_runtime, camera, direction, ticks)


func _drive_runtime(runtime, camera: Vector3, direction: Vector3, ticks: int) -> void:
	var projection := Projection.create_perspective(60.0, 1.0, 0.1, 200.0)
	var focal := Lod.focal_pixels_from_projection(projection, 1080.0)
	var view := Projection(Transform3D(Basis.looking_at(direction.normalized()), camera).affine_inverse())
	for i in ticks:
		runtime.update(camera, projection * view, focal, 0.016)
		if runtime.inflight_count() == 0 and runtime._load_queue.is_empty() and i > 40:
			break
		OS.delay_msec(2)


## A q24 pack must load with its own 24 B stride and publish the per-slot node
## frame the projection shader needs to rebuild int16 positions.
func _test_quantized_layout() -> void:
	var prefix := "user://stream_runtime_test/q24pack"
	var manifest := Fixture.build(prefix, DEPTH, NODE_CAP, HALF, true)
	if manifest.is_empty():
		_failures.append("q24 fixture failed to write a pack")
		return
	var pack: GaussianStreamPack = PackScript.new()
	if pack.load_from(manifest) != OK:
		_failures.append("q24 pack.load_from failed")
		return
	if pack.stride_bytes != 24 or pack.stride_words != 6 or not pack.is_quantized():
		_failures.append("q24 pack reports stride %d/%d layout %s"
			% [pack.stride_bytes, pack.stride_words, pack.record_layout])

	var runtime: RefCounted = RuntimeScript.new()
	runtime.configure(pack, BUDGET)
	runtime.max_sse = 0.5
	runtime.select_interval = 0.0
	_drive_runtime(runtime, Vector3(0, 0, HALF * 0.5), Vector3(1, 0, 0), 400)
	if runtime.io_failures != 0:
		_failures.append("q24 runtime had %d IO failures" % runtime.io_failures)
	if runtime.resident_splats() <= 0:
		_failures.append("q24 runtime loaded nothing")

	var info: PackedInt32Array = runtime.full_snapshot().get("slot_info", PackedInt32Array())
	if info.size() != runtime.capacity_slots() * SLOT_INFO_WORDS:
		_failures.append("q24 slot_info has %d words, expected %d"
			% [info.size(), runtime.capacity_slots() * SLOT_INFO_WORDS])
	for slot in runtime.active_slots():
		var node: int = runtime._slot_node[slot]
		var base: int = slot * SLOT_INFO_WORDS
		if absf(_bits_to_float(info[base + 2]) - pack.centre_x[node]) > 1e-4:
			_failures.append("q24 slot %d centre word does not match the node" % slot)
			break
		if absf(_bits_to_float(info[base + 3]) - pack.centre_y[node]) > 1e-4:
			_failures.append("q24 slot %d centre.y word does not match the node" % slot)
			break
		if absf(_bits_to_float(info[base + 5]) - pack.half_size[node]) > 1e-6:
			_failures.append("q24 slot %d half-size word does not match the node" % slot)
			break
	runtime.shutdown()
	DirAccess.remove_absolute(prefix + ".manifest.json")
	DirAccess.remove_absolute(prefix + ".nodes.bin")


## Every slot below active_slots must hold exactly one node, and no node may hold
## two slots. A hole here would make the projection dispatch read garbage.
func _check_density(label: String) -> void:
	var active: int = _runtime.active_slots()
	var seen: Dictionary = {}
	for slot in active:
		var node: int = _runtime._slot_node[slot]
		if node < 0:
			_failures.append("%s: slot %d is empty below active_slots=%d" % [label, slot, active])
			continue
		if seen.has(node):
			_failures.append("%s: node %d occupies two slots" % [label, node])
		seen[node] = slot
		if int(_runtime._node_slot.get(node, -1)) != slot:
			_failures.append("%s: node %d slot map disagrees (%s vs %d)"
				% [label, node, str(_runtime._node_slot.get(node, -1)), slot])
	for slot in range(active, _runtime.capacity_slots()):
		if _runtime._slot_node[slot] != -1:
			_failures.append("%s: slot %d above active_slots still holds a node" % [label, slot])
	if seen.size() != _runtime._node_slot.size():
		_failures.append("%s: %d slots but %d node mappings" % [label, seen.size(), _runtime._node_slot.size()])
	# resident_splats must equal the sum of the resident nodes' stored counts.
	var total := 0
	for node in seen:
		total += _pack.splat_count[node]
	if total != _runtime.resident_splats():
		_failures.append("%s: resident_splats %d but slots sum to %d"
			% [label, _runtime.resident_splats(), total])


func _check_budget() -> void:
	if _runtime.active_slots() > _runtime.capacity_slots():
		_failures.append("active_slots %d exceeds capacity %d"
			% [_runtime.active_slots(), _runtime.capacity_slots()])
	if _runtime.resident_splats() > _runtime.capacity_slots() * NODE_CAP:
		_failures.append("resident splats exceed the arena")


## Replay every delta from an empty arena and compare with the full mirror.
## Words 2..5 (node centre and half-size, used by the q24 decoder) only exist in
## the full mirror, so the replay compares the count/instance words it can see.
func _check_snapshots() -> void:
	var full: Dictionary = _runtime.full_snapshot()
	var info: PackedInt32Array = full.get("slot_info", PackedInt32Array())
	if info.size() != _runtime.capacity_slots() * SLOT_INFO_WORDS:
		_failures.append("slot_info has %d words, expected %d"
			% [info.size(), _runtime.capacity_slots() * SLOT_INFO_WORDS])
	var replay := PackedInt32Array()
	replay.resize(_runtime.capacity_slots() * SLOT_INFO_WORDS)
	replay.fill(0)
	var active := 0
	var resident := 0
	# consume(-1) hands back the full mirror when the window has rolled over, so
	# walk the retained ring instead to get the individual deltas.
	var deltas: Array = _runtime.consume(-1)
	for snapshot in deltas:
		for upload in snapshot.get("uploads", []):
			var slot: int = int(upload["slot"])
			replay[slot * SLOT_INFO_WORDS] = int(upload["count"])
			replay[slot * SLOT_INFO_WORDS + 1] = int(upload["instance"])
		active = int(snapshot.get("active_slots", active))
		resident = int(snapshot.get("resident_splats", resident))
	if active != int(full.get("active_slots", -1)):
		_failures.append("delta replay ends at active_slots %d, full says %d"
			% [active, int(full.get("active_slots", -1))])
	if resident != int(full.get("resident_splats", -1)):
		_failures.append("delta replay ends at resident_splats %d, full says %d"
			% [resident, int(full.get("resident_splats", -1))])
	for slot in _runtime.active_slots():
		var base: int = slot * SLOT_INFO_WORDS
		if replay[base] != info[base] or replay[base + 1] != info[base + 1]:
			_failures.append("slot_info disagrees at slot %d: delta %d/%d vs full %d/%d"
				% [slot, replay[base], replay[base + 1], info[base], info[base + 1]])
			break
		var node: int = _runtime._slot_node[slot]
		if absf(_bits_to_float(info[base + 5]) - _pack.half_size[node]) > 1e-6:
			_failures.append("slot %d half-size word does not round-trip" % slot)
			break


func _bits_to_float(bits: int) -> float:
	var buffer := PackedByteArray()
	buffer.resize(4)
	buffer.encode_u32(0, bits)
	return buffer.decode_float(0)


## Point the runtime at a payload file that is too short and confirm the read is
## rejected rather than assigned to a slot.
func _test_short_read() -> void:
	var broken := RuntimeScript.new()
	broken.configure(_pack, 4)
	broken.max_sse = 0.5
	broken.select_interval = 0.0
	var bin_path := _pack.nodes_bin_path
	var original := FileAccess.get_file_as_bytes(bin_path)
	var truncated := FileAccess.open(bin_path, FileAccess.WRITE)
	if truncated == null:
		_failures.append("could not reopen nodes.bin for the short-read test")
		return
	truncated.store_buffer(original.slice(0, 64))
	truncated.close()

	var projection := Projection.create_perspective(60.0, 1.0, 0.1, 200.0)
	var camera := Vector3(0, 0, HALF * 4.0)
	var view := Projection(Transform3D(Basis.looking_at(Vector3(0, 0, -1)), camera).affine_inverse())
	for i in 120:
		broken.update(camera, projection * view, 500.0, 0.016)
		OS.delay_msec(2)
	if broken.io_failures == 0:
		_failures.append("a truncated payload was not reported as an IO failure")
	if broken.active_slots() != 0:
		_failures.append("a short read still occupied %d slots" % broken.active_slots())
	broken.shutdown()

	var restored := FileAccess.open(bin_path, FileAccess.WRITE)
	if restored != null:
		restored.store_buffer(original)
		restored.close()


## Static and empty views must not keep walking the tree. Turns, projection,
## viewport focal length and policy edits must invalidate even a long interval.
func _test_selection_cache() -> void:
	var runtime := RuntimeScript.new()
	runtime.configure(_pack, BUDGET)
	runtime.max_sse = 0.5
	runtime.select_interval = 60.0
	runtime.max_loads_per_frame = 0
	var camera := Vector3(0, 0, HALF * 0.5)
	var projection := Projection.create_perspective(60.0, 1.0, 0.1, 200.0)
	var view := Projection(Transform3D(Basis.looking_at(Vector3.RIGHT), camera).affine_inverse())
	var vp := projection * view
	runtime.update(camera, vp, 540.0, 0.016)
	var initial := runtime.wanted_nodes()
	for tick in 120:
		runtime.update(camera, vp, 540.0, 1.0)
	if runtime.selections != 1:
		_failures.append("static view selected %d times instead of once" % runtime.selections)

	var before := runtime.selections
	view = Projection(Transform3D(Basis.looking_at(Vector3.LEFT), camera).affine_inverse())
	vp = projection * view
	runtime.update(camera, vp, 540.0, 0.0)
	if runtime.selections != before + 1 or runtime.wanted_nodes() == initial:
		_failures.append("an in-place camera turn did not immediately update selection")

	before = runtime.selections
	runtime.update(camera, vp, 1080.0, 0.0)
	if runtime.selections != before + 1:
		_failures.append("viewport focal length change waited for the interval")
	before = runtime.selections
	runtime.max_sse = 32.0
	runtime.update(camera, vp, 1080.0, 0.0)
	if runtime.selections != before + 1:
		_failures.append("SSE change waited for the interval")
	before = runtime.selections
	runtime.budget_nodes = 1
	runtime.update(camera, vp, 1080.0, 0.0)
	if runtime.selections != before + 1 or runtime.wanted_count() > 1:
		_failures.append("node budget change waited for the interval")
	before = runtime.selections
	projection = Projection.create_perspective(35.0, 1.0, 0.1, 200.0)
	vp = projection * view
	runtime.update(camera, vp, 1080.0, 0.0)
	if runtime.selections != before + 1:
		_failures.append("projection change waited for the interval")

	# Sub-threshold translation still obeys the periodic movement check.
	before = runtime.selections
	camera.x += 0.1
	view = Projection(Transform3D(Basis.looking_at(Vector3.LEFT), camera).affine_inverse())
	vp = projection * view
	runtime.update(camera, vp, 1080.0, 0.001)
	if runtime.selections != before:
		_failures.append("small translation unexpectedly bypassed the interval")
	runtime.update(camera, vp, 1080.0, 61.0)
	if runtime.selections != before + 1:
		_failures.append("small translation was not selected when the interval elapsed")

	# An intentionally empty selection is a cached result, not an uninitialized one.
	camera = Vector3(0, 0, HALF * 4.0)
	view = Projection(Transform3D(Basis.looking_at(Vector3.BACK), camera).affine_inverse())
	vp = projection * view
	runtime.update(camera, vp, 1080.0, 0.016)
	before = runtime.selections
	for tick in 10:
		runtime.update(camera, vp, 1080.0, 61.0)
	if not runtime.wanted_nodes().is_empty() or runtime.selections != before:
		_failures.append("empty static view was not cached")

	# Zero interval remains an explicit every-tick selection override.
	runtime.select_interval = 0.0
	before = runtime.selections
	for tick in 3:
		runtime.update(camera, vp, 1080.0, 0.016)
	if runtime.selections != before + 3:
		_failures.append("zero selection interval no longer forces every-tick selection")
	before = runtime.selections
	runtime.configure(_pack, BUDGET)
	runtime.select_interval = 60.0
	runtime.update(camera, vp, 1080.0, 0.0)
	if runtime.selections != before + 1:
		_failures.append("configure did not invalidate the previous selection")
	runtime.shutdown()


## Caching a stationary camera must still retire the coarse parent after the
## selected children finish streaming, then stop selecting once converged.
func _test_fallback_retirement() -> void:
	var runtime := RuntimeScript.new()
	runtime.configure(_pack, 256)
	runtime.max_sse = 1e9
	runtime.select_interval = 0.08
	var camera := Vector3(0, 0, HALF * 4.0)
	_drive_runtime(runtime, camera, Vector3.FORWARD, 120)
	if not runtime.is_resident(_pack.root):
		_failures.append("coarse view did not load the root")
	runtime.max_sse = 0.01
	_drive_runtime(runtime, camera, Vector3.FORWARD, 400)
	if runtime.is_resident(_pack.root):
		_failures.append("stationary refinement kept its obsolete coarse root")
	for node in runtime.wanted_nodes():
		if not runtime.is_resident(node):
			_failures.append("stationary refinement did not converge")
	var before := runtime.selections
	_drive_runtime(runtime, camera, Vector3.FORWARD, 120)
	if runtime.selections != before:
		_failures.append("converged residency kept reselecting a stationary view")
	runtime.shutdown()


func _finish() -> void:
	if _failures.is_empty():
		print("stream_runtime_test: PASS")
		quit(0)
		return
	for line in _failures:
		printerr("  FAIL: %s" % line)
	printerr("stream_runtime_test: %d failure(s)" % _failures.size())
	quit(1)
