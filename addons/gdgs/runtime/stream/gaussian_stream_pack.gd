@tool
extends Resource
class_name GaussianStreamPack

## A streamable LOD pack produced by tools/build_stream_pack.py.
##
## The pack is an octree where every node stores a fixed-capacity representative
## sample of its subtree. Only the node table lives in memory; the splat records
## stay on disk in `nodes.bin` and are read on demand by GaussianStreamRuntime.
## That is what lets a 50M-splat world cost a few hundred MB of VRAM instead of
## several GB: the resident set is a few hundred nodes, not the whole cloud.
##
## Node table layout (16 numbers per node, see NODE_TABLE_STRIDE):
##   0..2  centre.xyz        3     half size (cube)
##   4     geometric error   5     byte offset into nodes.bin
##   6     stored splats     7     source splats in the subtree
##   8..15 child node indices, -1 when the octant is empty

const NODE_TABLE_STRIDE := 16
const CHILD_SLOT := 8

@export var manifest_path: String = ""

var stride_bytes: int = 0
var stride_words: int = 0
## Record encoding of the payload. "f32" is the packed builder's 52 B layout;
## "q24" stores node-relative int16 positions and bf16 covariance in 24 B, which
## is decoded by the projection shader with the slot's own centre and half-size.
var record_layout: String = "f32"
var sh_degree: int = 0
var sh_scale: float = 1.0
var node_cap: int = 0
## Largest payload actually stored by a node. A small pack can contain far
## fewer splats than the builder's advertised node_cap; size GPU slots from
## the table instead of paying for records that can never be loaded.
var max_node_splats: int = 0
var leaf_cap: int = 0
var root: int = -1
var node_count: int = 0
var source_splats: int = 0
var stored_splats: int = 0
var splat_radius: float = 0.0
var world_aabb: AABB = AABB()
var nodes_bin_path: String = ""

var centre_x := PackedFloat32Array()
var centre_y := PackedFloat32Array()
var centre_z := PackedFloat32Array()
var half_size := PackedFloat32Array()
var geometric_error := PackedFloat32Array()
var byte_offset := PackedInt64Array()
var splat_count := PackedInt32Array()
var source_count := PackedInt32Array()
## 8 entries per node, -1 for an empty octant.
var children := PackedInt32Array()
## Parent node index, -1 for the root. Derived from `children` at load time; the
## residency manager walks it to find the coarse ancestor that covers a node
## still being streamed in.
var parent := PackedInt32Array()

var _loaded := false


func is_loaded() -> bool:
	return _loaded


## The q24 layout decodes positions against the owning slot's node centre and
## half-size, so the GPU needs a wider slot directory for this pack.
func is_quantized() -> bool:
	return record_layout == "q24"


## Reads the manifest next to `path` (a .manifest.json, or a prefix without it).
func load_from(path: String) -> Error:
	_loaded = false
	max_node_splats = 0
	var manifest_file := path
	if not manifest_file.ends_with(".json"):
		manifest_file = path + ".manifest.json"
	if not FileAccess.file_exists(manifest_file):
		push_error("[gdgs] stream pack manifest not found: %s" % manifest_file)
		return ERR_FILE_NOT_FOUND

	var file := FileAccess.open(manifest_file, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("[gdgs] stream pack manifest is not a JSON object: %s" % manifest_file)
		return ERR_PARSE_ERROR
	var manifest: Dictionary = parsed

	if int(manifest.get("version", 0)) != 1:
		push_error("[gdgs] unsupported stream pack version in %s" % manifest_file)
		return ERR_INVALID_DATA

	stride_bytes = int(manifest.get("stride_bytes", 0))
	stride_words = int(manifest.get("stride_words", 0))
	record_layout = str(manifest.get("record_layout", "f32"))
	if record_layout != "f32" and record_layout != "q24":
		push_error("[gdgs] stream pack has an unknown record_layout: %s" % record_layout)
		return ERR_INVALID_DATA
	sh_degree = int(manifest.get("sh_degree", 0))
	sh_scale = float(manifest.get("sh_scale", 1.0))
	node_cap = int(manifest.get("node_cap", 0))
	leaf_cap = int(manifest.get("leaf_cap", node_cap))
	root = int(manifest.get("root", -1))
	node_count = int(manifest.get("node_count", 0))
	source_splats = int(manifest.get("source_splats", 0))
	stored_splats = int(manifest.get("stored_splats", 0))
	splat_radius = float(manifest.get("splat_radius", 0.0))
	if stride_bytes <= 0 or node_cap <= 0 or node_count <= 0 or root < 0:
		push_error("[gdgs] stream pack manifest is incomplete: %s" % manifest_file)
		return ERR_INVALID_DATA

	var bin_value: String = str(manifest.get("nodes_bin", ""))
	if bin_value.is_empty():
		push_error("[gdgs] stream pack manifest has no nodes_bin")
		return ERR_INVALID_DATA
	nodes_bin_path = _resolve_relative(manifest_file, bin_value)
	if not FileAccess.file_exists(nodes_bin_path):
		push_error("[gdgs] stream pack payload not found: %s" % nodes_bin_path)
		return ERR_FILE_NOT_FOUND

	var table: Array = manifest.get("node_table", [])
	if table.size() != node_count * NODE_TABLE_STRIDE:
		push_error("[gdgs] stream pack node table size mismatch: %d entries for %d nodes"
			% [table.size(), node_count])
		return ERR_INVALID_DATA

	centre_x.resize(node_count)
	centre_y.resize(node_count)
	centre_z.resize(node_count)
	half_size.resize(node_count)
	geometric_error.resize(node_count)
	byte_offset.resize(node_count)
	splat_count.resize(node_count)
	source_count.resize(node_count)
	children.resize(node_count * 8)

	for node in node_count:
		var base := node * NODE_TABLE_STRIDE
		centre_x[node] = float(table[base + 0])
		centre_y[node] = float(table[base + 1])
		centre_z[node] = float(table[base + 2])
		half_size[node] = float(table[base + 3])
		geometric_error[node] = float(table[base + 4])
		byte_offset[node] = int(float(table[base + 5]))
		splat_count[node] = int(float(table[base + 6]))
		max_node_splats = maxi(max_node_splats, splat_count[node])
		source_count[node] = int(float(table[base + 7]))
		for slot in 8:
			children[node * 8 + slot] = int(float(table[base + CHILD_SLOT + slot]))

	parent.resize(node_count)
	parent.fill(-1)
	for node in node_count:
		for slot in 8:
			var child := children[node * 8 + slot]
			if child >= 0 and child < node_count:
				parent[child] = node

	var min_value: Array = manifest.get("aabb_min", [0.0, 0.0, 0.0])
	var max_value: Array = manifest.get("aabb_max", [0.0, 0.0, 0.0])
	world_aabb = AABB(
		Vector3(float(min_value[0]), float(min_value[1]), float(min_value[2])),
		Vector3(float(max_value[0]) - float(min_value[0]),
				float(max_value[1]) - float(min_value[1]),
				float(max_value[2]) - float(min_value[2])))

	manifest_path = manifest_file
	_loaded = true
	return OK


func node_aabb(node: int) -> AABB:
	var half := half_size[node]
	return AABB(
		Vector3(centre_x[node] - half, centre_y[node] - half, centre_z[node] - half),
		Vector3(half * 2.0, half * 2.0, half * 2.0))


func node_centre(node: int) -> Vector3:
	return Vector3(centre_x[node], centre_y[node], centre_z[node])


func is_leaf(node: int) -> bool:
	for slot in 8:
		if children[node * 8 + slot] >= 0:
			return false
	return true


func payload_bytes(node: int) -> int:
	return splat_count[node] * stride_bytes


## The manifest stores an absolute path from the machine that built the pack.
## Prefer a sibling of the manifest so a pack stays movable between machines.
func _resolve_relative(manifest_file: String, bin_value: String) -> String:
	var sibling := manifest_file.get_basename().get_basename() + ".nodes.bin"
	if FileAccess.file_exists(sibling):
		return sibling
	var directory := manifest_file.get_base_dir()
	var name := bin_value.replace("\\", "/").get_file()
	var joined := directory.path_join(name)
	if FileAccess.file_exists(joined):
		return joined
	return bin_value
