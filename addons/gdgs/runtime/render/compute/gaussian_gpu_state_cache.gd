@tool
extends RefCounted
class_name GaussianGpuStateCache

const RenderingDeviceContext := preload("res://addons/gdgs/runtime/render/compute/gaussian_rendering_device_context.gd")
const VisibleBudgetScript := preload("res://addons/gdgs/runtime/render/compute/gaussian_visible_budget.gd")
const SortBudgetScript := preload("res://addons/gdgs/runtime/render/compute/gaussian_sort_budget.gd")
const SharedWorkspaceScript := preload("res://addons/gdgs/runtime/render/compute/gaussian_shared_workspace.gd")
const SHARED_WORKSPACE_SETTING := "gsplat/rendering/shared_workspace"

const TILE_SIZE := 16
const TILE_SIZE_SMALL := 8
const WORKGROUP_SIZE := 512
const RADIX := 256
const PARTITION_DIVISION := 8
const PARTITION_SIZE := PARTITION_DIVISION * WORKGROUP_SIZE
const MAX_RENDER_STATES := 4
const FLOATS_PER_SPLAT := 60
const FLOATS_PER_CULLED_SPLAT := 12
const BYTES_PER_FLOAT := 4
const MAX_SORT_ELEMENTS_PER_SPLAT := 10
## Must match GaussianStreamRuntime.SLOT_INFO_WORDS and the slot_info stride in
## gsplat_projection.glsl / gsplat_dispatch.glsl.
const SLOT_INFO_WORDS := 8
# Relighting. Must match gsplat_projection.glsl and gaussian_light_rig.gd.
const LIGHTING_BYTES_PER_SPLAT := 4
const RELIGHT_FLOATS_PER_INSTANCE := 8
const MAX_LIGHTS := 8
const LIGHT_RIG_FLOATS := MAX_LIGHTS * 16

const SHADER_PATH_PROJECTION := "res://addons/gdgs/runtime/render/compute/shaders/gsplat_projection.glsl"
const SHADER_PATH_RADIX_UPSWEEP := "res://addons/gdgs/runtime/render/compute/shaders/radix_sort_upsweep.glsl"
const SHADER_PATH_RADIX_SPINE := "res://addons/gdgs/runtime/render/compute/shaders/radix_sort_spine.glsl"
const SHADER_PATH_RADIX_DOWNSWEEP := "res://addons/gdgs/runtime/render/compute/shaders/radix_sort_downsweep.glsl"
const SHADER_PATH_BOUNDARIES := "res://addons/gdgs/runtime/render/compute/shaders/gsplat_boundaries.glsl"
const SHADER_PATH_DISPATCH := "res://addons/gdgs/runtime/render/compute/shaders/gsplat_dispatch.glsl"
const SHADER_PATH_RENDER := "res://addons/gdgs/runtime/render/compute/shaders/gsplat_render.glsl"
const SHADER_PATH_RENDER_T8 := "res://addons/gdgs/runtime/render/compute/shaders/gsplat_render_t8.glsl"

class RenderState:
	extends RefCounted

	var texture_size := Vector2i.ONE
	var tile_dims := Vector2i.ONE
	var tile_dims_small := Vector2i.ONE
	## Raster tile edge this state renders with: 8 for streaming LOD (tiny splats),
	## 16 for canonical scenes (large splats would explode the sort at 8px).
	var render_tile_size := 16
	var camera_projection: Projection
	var camera_view: Projection
	var camera_push_constants := PackedByteArray()
	var camera_world_position := Vector3.ZERO
	var depth_capture_alpha := 0.5
	var needs_gpu_rebuild := true
	var needs_splat_upload := false
	var needs_instance_upload := false
	var needs_relight_upload := false
	## gsplat-stream: static-frame cache. When the camera, residency and uploads
	## are unchanged the compute pipeline is skipped and the previous frame's
	## textures are reused; the key records everything the pipeline reads.
	var frame_cache_key: Array = []
	var frame_cache_valid := false
	var context: GdgsRenderingDeviceContext
	## Retain borrowed buffers until this state's descriptor sets are freed.
	var shared_workspace: RefCounted
	var shaders: Dictionary = {}
	var pipelines: Dictionary = {}
	var descriptors: Dictionary = {}
	## gsplat-stream: visible-splat fraction used to size `culled_splats`.
	## Null until the first rebuild; the renderer feeds it readbacks.
	var visible_budget: RefCounted = null
	## gsplat-stream: worst-case sort slots per splat. Upstream hard-codes 10,
	## which reserves ~1.5 GB at 10M splats; this starts lower and adapts.
	var sort_budget: RefCounted = null
	## Bytes this state asked RenderingDevice for (sum of every allocation).
	var declared_bytes := 0
	## gsplat-stream: actual sort capacity in elements. The radix-sort push
	## constants must use THIS, not the upstream constant, or the sort walks past
	## the sized-for-the-budget buffers.
	var sort_elements_max := 0
	## Per-state limit even when a larger scratch workspace is shared.
	var culled_entries_max := 0
	## Frame counter used to throttle GPU readbacks.
	var frames_since_readback: int = 0
	## gsplat-stream: packed-layout state for the shader's uniform block.
	var packed_enabled := false
	var packed_stride_words := 0
	var sh_degree := 3
	var sh_scale := 1.0
	## gsplat-stream: disk-backed LOD arena appended after the canonical data.
	var stream_enabled := false
	var stream_capacity_splats := 0
	var stream_slot_splats := 0
	var stream_arena_slots := 0
	var stream_base_point := 0
	var stream_base_unique := 0
	var stream_base_bytes := 0
	var stream_bytes_per_splat := 0
	## The arena may use a different record encoding than the canonical payload
	## (a q24 stream pack is 24 B/splat next to a 52 B canonical resource), so it
	## carries its own stride and a layout id the shader switches the decoder on.
	var stream_stride_words := 0
	var stream_layout := 0
	var stream_resident_splats := 0
	var stream_used_slots := 0
	var stream_runtimes: Array = []
	var stream_revisions: Dictionary = {}
	var stream_slot_info := PackedInt32Array()

var _render_states: Dictionary = {}
var _render_state_lru: Array = []
var _pending_gpu_cleanup := false
## Weak references prevent obsolete capacities from keeping GPU allocations alive.
var _workspaces: Dictionary = {}

func _acquire_workspace(device: RenderingDevice, culled_entries: int, sort_elements: int) -> RefCounted:
	if not bool(ProjectSettings.get_setting(SHARED_WORKSPACE_SETTING, true)):
		return SharedWorkspaceScript.new(device, culled_entries, sort_elements)
	for stale_key in _workspaces.keys():
		if _workspaces[stale_key].get_ref() == null:
			_workspaces.erase(stale_key)
	var key := "%d:%d:%d" % [device.get_instance_id(), culled_entries, sort_elements]
	var workspace: RefCounted = _workspaces[key].get_ref() if _workspaces.has(key) else null
	if workspace == null:
		workspace = SharedWorkspaceScript.new(device, culled_entries, sort_elements)
		_workspaces[key] = weakref(workspace)
	return workspace

## Render-thread snapshot of requested resource bytes, counting shared storage once.
## Excludes driver overhead, alignment, shader/pipeline caches and other plugins.
func get_memory_stats() -> Dictionary:
	var private_bytes := 0
	var workspace_bytes := 0
	var logical_workspace_bytes := 0
	var workspaces: Dictionary = {}
	var live_states := 0
	for state in _render_states.values():
		if state.context == null:
			continue
		live_states += 1
		var workspace = state.shared_workspace
		private_bytes += state.declared_bytes - workspace.declared_bytes
		logical_workspace_bytes += workspace.declared_bytes
		if not workspaces.has(workspace.get_instance_id()):
			workspaces[workspace.get_instance_id()] = true
			workspace_bytes += workspace.declared_bytes
	return {
		"render_states": live_states,
		"workspaces": workspaces.size(),
		"private_bytes": private_bytes,
		"workspace_bytes": workspace_bytes,
		"total_bytes": private_bytes + workspace_bytes,
		"shared_saved_bytes": logical_workspace_bytes - workspace_bytes,
	}

func has_render_states() -> bool:
	return not _render_states.is_empty()

func request_cleanup() -> void:
	_pending_gpu_cleanup = true

func flush_pending_cleanup() -> void:
	if _pending_gpu_cleanup:
		cleanup_all()

func get_or_create_render_state(texture_size: Vector2i):
	var state: RenderState = _render_states.get(texture_size, null)
	if state == null:
		state = RenderState.new()
		state.texture_size = texture_size
		state.tile_dims = (texture_size + Vector2i(TILE_SIZE - 1, TILE_SIZE - 1)) / TILE_SIZE
		state.tile_dims_small = (texture_size + Vector2i(TILE_SIZE_SMALL - 1, TILE_SIZE_SMALL - 1)) / TILE_SIZE_SMALL
		_render_states[texture_size] = state
		# States retain private sources/outputs; matching scratch capacities share.
		print("[gsplat] creating render state for %s (total states: %d)"
			% [str(texture_size), _render_states.size()])
	_touch_render_state(texture_size)
	_enforce_render_state_cache_limit()
	return state

func mark_all_render_states_needs_gpu_rebuild() -> void:
	for state in _render_states.values():
		state.needs_gpu_rebuild = true

func mark_all_render_states_needs_splat_upload(value: bool) -> void:
	for state in _render_states.values():
		state.needs_splat_upload = value

func mark_all_render_states_needs_instance_upload(value: bool) -> void:
	for state in _render_states.values():
		state.needs_instance_upload = value

func mark_all_render_states_needs_relight_upload(value: bool) -> void:
	for state in _render_states.values():
		state.needs_relight_upload = value

func rebuild_gpu_state(
	state,
	point_count: int,
	unique_data_size: int,
	instance_count: int,
	packed_enabled: bool = false,
	packed_stride_words: int = 0,
	sh_degree: int = 3,
	sh_scale: float = 1.0,
	splat_data: PackedByteArray = PackedByteArray(),
	stream: Dictionary = {}
) -> void:
	cleanup_state(state)
	if point_count <= 0 and not bool(stream.get("enabled", false)):
		return

	state.context = RenderingDeviceContext.create(RenderingServer.get_rendering_device())

	state.shaders["projection"] = state.context.load_shader(SHADER_PATH_PROJECTION)
	state.shaders["radix_upsweep"] = state.context.load_shader(SHADER_PATH_RADIX_UPSWEEP)
	state.shaders["radix_spine"] = state.context.load_shader(SHADER_PATH_RADIX_SPINE)
	state.shaders["radix_downsweep"] = state.context.load_shader(SHADER_PATH_RADIX_DOWNSWEEP)
	state.shaders["boundaries"] = state.context.load_shader(SHADER_PATH_BOUNDARIES)
	state.shaders["dispatch"] = state.context.load_shader(SHADER_PATH_DISPATCH)
	state.shaders["render"] = state.context.load_shader(SHADER_PATH_RENDER)
	state.shaders["render_t8"] = state.context.load_shader(SHADER_PATH_RENDER_T8)

	# gsplat-stream: size the culled buffer by the predicted visible count rather
	# than point_count. The projection pass compacts into it, so entries past the
	# visible set are never needed.
	if state.visible_budget == null:
		state.visible_budget = VisibleBudgetScript.new()
	if state.sort_budget == null:
		state.sort_budget = SortBudgetScript.new()
	# gsplat-stream: the LOD arena is appended to the same splat buffer, so every
	# downstream buffer is sized for the worst case (canonical points + the whole
	# arena), not for the residency of the moment. Residency then only moves the
	# dispatch width, never an allocation.
	state.stream_enabled = bool(stream.get("enabled", false))
	# 8px tiles cut raster waste for ~1px LOD splats but multiply sort elements
	# for splats that span a tile. With <=2 entries/point, prefer 16px tiles to
	# preserve coverage in dense close-ups without growing scratch memory.
	# force_tile_size (8/16) overrides this policy. The sort key packs the tile
	# id into 16 bits, so the small grid is only usable up to 65535 tiles.
	var small_fits: bool = state.tile_dims_small.x * state.tile_dims_small.y <= 65535
	var force_tile: int = int(ProjectSettings.get_setting("gsplat/rendering/force_tile_size", 0))
	if force_tile == TILE_SIZE:
		state.render_tile_size = TILE_SIZE
	elif force_tile == TILE_SIZE_SMALL and small_fits:
		state.render_tile_size = TILE_SIZE_SMALL
	else:
		var ample_sort: bool = int(state.sort_budget.elements) > 2
		# q24 LOD representatives benefit from small tiles. A full f32 source
		# cloud has millions of original points: 8px tiles multiply sort entries.
		var quantized_lod: bool = state.stream_enabled and int(stream.get("layout", 0)) == 1
		state.render_tile_size = TILE_SIZE_SMALL if quantized_lod and small_fits and ample_sort else TILE_SIZE
	state.stream_capacity_splats = int(stream.get("capacity_splats", 0))
	state.stream_slot_splats = int(stream.get("slot_splats", 0))
	state.stream_arena_slots = int(stream.get("arena_slots", 0))
	state.stream_stride_words = int(stream.get("stride_words", 0))
	state.stream_layout = int(stream.get("layout", 0))
	state.stream_runtimes = stream.get("runtimes", [])
	state.stream_revisions.clear()
	state.stream_resident_splats = 0
	state.stream_used_slots = 0
	state.stream_slot_info = PackedInt32Array()
	state.stream_slot_info.resize(maxi(1, state.stream_arena_slots) * SLOT_INFO_WORDS)
	state.stream_slot_info.fill(0)
	var sizing_count: int = point_count + (int(stream.get("projection_capacity_splats", state.stream_capacity_splats)) if state.stream_enabled else 0)

	var culled_entries: int = state.visible_budget.capacity(sizing_count)
	state.culled_entries_max = culled_entries
	state.frames_since_readback = 0

	# gsplat-stream: allocate sort capacity for the adaptive budget, not the
	# upstream worst case of 10 slots/splat.
	var sort_elements_per_splat: int = maxi(1, int(state.sort_budget.elements))
	var num_sort_elements_max := sizing_count * sort_elements_per_splat
	state.sort_elements_max = num_sort_elements_max
	print("[gsplat] compute state %s: %d splats (+%d arena), sort budget %d elem/splat (%d elements), culled %d entries"
		% [str(state.texture_size), sizing_count, state.stream_capacity_splats, sort_elements_per_splat, num_sort_elements_max, culled_entries])
	var num_partitions := (num_sort_elements_max + PARTITION_SIZE - 1) / PARTITION_SIZE
	var block_dims := PackedInt32Array()
	block_dims.resize(6)
	block_dims.fill(1)
	# Pre-size indirect dispatch dimensions on the CPU. On macOS/Metal, updating this
	# buffer from the projection pass can cause the entire GS pipeline to go blank.
	block_dims[0] = num_partitions
	block_dims[3] = ceili(num_sort_elements_max / 256.0)

	# Relighting buffers, sized off the same unique-splat and instance counts as
	# the data above. Always allocated (a minimum of one element) so the shader's
	# bindings stay valid even with nothing baked; the per-instance `enabled`
	# flag is what actually gates the maths.
	# gsplat-stream: record the packed layout so the shader can pick a decoder and
	# so `unique_splat_count` divides by the right stride.
	state.packed_enabled = packed_enabled
	state.packed_stride_words = packed_stride_words
	state.sh_degree = sh_degree
	state.sh_scale = sh_scale
	var bytes_per_splat := packed_stride_words * BYTES_PER_FLOAT if packed_enabled \
		else FLOATS_PER_SPLAT * BYTES_PER_FLOAT

	var unique_splat_count := maxi(1, unique_data_size / maxi(bytes_per_splat, BYTES_PER_FLOAT))
	# gsplat-stream: arena geometry. `stream_base_*` is where the canonical data
	# ends and the slot arena begins, in points, unique splats and bytes.
	# The arena's own stride wins when it has one: a q24 pack is denser than the
	# canonical record it may sit next to, and the shader decodes it separately.
	state.stream_bytes_per_splat = state.stream_stride_words * BYTES_PER_FLOAT \
		if state.stream_stride_words > 0 else bytes_per_splat
	state.stream_base_point = point_count
	state.stream_base_unique = unique_data_size / maxi(bytes_per_splat, BYTES_PER_FLOAT)
	state.stream_base_bytes = int(unique_data_size)
	var arena_bytes: int = int(state.stream_capacity_splats) * state.stream_bytes_per_splat \
		if state.stream_enabled else 0
	# gsplat-stream: the lighting bake is indexed by unique splat, and arena points
	# continue that index space, so the record buffer covers both or a relit stream
	# node would read past the allocation.
	var lighting_splats: int = unique_splat_count + (int(state.stream_capacity_splats) if state.stream_enabled else 0)
	# gsplat-stream: the splat buffer is created empty and filled by
	# upload_splats(). Creating it with the payload in one call was measured
	# (2026-11-12, 10M splats) to save ~128 MB of VRAM but drop the frame rate
	# from 71 to 7.5 fps, so the separate upload is kept.
	state.descriptors["splats"] = state.context.create_storage_buffer(int(unique_data_size) + arena_bytes)
	state.descriptors["splat_lighting"] = state.context.create_storage_buffer(
		lighting_splats * LIGHTING_BYTES_PER_SPLAT)
	state.descriptors["light_rig"] = state.context.create_storage_buffer(
		LIGHT_RIG_FLOATS * BYTES_PER_FLOAT)
	state.descriptors["instance_relight"] = state.context.create_storage_buffer(
		maxi(1, instance_count) * RELIGHT_FLOATS_PER_INSTANCE * BYTES_PER_FLOAT)
	# Every compositor render finishes its compute passes before the next state
	# uses this workspace. Static-frame hits read private output textures only.
	state.shared_workspace = _acquire_workspace(state.context.device, culled_entries, num_sort_elements_max)
	for name in state.shared_workspace.descriptors:
		state.descriptors[name] = state.shared_workspace.descriptors[name]
	state.descriptors["grid_dimensions"] = state.context.create_storage_buffer(6 * 4, block_dims.to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	state.descriptors["splat_instance_ids"] = state.context.create_storage_buffer(maxi(1, point_count) * 4 * 2)
	state.descriptors["instance_transforms"] = state.context.create_storage_buffer(maxi(1, instance_count) * 16 * BYTES_PER_FLOAT)
	# gsplat-stream: slot_info[slot] = (splat_count, instance_id, node centre.xyz,
	# node half-size). The projection shader early-outs on empty slots, reads the
	# owning instance from here and rebuilds q24 positions against the node frame.
	state.descriptors["slot_info"] = state.context.create_storage_buffer(
		maxi(1, state.stream_arena_slots) * SLOT_INFO_WORDS * 4)
	# gsplat-stream: exclusive prefix of slot counts for the compacted projection
	# dispatch (arena_slots + 1 entries).
	state.descriptors["slot_offsets"] = state.context.create_storage_buffer((maxi(1, state.stream_arena_slots) + 1) * 4)
	# gsplat-stream: an eviction swaps the last slot into the freed one. Godot's
	# command graph rejects a buffer_copy whose source and destination are the
	# same buffer ("Command can't have itself as a dependency"), so swaps need a
	# one-slot staging buffer. Allocate it at the first move, not at rebuild:
	# a persistent one-slot stream cannot compact and may have a huge slot.
	# gsplat-stream: residency changes the dispatch width every frame, so the
	# projection pass is dispatched indirectly from this buffer instead of being
	# sized for the worst case (which would walk the whole arena).
	state.descriptors["projection_dims"] = state.context.create_storage_buffer(
		3 * 4, PackedInt32Array([1, 1, 1]).to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	# gsplat-stream: 24 words. Words 8..11 carry the packed-layout parameters
	# the projection shader needs (stride, SH degree, SH scale, packed flag);
	# words 12..15 carry the arena base point, base unique index, slot size and
	# the enabled flag; word 16 the slot directory length (OpArrayLength is not
	# available); word 17 the raster tile edge; word 18 the arena record stride
	# in words; word 19 the arena record layout (0 = float32, 1 = q24).
	# Words 20..23: logical culled/sort capacities and std140 padding.
	state.descriptors["uniforms"] = state.context.create_uniform_buffer(24 * 4)
	state.descriptors["tile_bounds"] = state.context.create_storage_buffer(state.tile_dims_small.x * state.tile_dims_small.y * 2 * 4)
	state.descriptors["render_texture"] = state.context.create_texture(state.texture_size, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
	state.descriptors["depth_texture"] = state.context.create_texture(state.texture_size, RenderingDevice.DATA_FORMAT_R32_SFLOAT)

	var projection_set: RID = state.context.create_descriptor_set([
		state.descriptors["splats"],
		state.descriptors["culled_splats"],
		state.descriptors["histogram"],
		state.descriptors["sort_keys"],
		state.descriptors["sort_values"],
		state.descriptors["grid_dimensions"],
		state.descriptors["splat_instance_ids"],
		state.descriptors["instance_transforms"],
		state.descriptors["uniforms"],
		# Bindings are assigned by position in create_descriptor_set, so these
		# three must stay last and in this order to match bindings 9/10/11.
		state.descriptors["light_rig"],
		state.descriptors["splat_lighting"],
		state.descriptors["instance_relight"],
		# gsplat-stream: binding 12, the culled compaction counter.
		state.descriptors["culled_counter"],
		# gsplat-stream: binding 13 aliases the SAME buffer as binding 0, but the
		# shader declares it as a uint array so it can decode the packed record.
		# Binding one RID twice keeps the canonical path untouched.
		state.descriptors["splats"],
		# gsplat-stream: binding 14, the slot directory.
		state.descriptors["slot_info"],
		# gsplat-stream: binding 15, the compacted-dispatch prefix sum.
		state.descriptors["slot_offsets"]
	], state.shaders["projection"], 0)

	var radix_upsweep_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"],
		state.descriptors["sort_keys"]
	], state.shaders["radix_upsweep"], 0)

	var radix_spine_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"]
	], state.shaders["radix_spine"], 0)

	var radix_downsweep_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"],
		state.descriptors["sort_keys"],
		state.descriptors["sort_values"]
	], state.shaders["radix_downsweep"], 0)

	var boundaries_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"],
		state.descriptors["sort_keys"],
		state.descriptors["tile_bounds"]
	], state.shaders["boundaries"], 0)

	# gsplat-stream: finalize pass reads the true element count and rewrites the
	# indirect sort/boundaries dispatch widths to follow residency, not capacity.
	var dispatch_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"],
		state.descriptors["grid_dimensions"],
		state.descriptors["slot_info"],
		state.descriptors["slot_offsets"],
		state.descriptors["projection_dims"]
	], state.shaders["dispatch"], 0)

	var render_set: RID = state.context.create_descriptor_set([
		state.descriptors["culled_splats"],
		state.descriptors["sort_values"],
		state.descriptors["tile_bounds"],
		state.descriptors["render_texture"],
		state.descriptors["depth_texture"]
	], state.shaders["render"], 0)

	var render_set_t8: RID = state.context.create_descriptor_set([
		state.descriptors["culled_splats"],
		state.descriptors["sort_values"],
		state.descriptors["tile_bounds"],
		state.descriptors["render_texture"],
		state.descriptors["depth_texture"]
	], state.shaders["render_t8"], 0)

	# Specialize from the merged layout, never from a dataset name or point count.
	# A driver can eliminate unused SH/decoder paths before allocating registers.
	var projection_constants: Array[RDPipelineSpecializationConstant] = []
	if bool(ProjectSettings.get_setting("gsplat/rendering/specialize_projection", true)):
		var packed_sh0 := RDPipelineSpecializationConstant.new()
		packed_sh0.constant_id = 0
		packed_sh0.value = packed_enabled and sh_degree == 0
		projection_constants.append(packed_sh0)
		var single_f32 := RDPipelineSpecializationConstant.new()
		single_f32.constant_id = 1
		single_f32.value = packed_enabled and state.stream_enabled and point_count == 0 \
			and state.stream_arena_slots == 1 and state.stream_layout == 0
		projection_constants.append(single_f32)
	state.pipelines["gsplat_projection"] = state.context.create_pipeline(
		[ceili(sizing_count / 256.0), 1, 1], [projection_set], state.shaders["projection"], projection_constants)
	state.pipelines["radix_sort_upsweep"] = state.context.create_pipeline([], [radix_upsweep_set], state.shaders["radix_upsweep"])
	state.pipelines["radix_sort_spine"] = state.context.create_pipeline([RADIX, 1, 1], [radix_spine_set], state.shaders["radix_spine"])
	state.pipelines["radix_sort_downsweep"] = state.context.create_pipeline([], [radix_downsweep_set], state.shaders["radix_downsweep"])
	state.pipelines["gsplat_boundaries"] = state.context.create_pipeline([], [boundaries_set], state.shaders["boundaries"])
	state.pipelines["gsplat_dispatch"] = state.context.create_pipeline([1, 1, 1], [dispatch_set], state.shaders["dispatch"])
	state.pipelines["gsplat_render"] = state.context.create_pipeline([state.tile_dims.x, state.tile_dims.y, 1], [render_set], state.shaders["render"])
	state.pipelines["gsplat_render_t8"] = state.context.create_pipeline([state.tile_dims_small.x, state.tile_dims_small.y, 1], [render_set_t8], state.shaders["render_t8"])

	state.needs_gpu_rebuild = false
	state.needs_splat_upload = true
	state.needs_instance_upload = true
	state.needs_relight_upload = true
	state.frame_cache_valid = false

	# gsplat-stream: exact accounting of what we asked for, so a driver-level
	# discrepancy can be told apart from a sizing mistake.
	var declared := 0
	declared += int(unique_data_size) + arena_bytes
	declared += lighting_splats * LIGHTING_BYTES_PER_SPLAT
	declared += LIGHT_RIG_FLOATS * BYTES_PER_FLOAT
	declared += maxi(1, instance_count) * RELIGHT_FLOATS_PER_INSTANCE * BYTES_PER_FLOAT
	declared += maxi(1, culled_entries) * FLOATS_PER_CULLED_SPLAT * BYTES_PER_FLOAT
	declared += 4  # culled_counter
	declared += 6 * 4  # grid_dimensions
	declared += 4 + (1 + 4 * RADIX + num_partitions * RADIX) * 4  # histogram
	declared += num_sort_elements_max * 4 * 2 * 2  # sort_keys + sort_values
	declared += maxi(1, point_count) * 4 * 2  # splat_instance_ids
	declared += maxi(1, instance_count) * 16 * BYTES_PER_FLOAT  # instance_transforms
	declared += maxi(1, state.stream_arena_slots) * SLOT_INFO_WORDS * 4  # slot_info
	declared += (maxi(1, state.stream_arena_slots) + 1) * 4  # slot_offsets
	declared += 3 * 4  # projection_dims
	declared += 24 * 4  # uniforms
	declared += state.tile_dims_small.x * state.tile_dims_small.y * 2 * 4  # tile_bounds
	declared += state.texture_size.x * state.texture_size.y * 16  # render_texture
	declared += state.texture_size.x * state.texture_size.y * 4   # depth_texture
	state.declared_bytes = declared
	print("[gsplat] declared GPU bytes: %.1f MB (%d splats + %d arena slots, %d sort elem/splat, %d culled)"
		% [declared / 1048576.0, sizing_count, state.stream_arena_slots, sort_elements_per_splat, culled_entries])

func upload_splats(state, point_data_byte: PackedByteArray, splat_instance_ids_byte: PackedByteArray) -> void:
	if state.context == null:
		return
	# gsplat-stream: a stream-only scene has no canonical payload, but the arena
	# still has to be marked clean or the renderer re-enters this every frame.
	if point_data_byte.is_empty() and splat_instance_ids_byte.is_empty():
		if state.stream_enabled:
			state.needs_splat_upload = false
		return
	if point_data_byte.is_empty() or splat_instance_ids_byte.is_empty():
		return
	# gsplat-stream: upload in bounded chunks. A single buffer_update of the whole
	# payload (hundreds of MB at 10M splats) makes the driver keep a full-size
	# staging allocation; chunking keeps the staging window small.
	const UPLOAD_CHUNK := 64 * 1024 * 1024
	var total := point_data_byte.size()
	var offset := 0
	while offset < total:
		var size := mini(UPLOAD_CHUNK, total - offset)
		state.context.device.buffer_update(
			state.descriptors["splats"].rid, offset, size,
			point_data_byte.slice(offset, offset + size))
		offset += size
	state.context.device.buffer_update(state.descriptors["splat_instance_ids"].rid, 0, splat_instance_ids_byte.size(), splat_instance_ids_byte)
	state.needs_splat_upload = false

## gsplat-stream: apply the residency snapshots the runtimes published since this
## state last consumed them. Called on the render thread, immediately before the
## projection dispatch, so the arena and the slot directory always agree.
func apply_stream_snapshots(state) -> void:
	if state.context == null or not state.stream_enabled:
		return
	var device: RenderingDevice = state.context.device
	var splats_rid: RID = state.descriptors["splats"].rid
	var slot_stride: int = int(state.stream_slot_splats) * int(state.stream_bytes_per_splat)
	var profile: bool = bool(ProjectSettings.get_setting("gsplat/stream/profile_apply", false))
	var t0: int = Time.get_ticks_usec() if profile else 0
	var n_moves := 0
	var n_uploads := 0
	for runtime in state.stream_runtimes:
		if runtime == null:
			continue
		var from_revision: int = state.stream_revisions.get(runtime, -1)
		var snapshots: Array = runtime.consume(from_revision)
		if snapshots.is_empty():
			continue
		for snapshot in snapshots:
			n_moves += snapshot.get("moves", []).size()
			n_uploads += snapshot.get("uploads", []).size()
			_apply_stream_snapshot(state, device, splats_rid, slot_stride, snapshot)
		# The main thread may publish again after consume() releases its mutex.
		# Acknowledge only what this render state actually applied, never that
		# newer revision; otherwise an upload/move delta can be skipped forever.
		state.stream_revisions[runtime] = int(snapshots[-1]["revision"])
	_refresh_stream_totals(state)
	if profile:
		var us: int = Time.get_ticks_usec() - t0
		if us > 2000:
			print("[gsplat-apply] %d us, %d moves, %d uploads" % [us, n_moves, n_uploads])

func _apply_stream_snapshot(state, device: RenderingDevice, splats_rid: RID, slot_stride: int, snapshot: Dictionary) -> void:
	var slot_base: int = int(snapshot.get("slot_base", 0))
	var directory_base: int = int(snapshot.get("directory_base", slot_base))
	# Moves first: an eviction swaps the last slot into the freed one, and a
	# later upload may target that same slot. Applying them out of order would
	# copy stale bytes over the freshly arrived node.
	for move in snapshot.get("moves", []):
		var src: int = int(state.stream_base_bytes) + (slot_base + int(move["src"])) * slot_stride
		var dst: int = int(state.stream_base_bytes) + (slot_base + int(move["dst"])) * slot_stride
		var bytes: int = int(move["bytes"])
		if not state.descriptors.has("stream_move_staging"):
			var staging_bytes := maxi(1, slot_stride)
			state.descriptors["stream_move_staging"] = state.context.create_storage_buffer(staging_bytes)
			state.declared_bytes += staging_bytes
		var staging: RID = state.descriptors["stream_move_staging"].rid
		device.buffer_copy(splats_rid, staging, src, 0, bytes)
		device.buffer_copy(staging, splats_rid, 0, dst, bytes)
	for upload in snapshot.get("uploads", []):
		var bytes: PackedByteArray = upload["bytes"]
		if bytes.is_empty():
			continue
		var dst: int = int(state.stream_base_bytes) + (slot_base + int(upload["slot"])) * slot_stride
		device.buffer_update(splats_rid, dst, bytes.size(), bytes)

	var info: PackedInt32Array = snapshot.get("slot_info", PackedInt32Array())
	var count := mini(info.size() / SLOT_INFO_WORDS, state.stream_arena_slots - directory_base)
	if count <= 0:
		return
	var words := count * SLOT_INFO_WORDS
	var packed := info.slice(0, words).to_byte_array()
	device.buffer_update(state.descriptors["slot_info"].rid,
		directory_base * SLOT_INFO_WORDS * 4, packed.size(), packed)
	for i in words:
		state.stream_slot_info[directory_base * SLOT_INFO_WORDS + i] = info[i]

func _refresh_stream_totals(state) -> void:
	var resident := 0
	var used := 0
	for runtime in state.stream_runtimes:
		if runtime == null:
			continue
		resident += int(runtime.resident_splats())
		used = maxi(used, int(runtime.slot_base) + int(runtime.active_slots()))
	state.stream_resident_splats = resident
	state.stream_used_slots = used

## gsplat-stream: the projection pass must cover exactly the resident points.
## Writing the indirect dispatch dimensions here keeps the CPU/GPU agreement in
## one place instead of duplicating the arithmetic in the renderer.
func write_projection_dims(state, point_count: int) -> void:
	if state.context == null:
		return
	# With an arena the GPU dispatch pre-pass owns projection_dims (resident
	# count); a CPU write here would race it back to the padded width.
	if state.stream_enabled:
		return
	var width: int = point_count
	var dims := PackedInt32Array([maxi(1, ceili(width / 256.0)), 1, 1])
	state.context.device.buffer_update(state.descriptors["projection_dims"].rid, 0, 12, dims.to_byte_array())

func upload_instance_transforms(state, instance_transforms_byte: PackedByteArray) -> void:
	if state.context == null or instance_transforms_byte.is_empty():
		return
	state.context.device.buffer_update(state.descriptors["instance_transforms"].rid, 0, instance_transforms_byte.size(), instance_transforms_byte)
	state.needs_instance_upload = false

## The baked per-splat records travel with the splat data (they change only when
## the scene's resources do), while the light rig and per-instance knobs move on
## their own cadence, so they upload separately.
func upload_splat_lighting(state, splat_lighting_byte: PackedByteArray) -> void:
	if state.context == null or splat_lighting_byte.is_empty():
		return
	state.context.device.buffer_update(state.descriptors["splat_lighting"].rid, 0, splat_lighting_byte.size(), splat_lighting_byte)

func upload_relight(state, light_rig_byte: PackedByteArray, instance_relight_byte: PackedByteArray) -> void:
	if state.context == null:
		return
	if not light_rig_byte.is_empty():
		state.context.device.buffer_update(state.descriptors["light_rig"].rid, 0, light_rig_byte.size(), light_rig_byte)
	if not instance_relight_byte.is_empty():
		state.context.device.buffer_update(state.descriptors["instance_relight"].rid, 0, instance_relight_byte.size(), instance_relight_byte)
	state.needs_relight_upload = false

func cleanup_state(state) -> void:
	if state == null:
		return
	if state.context != null:
		state.context.free()
		state.context = null
	state.shaders.clear()
	state.pipelines.clear()
	state.descriptors.clear()
	# Uniform sets must disappear before their borrowed buffers are released.
	state.shared_workspace = null
	state.declared_bytes = 0
	state.frame_cache_valid = false
	state.needs_gpu_rebuild = true
	state.needs_splat_upload = true
	state.needs_instance_upload = true
	state.needs_relight_upload = true

func cleanup_all() -> void:
	for state in _render_states.values():
		cleanup_state(state)
	_render_states.clear()
	_render_state_lru.clear()
	_workspaces.clear()
	_pending_gpu_cleanup = false

func _touch_render_state(texture_size: Vector2i) -> void:
	var existing_index := _render_state_lru.find(texture_size)
	if existing_index != -1:
		_render_state_lru.remove_at(existing_index)
	_render_state_lru.push_back(texture_size)

func _enforce_render_state_cache_limit() -> void:
	while _render_state_lru.size() > MAX_RENDER_STATES:
		var stale_size = _render_state_lru[0]
		_render_state_lru.remove_at(0)
		var stale_state = _render_states.get(stale_size, null)
		if stale_state != null:
			cleanup_state(stale_state)
			_render_states.erase(stale_size)
