extends SceneTree
## Replay actual payload bytes, not just slot counts, across eviction and IO.
const Pack := preload("res://addons/gdgs/runtime/stream/gaussian_stream_pack.gd")

class ControlledRuntime:
	extends "res://addons/gdgs/runtime/stream/gaussian_stream_runtime.gd"
	var targets: Array[int] = []
	func _select_wanted(_camera: Vector3, _projection: Projection, _focal: float) -> Array[int]:
		return targets.duplicate()

func _initialize() -> void:
	var preserved := preload("res://addons/gdgs/runtime/nodes/gaussian_splat_node.gd").new()
	var compatibility_ok := "dynamic_active" in preserved and "dynamic_rise_speed" in preserved
	preserved.free()
	var selector: Variant = preload("res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd")
	var backend := preload("res://addons/gdgs/runtime/render/compute/gaussian_compute_backend.gd").new()
	compatibility_ok = compatibility_ok and selector.has_method("release_gpu") and backend.has_method("release_gpu")
	if not compatibility_ok:
		push_error("[stream-bytes] existing game dynamic or scene-change API missing")
		quit(1)
		return
	var pack := Pack.new()
	pack.node_count = 4
	pack.node_cap = 1
	pack.stride_bytes = 24
	pack.splat_count = PackedInt32Array([1, 1, 1, 1])
	pack.source_count = PackedInt32Array([1, 1, 1, 1])
	pack.parent = PackedInt32Array([-1, -1, -1, -1])
	pack.children.resize(32)
	pack.children.fill(-1)
	pack.centre_x.resize(4)
	pack.centre_y.resize(4)
	pack.centre_z.resize(4)
	pack.half_size = PackedFloat32Array([1, 1, 1, 1])
	pack._loaded = true
	var runtime := ControlledRuntime.new()
	runtime.configure(pack, 2)
	runtime.max_loads_per_frame = 0
	var gpu: Array[PackedByteArray] = []
	for i in runtime.capacity_slots():
		gpu.append(PackedByteArray())
	for node in [0, 1]:
		runtime._assign_slot(node, _payload(node))
	runtime._publish()
	var revision := _replay(runtime, -1, gpu)
	# IO for node 2 completes on the frame that node 0 leaves the view.
	# An upload at slot 2 must not later be copied from an uninitialized GPU
	# slot or left at the old address after the eviction compacts the arena.
	runtime.targets.assign([1, 2])
	runtime._inflight[2] = true
	runtime._completed.append({"node": 2, "bytes": _payload(2), "expected": 24})
	runtime.update(Vector3.ZERO, Projection(), 500.0, .016)
	revision = _replay(runtime, revision, gpu)
	var failures := _check_payloads(runtime, gpu)
	# Continue through 100 moving frontiers, including two completions followed
	# by eviction/compaction and a render consumer that skips several ticks.
	for tick in 100:
		var desired: Array[int] = [tick % 4, (tick + 1) % 4]
		runtime.targets = desired
		for node in desired:
			if not runtime.is_resident(node):
				runtime._inflight[node] = true
				runtime._completed.append({"node": node, "bytes": _payload(node), "expected": 24})
		runtime.update(Vector3(float(tick + 1), 0, 0), Projection(), 500.0, .016)
		if tick % 3 == 0 or tick == 99:
			revision = _replay(runtime, revision, gpu)
			failures += _check_payloads(runtime, gpu)
	runtime.shutdown()
	print("[stream-bytes] RESULT %d failures; revision=%d; 101 moving frontiers; game APIs preserved" % [failures, revision])
	quit(0 if failures == 0 else 1)

func _check_payloads(runtime: RefCounted, gpu: Array[PackedByteArray]) -> int:
	var failures := 0
	for slot in runtime.active_slots():
		var node: int = runtime._slot_node[slot]
		if gpu[slot] != runtime._cpu_payload[node]:
			push_error("[stream-bytes] slot %d node %d GPU replay does not match CPU payload" % [slot, node])
			failures += 1
	return failures

func _payload(node: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(24)
	bytes.fill(32 + node)
	return bytes

func _replay(runtime: RefCounted, revision: int, gpu: Array[PackedByteArray]) -> int:
	for snapshot in runtime.consume(revision):
		for move in snapshot["moves"]:
			gpu[int(move["dst"])] = gpu[int(move["src"])].duplicate()
		for upload in snapshot["uploads"]:
			gpu[int(upload["slot"])] = upload["bytes"].duplicate()
		revision = int(snapshot["revision"])
	return revision
