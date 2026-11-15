extends RefCounted

## Builds a small synthetic stream pack on disk so the LOD/residency tests need
## neither the 4.9 GB benchmark pack nor a GPU. The record layout matches
## gaussian_packed_builder.gd (packed degree 0, 13 words / 52 bytes).

const STRIDE_WORDS := 13
const STRIDE_BYTES := 52
## q24: node-relative int16 position, opacity, degree, six bf16 covariances and
## the degree-0 SH block (24 B total).
const Q24_STRIDE_BYTES := 24
const NODE_TABLE_STRIDE := 16
const CHILD_SLOT := 8

## Writes a full octree of `depth` levels over [-half, half]^3.
## `quantized` writes the 24 B q24 layout instead of the 52 B float32 one.
## Returns the manifest path, or "" on failure.
static func build(prefix: String, depth: int, node_cap: int, half: float,
		quantized: bool = false) -> String:
	var nodes: Array = []
	_build_nodes(nodes, depth, node_cap, Vector3.ZERO, half, 0)

	var payload := PackedByteArray()
	var table: Array = []
	var leaf_source := 0
	for node in nodes:
		var centre: Vector3 = node["centre"]
		var node_half: float = node["half"]
		var error: float = 0.0 if node["leaf"] else node_half * 0.5
		var source: int = node_cap if node["leaf"] else int(node["source"])
		if node["leaf"]:
			leaf_source += source
		table.append_array([
			centre.x, centre.y, centre.z, node_half, error,
			float(payload.size()), float(node_cap), float(source),
		])
		for slot in 8:
			var child: int = node["children"][slot] if slot < node["children"].size() else -1
			table.append(float(child))
		payload.append_array(_records_q24(centre, node_half, node_cap) if quantized
			else _records(centre, node_half, node_cap))

	var manifest := {
		"version": 1,
		"record_layout": "q24" if quantized else "f32",
		"stride_bytes": Q24_STRIDE_BYTES if quantized else STRIDE_BYTES,
		"stride_words": Q24_STRIDE_BYTES / 4 if quantized else STRIDE_WORDS,
		"sh_degree": 0,
		"sh_scale": 0.05,
		"node_cap": node_cap,
		"leaf_cap": node_cap,
		"root": 0,
		"node_count": nodes.size(),
		"leaf_count": _count_leaves(nodes),
		"branch_count": nodes.size() - _count_leaves(nodes),
		"max_depth": depth,
		"source_splats": leaf_source,
		"stored_splats": nodes.size() * node_cap,
		"splat_radius": 0.01,
		"aabb_min": [-half, -half, -half],
		"aabb_max": [half, half, half],
		"centre": [0.0, 0.0, 0.0],
		"half_size": half,
		"nodes_bin": prefix.get_file() + ".nodes.bin",
		"nodes_bytes": payload.size(),
		"node_table": table,
	}

	var bin_path := prefix + ".nodes.bin"
	var bin := FileAccess.open(bin_path, FileAccess.WRITE)
	if bin == null:
		return ""
	bin.store_buffer(payload)
	bin.close()

	var json_path := prefix + ".manifest.json"
	var json := FileAccess.open(json_path, FileAccess.WRITE)
	if json == null:
		return ""
	json.store_string(JSON.stringify(manifest))
	json.close()
	return json_path


static func _build_nodes(nodes: Array, depth: int, node_cap: int, centre: Vector3, half: float, level: int) -> int:
	var index := nodes.size()
	var leaf := level >= depth
	nodes.append({
		"centre": centre,
		"half": half,
		"leaf": leaf,
		"children": [],
		"source": node_cap,
		"level": level,
	})
	if leaf:
		return index
	var child_half := half * 0.5
	var total := 0
	for octant in 8:
		var offset := Vector3(
			child_half if (octant & 1) != 0 else -child_half,
			child_half if (octant & 2) != 0 else -child_half,
			child_half if (octant & 4) != 0 else -child_half)
		var child := _build_nodes(nodes, depth, node_cap, centre + offset, child_half, level + 1)
		nodes[index]["children"].append(child)
		total += int(nodes[child]["source"])
	nodes[index]["source"] = total
	return index


static func _count_leaves(nodes: Array) -> int:
	var count := 0
	for node in nodes:
		if node["leaf"]:
			count += 1
	return count


## node_cap packed degree-0 records spread through the node's cube.
static func _records(centre: Vector3, half: float, node_cap: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(node_cap * STRIDE_BYTES)
	for i in node_cap:
		var base := i * STRIDE_BYTES
		# A deterministic spiral so every node's sample is distinct and the
		# eviction tests can tell payloads apart.
		var t := float(i) / float(maxi(node_cap - 1, 1))
		var angle := t * TAU * 3.0
		var position := centre + Vector3(
			cos(angle) * half * 0.6,
			(t * 2.0 - 1.0) * half * 0.6,
			sin(angle) * half * 0.6)
		bytes.encode_float(base + 0, position.x)
		bytes.encode_float(base + 4, position.y)
		bytes.encode_float(base + 8, position.z)
		# word 3: opacity byte | sh_degree byte | 2 pad bytes
		bytes.encode_u32(base + 12, 200 | (0 << 8))
		var covariance := 0.0004
		for c in 6:
			bytes.encode_float(base + 16 + c * 4, covariance if (c == 0 or c == 3 or c == 5) else 0.0)
		bytes.encode_u32(base + 40, 0)
		bytes.encode_u32(base + 44, 0)
		# SH DC term, quantized with bias 128.
		bytes[base + 48] = 140
		bytes[base + 49] = 138
		bytes[base + 50] = 136
		bytes[base + 51] = 0
	return bytes


## The same sample expressed as a 24 B q24 record.
static func _records_q24(centre: Vector3, half: float, node_cap: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(node_cap * Q24_STRIDE_BYTES)
	var scale := half / 32767.0
	for i in node_cap:
		var base := i * Q24_STRIDE_BYTES
		var t := float(i) / float(maxi(node_cap - 1, 1))
		var angle := t * TAU * 3.0
		var offset := Vector3(
			cos(angle) * half * 0.6,
			(t * 2.0 - 1.0) * half * 0.6,
			sin(angle) * half * 0.6)
		var q := (offset / scale).round()
		bytes.encode_s16(base + 0, int(q.x))
		bytes.encode_s16(base + 2, int(q.y))
		bytes.encode_s16(base + 4, int(q.z))
		bytes.encode_u8(base + 6, 200)
		bytes.encode_u8(base + 7, 0)
		var covariance := 0.0004
		for c in 6:
			bytes.encode_u16(base + 8 + c * 2,
				_bf16(covariance if (c == 0 or c == 3 or c == 5) else 0.0))
		bytes.encode_u32(base + 20, 140 | (138 << 8) | (136 << 16))
	return bytes


static func _bf16(value: float) -> int:
	var buffer := PackedByteArray()
	buffer.resize(4)
	buffer.encode_float(0, value)
	var bits := buffer.decode_u32(0)
	return ((bits + 0x7FFF + ((bits >> 16) & 1)) & 0xFFFF0000) >> 16