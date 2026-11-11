extends SceneTree
## 重新生成混凝土贴图：**更细腻**（1024²，颗粒更小、层次更多）。
##
## 用户 2026-11-11：「太粗糙了，不够细腻，近看特别糊」。
##
## 上一版的问题（两条，都要修）：
##   ① 分辨率只有 512²，而一面墙有 8×6 m —— 单个纹素在墙上就有 1.5 cm，
##      近看必然糊；
##   ② 噪声的格点数太少（3/11/43），最小的颗粒也有很大一块 ——
##      所以看上去是"面粉团"而不是"水泥颗粒"。
##
## 这一版：
##   · 1024²（单纹素 ~0.8 cm，近看明显细腻）
##   · 格点加密到 **5 / 23 / 97 / 311**（四层），最细那层是毛发级颗粒
##   · 高度场改成"细颗粒主导"：细层权重最大，大斑驳只做很轻的底噪
##   · 法线强度也调低（1.4），避免近看一片凹凸肉麻
##
## 用法：& <godot_console.exe> --headless --path . --script res://scripts/_gen_concrete_tex.gd
## 输出：assets/tex/concrete_{albedo,rough,normal}.png

const OUT_DIR := "res://assets/tex"
## 贴图边长。1024² 是 RGB8 × 3 张 ≈ 2.4 MB 落盘，显存走 bptc 压缩后很小。
const SIZE := 1024


func _initialize() -> void:
	_gen.call_deferred()


func _gen() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var n := SIZE

	var alb := PackedFloat32Array()
	var rgh := PackedFloat32Array()
	var hgt := PackedFloat32Array()
	alb.resize(n * n)
	rgh.resize(n * n)
	hgt.resize(n * n)

	for y in n:
		for x in n:
			var fx := float(x) / float(n)
			var fy := float(y) / float(n)
			# 四层：大斑驳 / 中颗粒 / 细颗粒 / 毛发级
			var big := _fbm(fx, fy, 5, 3)
			var mid := _fbm(fx, fy, 23, 3)
			var fine := _fbm(fx, fy, 97, 2)
			var micro := _fbm(fx, fy, 311, 1)
			var i := y * n + x

			# 高度：**细层主导**，颗粒才细腻
			hgt[i] = micro * 0.40 + fine * 0.34 + mid * 0.20 + big * 0.06

			# 反照率起伏：0.86~1.04
			# ⚠️ 第一版给 0.90~1.06 太淡，墙上几乎看不出斑驳（只剩法线在动），
			#    用户看到的还是一张白纸。这里把低频/中频的权重加大一档，
			#    让"灰色的水泥斑"真的看得见，同时细颗粒仍占小份。
			alb[i] = 0.86 + big * 0.11 + mid * 0.10 + fine * 0.05

			# 粗糙度：0.84~0.96
			rgh[i] = 0.84 + big * 0.05 + fine * 0.04 + micro * 0.03

	# ── albedo（灰度）──
	var img_a := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var c := int(round(clampf(alb[y * n + x], 0.0, 1.0) * 255.0))
			img_a.set_pixel(x, y, Color8(c, c, c))
	img_a.save_png(ProjectSettings.globalize_path(OUT_DIR).path_join("concrete_albedo.png"))

	# ── roughness（灰度）──
	var img_r := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var c := int(round(clampf(rgh[y * n + x], 0.0, 1.0) * 255.0))
			img_r.set_pixel(x, y, Color8(c, c, c))
	img_r.save_png(ProjectSettings.globalize_path(OUT_DIR).path_join("concrete_rough.png"))

	# ── normal（Sobel，强度 1.4）──
	var img_n := Image.create(n, n, false, Image.FORMAT_RGB8)
	var strength := 1.4
	for y in n:
		for x in n:
			var xl := (x - 1 + n) % n
			var xr := (x + 1) % n
			var yu := (y - 1 + n) % n
			var yd := (y + 1) % n
			var dx := (hgt[y * n + xr] - hgt[y * n + xl]) * strength
			var dy := (hgt[yd * n + x] - hgt[yu * n + x]) * strength
			var nx := -dx
			var ny := -dy
			var nz := 1.0
			var l := sqrt(nx * nx + ny * ny + nz * nz)
			img_n.set_pixel(x, y, Color(
				nx / l * 0.5 + 0.5, ny / l * 0.5 + 0.5, nz / l * 0.5 + 0.5))
	img_n.save_png(ProjectSettings.globalize_path(OUT_DIR).path_join("concrete_normal.png"))

	print("[concrete] %d² 重新生成完毕（格点 5/23/97/311 四层）→ %s"
		% [n, ProjectSettings.globalize_path(OUT_DIR)])
	quit(0)


func _fbm(x: float, y: float, cells: int, octaves: int) -> float:
	var total := 0.0
	var amp := 1.0
	var norm := 0.0
	var c := cells
	for _o in octaves:
		total += _tile_noise(x, y, c) * amp
		norm += amp
		amp *= 0.5
		c *= 2
	return total / norm


func _tile_noise(x: float, y: float, c: int) -> float:
	var fx := x * float(c)
	var fy := y * float(c)
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var v00 := _rand01(_wrapi(x0, c), _wrapi(y0, c))
	var v10 := _rand01(_wrapi(x0 + 1, c), _wrapi(y0, c))
	var v01 := _rand01(_wrapi(x0, c), _wrapi(y0 + 1, c))
	var v11 := _rand01(_wrapi(x0 + 1, c), _wrapi(y0 + 1, c))
	return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), ty)


func _wrapi(v: int, m: int) -> int:
	return ((v % m) + m) % m


func _rand01(ix: int, iy: int) -> float:
	var h := ix * 374761393 + iy * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)
