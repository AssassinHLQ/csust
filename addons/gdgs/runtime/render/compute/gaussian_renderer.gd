@tool
extends RefCounted
class_name GaussianRenderer

const RenderingDeviceContext := preload("res://addons/gdgs/runtime/render/compute/gaussian_rendering_device_context.gd")
const RADIX := 256
const MAX_SORT_ELEMENTS_PER_SPLAT := 10

## Benchmark-only stage switches, OR-ed together. 0 (the default) renders
## everything. Tools/bench_scene.gd sets the `gsplat/rendering/profile_skip`
## setting to attribute frame time to one stage by dropping the others; the
## project setting is declared here so it never affects normal use.
const SKIP_PROJECTION := 1
const SKIP_SORT := 2
const SKIP_BOUNDARIES := 4
const SKIP_RENDER := 8

var _profile_skip: int = -1
## Diagnostic only; GPU timestamps remain disabled in ordinary rendering.
var profile_gpu_timestamps: bool = bool(ProjectSettings.get_setting("gsplat/rendering/profile_gpu_timestamps", false))

func _should_skip(flag: int) -> bool:
	if _profile_skip < 0:
		_profile_skip = int(ProjectSettings.get_setting("gsplat/rendering/profile_skip", 0))
	return (_profile_skip & flag) != 0

func render_for_compositor(
	state_cache: GaussianGpuStateCache,
	scene_registry: GaussianSceneRegistry,
	texture_size: Vector2i,
	camera_transform: Transform3D,
	camera_projection: Projection,
	camera_world_position: Vector3,
	depth_capture_alpha: float = 0.5
) -> Dictionary:
	state_cache.flush_pending_cleanup()

	if not scene_registry.has_gpu_data():
		if state_cache.has_render_states():
			state_cache.cleanup_all()
		return {}

	var point_count := scene_registry.get_point_count()
	var safe_size := Vector2i(maxi(texture_size.x, 1), maxi(texture_size.y, 1))
	var state = state_cache.get_or_create_render_state(safe_size)
	_update_camera_from_transform(state, camera_transform, camera_projection)
	state.camera_world_position = camera_world_position
	state.depth_capture_alpha = clampf(depth_capture_alpha, 0.0, 1.0)

	var unique_data_size := scene_registry.get_point_data_byte().size()

	if state.context == null or state.needs_gpu_rebuild:
		state_cache.rebuild_gpu_state(
			state,
			point_count,
			unique_data_size,
			scene_registry.get_instance_count(),
			scene_registry.get_packed_enabled(),
			scene_registry.get_packed_stride_words(),
			scene_registry.get_sh_degree(),
			scene_registry.get_sh_scale(),
			scene_registry.get_point_data_byte(),
			{
				"enabled": scene_registry.has_stream_sources(),
				"capacity_splats": scene_registry.get_stream_capacity_splats(),
				"projection_capacity_splats": scene_registry.get_stream_projection_capacity_splats(),
				"slot_splats": scene_registry.get_stream_slot_splats(),
				"arena_slots": scene_registry.get_stream_arena_slots(),
				"stride_words": scene_registry.get_stream_stride_words(),
				"layout": scene_registry.get_stream_layout(),
				"runtimes": scene_registry.get_stream_runtimes(),
			}
		)
	if state.context == null:
		return {}

	if state.needs_splat_upload:
		state_cache.upload_splats(state, scene_registry.get_point_data_byte(), scene_registry.get_splat_instance_ids_byte())
		state_cache.upload_splat_lighting(state, scene_registry.get_splat_lighting_byte())
	if state.needs_instance_upload:
		state_cache.upload_instance_transforms(state, scene_registry.get_instance_transforms_byte())
	if state.needs_relight_upload:
		state_cache.upload_relight(
			state, scene_registry.get_light_rig_byte(), scene_registry.get_instance_relight_byte()
		)

	if state.camera_push_constants.is_empty():
		return {}

	# gsplat-stream: static-frame cache. A streaming scene whose camera,
	# residency, uploads and lights are all unchanged produces byte-identical
	# output, so the whole compute pipeline can be skipped and the previous
	# frame's textures reused. This is what makes standing still and looking at
	# the scene nearly free; any camera move or streamed load misses the cache
	# and renders normally. Canonical scenes keep animating (intro reveal), so
	# only streaming states participate.
	var cache_key: Array = []
	if state.stream_enabled and bool(ProjectSettings.get_setting("gsplat/rendering/static_frame_cache", true)):
		cache_key = _frame_cache_key(state, scene_registry, camera_transform, camera_projection, point_count)
		if state.frame_cache_valid and cache_key == state.frame_cache_key:
			return {
				"color_alpha_texture": state.descriptors["render_texture"].rid,
				"depth_texture": state.descriptors["depth_texture"].rid
			}

	# gsplat-stream: residency is applied on the render thread, right before the
	# dispatch that reads it, so the arena and the slot directory can never
	# disagree within a frame.
	state_cache.apply_stream_snapshots(state)
	state_cache.write_projection_dims(state, point_count)

	_rasterize_state(state, point_count, scene_registry.get_light_count())
	if not cache_key.is_empty():
		state.frame_cache_key = cache_key
		state.frame_cache_valid = true
	if state.descriptors.has("render_texture") and state.descriptors.has("depth_texture"):
		return {
			"color_alpha_texture": state.descriptors["render_texture"].rid,
			"depth_texture": state.descriptors["depth_texture"].rid
		}
	return {}


## Everything the compute pipeline reads, as a comparable value. Residency is
## summarised by the runtimes' snapshot revisions. Instance and lighting bytes
## also cover edits whose upload flags were cleared before this comparison.
func _frame_cache_key(state, scene_registry, camera_transform: Transform3D, camera_projection: Projection, point_count: int) -> Array:
	if _profile_skip < 0:
		_profile_skip = int(ProjectSettings.get_setting("gsplat/rendering/profile_skip", 0))
	var revision_sum := 0
	for runtime in state.stream_runtimes:
		if runtime != null:
			revision_sum += int(runtime.latest_revision())
	return [
		camera_transform,
		camera_projection,
		state.camera_world_position,
		state.depth_capture_alpha,
		point_count,
		revision_sum,
		scene_registry.get_instance_transforms_byte(),
		scene_registry.get_instance_relight_byte(),
		scene_registry.get_light_rig_byte(),
		scene_registry.get_light_count(),
		state.needs_splat_upload,
		state.needs_instance_upload,
		state.needs_relight_upload,
		_profile_skip,
	]

func _rasterize_state(state, point_count: int, light_count: int) -> void:
	if state.context == null:
		return
	if profile_gpu_timestamps:
		state.context.device.capture_timestamp("gdgs/start")

	var uniforms := RenderingDeviceContext.create_push_constant([
		state.camera_world_position.x,
		state.camera_world_position.y,
		state.camera_world_position.z,
		Time.get_ticks_msec() * 1e-3,
		state.texture_size.x,
		state.texture_size.y,
		point_count,
		# The trailing slot used to be padding; it now carries the active light
		# count, which is what bounds the projection shader's relight loop.
		light_count,
		# gsplat-stream packed layout (uniform block words 8..11).
		state.packed_stride_words,
		state.sh_degree,
		state.sh_scale,
		1 if state.packed_enabled else 0,
		# gsplat-stream arena layout (uniform block words 12..15).
		state.stream_base_point,
		state.stream_base_unique,
		state.stream_slot_splats,
		1 if state.stream_enabled else 0,
		# Word 16: slot directory length. Word 17: raster tile edge (8 or 16).
		# Word 18: arena record stride in words. Word 19: arena record layout.
		state.stream_arena_slots,
		state.render_tile_size,
		state.stream_stride_words,
		state.stream_layout,
		# Words 20..23: culled capacity, one-bank sort capacity and padding.
		state.culled_entries_max,
		state.sort_elements_max,
		0, 0
	])
	state.context.device.buffer_update(state.descriptors["uniforms"].rid, 0, 24 * 4, uniforms)
	state.context.device.buffer_clear(state.descriptors["histogram"].rid, 0, 4 + 4 * RADIX * 4)
	# gsplat-stream: reset the culled compaction counter every frame.
	if state.descriptors.has("culled_counter"):
		state.context.device.buffer_clear(state.descriptors["culled_counter"].rid, 0, 4)
	state.context.device.buffer_clear(state.descriptors["tile_bounds"].rid, 0, state.tile_dims_small.x * state.tile_dims_small.y * 2 * 4)
	if profile_gpu_timestamps:
		state.context.device.capture_timestamp("gdgs/setup")

	if not _should_skip(SKIP_PROJECTION):
		# gsplat-stream: pre-pass builds the slot-count prefix sum and sizes the
		# projection dispatch to the resident splat count, so no invocation is
		# launched for empty arena padding.
		if state.stream_enabled:
			var pre_list: int = state.context.compute_list_begin()
			state.pipelines["gsplat_dispatch"].call(
				state.context, pre_list, RenderingDeviceContext.create_push_constant([state.stream_arena_slots]))
			state.context.compute_list_end()
		var compute_list: int = state.context.compute_list_begin()
		# gsplat-stream: with an arena the dispatch width changes every frame, so
		# it comes from a GPU buffer instead of the pipeline's baked dimensions.
		var projection_dims: RID = state.descriptors["projection_dims"].rid if state.stream_enabled else RID()
		state.pipelines["gsplat_projection"].call(
			state.context, compute_list, state.camera_push_constants, [], projection_dims, 0)
		state.context.compute_list_end()

	# gsplat-stream: rewrite the indirect sort/boundaries dispatch widths from the
	# true element count projection just wrote, so they follow residency instead
	# of the worst-case capacity the buffers were allocated for.
	if profile_gpu_timestamps:
		state.context.device.capture_timestamp("gdgs/projection")
	if not (_should_skip(SKIP_SORT) and _should_skip(SKIP_BOUNDARIES)):
		var dispatch_list: int = state.context.compute_list_begin()
		state.pipelines["gsplat_dispatch"].call(
			state.context, dispatch_list, RenderingDeviceContext.create_push_constant([state.stream_arena_slots]))
		state.context.compute_list_end()

	if not _should_skip(SKIP_SORT):
		var sort_list: int = state.context.compute_list_begin()
		# gsplat-stream: stride the radix sort over the ACTUAL capacity. Using the
		# upstream constant here while the buffers are sized for the adaptive budget
		# walks out of the allocation (measured as a 65 -> 7.5 fps collapse).
		var sort_elements_max: int = maxi(state.sort_elements_max, point_count)
		for radix_shift_pass in range(4):
			var sort_push_constant := RenderingDeviceContext.create_push_constant([
				radix_shift_pass,
				sort_elements_max * (radix_shift_pass % 2),
				sort_elements_max * (1 - (radix_shift_pass % 2)),
				0
			])
			state.pipelines["radix_sort_upsweep"].call(state.context, sort_list, sort_push_constant, [], state.descriptors["grid_dimensions"].rid, 0)
			state.pipelines["radix_sort_spine"].call(state.context, sort_list, sort_push_constant)
			state.pipelines["radix_sort_downsweep"].call(state.context, sort_list, sort_push_constant, [], state.descriptors["grid_dimensions"].rid, 0)
		state.context.compute_list_end()

	if profile_gpu_timestamps:
		state.context.device.capture_timestamp("gdgs/sort")
	if not _should_skip(SKIP_BOUNDARIES):
		var bounds_list: int = state.context.compute_list_begin()
		state.pipelines["gsplat_boundaries"].call(state.context, bounds_list, PackedByteArray(), [], state.descriptors["grid_dimensions"].rid, 3 * 4)
		state.context.compute_list_end()

	if profile_gpu_timestamps:
		state.context.device.capture_timestamp("gdgs/boundaries")
	if not _should_skip(SKIP_RENDER):
		var render_list: int = state.context.compute_list_begin()
		var render_pipeline: String = "gsplat_render_t8" if state.render_tile_size == 8 else "gsplat_render"
		state.pipelines[render_pipeline].call(
			state.context,
			render_list,
			RenderingDeviceContext.create_push_constant([0.0, state.depth_capture_alpha, 0.0, 0.0])
		)
		state.context.compute_list_end()
	if profile_gpu_timestamps:
		state.context.device.capture_timestamp("gdgs/render")

func _update_camera_from_transform(state, camera_transform: Transform3D, camera_projection: Projection) -> void:
	var view := Projection(camera_transform.affine_inverse())
	if view != state.camera_view or camera_projection != state.camera_projection:
		state.camera_view = view
		state.camera_projection = camera_projection
		state.camera_push_constants = RenderingDeviceContext.create_push_constant(
			_projection_to_column_major_floats(view) + _projection_to_column_major_floats(camera_projection)
		)

func _projection_to_column_major_floats(matrix: Projection) -> Array:
	return [
		matrix.x[0], matrix.x[1], matrix.x[2], matrix.x[3],
		matrix.y[0], matrix.y[1], matrix.y[2], matrix.y[3],
		matrix.z[0], matrix.z[1], matrix.z[2], matrix.z[3],
		matrix.w[0], matrix.w[1], matrix.w[2], matrix.w[3]
	]
