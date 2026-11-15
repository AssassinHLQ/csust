#[compute]
#version 460

// gsplat-stream: indirect-dispatch finalize.
//
// The projection pass writes the true number of sort elements into
// histogram[0] (sort_buffer_size). The radix sort and the tile-boundaries pass
// are dispatched indirectly from grid_dimensions, but that buffer is pre-sized
// on the CPU for the WORST case (whole arena capacity x sort budget). At runtime
// only a small fraction of those elements exist, so the sort launches thousands
// of empty partitions and boundaries launches tens of millions of invocations
// that immediately early-out.
//
// This single-thread pass runs after projection and rewrites the two dispatch
// widths to follow the actual element count, so downstream work (and the empty
// workgroup launch overhead) tracks residency instead of capacity. The CPU
// pre-size remains as the initial value, so if this pass is skipped the pipeline
// still runs correctly at the worst-case width.
//
// It also runs BEFORE projection: the slot-count prefix sum it writes lets the
// projection pass dispatch exactly the resident splat count (binary-searching
// the prefix for its slot) instead of walking every arena slot's full capacity.

#define PARTITION_SIZE (8 * 512)
#define BOUNDS_BLOCK   (256)
#define PROJECTION_BLOCK (256)

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict readonly buffer Histograms {
	uint sort_buffer_size;
	uint histogram[];
};

layout(std430, set = 0, binding = 1) restrict buffer GridDimensions {
	uint grid_dims[];
};

// Must match gsplat_projection.glsl: 8 words per slot, word 0 is the count.
#define STREAM_SLOT_WORDS 8
layout(std430, set = 0, binding = 2) restrict readonly buffer SlotInfo {
	uint slot_info[];
};

layout(std430, set = 0, binding = 3) restrict writeonly buffer SlotOffsets {
	uint slot_offsets[]; // arena_slots + 1 entries, exclusive prefix of counts
};

layout(std430, set = 0, binding = 4) restrict writeonly buffer ProjectionDims {
	uint projection_dims[];
};

layout(push_constant) restrict readonly uniform PushConstants {
	uint arena_slots;
	uint pad0;
	uint pad1;
	uint pad2;
};

void main() {
	uint count = sort_buffer_size;
	// Sort upsweep/downsweep read offset 0 (partition count).
	grid_dims[0] = (count + PARTITION_SIZE - 1) / PARTITION_SIZE;
	// Boundaries reads offset 3 (256-wide workgroup count).
	grid_dims[3] = (count + BOUNDS_BLOCK - 1) / BOUNDS_BLOCK;

	uint total = 0;
	for (uint s = 0; s < arena_slots; ++s) {
		slot_offsets[s] = total;
		total += slot_info[s * STREAM_SLOT_WORDS];
	}
	slot_offsets[arena_slots] = total;
	projection_dims[0] = max(1u, (total + PROJECTION_BLOCK - 1) / PROJECTION_BLOCK);
	projection_dims[1] = 1;
	projection_dims[2] = 1;
}