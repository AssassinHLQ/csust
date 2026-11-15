extends SceneTree
## GPU byte-level regression. Launch on an inactive desktop with --no-capture.
const Cache := preload("res://addons/gdgs/runtime/render/compute/gaussian_gpu_state_cache.gd")
var checks := 0
var failures: PackedStringArray = []
var done := false

func _initialize() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_run.call_deferred()

func _run() -> void:
	if RenderingServer.get_rendering_device() == null or not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	RenderingServer.call_on_render_thread(func():
		for stride in [24, 52]: _exercise(stride)
		done = true)
	while not done: await process_frame
	for failure in failures: printerr("FAIL: " + failure)
	print("stream move staging GPU: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _exercise(stride: int) -> void:
	var cache := Cache.new()
	var state = cache.get_or_create_render_state(Vector2i(16, 16))
	var canonical := _pattern(104, 7)
	var slot_bytes := 4 * stride
	cache.rebuild_gpu_state(state, 2, canonical.size(), 1, true, 13, 0, 1.0, PackedByteArray(), {
		"enabled": true, "capacity_splats": 8, "slot_splats": 4, "arena_slots": 2,
		"stride_words": stride / 4, "layout": 1 if stride == 24 else 0})
	var rd: RenderingDevice = state.context.device
	var arena: RID = state.descriptors["splats"].rid
	rd.buffer_update(arena, 0, canonical.size(), canonical)
	var declared_before: int = state.declared_bytes
	_check(not state.descriptors.has("stream_move_staging"), "rebuild reserves no unused staging")
	var left := _pattern(slot_bytes, 19)
	var right := _pattern(slot_bytes, 83)
	cache._apply_stream_snapshot(state, rd, arena, slot_bytes, {
		"uploads": [{"slot": 0, "bytes": left}, {"slot": 1, "bytes": right}]})
	_check(not state.descriptors.has("stream_move_staging"), "uploads need no staging")
	_check(state.declared_bytes == declared_before, "upload-only accounting stays unchanged")
	_check(rd.buffer_get_data(arena) == canonical + left + right, "initial uploads preserve canonical prefix")
	var replacement := _pattern(slot_bytes, 131)
	cache._apply_stream_snapshot(state, rd, arena, slot_bytes, {
		"moves": [{"src": 1, "dst": 0, "bytes": slot_bytes}],
		"uploads": [{"slot": 1, "bytes": replacement}]})
	_check(state.descriptors.has("stream_move_staging"), "first move creates staging")
	_check(state.declared_bytes == declared_before + slot_bytes, "staging counted exactly once")
	_check(rd.buffer_get_data(arena) == canonical + right + replacement, "move precedes same-snapshot upload byte for byte")
	var staging: RID = state.descriptors["stream_move_staging"].rid
	var allocation_count: int = state.context.deletion_queue.queue.size()
	cache._apply_stream_snapshot(state, rd, arena, slot_bytes, {
		"moves": [{"src": 0, "dst": 1, "bytes": stride * 2}]})
	_check(state.descriptors["stream_move_staging"].rid == staging, "later moves reuse staging")
	_check(state.context.deletion_queue.queue.size() == allocation_count, "later moves allocate no extra RIDs")
	_check(state.declared_bytes == declared_before + slot_bytes, "later moves do not double-count bytes")
	_check(rd.buffer_get_data(arena) == canonical + right + right.slice(0, stride * 2) + replacement.slice(stride * 2),
		"partial reverse move preserves both source and destination tail")
	cache.cleanup_all()
	_check(state.context == null and state.descriptors.is_empty(), "scene cleanup releases lazy storage with its render state")

func _pattern(size: int, seed_value: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(size)
	for i in size: result[i] = (seed_value + i * 37) % 256
	return result

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
