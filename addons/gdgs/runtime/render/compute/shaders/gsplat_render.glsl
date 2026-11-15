#[compute]
#version 460

#define MIN_FACTOR     (255)
#define MIN_ALPHA      (1.0 / MIN_FACTOR)
#define DEPTH_ALPHA    (1e-6)
#define TILE_SIZE      (16)
#define WORKGROUP_SIZE (TILE_SIZE*TILE_SIZE)

layout (local_size_x = TILE_SIZE, local_size_y = TILE_SIZE, local_size_z = 1) in;

// Must match gsplat_projection.glsl (48 B std430 stride).
struct RasterizeData {
	vec4 color;
	vec2 image_pos;
	vec2 conic_xz;   // conic.x, conic.z
	vec2 conic_y_rx; // conic.y, power-cutoff bounding half-width
	vec2 ry_depth;   // power-cutoff bounding half-height, view depth
};

layout(std430, set = 0, binding = 0) restrict readonly buffer CulledBuffer {
	RasterizeData culled_buffer[];
};

layout (std430, set = 0, binding = 1) restrict readonly buffer SortBuffer {
    uint sort_buffer[];
};

layout (std430, set = 0, binding = 2) restrict readonly buffer BoundsBuffer {
    uvec2 bounds_buffer[];
};

layout(rgba32f, set = 0, binding = 3) uniform restrict writeonly image2D rasterized_image;
layout(r32f, set = 0, binding = 4) uniform restrict writeonly image2D rasterized_depth;

layout(push_constant) restrict readonly uniform PushConstants {
	float heatmap_factor;
    float depth_capture_alpha;
    float _pad0;
    float _pad1;
};

shared vec3[WORKGROUP_SIZE] conic_tile;
shared vec4[WORKGROUP_SIZE] color_tile;
shared vec2[WORKGROUP_SIZE] image_pos_tile;
shared float[WORKGROUP_SIZE] depth_tile;
shared vec2[WORKGROUP_SIZE] radii_tile;
shared uint shared_t;

const float INVALID_DEPTH = 1e20;

void main() {
    if (gl_LocalInvocationIndex == 0) {
        shared_t = ~0u; // Initialize shared alpha to MAX_UINT
    }
    barrier();
	const ivec2 dims = imageSize(rasterized_image);
	const uvec2 grid_size = (dims + TILE_SIZE - 1) / TILE_SIZE;
    
    const uvec2 id_block = gl_WorkGroupID.xy;
    const uint id_local = gl_LocalInvocationIndex;
    const uint tile_id = id_block.y*grid_size.x + id_block.x;
    const uvec2 pixel = id_block*TILE_SIZE + gl_LocalInvocationID.xy;
    const bool pixel_in_bounds = pixel.x < uint(dims.x) && pixel.y < uint(dims.y);
    const vec2 image_pos = vec2(pixel);

    const uvec2 bounds = bounds_buffer[tile_id];
    const uint num_splats = uint(max(0, int(bounds.y - bounds.x)));
    const uint num_iterations = uint(ceil(float(num_splats) / float(WORKGROUP_SIZE)));

    vec3 blended_color = vec3(0.0); //imageLoad(rasterized_image, ivec2(image_pos)).rgb;
    float t = pixel_in_bounds ? 1.0 : 0.0;
    float first_hit_depth = INVALID_DEPTH;
    for (uint i = 0; i < num_iterations && shared_t > MIN_FACTOR; ++i) {
        const uint sort_offset = WORKGROUP_SIZE*i;
        const uint chunk_size = min(uint(WORKGROUP_SIZE), num_splats - sort_offset);

        barrier();
        // Coalesced load of the next tile of data into shared memory.
        RasterizeData data;
        if (id_local < chunk_size) {
            data = culled_buffer[sort_buffer[(bounds.x + sort_offset) + id_local]];
        } else {
            data.conic_xz = vec2(0.0);
            data.conic_y_rx = vec2(0.0);
            data.ry_depth = vec2(0.0, INVALID_DEPTH);
            data.color = vec4(0.0);
            data.image_pos = vec2(0.0);
        }
        conic_tile[id_local] = vec3(data.conic_xz.x, data.conic_y_rx.x, data.conic_xz.y);
        color_tile[id_local] = data.color;
        image_pos_tile[id_local] = data.image_pos;
        depth_tile[id_local] = data.ry_depth.y;
        radii_tile[id_local] = vec2(data.conic_y_rx.y, data.ry_depth.x);
        if (id_local == 0) {
            shared_t = 0u; // Reset shared alpha
        }
        barrier();

        for (uint j = 0; pixel_in_bounds && j < chunk_size && t > MIN_ALPHA; ++j) {
            vec2 offset = image_pos_tile[j] - image_pos;
            // Bounding-box reject: outside this box the conic power is below
            // the -5.54 cutoff, so skip the quadratic form entirely. Per-axis
            // extents (the ellipse's marginal variances) tighten the box for
            // anisotropic splats without dropping any covered pixel.
            vec2 rad = radii_tile[j];
            if (abs(offset.x) > rad.x || abs(offset.y) > rad.y) continue;
            vec3 conic = conic_tile[j];
            vec4 color = color_tile[j];
            float splat_depth = depth_tile[j];
            
            float power = -0.5 * (conic.x * offset.x*offset.x + conic.z * offset.y*offset.y) - conic.y * offset.x*offset.y;
            // gsplat-stream: reject pixels whose contribution is below MIN_ALPHA
            // BEFORE the expensive exp(). For a colour alpha <= 1, power < log(MIN_ALPHA)
            // guarantees alpha < 1/255, which the blend loop already treats as nothing.
            // LOD splats are ~1px, so most of a 16x16 tile is far outside each splat and
            // this skips the vast majority of exp() calls. Depth capture needs alpha >= 0.5
            // (power >= -0.69), so it is never affected by this cutoff.
            if (power < -5.54) continue;
            float alpha = color.a * exp(power);
            // if (alpha < MIN_ALPHA) continue;
            float next_t = t * (1.0 - alpha);
            if (
                alpha > DEPTH_ALPHA &&
                first_hit_depth == INVALID_DEPTH &&
                (1.0 - next_t) >= depth_capture_alpha
            ) {
                first_hit_depth = splat_depth;
            }

            blended_color += color.rgb * alpha * t;
            t = next_t;
        }

        // We add up all the alpha across the block; if it is greater than MIN_FACTOR, the
        // alpha of the entire block will be greater than MIN_ALPHA.
        // In such case, some threads still have splats to draw and all threads in the block
        // will continue to loop fetching the remaining splats into shared memory.
        atomicAdd(shared_t, uint(t*MIN_FACTOR));
        barrier();
    }
    vec3 heatmap_color = mix(vec3(0,0,1), vec3(1,0.2,0.2), float(num_splats) * 5e-4) * (1.0 - t) * heatmap_factor;
    if (pixel_in_bounds) {
        float final_alpha = 1.0 - t;
	    imageStore(rasterized_image, ivec2(pixel), vec4(blended_color + heatmap_color, final_alpha));
        imageStore(rasterized_depth, ivec2(pixel), vec4(first_hit_depth, 0.0, 0.0, 0.0));
    }
}
