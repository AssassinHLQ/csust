@tool
extends RefCounted

## 8-bit spherical-harmonics quantization (gsplat-stream addition).
##
## The canonical GDGS GPU layout is 60 float32 per splat (240 B), of which
## 48 floats (192 B, 80%) are SH coefficients. This module replaces that
## payload with signed 8-bit coefficients sharing one global scale per
## resource, storing 3/12/27/48 B per splat for SH degree 0/1/2/3.
##
## Storage convention: value_i8 = clamp(round(coeff / scale), -127, 127),
## written as unsigned (value_i8 + BIAS). The shader decodes with
## float(byte) - BIAS, then multiplies by the resource scale.
##
## Everything here is CPU-only and headless-testable; it does not touch GPU
## resources.

## Coefficients per colour channel for SH degree 0..3.
const COEFFS_PER_CHANNEL := [1, 4, 9, 16]
## Bytes per splat, 4-byte aligned so shaders can read it as uint words.
const STRIDE_PER_DEGREE := [4, 12, 28, 48]
## Bias added when packing a signed coefficient into an unsigned byte.
const BIAS := 128
## Float count of the canonical (degree 3) SH payload per splat.
const CANONICAL_SH_FLOATS := 48
## Canonical SH byte cost per splat (48 * 4).
const CANONICAL_SH_BYTES := 192


static func clamp_degree(degree: int) -> int:
	return clampi(degree, 0, 3)


static func coeff_count(degree: int) -> int:
	return COEFFS_PER_CHANNEL[clamp_degree(degree)] * 3


static func stride(degree: int) -> int:
	return STRIDE_PER_DEGREE[clamp_degree(degree)]


static func bytes_per_splat(degree: int) -> int:
	return stride(degree)


## Ratio between the canonical float32 SH payload and the quantized one.
static func savings_vs_canonical(degree: int) -> float:
	return float(CANONICAL_SH_BYTES) / float(stride(degree))


## Quantize a canonical SH buffer (`count * 48` floats, channel-major per
## splat in the same order the decoder produced) into packed bytes.
##
## Returns {"ok", "bytes", "scale", "degree", "coeff_count"} or
## {"ok": false, "message"} on a size mismatch.
static func quantize(sh_floats: PackedFloat32Array, count: int, degree: int) -> Dictionary:
	var d := clamp_degree(degree)
	var cc := coeff_count(d)
	var st := stride(d)

	if count <= 0:
		return {
			"ok": true,
			"bytes": PackedByteArray(),
			"scale": 1.0,
			"degree": d,
			"coeff_count": cc,
		}
	if sh_floats.size() != count * CANONICAL_SH_FLOATS:
		return {
			"ok": false,
			"message": "SH buffer size mismatch: expected %d, got %d" % [
				count * CANONICAL_SH_FLOATS, sh_floats.size()
			],
		}

	# One global scale keeps the byte stream free of per-splat metadata.
	var max_abs := 0.0
	for s in count:
		var base := s * CANONICAL_SH_FLOATS
		for c in cc:
			var v := absf(sh_floats[base + c])
			if v > max_abs:
				max_abs = v

	var scale := max_abs / 127.0
	if scale <= 1e-12:
		scale = 1.0 / 127.0
	var inv_scale := 1.0 / scale

	var out := PackedByteArray()
	out.resize(count * st)
	out.fill(0)
	for s in count:
		var src := s * CANONICAL_SH_FLOATS
		var dst := s * st
		for c in cc:
			var q := int(round(sh_floats[src + c] * inv_scale))
			if q > 127:
				q = 127
			elif q < -127:
				q = -127
			out[dst + c] = q + BIAS

	return {
		"ok": true,
		"bytes": out,
		"scale": scale,
		"degree": d,
		"coeff_count": cc,
	}


## Inverse of `quantize`, used by tests and by any CPU-side preview path.
## Coefficients above the stored degree come back as 0.
static func dequantize(packed: PackedByteArray, count: int, degree: int, scale: float) -> PackedFloat32Array:
	var d := clamp_degree(degree)
	var cc := coeff_count(d)
	var st := stride(d)

	var out := PackedFloat32Array()
	out.resize(maxi(count, 0) * CANONICAL_SH_FLOATS)
	out.fill(0.0)
	if count <= 0 or packed.size() < count * st:
		return out

	for s in count:
		var src := s * st
		var dst := s * CANONICAL_SH_FLOATS
		for c in cc:
			out[dst + c] = float(int(packed[src + c]) - BIAS) * scale
	return out


## Byte cost of the quantized SH buffer for `count` splats.
static func buffer_bytes(count: int, degree: int) -> int:
	return maxi(count, 0) * stride(degree)
