@tool
extends RefCounted

## VRAM planner for the Compute backend (gsplat-stream addition).
##
## Mirrors the buffer allocation in gaussian_gpu_state_cache.rebuild_gpu_state()
## so the memory cost of a configuration can be computed on the CPU, in tests,
## and in tooling — without creating a RenderingDevice or a window.
##
## Every number here corresponds to one `create_storage_buffer` /
## `create_uniform_buffer` / `create_texture` call in that file. If that file's
## allocation changes, this file must change with it.
##
## Usage:
##   var plan := MemoryPlan.compute(6_000_000, 10, 2, Vector2i(1920, 1080), 1)
##   print(MemoryPlan.format_table(plan))

const TILE_SIZE := 16
const WORKGROUP_SIZE := 512
const RADIX := 256
const PARTITION_DIVISION := 8
const PARTITION_SIZE := PARTITION_DIVISION * WORKGROUP_SIZE  # 4096
const BYTES_PER_FLOAT := 4

## Canonical (unquantized) GPU record: 60 float32.
const CANONICAL_FLOATS_PER_SPLAT := 60
## Projected-splat record: 12 float32 (RasterizeData).
const FLOATS_PER_CULLED_SPLAT := 12
## One RGBA8 relight record per unique splat.
const LIGHTING_BYTES_PER_SPLAT := 4
## Per-instance relight: two vec4.
const RELIGHT_FLOATS_PER_INSTANCE := 8
## Light rig: 8 lights x 4 vec4.
const LIGHT_RIG_FLOATS := 8 * 16
## (instance, unique splat) pair.
const INSTANCE_ID_BYTES_PER_SPLAT := 8
## mat4 per instance.
const INSTANCE_TRANSFORM_FLOATS := 16

## Bytes of one sort element: uint32 key + uint32 value.
const SORT_ELEMENT_BYTES := 8
## Radix ping-pong keeps two halves of each sort buffer alive.
const SORT_BUFFER_HALVES := 2

## SH strides copied from gaussian_sh_quantizer (kept local so this planner has
## no runtime dependency).
const SH_STRIDE_PER_DEGREE := [4, 12, 28, 48]
const CORE_BYTES_PER_SPLAT := 48  # position(12) + opacity(4) + covariance(24) + pad(8)


static func clamp_degree(degree: int) -> int:
	return clampi(degree, 0, 3)


## Bytes per splat of the `splats` buffer.
##   degree < 0 -> canonical 240 B layout (the unmodified GDGS format)
##   degree >= 0 -> quantized core (48 B) + 8-bit SH payload
static func splat_bytes_per_splat(degree: int) -> int:
	if degree < 0:
		return CANONICAL_FLOATS_PER_SPLAT * BYTES_PER_FLOAT
	return CORE_BYTES_PER_SPLAT + SH_STRIDE_PER_DEGREE[clamp_degree(degree)]


## Exact VRAM footprint for one render state.
##
## point_count          splats submitted (before culling)
## max_splat_elements   MAX_SORT_ELEMENTS_PER_SPLAT (worst-case tiles per splat)
## degree               SH degree, or -1 for the canonical 240 B layout
## texture_size         offscreen colour/depth target size
## instance_count       GaussianSplatNode instances sharing this state
##
## Returns a Dictionary with a per-buffer byte breakdown and totals.
static func compute(
	point_count: int,
	max_splat_elements: int,
	degree: int,
	texture_size: Vector2i,
	instance_count: int = 1,
	culled_fraction: float = 1.0
) -> Dictionary:
	var n := maxi(point_count, 0)
	var inst := maxi(instance_count, 1)
	var max_elements := maxi(max_splat_elements, 1)
	var culled_entries := int(ceil(float(n) * clampf(culled_fraction, 0.0, 1.0)))
	var w := maxi(texture_size.x, 1)
	var h := maxi(texture_size.y, 1)

	var tiles_x := int(ceil(w / float(TILE_SIZE)))
	var tiles_y := int(ceil(h / float(TILE_SIZE)))
	var tile_count := tiles_x * tiles_y

	var sort_elements := n * max_elements
	var num_partitions := int(ceil(sort_elements / float(PARTITION_SIZE)))

	var buffers := {}
	buffers["splats"] = n * splat_bytes_per_splat(degree)
	buffers["splat_lighting"] = n * LIGHTING_BYTES_PER_SPLAT
	buffers["light_rig"] = LIGHT_RIG_FLOATS * BYTES_PER_FLOAT
	buffers["instance_relight"] = inst * RELIGHT_FLOATS_PER_INSTANCE * BYTES_PER_FLOAT
	buffers["culled_splats"] = culled_entries * FLOATS_PER_CULLED_SPLAT * BYTES_PER_FLOAT
	buffers["grid_dimensions"] = 6 * 4
	buffers["histogram"] = 4 + (1 + 4 * RADIX + num_partitions * RADIX) * 4
	buffers["sort_keys"] = sort_elements * SORT_ELEMENT_BYTES / 2 * SORT_BUFFER_HALVES
	buffers["sort_values"] = sort_elements * SORT_ELEMENT_BYTES / 2 * SORT_BUFFER_HALVES
	buffers["splat_instance_ids"] = n * INSTANCE_ID_BYTES_PER_SPLAT
	buffers["instance_transforms"] = inst * INSTANCE_TRANSFORM_FLOATS * BYTES_PER_FLOAT
	buffers["uniforms"] = 8 * BYTES_PER_FLOAT
	buffers["tile_bounds"] = tile_count * 2 * 4
	buffers["render_texture"] = w * h * 16
	buffers["depth_texture"] = w * h * 4

	var total := 0
	for key in buffers:
		total += int(buffers[key])

	# Per-splat costs, excluding the fixed-size and per-frame image targets.
	var fixed := int(buffers["light_rig"]) + int(buffers["grid_dimensions"]) \
		+ int(buffers["uniforms"]) \
		+ int(buffers["render_texture"]) + int(buffers["depth_texture"]) \
		+ int(buffers["tile_bounds"]) + int(buffers["instance_transforms"]) \
		+ int(buffers["instance_relight"]) + int(buffers["histogram"])

	return {
		"point_count": n,
		"instance_count": inst,
		"max_splat_elements": max_elements,
		"degree": degree,
		"splat_bytes_per_splat": splat_bytes_per_splat(degree),
		"sort_elements": sort_elements,
		"num_partitions": num_partitions,
		"tile_count": tile_count,
		"buffers": buffers,
		"total_bytes": total,
		"total_mb": total / (1024.0 * 1024.0),
		"per_splat_bytes": float(total - fixed) / float(maxi(n, 1)),
	}


## Human-readable one-block summary.
static func format_block(plan: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append(
		"N=%d  degree=%s  max_elem=%d  -> %.1f MB  (%.1f B/splat incl. sort/culled)"
		% [
			int(plan["point_count"]),
			"canonical" if int(plan["degree"]) < 0 else str(int(plan["degree"])),
			int(plan["max_splat_elements"]),
			float(plan["total_mb"]),
			float(plan["per_splat_bytes"]),
		]
	)
	var buffers: Dictionary = plan["buffers"]
	var keys: Array = buffers.keys()
	keys.sort()
	for key in keys:
		var bytes := int(buffers[key])
		if bytes < 1024:
			continue
		lines.append("    %-22s %10.2f MB" % [key, bytes / (1024.0 * 1024.0)])
	return "\n".join(lines)
