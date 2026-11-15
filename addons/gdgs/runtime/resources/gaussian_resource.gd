@tool
@icon("res://addons/gdgs/editor/icons/gaussian_resource.svg")
extends Resource
class_name GaussianResource

# GPU-ready std430 layout.
# Each splat occupies 60 float32 values (240 bytes).
@export var point_count: int = 0
@export var point_data_float: PackedFloat32Array
@export var point_data_byte: PackedByteArray
@export var xyz: PackedVector3Array
@export var aabb: AABB = AABB()

# --- gsplat-stream packed layout (optional) ---------------------------------
#
# When `packed_enabled` is true, `point_data_byte` holds the packed record
# emitted by gaussian_packed_builder.gd instead of the canonical 240 B float
# record: 48 B core (position + opacity byte + covariance) followed by 8-bit
# quantized SH at `sh_degree`.
#
# All packed resources in one scene MUST share the same `sh_degree` and
# `packed_stride_words`, because the Compute backend merges unique splat data
# into a single buffer with one stride. Mixing degrees disables the packed path
# at the registry level and falls back to the canonical layout.
@export var packed_enabled: bool = false
## Words (uint32) per splat: (48 + sh_stride) / 4.
@export var packed_stride_words: int = 0
## SH degree stored in the packed SH block (0..3).
@export var sh_degree: int = 3
## Global dequantization scale for the packed SH bytes.
@export var sh_scale: float = 1.0
