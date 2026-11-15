@tool
extends RefCounted
class_name GaussianStreamRuntime

## Residency manager for one GaussianStreamPack: decides which octree nodes are
## wanted, reads their payloads off disk on worker threads, packs them into a
## fixed-size GPU slot arena and publishes the resulting upload/move operations
## for the render thread.
##
## The arena has at most `budget_nodes + FALLBACK_SLACK` slots, bounded by the
## pack's node count. The registry sizes each slot for the largest stored node
## across the scene's packs. Eviction swaps the last slot into the freed one,
## keeping the active range dense without defragmenting. Projection uses the
## actual resident counts, so partial nodes never dispatch their slot padding.
##
## Thread contract:
##   main thread   - update(), consume(), full_snapshot(), stats
##   worker thread - _io_read() only; touches immutable pack fields and the
##                   mutex-guarded completion queue
##   render thread - consume() results are applied to the GPU by the state cache

const Lod := preload("res://addons/gdgs/runtime/stream/gaussian_stream_lod.gd")

## Extra slots beyond the node budget, used to hold a coarse parent while its
## children stream in. Without them refining a node would blink a hole in the
## world for the frames the children take to arrive.
const FALLBACK_SLACK := 16
## Snapshots retained for late consumers (a second render state). Older than
## this and the consumer is handed a full re-upload instead.
const SNAPSHOT_WINDOW := 64
## Words per slot in the published directory:
##   0 splat count   1 instance id
##   2..4 node centre (float bits)   5 node half-size (float bits)
##   6 absolute physical slot + 1 (0 uses legacy slot-major addressing)
##   7 reserved. Shared instances can address one payload from several draws.
## The q24 decoder rebuilds positions from the centre and half-size, so this has
## to travel with the residency, not just the pack.
const SLOT_INFO_WORDS := 8

var pack: GaussianStreamPack = null
## Resident node budget. The splat budget is this times pack.node_cap.
var budget_nodes: int = 96
## Screen-space error threshold in pixels; above it the tree refines.
var max_sse: float = 16.0
var max_loads_per_frame: int = 4
var max_inflight: int = 4
## Seconds between small-translation/residency rechecks. Large moves, turns,
## projection and policy changes select immediately. A converged static view
## reuses its selection; zero explicitly requests selection on every tick.
var select_interval: float = 0.08
## GPU instance index this source's splats are drawn with.
var instance_id: int = 0
## First arena slot this source owns. The registry assigns it so several stream
## sources can share one GPU arena; all slot indices in a snapshot are local to
## this base and the state cache adds it when addressing the buffer.
var slot_base: int = 0
## Draw-directory base can differ from payload base when instances share data.
var directory_base: int = 0

var _slot_node := PackedInt32Array()
var _node_slot: Dictionary = {}
var _cpu_payload: Dictionary = {}
var _active_slots := 0
var _resident_splats := 0
var _capacity_slots := 0

var _inflight: Dictionary = {}
var _task_ids: Dictionary = {}
var _completed: Array = []
var _io_mutex := Mutex.new()
var _load_queue: Array[int] = []
var _wanted: Array[int] = []
var _keep: Dictionary = {}
## Nodes whose payload read failed. Without this a corrupt or truncated pack is
## re-queued on every selection and hammers the disk forever.
var _failed: Dictionary = {}

var _ops_mutex := Mutex.new()
var _snapshots: Array = []
var _last_full: Dictionary = {}
var _revision := 0
var _pending_uploads: Array = []
var _pending_moves: Array = []
var _ops_dirty := false

var _select_timer := 0.0
var _last_camera := Vector3(INF, INF, INF)
var _last_view_projection := Projection()
var _last_focal_pixels := 0.0
var _last_max_sse := 0.0
var _last_budget_nodes := 0
var _has_selection := false
var _residency_changed := false
var _running := false
## Reused 4-byte scratch for float -> uint bit conversion, keeping the per-frame
## slot directory build allocation-free.
var _bits_scratch := PackedByteArray()

# --- statistics -------------------------------------------------------------
var selections := 0
var loads_completed := 0
var loaded_splats := 0
var evictions := 0
var moves := 0
var budget_coarsen_events := 0
var io_failures := 0
## Distinct leaf nodes ever resident. Leaves partition the source cloud, so the
## sum of their source_count is the number of source splats actually streamed.
var _loaded_leaves: Dictionary = {}
var covered_source_splats := 0
var peak_resident_splats := 0
var peak_active_slots := 0


func configure(source_pack: GaussianStreamPack, node_budget: int) -> void:
	shutdown()
	pack = source_pack
	budget_nodes = maxi(node_budget, 1)
	_capacity_slots = mini(budget_nodes + FALLBACK_SLACK, pack.node_count)
	_slot_node.resize(_capacity_slots)
	_slot_node.fill(-1)
	_active_slots = 0
	_resident_splats = 0
	_node_slot.clear()
	_cpu_payload.clear()
	_load_queue.clear()
	_wanted.clear()
	_keep.clear()
	_failed.clear()
	_pending_uploads.clear()
	_pending_moves.clear()
	_last_full.clear()
	_ops_dirty = true
	_revision = 0
	_running = true
	_select_timer = 0.0
	_last_camera = Vector3(INF, INF, INF)
	_has_selection = false
	_residency_changed = false


func is_running() -> bool:
	return _running and pack != null and pack.is_loaded()


func capacity_slots() -> int:
	return _capacity_slots


func directory_slots() -> int:
	return _capacity_slots


func active_slots() -> int:
	return _active_slots


func resident_splats() -> int:
	return _resident_splats


func resident_bytes() -> int:
	return _resident_splats * (pack.stride_bytes if pack != null else 0)


func inflight_count() -> int:
	return _inflight.size()


## Whether a node currently occupies an arena slot. A coverage sweep uses this to
## decide when the camera has streamed the region it is aiming at.
func is_resident(node: int) -> bool:
	return _node_slot.has(node)


## Whether a leaf has ever been resident, i.e. its share of the source cloud has
## been streamed at least once. Unlike is_resident this never goes back to false.
func has_loaded_leaf(node: int) -> bool:
	return _loaded_leaves.has(node)


func wanted_count() -> int:
	return _wanted.size()


## The current selection, nearest first. Lets a viewer wait until the picture
## has converged before it screenshots or reports.
func wanted_nodes() -> Array[int]:
	return _wanted.duplicate()


## Resident nodes as [node_index, splat_count] pairs, in slot order. Diagnostics
## and tests use this to correlate what is on the GPU with where the camera is.
func resident_nodes() -> Array:
	var out: Array = []
	for slot in _active_slots:
		var node := _slot_node[slot]
		if node >= 0:
			out.append([node, pack.splat_count[node]])
	return out


## Main-thread tick. `camera_position` is in the pack's coordinate space.
func update(camera_position: Vector3, view_projection: Projection, focal_pixels: float, delta: float) -> void:
	if not is_running():
		return
	_select_timer -= delta
	var moved := _last_camera.distance_to(camera_position) > 0.25
	# Translation only changes the final column of projection * view. Compare
	# the linear columns separately so turns/zoom never wait out the interval.
	var view_changed := view_projection.x != _last_view_projection.x \
		or view_projection.y != _last_view_projection.y \
		or view_projection.z != _last_view_projection.z \
		or focal_pixels != _last_focal_pixels
	var policy_changed := max_sse != _last_max_sse or budget_nodes != _last_budget_nodes
	var camera_changed := camera_position != _last_camera or view_projection != _last_view_projection
	var due := _select_timer <= 0.0 \
		and (camera_changed or _residency_changed or select_interval <= 0.0)
	if not _has_selection or moved or view_changed or policy_changed or due:
		_select_timer = select_interval
		_last_camera = camera_position
		_last_view_projection = view_projection
		_last_focal_pixels = focal_pixels
		_last_max_sse = max_sse
		_last_budget_nodes = budget_nodes
		_has_selection = true
		_residency_changed = false
		_reselect(camera_position, view_projection, focal_pixels)

	# Evict/compact previously published slots before assigning newly completed
	# IO. GPU snapshots replay moves before uploads: moving a slot uploaded in
	# this same snapshot would copy uninitialized bytes and leave that upload at
	# its pre-compaction address. The CPU directory would then decode another
	# node's bytes, producing displaced/oversized splats during camera movement.
	_drain_completed()
	_start_loads()
	_publish()


func _reselect(camera_position: Vector3, view_projection: Projection, focal_pixels: float) -> void:
	var before := _wanted.size()
	_wanted = _select_wanted(camera_position, view_projection, focal_pixels)
	selections += 1
	if _wanted.size() < before and before > budget_nodes:
		budget_coarsen_events += 1

	var wanted_set: Dictionary = {}
	for node in _wanted:
		wanted_set[node] = true

	# A resident ancestor stays until the wanted descendants that replace it are
	# themselves resident, so refinement never exposes an empty region.
	var fallback: Dictionary = {}
	for node in _wanted:
		if _node_slot.has(node):
			continue
		var ancestor := pack.parent[node]
		while ancestor >= 0:
			if _node_slot.has(ancestor):
				fallback[ancestor] = true
				break
			ancestor = pack.parent[ancestor]

	_keep = wanted_set.duplicate()
	for node in fallback:
		if _keep.size() >= _capacity_slots:
			break
		_keep[node] = true

	var to_evict: Array[int] = []
	for slot in _active_slots:
		var node := _slot_node[slot]
		if node >= 0 and not _keep.has(node):
			to_evict.append(node)
	if not to_evict.is_empty():
		_evict(to_evict)

	_load_queue.clear()
	for node in _wanted:
		if not _node_slot.has(node) and not _inflight.has(node) and not _failed.has(node):
			_load_queue.append(node)


## Override the frontier while retaining the bounded IO/residency machinery.
func _select_wanted(camera_position: Vector3, view_projection: Projection, focal_pixels: float) -> Array[int]:
	return Lod.select(pack, camera_position, view_projection, focal_pixels, max_sse, budget_nodes)


## Rebinding a source must also republish its full snapshot. Otherwise a GPU
## rebuild after removing an earlier source can replay the old arena offsets.
func set_gpu_binding(index: int, base: int, draw_base: int = -1) -> void:
	var next_directory := base if draw_base < 0 else draw_base
	if instance_id == index and slot_base == base and directory_base == next_directory:
		return
	instance_id = index
	slot_base = base
	directory_base = next_directory
	_ops_dirty = true
	_publish()


func _evict(nodes: Array[int]) -> void:
	for node in nodes:
		if not _node_slot.has(node):
			continue
		var slot: int = _node_slot[node]
		var last := _active_slots - 1
		if slot != last:
			var moved_node := _slot_node[last]
			_pending_moves.append({
				"dst": slot,
				"src": last,
				"bytes": pack.splat_count[moved_node] * pack.stride_bytes,
			})
			_slot_node[slot] = moved_node
			_node_slot[moved_node] = slot
			moves += 1
		_slot_node[last] = -1
		_node_slot.erase(node)
		_cpu_payload.erase(node)
		_active_slots -= 1
		_resident_splats -= pack.splat_count[node]
		evictions += 1
		_ops_dirty = true


func _start_loads() -> void:
	var started := 0
	while started < max_loads_per_frame and not _load_queue.is_empty():
		if _inflight.size() >= max_inflight:
			break
		if _active_slots + _inflight.size() >= _capacity_slots:
			break
		var node: int = _load_queue.pop_front()
		if _node_slot.has(node) or _inflight.has(node):
			continue
		_inflight[node] = true
		var task_id := WorkerThreadPool.add_task(
			Callable(self, "_io_read").bind(node), false, "gdgs-stream-load")
		_task_ids[node] = task_id
		started += 1


## Worker thread. Only immutable pack fields and the completion queue are
## touched, so this never races the main thread's residency bookkeeping.
func _io_read(node: int) -> void:
	var expected := pack.splat_count[node] * pack.stride_bytes
	var bytes := PackedByteArray()
	var file := FileAccess.open(pack.nodes_bin_path, FileAccess.READ)
	if file != null:
		file.seek(pack.byte_offset[node])
		bytes = file.get_buffer(expected)
		file.close()
	_io_mutex.lock()
	_completed.append({"node": node, "bytes": bytes, "expected": expected})
	_io_mutex.unlock()


func _drain_completed() -> void:
	_io_mutex.lock()
	var done := _completed.duplicate()
	_completed.clear()
	_io_mutex.unlock()
	if done.is_empty():
		return
	for item in done:
		var node: int = item["node"]
		_inflight.erase(node)
		_task_ids.erase(node)
		var bytes: PackedByteArray = item["bytes"]
		if bytes.size() != int(item["expected"]):
			io_failures += 1
			_failed[node] = true
			push_warning("[gdgs] stream: short read for node %d (%d of %d bytes)"
				% [node, bytes.size(), int(item["expected"])])
			continue
		if _node_slot.has(node) or _active_slots >= _capacity_slots:
			continue
		_assign_slot(node, bytes)


func _assign_slot(node: int, bytes: PackedByteArray) -> void:
	var slot := _active_slots
	_slot_node[slot] = node
	_node_slot[node] = slot
	_cpu_payload[node] = bytes
	_active_slots += 1
	var count := pack.splat_count[node]
	_resident_splats += count
	_pending_uploads.append({"slot": slot, "bytes": bytes, "count": count, "instance": instance_id})
	_ops_dirty = true
	# Reselect at the next interval even for a motionless camera, so a fallback
	# ancestor is retired once its selected descendants have become resident.
	_residency_changed = true

	loads_completed += 1
	loaded_splats += count
	peak_active_slots = maxi(peak_active_slots, _active_slots)
	peak_resident_splats = maxi(peak_resident_splats, _resident_splats)
	if pack.is_leaf(node) and not _loaded_leaves.has(node):
		_loaded_leaves[node] = true
		covered_source_splats += pack.source_count[node]


func _publish() -> void:
	if not _ops_dirty:
		return
	_ops_dirty = false
	_revision += 1
	var slot_info := _build_slot_info()
	var snapshot := {
		"revision": _revision,
		"moves": _pending_moves.duplicate(),
		"uploads": _pending_uploads.duplicate(),
		"slot_info": slot_info,
		"active_slots": _active_slots,
		"resident_splats": _resident_splats,
		"slot_base": slot_base,
		"directory_base": directory_base,
		"full": false,
	}
	# A complete mirror of the residency, rebuilt on the main thread so the
	# render thread never has to read mutable bookkeeping to recover a state
	# that fell out of the snapshot window.
	var uploads: Array = []
	for slot in _active_slots:
		var node := _slot_node[slot]
		if node < 0 or not _cpu_payload.has(node):
			continue
		uploads.append({
			"slot": slot,
			"bytes": _cpu_payload[node],
			"count": pack.splat_count[node],
			"instance": instance_id,
		})
	var full := {
		"revision": _revision,
		"moves": [],
		"uploads": uploads,
		"slot_info": slot_info,
		"active_slots": _active_slots,
		"resident_splats": _resident_splats,
		"slot_base": slot_base,
		"directory_base": directory_base,
		"full": true,
	}
	_pending_moves.clear()
	_pending_uploads.clear()
	_ops_mutex.lock()
	_snapshots.append(snapshot)
	while _snapshots.size() > SNAPSHOT_WINDOW:
		_snapshots.pop_front()
	_last_full = full
	_ops_mutex.unlock()


func _build_slot_info() -> PackedInt32Array:
	var info := PackedInt32Array()
	info.resize(_capacity_slots * SLOT_INFO_WORDS)
	info.fill(0)
	for slot in _active_slots:
		var node := _slot_node[slot]
		if node < 0:
			continue
		var base := slot * SLOT_INFO_WORDS
		info[base] = pack.splat_count[node]
		info[base + 1] = instance_id
		info[base + 2] = _float_bits(pack.centre_x[node])
		info[base + 3] = _float_bits(pack.centre_y[node])
		info[base + 4] = _float_bits(pack.centre_z[node])
		info[base + 5] = _float_bits(pack.half_size[node])
		info[base + 6] = slot_base + slot + 1
	return info


## Bit pattern of a float, so it can ride in the integer slot directory.
func _float_bits(value: float) -> int:
	_bits_scratch.resize(4)
	_bits_scratch.encode_float(0, value)
	return _bits_scratch.decode_u32(0)


## Render-thread side: every snapshot newer than `from_revision`. A consumer
## that fell outside the retained window gets one full re-upload instead.
func consume(from_revision: int) -> Array:
	_ops_mutex.lock()
	var out: Array = []
	if from_revision < _revision:
		var oldest: int = _revision
		if not _snapshots.is_empty():
			oldest = int(_snapshots[0]["revision"])
		if from_revision < oldest - 1:
			if _last_full.has("revision"):
				out.append(_last_full)
		else:
			for snapshot in _snapshots:
				if int(snapshot["revision"]) > from_revision:
					out.append(snapshot)
	_ops_mutex.unlock()
	return out


func latest_revision() -> int:
	return _revision


## A complete upload of the current residency, for a freshly built render state.
func full_snapshot() -> Dictionary:
	_ops_mutex.lock()
	var snapshot := _last_full.duplicate()
	_ops_mutex.unlock()
	if snapshot.is_empty():
		return {
			"revision": 0, "moves": [], "uploads": [],
			"slot_info": PackedInt32Array(), "active_slots": 0,
			"resident_splats": 0, "slot_base": slot_base,
			"directory_base": directory_base, "full": true,
		}
	return snapshot


## Blocks until every in-flight read finishes, then drops the CPU mirror. Call
## from the main thread before releasing the runtime.
func shutdown() -> void:
	_running = false
	for node in _task_ids.keys():
		WorkerThreadPool.wait_for_task_completion(int(_task_ids[node]))
	_task_ids.clear()
	_io_mutex.lock()
	_completed.clear()
	_io_mutex.unlock()
	_inflight.clear()
	_cpu_payload.clear()
	_load_queue.clear()
	_ops_mutex.lock()
	_snapshots.clear()
	_ops_mutex.unlock()


func describe() -> String:
	return "stream: %d/%d slots, %d resident splats (%.1f MB), %d wanted, %d in flight, loads=%d evictions=%d moves=%d" % [
		_active_slots, _capacity_slots, _resident_splats, resident_bytes() / 1048576.0,
		_wanted.size(), _inflight.size(), loads_completed, evictions, moves
	]
