extends SceneTree
## GPU regression. Run only on an inactive Windows desktop via the private
## desktop runner, never as an ordinary visible project. Source path overrides
## allow the same test to check full coarse and fine campus data.

const Raster := preload("res://addons/ggs_campus/gaussian_splatting_rasterizer.gd")
const Ply := preload("res://addons/ggs_campus/ply_file.gd")
const Context := preload("res://addons/ggs_campus/render_context.gd")

var camera: Camera3D
var rasters: Array = []
var done := false
var passes := 0
var failures := 0
var before_images: Array = []
var before_signatures: Array = []
var repeat_errors: Array = []
var sample_signature := 0
var sample_pairs := 0
var before_buffers := 0
var shared_buffers := 0
var base_buffers := 0
var base_textures := 0
var private_textures := 0
var shared_textures := 0
var sources := ["res://campus_sample.bin", "res://campus_sample.bin"]
var counts := [32768, 8192]
var dims := Vector2i(800, 450)
var capacity := 32768


func _initialize() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.max_fps = 165
	_run.call_deferred()


func _run() -> void:
	if RenderingServer.get_rendering_device() == null:
		printerr("GPU workspace regression requires the inactive-desktop GPU runner.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--coarse="):
			sources[0] = arg.trim_prefix("--coarse=")
			counts[0] = FileAccess.open(sources[0], FileAccess.READ).get_length() / 240
		if arg.begins_with("--fine="):
			sources[1] = arg.trim_prefix("--fine=")
			counts[1] = FileAccess.open(sources[1], FileAccess.READ).get_length() / 240
		if arg == "--full-resolution":
			dims = Vector2i(1920, 1000)
	capacity = maxi(counts[0], counts[1])
	if capacity > 32768:
		capacity = maxi(capacity, 1608101)
	camera = Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.position = Vector3(-20.0, 4.5, -210.0)
	camera.look_at(Vector3(-8.0, 7.0, -252.0))
	var initial_transform := camera.transform
	await _on_render(_test_boundaries)
	await _on_render(_test_transparent_corner)
	for tick in 5:
		await process_frame
	await _on_render(func():
		base_buffers = _buffers()
		base_textures = _textures())
	for shared in [false, true]:
		camera.transform = initial_transform
		for i in 2:
			rasters.append(_new_raster(i, shared))
		for tick in 3000:
			await _draw_layers()
			if rasters[0].is_loaded and rasters[1].is_loaded:
				break
		_check(rasters[0].is_loaded and rasters[1].is_loaded, "both layers finish upload")
		await _draw_layers()
		await _on_render(func():
			if shared:
				shared_buffers = _buffers() - base_buffers
				shared_textures = _textures() - base_textures
			else:
				before_buffers = _buffers() - base_buffers
				private_textures = _textures() - base_textures)
		if shared:
			_check(rasters[0].descriptors["sort_keys"].rid == rasters[1].descriptors["sort_keys"].rid,
				"unequal layers share sort allocation")
			_check(rasters[0].descriptors["splats"].rid != rasters[1].descriptors["splats"].rid,
				"source records stay independent")
		for view in 3:
			camera.rotation.y += 0.025 if view > 0 else 0.0
			await _draw_layers()
			for i in 2:
				var pixels := await _snapshot(i, true)
				_check(pixels.count(0) < pixels.size(), "campus produces nontransparent pixels")
				if not shared:
					before_images.append(pixels)
					before_signatures.append(sample_signature)
					var envelope := {"max": 0.0, "rms": 0.0, "alpha_max": 0.0}
					for repeat in 3:
						rasters[i]._rendered_once = false
						await _draw_layers()
						var error := _image_error(pixels, await _snapshot(i))
						for key in envelope:
							envelope[key] = maxf(envelope[key], error[key])
					repeat_errors.append(envelope)
				else:
					var index := view * 2 + i
					_check(before_signatures[index] == sample_signature and sample_pairs > 0,
						"identical projected tile/point/depth set, view %d layer %d" % [view, i])
					var error := _image_error(before_images[index], pixels)
					# Equal 16-bit depth keys already blend in nondeterministic atomic
					# order in private mode. Compare against a same-mode repeat too.
					print("WORKSPACE_IMAGE_ERROR: ", JSON.stringify({"shared": error, "private_repeat": repeat_errors[index]}))
					_check(error["alpha_max"] <= 1.0 / 255.0 + 0.000001 and error["rms"] <= maxf(0.0005, repeat_errors[index]["rms"] * 3.0),
						"coverage and color stay within private repeat variation, view %d layer %d" % [view, i])
		if shared:
			var cached := await _snapshot(0)
			for tick in 5:
				await _draw_layers()
			_check(cached == await _snapshot(0), "idle texture survives other layer's scratch writes")
			# Force another writer, then verify picking rebuilds the correct scratch.
			rasters[1]._rendered_once = false
			await _draw_layers()
			await _on_render(func():
				rasters[0].get_splat_position(dims / 2)
				_check(rasters[0]._workspace.last_writer_id == rasters[0].context.get_instance_id(), "picking restores its own layer's scratch"))
			var workspace_weak: WeakRef = weakref(rasters[1]._workspace)
			await _on_render(func():
				var ctx = rasters[0].context
				rasters[0].release_all_now()
				ctx.free())
			_check(workspace_weak.get_ref() != null, "releasing one layer retains the other layer's workspace")
			var replacement = _new_raster(0, true)
			var old = rasters[0]
			rasters[0] = replacement
			old = null
			for tick in 3000:
				await _draw_layers()
				if replacement.is_loaded:
					break
			_check(replacement._workspace == rasters[1]._workspace, "window replacement reuses resident scratch")
			await _release_all()
			_check(workspace_weak.get_ref() == null, "last context frees scratch; registry does not retain it")
		else:
			await _release_all()
	for tick in 5:
		await process_frame
	print("WORKSPACE_RESULT: ", JSON.stringify({"counts": counts, "dims": [dims.x, dims.y],
		"capacity": capacity, "private_buffer_bytes": before_buffers, "shared_buffer_bytes": shared_buffers,
		"private_texture_bytes": private_textures, "shared_texture_bytes": shared_textures,
		"saved_mib": (before_buffers - shared_buffers) / 1048576.0, "passes": passes, "failures": failures}))
	camera.free()
	quit(0 if failures == 0 else 1)


func _new_raster(index: int, shared: bool):
	var cloud := Ply.new()
	cloud.size = counts[index]
	var raster = Raster.new(cloud, dims, Texture2DRD.new(), camera)
	raster.bin_path = sources[index]
	raster.cov_scale[0] = 0.1
	raster.cov_limit[0] = 0.09
	raster.cov_limit[1] = 0.036
	if shared:
		raster.workspace_group = "gpu-regression"
		raster.workspace_points = capacity
	return raster


func _test_boundaries() -> void:
	var ctx = Context.create(RenderingServer.get_rendering_device())
	var shader: RID = ctx.load_shader("res://addons/ggs_campus/shaders/gsplat_boundaries.glsl")
	var histogram = ctx.create_storage_buffer(4)
	var keys = ctx.create_storage_buffer(257 * 4)
	var bounds = ctx.create_storage_buffer(64 * 8)
	var set_: RID = ctx.create_descriptor_set([histogram, keys, bounds], shader)
	var pipeline: Callable = ctx.create_pipeline([2, 1, 1], [set_], shader)
	var crossing := PackedInt32Array()
	crossing.resize(257)
	crossing.fill(3 << 16)
	crossing[256] = 6 << 16
	var fixtures := [
		[PackedInt32Array(), {}],
		[PackedInt32Array([5 << 16]), {5: Vector2i(0, 1)}],
		[PackedInt32Array([5 << 16, 8 << 16, 8 << 16, 8 << 16, 17 << 16, 17 << 16]),
			{5: Vector2i(0, 1), 8: Vector2i(1, 4), 17: Vector2i(4, 6)}],
		[crossing, {3: Vector2i(0, 256), 6: Vector2i(256, 257)}]]
	for index in fixtures.size():
		var fixture: Array = fixtures[index]
		var input: PackedInt32Array = fixture[0]
		ctx.device.buffer_update(histogram.rid, 0, 4, PackedInt32Array([input.size()]).to_byte_array())
		ctx.device.buffer_clear(bounds.rid, 0, 64 * 8)
		if not input.is_empty():
			ctx.device.buffer_update(keys.rid, 0, input.size() * 4, input.to_byte_array())
		var list_: int = ctx.compute_list_begin()
		pipeline.call(ctx, list_)
		ctx.compute_list_end()
		var output: PackedInt32Array = ctx.device.buffer_get_data(bounds.rid).to_int32_array()
		var correct := true
		for tile in 64:
			var expected: Vector2i = fixture[1].get(tile, Vector2i.ZERO)
			correct = correct and output[tile * 2] == expected.x and output[tile * 2 + 1] == expected.y
		_check(correct, "tile bounds fixture %d handles sparse/exclusive/partial groups" % index)
	ctx.free()


func _test_transparent_corner() -> void:
	var ctx = Context.create(RenderingServer.get_rendering_device())
	var shader: RID = ctx.load_shader("res://addons/ggs_campus/shaders/gsplat_render.glsl")
	var records := PackedByteArray()
	records.resize(257 * 48)
	var indices := PackedInt32Array()
	indices.resize(257)
	for i in 257:
		indices[i] = i
		var off := i * 48
		records.encode_float(off + 16, 0.023 if i < 256 else 1.0)
		records.encode_float(off + 24, 0.023 if i < 256 else 1.0)
		records.encode_float(off + 32, 1.0 if i < 256 else 0.0)
		records.encode_float(off + 36, 0.0 if i < 256 else 1.0)
		records.encode_float(off + 44, 1.0)
	records.encode_float(256 * 48, 15.0)
	records.encode_float(256 * 48 + 4, 15.0)
	var culled = ctx.create_storage_buffer(records.size(), records)
	var sorted = ctx.create_storage_buffer(indices.size() * 4, indices.to_byte_array())
	var bounds = ctx.create_storage_buffer(8, PackedInt32Array([0, 257]).to_byte_array())
	var picked = ctx.create_storage_buffer(16)
	var target = ctx.create_texture(Vector2i(16, 16), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
	var set_: RID = ctx.create_descriptor_set([culled, sorted, bounds, picked, target], shader)
	var pipeline: Callable = ctx.create_pipeline([1, 1, 1], [set_], shader)
	var list_: int = ctx.compute_list_begin()
	pipeline.call(ctx, list_, Context.create_push_constant([0.0, -1]))
	ctx.compute_list_end()
	var pixels: PackedByteArray = ctx.device.texture_get_data(target.rid, 0)
	var corner := (15 * 16 + 15) * 16
	_check(pixels.decode_float(corner + 12) > 0.999 and pixels.decode_float(corner + 4) > 0.1,
		"an unfinished corner receives the next batch after its neighbors turn opaque")
	ctx.free()


func _draw_layers() -> void:
	for raster in rasters:
		raster.update_camera_matrices()
	await _on_render(func():
		for raster in rasters:
			raster.rasterize())
	await RenderingServer.frame_post_draw


func _snapshot(index: int, inspect := false) -> PackedByteArray:
	var output := [PackedByteArray()]
	await _on_render(func():
		var raster = rasters[index]
		if inspect:
			raster._rendered_once = false
			raster.rasterize()
			var rd = raster.context.device
			sample_pairs = rd.buffer_get_data(raster.descriptors["histogram"].rid, 0, 4).decode_u32(0)
			_check(sample_pairs <= raster._sort_capacity, "tile expansion fits allocated capacity")
			if sample_pairs > 0 and sample_pairs <= raster._sort_capacity:
				var keys: PackedInt32Array = rd.buffer_get_data(raster.descriptors["sort_keys"].rid, 0, sample_pairs * 4).to_int32_array()
				var values: PackedInt32Array = rd.buffer_get_data(raster.descriptors["sort_values"].rid, 0, sample_pairs * 4).to_int32_array()
				var pairs := PackedInt64Array()
				pairs.resize(sample_pairs)
				for p in sample_pairs:
					pairs[p] = (int(keys[p]) << 32) | values[p]
				pairs.sort()
				sample_signature = hash(pairs)
		output[0] = raster.context.device.texture_get_data(raster.descriptors["render_texture"].rid, 0))
	return output[0]


func _release_all() -> void:
	await _on_render(func():
		for raster in rasters:
			var ctx = raster.context
			raster.release_all_now()
			ctx.free())
	rasters.clear()
	for tick in 5:
		await process_frame


func _on_render(job: Callable) -> void:
	done = false
	RenderingServer.call_on_render_thread(func():
		job.call()
		done = true)
	while not done:
		await process_frame


func _buffers() -> int:
	return RenderingServer.get_rendering_device().get_memory_usage(RenderingDevice.MEMORY_BUFFERS)


func _textures() -> int:
	return RenderingServer.get_rendering_device().get_memory_usage(RenderingDevice.MEMORY_TEXTURES)


func _image_error(a: PackedByteArray, b: PackedByteArray) -> Dictionary:
	if a == b:
		return {"max": 0.0, "rms": 0.0, "alpha_max": 0.0}
	var left := a.to_float32_array()
	var right := b.to_float32_array()
	if left.size() != right.size():
		return {"max": INF, "rms": INF, "alpha_max": INF}
	var max_error := 0.0
	var sum_square := 0.0
	var alpha_error := 0.0
	for i in left.size():
		if not is_finite(left[i]) or not is_finite(right[i]):
			return {"max": INF, "rms": INF, "alpha_max": INF}
		max_error = maxf(max_error, absf(left[i] - right[i]))
		sum_square += (left[i] - right[i]) * (left[i] - right[i])
		if i % 4 == 3:
			alpha_error = maxf(alpha_error, absf(left[i] - right[i]))
	return {"max": max_error, "rms": sqrt(sum_square / left.size()), "alpha_max": alpha_error}


func _check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
		print("PASS: ", label)
	else:
		failures += 1
		printerr("FAIL: ", label)
