@tool
extends RefCounted
class_name GaussianSceneRegistry

const FLOATS_PER_SPLAT := 60
const BYTES_PER_FLOAT := 4
# Relighting: one baked record per splat (oct normal, AO, confidence) and two
# vec4 of per-instance knobs. Must match gsplat_projection.glsl.
const LIGHTING_BYTES_PER_SPLAT := 4
const RELIGHT_FLOATS_PER_INSTANCE := 8

class NodeEntry:
	extends RefCounted

	var point_count := 0
	var instance_index := -1
	var point_data_byte := PackedByteArray()
	var lighting_byte := PackedByteArray()
	var model_transform: Transform3D = Transform3D.IDENTITY
	var visible: bool = true
	var has_lighting := false
	# gsplat-stream packed layout metadata (per resource).
	var packed_enabled := false
	var packed_stride_words := 0
	var sh_degree := 3
	var sh_scale := 1.0

var _splat_nodes: Array[Node] = []
var _node_entries: Dictionary = {}

# --- gsplat-stream: streaming sources ---------------------------------------
# A stream node owns an octree pack whose payloads live on disk. Its splats are
# not merged into `_point_data_byte`; they occupy a fixed-size slot arena that
# the state cache appends after the canonical data. The registry only hands out
# instance indices and transforms for them, plus the arena geometry.
var _stream_nodes: Array[Node] = []
var _stream_instance_base := 0
var _stream_instance_count := 0
var _stream_capacity_splats := 0
var _stream_slot_splats := 0
var _stream_arena_slots := 0
var _stream_payload_slots := 0
## Arena record geometry. Independent of the canonical packed layout: a q24 pack
## (24 B/splat) can stream next to a 52 B canonical resource.
var _stream_stride_words := 0
var _stream_layout := 0
var _stream_runtimes: Array = []
var _stream_transforms: Array = []
var _stream_node_ranges: Dictionary = {}

var _point_count := 0
var _point_data_byte := PackedByteArray()
var _splat_lighting_byte := PackedByteArray()
var _splat_instance_ids_byte := PackedByteArray()
var _instance_count := 0
var _instance_transforms_byte := PackedByteArray()
var _instance_relight_byte := PackedByteArray()
# gsplat-stream: merged packed-layout metadata. The Compute backend merges the
# unique resources into one buffer, so every packed resource must agree on the
# stride and SH degree; a mismatch disables the packed path for the whole scene.
var _packed_enabled := false
var _packed_stride_words := 0
var _sh_degree := 3
var _sh_scale := 1.0
# The light rig is produced on the main thread and parked here so the renderer,
# which runs on the rendering thread, only ever uploads bytes.
var _light_rig_byte := PackedByteArray()
var _light_count := 0

func register_splat_node(node: Node) -> Dictionary:
	if node == null or _splat_nodes.has(node):
		return {}
	_splat_nodes.push_back(node)
	return _sync_scene_resources(true)

func unregister_splat_node(node: Node) -> Dictionary:
	_splat_nodes.erase(node)
	return _sync_scene_resources(true)

## gsplat-stream: register a node backed by a disk-resident LOD pack.
func register_stream_node(node: Node) -> Dictionary:
	if node == null or _stream_nodes.has(node):
		return {}
	_stream_nodes.push_back(node)
	return _sync_scene_resources(true)

func unregister_stream_node(node: Node) -> Dictionary:
	_stream_nodes.erase(node)
	return _sync_scene_resources(true)

func has_stream_sources() -> bool:
	return _stream_instance_count > 0 and _stream_capacity_splats > 0

func get_stream_instance_base() -> int:
	return _stream_instance_base

func get_stream_instance_count() -> int:
	return _stream_instance_count

func get_stream_capacity_splats() -> int:
	return _stream_capacity_splats

func get_stream_projection_capacity_splats() -> int:
	return _stream_arena_slots * _stream_slot_splats

func get_stream_slot_splats() -> int:
	return _stream_slot_splats

func get_stream_stride_words() -> int:
	return _stream_stride_words

## 0 = float32 packed record, 1 = q24 (node-relative int16 + bf16 covariance).
func get_stream_layout() -> int:
	return _stream_layout

func get_stream_arena_slots() -> int:
	return _stream_arena_slots

func get_stream_runtimes() -> Array:
	return _stream_runtimes

func mark_resource_dirty(node: Node) -> Dictionary:
	if node == null:
		return {}
	return _sync_scene_resources(false)

func mark_transform_dirty(node: Node) -> Dictionary:
	if node == null:
		return {}
	return _sync_node_transform(node)

func has_gpu_data() -> bool:
	if _point_count > 0 and not _point_data_byte.is_empty():
		return true
	return has_stream_sources()

func get_point_count() -> int:
	return _point_count

func get_point_data_byte() -> PackedByteArray:
	return _point_data_byte

func get_splat_instance_ids_byte() -> PackedByteArray:
	return _splat_instance_ids_byte

func get_instance_count() -> int:
	return _instance_count

func get_instance_transforms_byte() -> PackedByteArray:
	return _instance_transforms_byte

func get_splat_lighting_byte() -> PackedByteArray:
	return _splat_lighting_byte

func get_instance_relight_byte() -> PackedByteArray:
	return _instance_relight_byte

func get_light_rig_byte() -> PackedByteArray:
	return _light_rig_byte

func get_light_count() -> int:
	return _light_count

## gsplat-stream packed-layout getters. When `get_packed_enabled()` is false the
## backend must use the canonical 60-float record.
func get_packed_enabled() -> bool:
	return _packed_enabled

func get_packed_stride_words() -> int:
	return _packed_stride_words

func get_sh_degree() -> int:
	return _sh_degree

func get_sh_scale() -> float:
	return _sh_scale

## Main-thread tick from the render manager: parks the freshly packed light rig
## and re-reads every node's relight knobs. Returns true when the renderer needs
## to re-upload, which is only when something actually changed.
func refresh_relight(light_rig_byte: PackedByteArray, light_count: int) -> bool:
	var changed := false
	if light_count != _light_count or light_rig_byte != _light_rig_byte:
		_light_rig_byte = light_rig_byte
		_light_count = light_count
		changed = true
	var relight := _build_instance_relight_byte()
	if relight != _instance_relight_byte:
		_instance_relight_byte = relight
		changed = true
	return changed

func _sync_scene_resources(force_rebuild: bool) -> Dictionary:
	_prune_splat_nodes()

	var next_entries: Dictionary = {}
	var merged_point_data := PackedByteArray()
	var merged_lighting := PackedByteArray()
	var merged_instance_ids := PackedInt32Array()
	var merged_instance_transforms := PackedFloat32Array()
	var total_point_count := 0
	var next_instance_index := 0

	# Keep track of which resources we've already packed into the raw VRAM buffer
	var unique_resources := {}
	# The baked lighting records ride alongside the splat data under the same
	# unique index, so instanced nodes share one upload. A bake is a function of
	# the GaussianResource, so nodes sharing a resource are expected to share a
	# bake; if they disagree the first one wins and the conflict is reported.
	var unique_lighting := {}
	# gsplat-stream: the merged buffer has one stride, so every accepted entry
	# must agree on layout. `null` until the first accepted splat node.
	var merged_layout = null
	var merged_sh_scale := 1.0

	for node in _splat_nodes:
		if not is_instance_valid(node):
			continue

		var entry := _build_node_entry(node, next_instance_index)
		if entry.point_count <= 0:
			continue

		# Reject a node whose record layout does not match the merged buffer's.
		var layout := [entry.packed_enabled, entry.packed_stride_words, entry.sh_degree]
		if merged_layout == null:
			merged_layout = layout
			merged_sh_scale = entry.sh_scale
		elif layout != merged_layout:
			push_warning(
				"[gdgs] compute: skipping a splat node whose record layout (packed=%s, stride=%d, sh_degree=%d) "
				% [str(entry.packed_enabled), entry.packed_stride_words, entry.sh_degree]
				+ "differs from the scene's already-merged layout (packed=%s, stride=%d, sh_degree=%d)."
				% [str(merged_layout[0]), int(merged_layout[1]), int(merged_layout[2])]
			)
			continue

		next_entries[node.get_instance_id()] = entry

		var gaussian: Resource = node.get("gaussian")
		var resource_start_index: int
		var bytes_per_splat := entry.packed_stride_words * BYTES_PER_FLOAT if entry.packed_enabled \
			else FLOATS_PER_SPLAT * BYTES_PER_FLOAT
		
		# Only upload the splat data if we haven't seen this resource yet
		if not unique_resources.has(gaussian):
			resource_start_index = merged_point_data.size() / bytes_per_splat
			unique_resources[gaussian] = resource_start_index
			unique_lighting[gaussian] = entry.has_lighting
			merged_point_data.append_array(entry.point_data_byte)
			merged_lighting.append_array(entry.lighting_byte)
		else:
			# If we already uploaded it, just get the index where it lives in the GPU buffer
			resource_start_index = unique_resources[gaussian]
			if entry.has_lighting and not bool(unique_lighting[gaussian]):
				push_warning(
					"[gdgs] compute: instanced nodes share a GaussianResource but only some "
					+ "carry a lighting bake; the first node's bake is used for all of them"
				)

		# Build the indirection array for this specific node (2 integers per point)
		var node_instance_ids := PackedInt32Array()
		node_instance_ids.resize(entry.point_count * 2) 
		for i in range(entry.point_count):
			node_instance_ids[i * 2] = next_instance_index          # x: Which transform matrix to use
			node_instance_ids[i * 2 + 1] = resource_start_index + i # y: Which raw splat data to read

		merged_instance_ids.append_array(node_instance_ids)
		merged_instance_transforms.append_array(_transform_to_column_major_packed_floats(entry.model_transform, entry.visible))

		total_point_count += entry.point_count
		next_instance_index += 1
	
	# --- gsplat-stream: streaming sources ------------------------------------
	# They take the instance indices after the canonical nodes and must share the
	# merged buffer's record layout, because the arena is appended to the same
	# GPU buffer with one stride.
	_prune_stream_nodes()
	var previous_stream_capacity := _stream_capacity_splats
	var previous_stream_slots := _stream_arena_slots
	var previous_stream_slot_splats := _stream_slot_splats
	var previous_stream_base := _stream_instance_base
	_stream_instance_base = next_instance_index
	_stream_instance_count = 0
	_stream_capacity_splats = 0
	_stream_slot_splats = 0
	_stream_arena_slots = 0
	_stream_payload_slots = 0
	_stream_stride_words = 0
	_stream_layout = 0
	_stream_runtimes = []
	_stream_transforms = []
	_stream_node_ranges.clear()
	for node in _stream_nodes:
		var stream_pack: Resource = node.get("stream_pack")
		var stream_runtime: RefCounted = node.get_stream_runtime()
		if stream_pack == null or stream_runtime == null or not bool(stream_pack.call("is_loaded")):
			continue
		var models := _get_stream_transforms(node)
		if models.is_empty():
			continue
		# The arena decodes its own records, so only the SH degree and scale have
		# to agree with the canonical data for colours to match; the stride and
		# encoding may differ (that is what q24 buys).
		var stream_degree := int(stream_pack.get("sh_degree"))
		var stream_stride_words := int(stream_pack.get("stride_words"))
		var stream_layout := 1 if bool(stream_pack.call("is_quantized")) else 0
		if merged_layout != null and int(merged_layout[2]) != stream_degree:
			push_warning(
				"[gdgs] compute: skipping a stream node whose SH degree (%d) "
				% stream_degree
				+ "differs from the scene's merged degree (%d)" % int(merged_layout[2])
			)
			continue
		if merged_layout == null:
			merged_layout = [true, stream_stride_words, stream_degree]
			merged_sh_scale = float(stream_pack.get("sh_scale"))
		elif stream_layout == 0 and int(merged_layout[1]) != stream_stride_words:
			# A float32 arena record is decoded with the canonical stride, so it
			# can only sit next to data that uses that same stride.
			push_warning(
				"[gdgs] compute: skipping a float32 stream node with a %d B record next to "
				% (stream_stride_words * 4)
				+ "a %d B canonical layout" % (int(merged_layout[1]) * 4)
			)
			continue
		if _stream_stride_words == 0:
			_stream_stride_words = stream_stride_words
			_stream_layout = stream_layout
		elif _stream_stride_words != stream_stride_words or _stream_layout != stream_layout:
			push_warning(
				"[gdgs] compute: skipping a stream node with a %d B q24=%d record; "
				% [stream_stride_words * 4, stream_layout]
				+ "the scene already streams %d B q24=%d records"
				% [_stream_stride_words * 4, _stream_layout]
			)
			continue
		# All sources share one slot stride. Use the largest actual payload,
		# including partially filled packs and packs built with different caps.
		_stream_slot_splats = maxi(_stream_slot_splats, int(stream_pack.get("max_node_splats")))
		var slots := int(stream_runtime.call("capacity_slots"))
		stream_runtime.set_gpu_binding(next_instance_index, _stream_payload_slots, _stream_arena_slots)
		_stream_node_ranges[node.get_instance_id()] = Vector2i(_stream_instance_count, models.size())
		for model in models:
			var stream_transform := _transform_to_column_major_packed_floats(
				model, _get_node_visibility(node))
			merged_instance_transforms.append_array(stream_transform)
			_stream_transforms.append(stream_transform)
		_stream_runtimes.append(stream_runtime)
		_stream_arena_slots += int(stream_runtime.directory_slots())
		_stream_payload_slots += slots
		_stream_instance_count += models.size()
		next_instance_index += models.size()
	_stream_capacity_splats = _stream_payload_slots * _stream_slot_splats

	_node_entries = next_entries

	var merged_instance_ids_byte := merged_instance_ids.to_byte_array()
	var merged_instance_transforms_byte := merged_instance_transforms.to_byte_array()
	if (total_point_count <= 0 or merged_point_data.is_empty()) and _stream_instance_count <= 0:
		_point_count = 0
		_point_data_byte = PackedByteArray()
		_splat_lighting_byte = PackedByteArray()
		_splat_instance_ids_byte = PackedByteArray()
		_instance_count = 0
		_instance_transforms_byte = PackedByteArray()
		_instance_relight_byte = PackedByteArray()
		_packed_enabled = false
		_packed_stride_words = 0
		_sh_degree = 3
		_sh_scale = 1.0
		return _change_result(true, false, false, false)

	var count_changed := total_point_count != _point_count
	var point_data_size_changed := merged_point_data.size() != _point_data_byte.size()
	var instance_ids_size_changed := merged_instance_ids_byte.size() != _splat_instance_ids_byte.size()
	var instance_count_changed := next_instance_index != _instance_count
	var instance_transforms_size_changed := merged_instance_transforms_byte.size() != _instance_transforms_byte.size()
	var stream_geometry_changed := _stream_capacity_splats != previous_stream_capacity \
		or _stream_arena_slots != previous_stream_slots \
		or _stream_slot_splats != previous_stream_slot_splats \
		or _stream_instance_base != previous_stream_base

	_point_count = total_point_count
	_point_data_byte = merged_point_data
	_splat_lighting_byte = merged_lighting
	_splat_instance_ids_byte = merged_instance_ids_byte
	_instance_count = next_instance_index
	_instance_transforms_byte = merged_instance_transforms_byte
	_instance_relight_byte = _build_instance_relight_byte()

	# gsplat-stream: publish the merged packed-layout metadata.
	_packed_enabled = merged_layout != null and bool(merged_layout[0])
	_packed_stride_words = int(merged_layout[1]) if merged_layout != null else 0
	_sh_degree = int(merged_layout[2]) if merged_layout != null else 3
	_sh_scale = merged_sh_scale

	return _change_result(
		false,
		force_rebuild or count_changed or point_data_size_changed or instance_ids_size_changed or instance_count_changed or instance_transforms_size_changed or stream_geometry_changed,
		true,
		true
	)

func _sync_node_transform(node: Node) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {}
	if _stream_node_ranges.has(node.get_instance_id()):
		var span: Vector2i = _stream_node_ranges[node.get_instance_id()]
		var models := _get_stream_transforms(node)
		if models.size() != span.y:
			return _sync_scene_resources(false)
		var changed := false
		for i in models.size():
			var packed := _transform_to_column_major_packed_floats(models[i], _get_node_visibility(node))
			if _stream_transforms[span.x + i] != packed:
				_stream_transforms[span.x + i] = packed
				changed = true
		if not changed:
			return {}
		_instance_transforms_byte = _build_instance_transforms_byte()
		return _change_result(false, false, false, true)

	var entry: NodeEntry = _node_entries.get(node.get_instance_id(), null)
	if entry == null:
		return _sync_scene_resources(false)

	var model_transform := _get_node_transform(node)
	var model_visible := _get_node_visibility(node)
	if entry.model_transform == model_transform and entry.visible == model_visible:
		return {}

	entry.model_transform = model_transform
	entry.visible = model_visible
	if entry.instance_index < 0 or _instance_count <= 0:
		return {}

	var instance_transforms_byte := _build_instance_transforms_byte()
	var size_changed := instance_transforms_byte.size() != _instance_transforms_byte.size()
	_instance_transforms_byte = instance_transforms_byte

	return _change_result(false, size_changed, false, true)

func _build_node_entry(node: Node, instance_index: int) -> NodeEntry:
	var entry := NodeEntry.new()
	entry.model_transform = _get_node_transform(node)
	entry.visible = _get_node_visibility(node)

	var gaussian: Resource = node.get("gaussian")
	if gaussian == null:
		return entry

	var point_count := int(gaussian.get("point_count"))
	var point_data: PackedByteArray = gaussian.get("point_data_byte")
	if point_count <= 0 or point_data.is_empty():
		return entry

	# gsplat-stream: accept either the canonical 60-float record or the packed
	# core+quantized-SH record, and remember which one this resource uses.
	var packed_enabled := bool(gaussian.get("packed_enabled"))
	var stride_words := int(gaussian.get("packed_stride_words"))
	if packed_enabled and stride_words > 0:
		var expected_packed := point_count * stride_words * BYTES_PER_FLOAT
		if point_data.size() != expected_packed:
			push_warning(
				"[gdgs] Packed GaussianResource size mismatch. Expected %d, got %d bytes."
				% [expected_packed, point_data.size()]
			)
			return entry
		entry.packed_enabled = true
		entry.packed_stride_words = stride_words
		entry.sh_degree = int(gaussian.get("sh_degree"))
		entry.sh_scale = float(gaussian.get("sh_scale"))
	else:
		var expected_size := point_count * FLOATS_PER_SPLAT * BYTES_PER_FLOAT
		if point_data.size() != expected_size:
			push_warning("[gdgs] GaussianResource data size mismatch. Expected %d, got %d bytes." % [expected_size, point_data.size()])
			return entry

	entry.point_count = point_count
	entry.instance_index = instance_index
	entry.point_data_byte = point_data
	entry.lighting_byte = _build_lighting_byte(node, point_count)
	entry.has_lighting = entry.lighting_byte.size() == point_count * LIGHTING_BYTES_PER_SPLAT and _node_has_bake(node)
	return entry

## The node's baked per-splat records, or a zero-filled block of the right size
## when there is no usable bake. The buffer must stay parallel to the splat
## data either way; the per-instance `enabled` flag is what actually gates
## relighting, so zeros are never read.
func _build_lighting_byte(node: Node, point_count: int) -> PackedByteArray:
	var expected := point_count * LIGHTING_BYTES_PER_SPLAT
	var lighting: Variant = node.get("lighting")
	if lighting != null and is_instance_valid(lighting) and lighting is Resource:
		var resource := lighting as Resource
		if resource.has_method("is_splat_data_valid") and bool(resource.call("is_splat_data_valid")):
			if int(resource.get("source_point_count")) == point_count:
				var data: PackedByteArray = resource.get("splat_data")
				if data.size() == expected:
					return data
			else:
				push_warning(
					"[gdgs] compute: lighting bake is for %d splats but the resource has %d; rebake it"
					% [int(resource.get("source_point_count")), point_count]
				)
	var empty := PackedByteArray()
	empty.resize(expected)
	return empty

func _node_has_bake(node: Node) -> bool:
	var lighting: Variant = node.get("lighting")
	if lighting == null or not is_instance_valid(lighting) or not (lighting is Resource):
		return false
	var resource := lighting as Resource
	return resource.has_method("is_splat_data_valid") and bool(resource.call("is_splat_data_valid"))

## Two vec4 per instance, in instance order:
##   [0] unlit level, light gain, DC-only flag, enabled flag
##   [1] ambient rgb, unused
func _build_instance_relight_byte() -> PackedByteArray:
	if _instance_count <= 0:
		return PackedByteArray()
	var packed := PackedFloat32Array()
	for node in _splat_nodes:
		if not is_instance_valid(node):
			continue
		var entry: NodeEntry = _node_entries.get(node.get_instance_id(), null)
		if entry == null or entry.point_count <= 0 or entry.instance_index < 0:
			continue
		var enabled := entry.has_lighting and bool(node.get("relight_enabled"))
		var ambient: Color = node.get("relight_ambient")
		packed.append_array(PackedFloat32Array([
			float(node.get("relight_unlit_level")),
			float(node.get("relight_light_gain")),
			1.0 if bool(node.get("relight_dc_only")) else 0.0,
			1.0 if enabled else 0.0,
			ambient.r, ambient.g, ambient.b, 0.0,
		]))
	# Streaming instances carry unlit RGBA tint records, never a lighting bake.
	# Pad any unused canonical records before emitting their negative sentinel.
	var disabled := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	while packed.size() < _stream_instance_base * RELIGHT_FLOATS_PER_INSTANCE:
		packed.append_array(disabled)
	for node in _stream_nodes:
		if not is_instance_valid(node) or not _stream_node_ranges.has(node.get_instance_id()):
			continue
		var span: Vector2i = _stream_node_ranges[node.get_instance_id()]
		var colors: PackedColorArray = node.get_stream_instance_colors() \
			if node.has_method("get_stream_instance_colors") else PackedColorArray()
		for i in span.y:
			var tint := colors[i] if i < colors.size() else Color.WHITE
			# Negative enabled is an unlit stream colour record. The existing
			# two-vec4 layout carries RGBA without another buffer or point copy.
			packed.append_array(PackedFloat32Array([0.0, 0.0, 0.0, -1.0,
				tint.r, tint.g, tint.b, tint.a]))
	return packed.to_byte_array()

func _get_stream_transforms(node: Node) -> Array[Transform3D]:
	if node.has_method("get_stream_instance_transforms"):
		return node.get_stream_instance_transforms()
	return [_get_node_transform(node)]

func _build_instance_transforms_byte() -> PackedByteArray:
	if _instance_count <= 0:
		return PackedByteArray()

	var transforms := PackedFloat32Array()
	for node in _splat_nodes:
		if not is_instance_valid(node):
			continue
		var entry: NodeEntry = _node_entries.get(node.get_instance_id(), null)
		if entry == null or entry.point_count <= 0 or entry.instance_index < 0:
			continue
		transforms.append_array(_transform_to_column_major_packed_floats(entry.model_transform, entry.visible))
	for stream_transform in _stream_transforms:
		transforms.append_array(stream_transform)
	return transforms.to_byte_array()

func _get_node_transform(node: Node) -> Transform3D:
	if node is Node3D:
		return (node as Node3D).global_transform
	return Transform3D.IDENTITY
	
func _get_node_visibility(node: Node) -> bool:
	if node is Node3D:
		return (node as Node3D).is_visible_in_tree()
	return true

func _transform_to_column_major_packed_floats(transform: Transform3D, visibility: bool) -> PackedFloat32Array:
	return PackedFloat32Array([
		transform.basis.x[0], transform.basis.x[1], transform.basis.x[2], 1.0 if visibility else 0.0,
		transform.basis.y[0], transform.basis.y[1], transform.basis.y[2], 0.0,
		transform.basis.z[0], transform.basis.z[1], transform.basis.z[2], 0.0,
		transform.origin.x, transform.origin.y, transform.origin.z, 1.0
	])

func _prune_splat_nodes() -> void:
	for i in range(_splat_nodes.size() - 1, -1, -1):
		if not is_instance_valid(_splat_nodes[i]):
			_splat_nodes.remove_at(i)

func _prune_stream_nodes() -> void:
	for i in range(_stream_nodes.size() - 1, -1, -1):
		if not is_instance_valid(_stream_nodes[i]):
			_stream_nodes.remove_at(i)

func _change_result(
	request_cleanup: bool,
	require_gpu_rebuild: bool,
	require_splat_upload: bool,
	require_instance_upload: bool
) -> Dictionary:
	return {
		"request_cleanup": request_cleanup,
		"require_gpu_rebuild": require_gpu_rebuild,
		"require_splat_upload": require_splat_upload,
		"require_instance_upload": require_instance_upload
	}
