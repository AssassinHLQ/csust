@tool
extends RefCounted

## Packed per-splat GPU record builder (gsplat-stream addition).
##
## The upstream Compute backend uploads the canonical 240 B float32 record:
##   position(12) + time(4) + covariance(24) + opacity(4) + pad(4) + SH deg3(192)
##
## This builder emits the gsplat-stream record instead, which drops the unused
## `time`/pad slots, keeps position + covariance + opacity as float32 (they are
## view-critical and cheap), and replaces the 192 B SH payload with the 8-bit
## quantized SH from gaussian_sh_quantizer:
##
##   word  0..2   float  position.xyz
##   word  3      byte   opacity (0..255) + byte SH-degree + 2 pad bytes
##   word  4..9   float  covariance[0..5]   (top triangle of the 3x3)
##   word 10..11  pad (keeps the SH block 16-byte aligned at word 12)
##   word 12..    bytes  quantized SH, stride 4/12/28/48 for degree 0/1/2/3
##
## Stride: 52/60/76/96 B per splat for degree 0/1/2/3 (vs 240 B upstream).
##
## Keep the covariance maths identical to gaussian_resource_builder.gd: the
## shader's DECODE_COVARIANCE expects the same six values in the same order.

const ShQuantizer = preload("res://addons/gdgs/runtime/resources/gaussian_sh_quantizer.gd")

## Words before the SH block: position(3) + packed opacity/degree(1) +
## covariance(6) + pad(2).
const CORE_WORDS := 12
const CORE_BYTES := CORE_WORDS * 4  # 48
const SH_BLOCK_WORD_OFFSET := CORE_WORDS

## Canonical SH float count per splat (degree 3).
const CANONICAL_SH_FLOATS := 48


## Total bytes per splat for a degree (including core).
static func stride_bytes(degree: int) -> int:
	return CORE_BYTES + ShQuantizer.stride(degree)


## Total words per splat for a degree.
static func stride_words(degree: int) -> int:
	return stride_bytes(degree) / 4


## Build the packed record buffer from a canonical dictionary as produced by
## gaussian_resource_builder.create_canonical().
##
## Returns:
##   ok, bytes (PackedByteArray), count, degree, stride_bytes, stride_words,
##   aabb (post-centering, matching the canonical builder), center, sh_scale
static func build_packed(canonical: Dictionary, degree: int) -> Dictionary:
	var d := ShQuantizer.clamp_degree(degree)
	var stride := stride_bytes(d)
	var words := stride_words(d)

	var count := int(canonical.get("count", 0))
	var positions: PackedVector3Array = canonical.get("positions", PackedVector3Array())
	var scales_linear: PackedVector3Array = canonical.get("scales_linear", PackedVector3Array())
	var rotations: Array = canonical.get("rotations", [])
	var opacities: PackedFloat32Array = canonical.get("opacities", PackedFloat32Array())
	var sh_coeffs: PackedFloat32Array = canonical.get("sh_coeffs", PackedFloat32Array())

	if count < 0:
		return _error(ERR_INVALID_DATA, "Canonical gaussian count is invalid")
	if positions.size() != count or scales_linear.size() != count \
		or rotations.size() != count or opacities.size() != count:
		return _error(ERR_INVALID_DATA, "Canonical gaussian arrays are inconsistent")
	if sh_coeffs.size() != count * CANONICAL_SH_FLOATS:
		return _error(ERR_INVALID_DATA, "Canonical SH coefficient buffer has an unexpected size")

	# Quantize SH first: one global scale for the whole resource.
	var quant: Dictionary = ShQuantizer.quantize(sh_coeffs, count, d)
	if not bool(quant.get("ok", false)):
		return _error(ERR_INVALID_DATA, "SH quantization failed: %s" % str(quant.get("message", "")))
	var sh_bytes: PackedByteArray = quant["bytes"]
	var sh_scale: float = float(quant["scale"])
	var sh_stride: int = ShQuantizer.stride(d)

	# Same centering as the canonical builder so both formats agree on the AABB.
	var center := Vector3.ZERO
	if count > 0:
		for i in count:
			center += positions[i]
		center /= float(count)

	var out := PackedByteArray()
	out.resize(count * stride)
	out.fill(0)

	var aabb_min_v := Vector3(INF, INF, INF)
	var aabb_max_v := Vector3(-INF, -INF, -INF)
	var degree_tag := d << 8

	for i in count:
		var pos: Vector3 = positions[i] - center
		var scale_linear: Vector3 = scales_linear[i]
		var rotation := Quaternion(0.0, 0.0, 0.0, 1.0)
		var rotation_value = rotations[i]
		if rotation_value is Quaternion:
			rotation = rotation_value.normalized()

		scale_linear = Vector3(
			maxf(scale_linear.x, 1e-6),
			maxf(scale_linear.y, 1e-6),
			maxf(scale_linear.z, 1e-6)
		)

		aabb_min_v = aabb_min_v.min(pos)
		aabb_max_v = aabb_max_v.max(pos)

		var base := i * stride
		# word 0..2: position
		out.encode_float(base + 0, pos.x)
		out.encode_float(base + 4, pos.y)
		out.encode_float(base + 8, pos.z)
		# word 3: opacity byte + degree byte
		var opacity_byte := clampi(int(round(clampf(opacities[i], 0.0, 1.0) * 255.0)), 0, 255)
		out[base + 12] = opacity_byte
		out[base + 13] = d
		out[base + 14] = 0
		out[base + 15] = 0

		# word 4..9: covariance (identical maths to the canonical builder)
		var scale_mat := Basis.from_scale(scale_linear)
		var rot_mat := Basis(rotation).transposed()
		var cov_3d := (scale_mat * rot_mat).transposed() * (scale_mat * rot_mat)
		out.encode_float(base + 16, cov_3d.x[0])
		out.encode_float(base + 20, cov_3d.y[0])
		out.encode_float(base + 24, cov_3d.z[0])
		out.encode_float(base + 28, cov_3d.y[1])
		out.encode_float(base + 32, cov_3d.z[1])
		out.encode_float(base + 36, cov_3d.z[2])

		# word 12..: quantized SH bytes
		var sh_dst := base + CORE_BYTES
		var sh_src := i * sh_stride
		for b in sh_stride:
			out[sh_dst + b] = sh_bytes[sh_src + b]

	return {
		"ok": true,
		"bytes": out,
		"count": count,
		"degree": d,
		"stride_bytes": stride,
		"stride_words": words,
		"core_bytes": CORE_BYTES,
		"sh_stride_bytes": sh_stride,
		"sh_scale": sh_scale,
		"sh_degree_tag": degree_tag,
		"center": center,
		"aabb": AABB(aabb_min_v, aabb_max_v - aabb_min_v) if count > 0 else AABB(),
	}


## Decode one packed splat back to CPU-side values. Tests and tooling only.
static func decode_splat(bytes: PackedByteArray, index: int, degree: int) -> Dictionary:
	var d := ShQuantizer.clamp_degree(degree)
	var stride := stride_bytes(d)
	var base := index * stride
	if base + stride > bytes.size():
		return {"ok": false, "message": "index out of range"}
	var cov := PackedFloat32Array()
	cov.resize(6)
	for k in 6:
		cov[k] = bytes.decode_float(base + 16 + k * 4)
	return {
		"ok": true,
		"position": Vector3(
			bytes.decode_float(base + 0),
			bytes.decode_float(base + 4),
			bytes.decode_float(base + 8)
		),
		"opacity": float(bytes[base + 12]) / 255.0,
		"degree": int(bytes[base + 13]),
		"covariance": cov,
		"sh_start": base + CORE_BYTES,
	}


static func _error(code: Error, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"message": message
	}
