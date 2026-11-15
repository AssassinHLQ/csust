#[compute]
#version 460

#extension GL_KHR_shader_subgroup_arithmetic: enable
#extension GL_KHR_shader_subgroup_basic: enable
#extension GL_KHR_shader_subgroup_ballot: enable

#define SH_C0 0.28209479177387814
#define SH_C1 0.4886025119029199

#define SH_C2_0 1.0925484305920792
#define SH_C2_1 1.0925484305920792
#define SH_C2_2 0.31539156525252005
#define SH_C2_3 1.0925484305920792
#define SH_C2_4 0.5462742152960396

#define SH_C3_0 0.5900435899266435
#define SH_C3_1 2.890611442640554
#define SH_C3_2 0.4570457994644658
#define SH_C3_3 0.3731763325901154
#define SH_C3_4 0.4570457994644658
#define SH_C3_5 1.445305721320277
#define SH_C3_6 0.5900435899266435

#define NUM_BLOCKS_PER_WORKGROUP (32)
#define SORT_WORKGROUP_SIZE      (512)
#define SORT_PARTITION_DIVISION  (8)
#define SORT_PARTITION_SIZE      (SORT_PARTITION_DIVISION * SORT_WORKGROUP_SIZE)

#define DECODE_COVARIANCE(c) (mat3(c[0], c[1], c[2], c[1], c[3], c[4], c[2], c[4], c[5]))

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct Splat {
	vec3 position;
	float time;
	float covariance[6]; // Contains top triangle of symmetric matrix
	float opacity;
	float _pad;
	float sh_coefficients[16*3]; // Spherical harmonic coefficients in increasing order
};

// 48 B std430 stride. The upstream 64 B record carried world pos_xy/pos_z for
// a cursor-pick hook nothing in this fork reads; dropping them cuts ~94 MB of
// write+read traffic per frame at 2M visible splats.
struct RasterizeData {
	vec4 color;
	vec2 image_pos;
	vec2 conic_xz;   // conic.x, conic.z
	vec2 conic_y_rx; // conic.y, power-cutoff bounding half-width
	vec2 ry_depth;   // power-cutoff bounding half-height, view depth
};

layout(std430, set = 0, binding = 0) restrict readonly buffer SplatsBuffer {
	Splat splat_buffer[];
};

layout(std430, set = 0, binding = 1) restrict writeonly buffer CulledBuffer {
	RasterizeData culled_buffer[];
};

layout (std430, set = 0, binding = 2) restrict buffer Histograms {
	uint sort_buffer_size;
    uint histogram[];
};

layout (std430, set = 0, binding = 3) restrict writeonly buffer SortKeysBuffer {
    uint sort_keys[];
};

layout (std430, set = 0, binding = 4) restrict writeonly buffer SortValuesBuffer {
    uint sort_values[];
};

layout (std430, set = 0, binding = 5) restrict writeonly buffer GridDimensionsBuffer {
	uint grid_dims[];
};

layout (std430, set = 0, binding = 6) restrict readonly buffer SplatInstanceIdsBuffer {
	uvec2 splat_instance_data[]; // x = unique instance id, y = which splat data to use
};

layout (std430, set = 0, binding = 7) restrict readonly buffer InstanceTransformsBuffer {
	mat4 instance_model_matrices[];
};

layout (std140, set = 0, binding = 8) restrict uniform Uniforms {
	vec3 camera_pos;
	float time;
	ivec2 dims; // Texture size
	int point_count;
	int light_count; // relighting; 0 disables the loop entirely
	// gsplat-stream packed layout. `packed_enabled` 0 keeps the canonical path.
	int packed_stride_words; // uint words per packed splat
	int sh_degree;           // 0..3, stored in the packed record
	float sh_scale;          // dequantization scale for the packed SH bytes
	int packed_enabled;
	// gsplat-stream disk-resident LOD arena. Indices >= stream_base_point address
	// the arena instead of the canonical buffer; each slot holds one octree node.
	int stream_base_point;   // first arena point index
	int stream_base_unique;  // first arena unique-splat index
	int stream_slot_splats;  // splats per arena slot
	int stream_enabled;
	// Slot directory length, passed explicitly: Godot's SPIR-V path does not
	// support OpArrayLength, so slot_info.length() is not usable here.
	int stream_arena_slots;
	int tile_size; // raster tile edge in pixels (16 canonical, 8 streaming LOD)
	// Arena record geometry. The arena decodes its own records, so it may use a
	// denser layout than the canonical payload; 0 keeps the float32 decode.
	int stream_stride_words;
	int stream_layout; // 0 = float32 packed record, 1 = q24
	// Logical capacities, not the physical length of shared scratch buffers.
	// sort_keys/values contain TWO radix banks; only the first is projection output.
	uint culled_capacity;
	uint sort_capacity;
	uvec2 capacity_padding;
};

// --- relighting (see CLAUDE.md, phase R4) ------------------------------------
// The maths below is a deliberate re-expression of the Raster backend's spatial
// shader (render/raster/materials/gaussian_raster.gdshader). The two MUST stay
// in parity; keep this comment in both when either changes. Both evaluate
// lighting once per splat and multiply the SH colour in sRGB space, before any
// linear conversion, so the two backends stay numerically comparable.

// Four vec4 per light, packed by runtime/lighting/gaussian_light_rig.gd:
//   +0 direction to light (directional) or world position
//   +1 colour * energy, w = type (0 directional, 1 omni, 2 spot)
//   +2 1/range, decay, cos(spot angle), spot angle attenuation
//   +3 direction the light travels (spot cone axis)
layout (std430, set = 0, binding = 9) restrict readonly buffer LightRigBuffer {
	vec4 light_rig[];
};

// One baked record per unique splat, RGBA8 packed into a uint: octahedral
// normal in bytes 0-1, ambient occlusion in 2, confidence in 3.
layout (std430, set = 0, binding = 10) restrict readonly buffer SplatLightingBuffer {
	uint splat_lighting[];
};

// Two vec4 per instance: (unlit level, gain, DC-only, enabled), (ambient rgb, _).
layout (std430, set = 0, binding = 11) restrict readonly buffer InstanceRelightBuffer {
	vec4 instance_relight[];
};

// gsplat-stream: compacted culled-splat counter.
//
// Upstream writes `culled_buffer[id]` for every visible splat, so the buffer
// must hold point_count entries even though most splats never get one. This
// fork compacts: a splat claims the next slot here and the sort key stores that
// compacted index, which gsplat_render.glsl already resolves as
// `culled_buffer[sort_value]`. The buffer is therefore sized by the visible
// count (see GaussianVisibleBudget on the CPU side).
layout (std430, set = 0, binding = 12) restrict buffer CulledCounter {
	uint culled_count;
};

// gsplat-stream: packed record view of the SAME buffer as binding 0.
//
// Layout per splat (see gaussian_packed_builder.gd):
//   word 0..2  float position.xyz
//   word 3     byte opacity(0..255) | byte sh_degree | 2 pad bytes
//   word 4..9  float covariance[0..5]
//   word 10..11 pad
//   byte 48..  quantized SH, 3 bytes per coefficient (bias 128)
layout (std430, set = 0, binding = 13) restrict readonly buffer PackedSplatsBuffer {
	uint packed_splats[];
};

// gsplat-stream: slot directory, 8 words per slot. Word 0 is the splat count
// (a zero count means the slot is not resident this frame), word 1 the GPU
// instance index, words 2..4 the node centre and word 5 its half-size as float
// bits. The last two are only read by the q24 decoder, which rebuilds each
// position from the node it belongs to.
#define STREAM_SLOT_WORDS 8u
layout (std430, set = 0, binding = 14) restrict readonly buffer SlotInfoBuffer {
	uint slot_info[];
};
uint slot_count(uint slot) { return slot_info[slot * STREAM_SLOT_WORDS]; }
uint slot_instance(uint slot) { return slot_info[slot * STREAM_SLOT_WORDS + 1u]; }
// Zero preserves ordinary slot-major streams. Instance groups use a 1-based
// physical slot address so several draw records can share one payload.
uint slot_payload(uint slot) {
	uint address = slot_info[slot * STREAM_SLOT_WORDS + 6u];
	return address == 0u ? slot : address - 1u;
}
vec3 slot_centre(uint slot) {
	const uint base = slot * STREAM_SLOT_WORDS + 2u;
	return vec3(uintBitsToFloat(slot_info[base]),
				uintBitsToFloat(slot_info[base + 1u]),
				uintBitsToFloat(slot_info[base + 2u]));
}
float slot_half(uint slot) { return uintBitsToFloat(slot_info[slot * STREAM_SLOT_WORDS + 5u]); }

// gsplat-stream: exclusive prefix sum of slot counts, written by the dispatch
// pre-pass. The projection dispatch covers exactly the resident splat count;
// each invocation binary-searches this array for its slot.
layout (std430, set = 0, binding = 15) restrict readonly buffer SlotOffsetsBuffer {
	uint slot_offsets[];
};

vec3 pk_position(uint base) {
	return vec3(
		uintBitsToFloat(packed_splats[base + 0u]),
		uintBitsToFloat(packed_splats[base + 1u]),
		uintBitsToFloat(packed_splats[base + 2u]));
}

float pk_opacity(uint base) {
	return float(packed_splats[base + 3u] & 0xFFu) / 255.0;
}

void pk_covariance(uint base, out float cov[6]) {
	cov[0] = uintBitsToFloat(packed_splats[base + 4u]);
	cov[1] = uintBitsToFloat(packed_splats[base + 5u]);
	cov[2] = uintBitsToFloat(packed_splats[base + 6u]);
	cov[3] = uintBitsToFloat(packed_splats[base + 7u]);
	cov[4] = uintBitsToFloat(packed_splats[base + 8u]);
	cov[5] = uintBitsToFloat(packed_splats[base + 9u]);
}

// --- q24 arena records -------------------------------------------------------
// 24 B/splat for degree 0 (tools/build_stream_pack.py --quantize q24):
//   word 0  position.x int16 | position.y int16   relative to the node centre,
//   word 1  position.z int16 | opacity u8 | SH degree u8   scale = half/32767
//   word 2  covariance[0..1] bf16
//   word 3  covariance[2..3] bf16
//   word 4  covariance[4..5] bf16
//   word 5+ quantized SH bytes (starts at byte 20)
// Positions are node-relative because a global int16 would quantize a 1 km world
// to metres; per node the step is half/32767, always one 32767th of the size at
// which that node stops being visible.

int q24_i16(uint word, bool high) {
	const uint raw = high ? (word >> 16u) : (word & 0xFFFFu);
	return int(raw << 16u) >> 16;
}

float q24_bf16(uint word, bool high) {
	return uintBitsToFloat(high ? (word & 0xFFFF0000u) : (word << 16u));
}

vec3 q24_position(uint base, vec3 centre, float node_half) {
	const uint w0 = packed_splats[base + 0u];
	const uint w1 = packed_splats[base + 1u];
	const vec3 q = vec3(float(q24_i16(w0, false)),
						float(q24_i16(w0, true)),
						float(q24_i16(w1, false)));
	return centre + q * (node_half / 32767.0);
}

float q24_opacity(uint base) {
	return float((packed_splats[base + 1u] >> 16u) & 0xFFu) / 255.0;
}

void q24_covariance(uint base, out float cov[6]) {
	const uint w2 = packed_splats[base + 2u];
	const uint w3 = packed_splats[base + 3u];
	const uint w4 = packed_splats[base + 4u];
	cov[0] = q24_bf16(w2, false);
	cov[1] = q24_bf16(w2, true);
	cov[2] = q24_bf16(w3, false);
	cov[3] = q24_bf16(w3, true);
	cov[4] = q24_bf16(w4, false);
	cov[5] = q24_bf16(w4, true);
}

// `sh_start` is the byte offset of the SH block inside the record: 48 for the
// packed builder's float32 layout, 20 for a q24 arena record.
float pk_sh_byte(uint base, uint sh_start, uint byte_index) {
	const uint absolute = sh_start + byte_index;
	const uint word = packed_splats[base + (absolute >> 2u)];
	const uint raw = (word >> ((absolute & 3u) * 8u)) & 0xFFu;
	return (float(raw) - 128.0) * sh_scale;
}

/** Three channels of one SH coefficient, decoded from the packed bytes. */
vec3 pk_sh3(uint base, uint sh_start, uint coefficient) {
	const uint offset = coefficient * 3u;
	return vec3(
		pk_sh_byte(base, sh_start, offset),
		pk_sh_byte(base, sh_start, offset + 1u),
		pk_sh_byte(base, sh_start, offset + 2u));
}

/** Packed-layout counterpart of get_color(). Reads only the stored degree. */
vec3 get_color_packed(uint base, uint sh_start, vec3 view_dir) {
	const float x = view_dir.x,
			    y = view_dir.y,
				z = view_dir.z;
	const float xx = x*x, yy = y*y, zz = z*z,
			    xy = x*y, yz = y*z, xz = x*z;
	vec3 color = vec3(0.5) + pk_sh3(base, sh_start, 0u) * SH_C0;
	if (sh_degree < 1) return max(vec3(0), color);
	color -= pk_sh3(base, sh_start, 1u) * SH_C1 * y;
	color += pk_sh3(base, sh_start, 2u) * SH_C1 * z;
	color -= pk_sh3(base, sh_start, 3u) * SH_C1 * x;
	if (sh_degree < 2) return max(vec3(0), color);
	color += pk_sh3(base, sh_start, 4u) * SH_C2_0 * xy;
	color -= pk_sh3(base, sh_start, 5u) * SH_C2_1 * yz;
	color += pk_sh3(base, sh_start, 6u) * SH_C2_2 * (2.0*zz - xx - yy);
	color -= pk_sh3(base, sh_start, 7u) * SH_C2_3 * xz;
	color += pk_sh3(base, sh_start, 8u) * SH_C2_4 * (xx - yy);
	if (sh_degree < 3) return max(vec3(0), color);
	color -= pk_sh3(base, sh_start,  9u) * SH_C3_0 * y * (3.0*xx - yy);
	color += pk_sh3(base, sh_start, 10u) * SH_C3_1 * x * yz;
	color -= pk_sh3(base, sh_start, 11u) * SH_C3_2 * y * (4.0*zz - xx - yy);
	color += pk_sh3(base, sh_start, 12u) * SH_C3_3 * z * (2.0*zz - 3.0*xx - 3.0*yy);
	color -= pk_sh3(base, sh_start, 13u) * SH_C3_4 * x * (4.0*zz - xx - yy);
	color += pk_sh3(base, sh_start, 14u) * SH_C3_5 * z * (xx - yy);
	color -= pk_sh3(base, sh_start, 15u) * SH_C3_6 * x * (xx - 3.0*yy);
	return max(vec3(0), color);
}

layout(push_constant) restrict readonly uniform PushConstants {
	mat4 view_matrix;
	mat4 projection_matrix;
};

float ease_out_cubic(in float x) {
	float a = 1.0 - x;
	return 1.0 - a*a*a;
}

/** Calculates the color from given spherical harmonic coefficients and view direction. */
#define SH_COEFFICIENTS(x) (vec3(sh_coefficients[x*3], sh_coefficients[x*3+1], sh_coefficients[x*3+2]))
vec3 get_color(in vec3 view_dir, in float sh_coefficients[16*3]) {
	const float x = view_dir.x,
			    y = view_dir.y,
				z = view_dir.z;
	const float xx = x*x, yy = y*y, zz = z*z,
			    xy = x*y, yz = y*z, xz = x*z;
	return max(vec3(0), 0.5 
		// Degree 0
		+  SH_COEFFICIENTS(0) *   SH_C0
		// Degree 1
		-  SH_COEFFICIENTS(1) *   SH_C1 * y
		+  SH_COEFFICIENTS(2) *   SH_C1 * z
		-  SH_COEFFICIENTS(3) *   SH_C1 * x
		// Degree 2
		+  SH_COEFFICIENTS(4) * SH_C2_0 * xy
		-  SH_COEFFICIENTS(5) * SH_C2_1 * yz
		+  SH_COEFFICIENTS(6) * SH_C2_2 * (2.0*zz - xx - yy)
		-  SH_COEFFICIENTS(7) * SH_C2_3 * xz
		+  SH_COEFFICIENTS(8) * SH_C2_4 * (xx - yy)
		// Degree 3
		-  SH_COEFFICIENTS(9) * SH_C3_0 * y * (3.0*xx - yy)
		+ SH_COEFFICIENTS(10) * SH_C3_1 * x * yz
		- SH_COEFFICIENTS(11) * SH_C3_2 * y * (4.0*zz - xx - yy)
		+ SH_COEFFICIENTS(12) * SH_C3_3 * z * (2.0*zz - 3.0*xx - 3.0*yy)
		- SH_COEFFICIENTS(13) * SH_C3_4 * x * (4.0*zz - xx - yy)
		+ SH_COEFFICIENTS(14) * SH_C3_5 * z * (xx - yy)
		- SH_COEFFICIENTS(15) * SH_C3_6 * x * (xx - 3.0*yy));
}

/** Unpacks one RGBA8 lighting record. Byte 0 lands in the low bits. */
vec4 unpack_lighting(in uint packed_record) {
	return vec4(
		float( packed_record        & 0xFFu),
		float((packed_record >>  8) & 0xFFu),
		float((packed_record >> 16) & 0xFFu),
		float((packed_record >> 24) & 0xFFu)) / 255.0;
}

/** Octahedral unit-vector decode; parity with oct_decode() in the raster shader
    and in runtime/resources/gaussian_lighting_resource.gd, which wrote these
    bytes. sign() is avoided because it returns 0 at 0 and collapses a fold. */
vec3 oct_decode(in vec2 e) {
	vec3 v = vec3(e, 1.0 - abs(e.x) - abs(e.y));
	if (v.z < 0.0) {
		v.xy = (1.0 - abs(e.yx)) * vec2(e.x >= 0.0 ? 1.0 : -1.0, e.y >= 0.0 ? 1.0 : -1.0);
	}
	float len = length(v);
	return len > 0.0 ? v / len : vec3(0.0, 0.0, 1.0);
}

/** Godot's own omni/spot distance falloff, so a light reads the same on splats
    as on the mesh beside them. Parity with the raster shader. */
float omni_attenuation(in float dist, in float inv_range, in float decay) {
	float nd = dist * inv_range;
	nd *= nd;
	nd *= nd;
	nd = max(1.0 - nd, 0.0);
	nd *= nd;
	return nd * pow(max(dist, 0.0001), -decay);
}

/** Per-splat lighting multiplier. Parity with relight_factor() in the raster
    shader; `confidence` gates only the directional response so floaters and
    interior splats fade to flat ambient instead of picking up a bogus
    terminator. */
vec3 relight_factor(
	in uint splat_index,
	in vec3 world_position,
	in mat3 object_linear,
	in float unlit_level,
	in float gain,
	in vec3 ambient
) {
	vec4 record = unpack_lighting(splat_lighting[splat_index]);
	vec3 world_normal = object_linear * oct_decode(record.rg * 2.0 - 1.0);
	float normal_length = length(world_normal);
	world_normal = normal_length > 0.0 ? world_normal / normal_length : vec3(0.0, 0.0, 1.0);
	float ao = record.b;
	float confidence = record.a;

	vec3 direct = vec3(0.0);
	for (int i = 0; i < light_count; i++) {
		vec4 tint = light_rig[i * 4 + 1];
		vec4 setup = light_rig[i * 4 + 2];
		int type = int(tint.a + 0.5);
		vec3 to_light = light_rig[i * 4 + 0].xyz;
		float attenuation = 1.0;
		if (type != 0) {
			vec3 relative = light_rig[i * 4 + 0].xyz - world_position;
			float dist = length(relative);
			if (dist < 1e-6) {
				continue;
			}
			to_light = relative / dist;
			attenuation = omni_attenuation(dist, setup.r, setup.g);
			if (type == 2) {
				float cone_cosine = max(dot(-to_light, light_rig[i * 4 + 3].xyz), setup.b);
				float rim = (1.0 - cone_cosine) / max(1e-4, 1.0 - setup.b);
				attenuation *= 1.0 - pow(clamp(rim, 0.0, 1.0), setup.a);
			}
		}
		direct += tint.rgb * attenuation * max(dot(world_normal, to_light), 0.0);
	}

	vec3 irradiance = ambient * ao + direct * confidence;
	return vec3(unlit_level) + gain * irradiance;
}

/** Computes a 2D projected covariance matrix from the given Gaussian parameters. */
vec3 project_covariance(in mat3 covariance_3d, in float scale_modifier, in vec3 mean, in ivec2 dims) {
	const mat3 cov_3d = covariance_3d * scale_modifier*scale_modifier;
	// Godot camera space looks down -Z, so use positive forward depth here.
	vec2 tan_fov_inv = vec2(projection_matrix[0][0], projection_matrix[1][1]);
	vec2 focal = vec2(dims - 1) * 0.5 * tan_fov_inv;
	// RenderData projections can encode a Y flip in projection_matrix[1][1].
	// Keep that sign in the focal scale, but use absolute FOV extents for clamping.
	vec2 tan_fov = 1.0 / abs(tan_fov_inv);
	float depth_inv = -1.0 / mean.z;
	focal *= depth_inv;

	mean.xy = clamp(mean.xy * depth_inv, -tan_fov * 1.3, tan_fov * 1.3);
	mat3 view_linear = mat3(view_matrix);
	mat3 jacobian = mat3(
		focal.x, 0, 0,
		0, focal.y, 0,
		focal.x * mean.x, focal.y * mean.y, 0);
	mat3 screen_transform = jacobian * view_linear;
	mat3 cov_2d = screen_transform * cov_3d * transpose(screen_transform);
	return vec3(cov_2d[0][0] + 0.3, cov_2d[0][1], cov_2d[1][1] + 0.3);
}

uvec4 get_rect(in vec2 image_pos, in vec2 radius, in uvec2 grid_size, in uint tile) {
	return ivec4(
		clamp(     (image_pos - radius) / tile,  vec2(0), grid_size),
		clamp(ceil((image_pos + radius) / tile), vec2(0), grid_size));
}

// Only values consumed after workgroup allocation cross the reconvergence point.
struct ProjectedSplat {
	uint instance_id;
	uint unique_splat_index;
	uint pk_base;
	uint sh_start;
	bool is_packed;
	bool identity_basis;
	mat3 object_linear;
	vec3 world_pos;
	vec3 covariance;
	float det;
	vec2 image_pos;
	float splat_opacity;
	float view_depth;
	float raster_depth;
	uvec4 rect_bounds;
	uint culled_index;
};

// One entry per possible subgroup, including one-invocation subgroups.
shared uint subgroup_tile_counts[256];
shared uint subgroup_tile_offsets[256];
shared uint workgroup_sort_start;

bool prepare_splat(out ProjectedSplat prepared) {
	const int id = int(gl_GlobalInvocationID.x);
	const uint tile = uint(tile_size);
	const uvec2 grid_size = (dims + tile - 1) / tile;

	// gsplat-stream: resolve the record address. Canonical points keep the
	// upstream instance-id lookup; arena points derive their slot from the index
	// and early-out when the slot is empty or the local offset is past its count.
	// All early returns stay inside this helper. main() reconverges every lane
	// before its workgroup barriers, including nonresident and culled lanes.
	uint instance_id;
	uint unique_splat_index;
	// q24 arena splats decode against their own node, so the address and the
	// quantization frame are resolved together with the slot.
	bool from_arena = false;
	vec3 arena_centre = vec3(0.0);
	float arena_half = 1.0;
	if (stream_enabled != 0 && stream_slot_splats > 0 && id >= stream_base_point) {
		const uint aid = uint(id - stream_base_point);
		if (aid >= slot_offsets[stream_arena_slots]) return false;
		uint lo = 0u;
		uint hi = uint(stream_arena_slots);
		while (lo < hi) {
			uint mid = (lo + hi) >> 1u;
			if (slot_offsets[mid + 1u] <= aid) lo = mid + 1u; else hi = mid;
		}
		const uint slot = lo;
		const uint local = aid - slot_offsets[slot];
		instance_id = slot_instance(slot);
		// Records stay slot-major in the arena; map the compacted id back.
		unique_splat_index = uint(stream_base_unique) + slot_payload(slot) * uint(stream_slot_splats) + local;
		from_arena = true;
		arena_centre = slot_centre(slot);
		arena_half = slot_half(slot);
	} else {
		if (id >= uint(point_count)) return false;
		const uvec2 instance_data = splat_instance_data[id];
		instance_id = instance_data.x;
		unique_splat_index = instance_data.y;
	}

	// --- gsplat-stream: pick the record decoder ------------------------------
	const bool is_packed = packed_enabled != 0;
	const bool is_q24 = from_arena && stream_layout == 1;
	// Arena records are addressed from the canonical payload's end with the
	// arena's own stride; the canonical/packed path keeps the merged stride.
	const uint pk_base = is_q24
		? uint(stream_base_unique) * uint(packed_stride_words)
			+ (unique_splat_index - uint(stream_base_unique)) * uint(stream_stride_words)
		: (is_packed ? uint(unique_splat_index) * uint(packed_stride_words) : 0u);
	const uint sh_start = is_q24 ? 20u : 48u;
	vec3 splat_position;
	float splat_opacity_raw;
	float splat_cov[6];
	if (is_q24) {
		splat_position = q24_position(pk_base, arena_centre, arena_half);
		splat_opacity_raw = q24_opacity(pk_base);
		q24_covariance(pk_base, splat_cov);
	} else if (is_packed) {
		splat_position = pk_position(pk_base);
		splat_opacity_raw = pk_opacity(pk_base);
		pk_covariance(pk_base, splat_cov);
	} else {
		const Splat canonical = splat_buffer[unique_splat_index];
		splat_position = canonical.position;
		splat_opacity_raw = canonical.opacity;
		splat_cov = canonical.covariance;
	}
	mat4 model_matrix = instance_model_matrices[instance_id];

	// --- VISIBILITY ---
	float is_visible = model_matrix[0][3];
	if (is_visible < 0.5) return false;
	model_matrix[0][3] = 0.0;
	
	// --- FRUSTUM CULLING ---
	mat3 object_linear = mat3(model_matrix);
	// gsplat-stream: a streaming node is normally a single identity instance, so
	// the basis transform and its inverse are no-ops. Branch on it (coherent across
	// the whole dispatch for one instance) to skip a mat3 inverse + two mat3 muls
	// per splat. Non-identity instances keep the full transform.
	bool identity_basis = object_linear == mat3(1.0);
	mat3 world_covariance = identity_basis
		? DECODE_COVARIANCE(splat_cov)
		: object_linear * DECODE_COVARIANCE(splat_cov) * transpose(object_linear);
	vec4 world_pos = model_matrix * vec4(splat_position, 1.0);
	vec4 view_pos = view_matrix * world_pos;
	vec4 clip_pos = projection_matrix * view_pos;
	vec2 view_bounds = clip_pos.ww*1.2;
	if (any(lessThan(clip_pos.xyz, vec3(-view_bounds, 0.0))) || any(greaterThan(clip_pos.xyz, vec3(view_bounds, clip_pos.w)))) {
		return false;
	}
	
	// --- GAUSSIAN PROJECTION ---
	// The packed record has no per-splat reveal timestamp, so packed scenes skip
	// the intro animation entirely (time_factor == 1).
	float splat_time = is_packed ? 1.0 : (time - splat_buffer[unique_splat_index].time);
	float time_factor = ease_out_cubic(clamp(splat_time, 0, 1));
	float time_factor_late = ease_out_cubic(clamp(splat_time - 0.35, 0, 1));

	float splat_opacity = splat_opacity_raw * time_factor_late*time_factor_late;
	float splat_scale = mix(2.0, 1.0, time_factor_late);

	const vec3 covariance = project_covariance(world_covariance, splat_scale, view_pos.xyz, dims);
	float det = covariance.x*covariance.z - covariance.y*covariance.y;
	if (det == 0.0) return false;

	float mid = 0.5 * (covariance.x + covariance.z);
	vec2 eigenvalues = mid + vec2(1, -1)*sqrt(max(0.1, mid*mid - det));
	if (any(lessThan(eigenvalues, vec2(0)))) return false;

	vec3 ndc_pos = clip_pos.xyz / clip_pos.w;
	vec2 image_pos = ((ndc_pos.xy + 1.0)*0.5 - vec2(1,0.75)*(1.0 - time_factor)) * (dims - 1);

	// We bias the radius (w/ base=2.5x standard deviation) such that low opacity splats cover
	// fewer screen tiles. This has the effect of making the image *slightly* brighter while
	// minimizing perceptible tile artifacts.
	// gsplat-stream: per-axis tile rect. The marginal std sqrt(cov.x/z) is <= sqrt(lambda_max),
	// so an anisotropic splat covers fewer tiles along its minor axis than the isotropic
	// sqrt(lambda_max) box. Same 2.5sigma opacity-biased truncation as before (the pixel bbox
	// stays the wider 3.33sigma per-axis superset), so this only drops the faint tail the
	// isotropic box already dropped along the major axis -- shorter per-tile lists for both
	// the sort and the rasterizer, which is the dense-overdraw bottleneck.
	float opacity_bias = pow(splat_opacity, 0.2) * 2.5;
	vec2 radius = opacity_bias * sqrt(max(vec2(0.0), vec2(covariance.x, covariance.z)));
	uvec4 rect_bounds = get_rect(image_pos, radius, grid_size, tile);
	uint num_tiles_touched = (rect_bounds.z - rect_bounds.x)*(rect_bounds.w - rect_bounds.y);

	if (num_tiles_touched == 0 /*|| num_tiles_touched > grid_size.x*grid_size.y/3*/) return false;

	// --- CULLED COMPACTION (gsplat-stream) ----------------------------------
	// Claim a compacted slot. Explicit capacities avoid OpArrayLength, which
	// Godot's shader path does not support. Over-capacity splats are dropped (no
	// culled entry, no sort entries) which keeps every downstream buffer
	// consistent. The counter measures demand; changing capacity needs a rebuild.
	// Compact active lanes together: one contended global atomic per subgroup,
	// instead of one per visible splat. The counter still records all demand.
	uvec4 visible_mask = subgroupBallot(true);
	uint culled_start = 0u;
	if (subgroupElect()) {
		culled_start = atomicAdd(culled_count, subgroupBallotBitCount(visible_mask));
	}
	culled_start = subgroupBroadcastFirst(culled_start);
	uint culled_index = culled_start + subgroupBallotExclusiveBitCount(visible_mask);
	if (culled_index >= culled_capacity) return false;

	prepared.instance_id = instance_id;
	prepared.unique_splat_index = unique_splat_index;
	prepared.pk_base = pk_base;
	prepared.sh_start = sh_start;
	prepared.is_packed = is_packed;
	prepared.identity_basis = identity_basis;
	prepared.object_linear = object_linear;
	prepared.world_pos = world_pos.xyz;
	prepared.covariance = covariance;
	prepared.det = det;
	prepared.image_pos = image_pos;
	prepared.splat_opacity = splat_opacity;
	prepared.view_depth = max(0.0, clip_pos.w);
	prepared.raster_depth = -view_pos.z;
	prepared.rect_bounds = rect_bounds;
	prepared.culled_index = culled_index;
	return true;
}

void main() {
	ProjectedSplat prepared;
	bool visible = prepare_splat(prepared);
	uint num_tiles_touched = visible
		? (prepared.rect_bounds.z - prepared.rect_bounds.x)
			* (prepared.rect_bounds.w - prepared.rect_bounds.y) : 0u;
	uint group_needed = subgroupAdd(num_tiles_touched);
	uint lane_offset = subgroupExclusiveAdd(num_tiles_touched);
	if (subgroupElect()) subgroup_tile_counts[gl_SubgroupID] = group_needed;
	// Every invocation reaches both barriers: prepare_splat() returns to main,
	// never out of this entry point. Empty and partial workgroups participate.
	barrier();
	if (gl_LocalInvocationIndex == 0u) {
		uint needed = 0u;
		for (uint group = 0u; group < gl_NumSubgroups; ++group) {
			subgroup_tile_offsets[group] = needed;
			needed += subgroup_tile_counts[group];
		}
		uint start = 0u;
		if (needed != 0u) {
			start = atomicAdd(sort_buffer_size, 0u);
			while (start < sort_capacity) {
				uint end = start + min(needed, sort_capacity - start);
				uint previous = atomicCompSwap(sort_buffer_size, start, end);
				if (previous == start) break;
				start = previous;
			}
		}
		workgroup_sort_start = start;
	}
	barrier();
	uint sort_buffer_offset = workgroup_sort_start
		+ subgroup_tile_offsets[gl_SubgroupID] + lane_offset;
	if (!visible || sort_buffer_offset >= sort_capacity) return;
	const uint sort_end = sort_buffer_offset
		+ min(num_tiles_touched, sort_capacity - sort_buffer_offset);
	// One bounded CAS reservation per workgroup replaces up to eight contending
	// subgroup reservations. It publishes no gaps and never touches radix bank 2.
	uint instance_id = prepared.instance_id;
	uint unique_splat_index = prepared.unique_splat_index;
	uint pk_base = prepared.pk_base;
	uint sh_start = prepared.sh_start;
	bool is_packed = prepared.is_packed;
	bool identity_basis = prepared.identity_basis;
	mat3 object_linear = prepared.object_linear;
	vec4 world_pos = vec4(prepared.world_pos, 1.0);
	vec3 covariance = prepared.covariance;
	float det = prepared.det;
	vec2 image_pos = prepared.image_pos;
	float splat_opacity = prepared.splat_opacity;
	uvec4 rect_bounds = prepared.rect_bounds;
	uint culled_index = prepared.culled_index;
	const uint tile = uint(tile_size);
	const uvec2 grid_size = (dims + tile - 1) / tile;

	// SH coefficients live in the splat's object space, so the view direction
	// must be brought into that space (issue #29). inverse(), not transpose():
	// object_linear may carry non-uniform scale.
	vec3 view_dir = identity_basis
		? normalize(world_pos.xyz - camera_pos)
		: normalize(inverse(object_linear) * (world_pos.xyz - camera_pos));

	vec3 base_color = is_packed
		? get_color_packed(pk_base, sh_start, view_dir)
		: get_color(view_dir, splat_buffer[unique_splat_index].sh_coefficients);
	vec4 relight = instance_relight[instance_id * 2u];
	if (relight.w > 0.5) {
		if (relight.z > 0.5) {
			// DC-only: baked view-dependent specular fights new lighting.
			vec3 dc = is_packed ? pk_sh3(pk_base, sh_start, 0u) : vec3(
				splat_buffer[unique_splat_index].sh_coefficients[0],
				splat_buffer[unique_splat_index].sh_coefficients[1],
				splat_buffer[unique_splat_index].sh_coefficients[2]);
			base_color = max(vec3(0.0), vec3(0.5) + dc * SH_C0);
		}
		base_color *= relight_factor(
			unique_splat_index, world_pos.xyz, object_linear,
			relight.x, relight.y, instance_relight[instance_id * 2u + 1u].rgb
		);
	}

	RasterizeData data;
	data.color = vec4(base_color, splat_opacity);
	if (relight.w < -0.5) {
		data.color *= instance_relight[instance_id * 2u + 1u];
	}
	data.image_pos = image_pos;
	data.conic_xz = vec2(covariance.z, covariance.x) / det; // Inverse 2D covariance
	// gsplat-stream: per-axis AABB of the power>=-5.54 cutoff ellipse. The
	// half-extents of a (rotated) ellipse are sqrt(11.08 * marginal variance),
	// a strict superset of the ellipse and tighter than the isotropic
	// sqrt(lambda_max) box for anisotropic splats, so the raster rejects more
	// pixels before the quadratic form with zero image change.
	data.conic_y_rx = vec2(-covariance.y / det, 3.3286 * sqrt(covariance.x));
	data.ry_depth = vec2(3.3286 * sqrt(covariance.z), prepared.raster_depth);
	// Allocation completes before any culled or sort record writes.
	culled_buffer[culled_index] = data;

	// --- GAUSSIAN DUPLICATION ---
	// Use clip-space w as a monotonic distance proxy so ordering stays front-to-back
	// even when the renderer uses reverse-z projection.
	float view_depth = prepared.view_depth;
	float depth01 = view_depth / (1.0 + view_depth);
	uint depth = uint(depth01 * 65535.0) & 0xFFFF;
	for (uint y = rect_bounds.y; y < rect_bounds.w; ++y)
	for (uint x = rect_bounds.x; x < rect_bounds.z; ++x) {
		if (sort_buffer_offset >= sort_end) return;
		uint tile_id = y*grid_size.x + x;
		uint key = (tile_id << 16) | depth;
		sort_keys[sort_buffer_offset] = key;
		// gsplat-stream: the compacted index, not the raw splat id.
		sort_values[sort_buffer_offset] = culled_index;
		sort_buffer_offset++;
	}
}
