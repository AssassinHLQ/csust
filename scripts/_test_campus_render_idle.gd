extends SceneTree

## CPU-only regression for campus rendering under shared GPU load. The device
## records commands without allocating GPU resources or opening a window.
## godot --headless --path . --script scripts/_test_campus_render_idle.gd -- --no-capture

const Rasterizer := preload("res://addons/ggs_campus/gaussian_splatting_rasterizer.gd")
const RenderContext := preload("res://addons/ggs_campus/render_context.gd")

class ShaderCompilerSpy:
	extends RefCounted
	var calls := 0
	var fail_compile := false
	var last_source := ""

	func shader_compile_spirv_from_source(source: RDShaderSource) -> RDShaderSPIRV:
		calls += 1
		last_source = source.source_compute
		var spirv := RDShaderSPIRV.new()
		if fail_compile:
			spirv.compile_error_compute = "synthetic compiler failure"
		return spirv

class DeviceSpy:
	extends RefCounted
	var updates: Array = []
	var clears := 0
	var stamps := 0
	var upload_delay_usec := 0

	func buffer_update(_rid, offset, size, bytes) -> void:
		if upload_delay_usec > 0:
			OS.delay_usec(upload_delay_usec)
		updates.append([offset, size, bytes])

	func buffer_clear(_rid, _offset, _size) -> void:
		pass

	func texture_clear(_rid, _color, _mip, _mips, _layer, _layers) -> void:
		clears += 1

	func capture_timestamp(_label) -> void:
		stamps += 1

class ContextSpy:
	extends RefCounted
	var device := DeviceSpy.new()
	var dispatches := 0

	func compute_list_begin() -> int:
		return 1

	func compute_list_end() -> void:
		pass

	func dispatch(_ctx, _list, _push = PackedByteArray(), _overwrites = [],
			_indirect = RID(), _offset = 0) -> void:
		dispatches += 1

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	var raster := Rasterizer.new({"size": 100}, Vector2i(1600, 900), Texture2DRD.new(), camera)
	var context := ContextSpy.new()
	raster.context = context
	raster.camera = camera
	raster.texture_size = Vector2i(1600, 900)
	raster.point_cloud = {"size": 100}
	for name_ in ["uniforms", "histogram", "tile_bounds", "grid_dimensions"]:
		raster.descriptors[name_] = {"rid": RID()}
	for name_ in ["gsplat_projection", "radix_sort_upsweep", "radix_sort_spine",
			"radix_sort_downsweep", "gsplat_boundaries", "gsplat_render"]:
		raster.pipelines[name_] = context.dispatch
	raster.intro_end_ms = 0
	raster.update_camera_matrices()
	raster.rasterize()
	var first := context.dispatches
	_check(first == 15, "first frame dispatches projection, four sort passes and raster")
	_check(context.device.clears == 0, "fully overwritten target needs no per-frame clear")
	_check(context.device.stamps == 0, "normal rendering issues no profiling queries")
	_check(_has_dispatch_reset(context.device.updates), "indirect dispatch is reset before projection")

	for tick in 1000:
		raster.update_camera_matrices()
		raster.rasterize()
	_check(context.dispatches == first, "1000 stationary ticks reuse the rendered frame")

	# A second unchanged main-thread tick used to erase _camera_changed before
	# the render thread could consume the first tick's pending move.
	camera.position.x += 1.0
	raster.update_camera_matrices()
	raster.update_camera_matrices()
	_check(not raster._camera_changed, "fixture reproduces two camera ticks before rendering")
	raster.rasterize()
	_check(context.dispatches == first * 2, "pending camera move renders despite a later unchanged tick")

	var before := context.dispatches
	for change in ["model", "covariance", "cap", "reference", "heatmap", "projection", "size"]:
		match change:
			"model": raster.model_scale[0] = 2.0
			"covariance": raster.cov_scale[0] = 0.5
			"cap": raster.cov_limit[0] = 0.01
			"reference": raster.cov_limit[1] = 0.002
			"heatmap": raster.should_enable_heatmap[0] = true
			"projection":
				camera.fov += 10.0
				raster.update_camera_matrices()
			"size": raster.texture_size = Vector2i(1280, 720)
		raster.rasterize()
		_check(context.dispatches == before + first, change + " change invalidates cached output")
		before = context.dispatches
		raster.rasterize()
		_check(context.dispatches == before, change + " result becomes reusable after rendering")

	raster.idle_skip = false
	raster.profile_timestamps = true
	raster.rasterize()
	_check(context.dispatches == before + first, "idle-skip override forces rendering")
	_check(context.device.stamps == 5, "profiling remains available when explicitly enabled")
	_check(_dispatch_reset_count(context.device.updates) == context.dispatches / first,
		"every dispatched frame resets historical workgroup maxima")
	raster.idle_skip = true
	raster.intro_end_ms = Time.get_ticks_msec() + 1000
	_check(not raster._can_reuse_last_frame(), "intro guard prevents premature reuse")
	_test_upload_budget(raster, context.device)
	_test_shader_cache()
	raster.context = null
	camera.free()
	print("campus_render_idle: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _test_upload_budget(raster, device: DeviceSpy) -> void:
	var path := "res://_log/campus_upload_budget_test.bin"
	DirAccess.make_dir_recursive_absolute("res://_log")
	var bytes := PackedByteArray()
	bytes.resize(8192 * 240)
	for record in 8192:
		bytes.encode_u32(record * 240, record)
		bytes.encode_float(record * 240 + 12, 0.125)
		bytes.encode_u32(record * 240 + 236, record ^ 0x13579)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	raster.bin_path = path
	_check(raster.upload_budget_ms == 1.0, "each layer defaults to a one-ms soft upload budget")
	raster.upload_budget_ms = 4.0
	raster._begin_bin_load(8192)
	_check(not raster._rendered_once, "new payload invalidates a previously rendered frame")
	_check(raster._upload_chunk == 128 * 1024, "new load starts with a bounded staging chunk")
	device.updates.clear()
	device.upload_delay_usec = 2500
	var pending: bool = raster._pump_bin(device, RID())
	_check(pending and raster._bin_uploaded < bytes.size(),
		"several individually fast uploads must not exhaust the payload in one tick")
	_check(device.updates.size() <= 2, "cumulative four-ms budget stops after at most two 2.5-ms uploads")
	device.upload_delay_usec = 0
	var ticks := 0
	while raster._bin_loading and ticks < 100:
		raster._pump_bin(device, RID())
		ticks += 1
	_check(not raster._bin_loading and raster.num_splats_loaded[0] == 8192,
		"bounded loading still uploads every record")
	_check(raster._bin_file == null, "completed loading closes the input file")
	var uploaded := 0
	var intact := true
	for update in device.updates:
		intact = intact and update[0] == uploaded and update[2] == bytes.slice(uploaded, uploaded + update[1])
		uploaded += update[1]
	_check(intact and uploaded == bytes.size(), "every uploaded byte is contiguous and matches the input")
	_check(raster._splat_time_max == 0.125, "time sampling stays aligned across partial records")
	DirAccess.remove_absolute(path)


func _test_shader_cache() -> void:
	var device := ShaderCompilerSpy.new()
	var other_device := ShaderCompilerSpy.new()
	var first := RenderContext._compile_shader_once(device, "projection", "source A")
	var cached := RenderContext._compile_shader_once(device, "projection", "source A")
	_check(first == cached and device.calls == 1,
		"rebuilding a context reuses compiled shader bytes on the same device")
	var edited := RenderContext._compile_shader_once(device, "projection", "source B")
	_check(edited != first and device.calls == 2 and device.last_source == "source B",
		"source edits invalidate the compiled shader")
	RenderContext._compile_shader_once(other_device, "projection", "source B")
	_check(other_device.calls == 1, "different rendering devices compile independently")
	RenderContext._compile_shader_once(device, "render", "source B")
	_check(device.calls == 3, "different shader paths maintain independent revisions")
	device.fail_compile = true
	for attempt in 2:
		RenderContext._compile_shader_once(device, "projection", "broken")
	_check(device.calls == 5, "failed compilation is retried rather than cached as success")
	device.fail_compile = false
	var recovered := RenderContext._compile_shader_once(device, "projection", "source B")
	_check(recovered == edited and device.calls == 5,
		"a failed source edit preserves the last successfully compiled revision")


func _dispatch_reset_count(updates: Array) -> int:
	var count := 0
	for update in updates:
		if update[1] == 24:
			var dims: PackedInt32Array = update[2].to_int32_array()
			if dims == PackedInt32Array([1, 1, 1, 1, 1, 1]):
				count += 1
	return count


func _has_dispatch_reset(updates: Array) -> bool:
	return _dispatch_reset_count(updates) > 0


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
		print("PASS: " + message)
	else:
		_fail += 1
		printerr("FAIL: " + message)
