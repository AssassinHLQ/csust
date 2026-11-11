extends SceneTree
## 生成混凝土的**程序化噪声贴图**（粗糙度 + 法线），离线跑一次写进 `textures/`。
##
## 为什么要贴图：用户 2026-11-11「店里白墙改混凝土的质感」。
## 只把颜色改成灰色 = **灰色塑料**，不像混凝土。混凝土的特征是
##   · 表面有细密的颗粒/气孔（高频噪声）
##   · 大尺度上有斑驳（低频噪声）
##   · 粗糙度不均匀（有的地方更哑，有的地方微亮）
## 这三样都要贴图，法线贴图负责「颗粒感」在光照下的凹凸。
##
## 本脚本**生成三张图**（512²，够用了，别上 4K 浪费显存）：
##   concrete_albedo.png    灰度斑驳（叠在 albedo_color 上做明暗变化）
##   concrete_rough.png     粗糙度变化（0.80~0.95）
##   concrete_normal.png    法线（颗粒凹凸）
##
## 用法：& <godot_console.exe> --headless --path . --script res://scripts/_gen_concrete_tex.gd
## 输出：assets/tex/concrete_*.png（`.import` 已随仓库提供，按 lot_paver 的惯例写好）

const OUT_DIR := "res://assets/tex"


func _initialize() -> void:
	_gen.call_deferred()


func _gen() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var n := 512

	# 三张同尺寸的浮点缓冲
	var alb := PackedFloat32Array()
	var rgh := PackedFloat32Array()
	var hgt := PackedFloat32Array()
	alb.resize(n * n)
	rgh.resize(n * n)
	hgt.resize(n * n)

	# ── 可平铺的 value noise：整数格点 + 双线性 + smoothstep ──
	# `period` 让噪声在 period 格后重复 → 贴图无缝
	for y in n:
		for x in n:
			var fx := float(x) / float(n)
			var fy := float(y) / float(n)
			# 大斑驳：3 格一循环
			var big := _fbm(fx, fy, 3, 4)
			# 中颗粒：11 格
			var mid := _fbm(fx, fy, 11, 4)
			# 细颗粒（气孔）：43 格
			var fine := _fbm(fx, fy, 43, 2)
			var i := y * n + x
			# 高度：细颗粒为主，中颗粒给"抹子痕"
			hgt[i] = fine * 0.55 + mid * 0.45
			# 反照率：0.82~1.08 的明暗起伏（叠到 albedo_color 上）
			alb[i] = 0.82 + big * 0.16 + mid * 0.10
			# 粗糙度：0.80~0.95
			rgh[i] = 0.80 + big * 0.09 + fine * 0.06

	# ── 写 albedo（灰度）──
	var img_a := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var v := clampf(alb[y * n + x], 0.0, 1.0)
			var c := int(round(v * 255.0))
			img_a.set_pixel(x, y, Color8(c, c, c))
	img_a.save_png(ProjectSettings.globalize_path(OUT_DIR).path_join("concrete_albedo.png"))

	# ── 写 roughness（灰度）──
	var img_r := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var v := clampf(rgh[y * n + x], 0.0, 1.0)
			var c := int(round(v * 255.0))
			img_r.set_pixel(x, y, Color8(c, c, c))
	img_r.save_png(ProjectSettings.globalize_path(OUT_DIR).path_join("concrete_rough.png"))

	# ── 写法线（Sobel 求高度梯度）──
	var img_n := Image.create(n, n, false, Image.FORMAT_RGB8)
	var strength := 2.2
	for y in n:
		for x in n:
			var xl := (x - 1 + n) % n
			var xr := (x + 1) % n
			var yu := (y - 1 + n) % n
			var yd := (y + 1) % n
			var dx := (hgt[y * n + xr] - hgt[y * n + xl]) * strength
			var dy := (hgt[yd * n + x] - hgt[yu * n + x]) * strength
			# 切线空间法线：(-dx, -dy, 1) 归一化 → 映射到 0..1
			var nx := -dx
			var ny := -dy
			var nz := 1.0
			var l := sqrt(nx * nx + ny * ny + nz * nz)
			nx /= l
			ny /= l
			nz /= l
			img_n.set_pixel(x, y, Color(
				nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5))
	img_n.save_png(ProjectSettings.globalize_path(OUT_DIR).path_join("concrete_normal.png"))

	print("[concrete] 生成完毕：%d² albedo / rough / normal → %s"
		% [n, ProjectSettings.globalize_path(OUT_DIR)])
	quit(0)


## 可平铺 fbm：`cells` 个格点一循环，`octaves` 层叠加
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


## 一层的可平铺 value noise（在 c×c 网格上，周期 1.0）
func _tile_noise(x: float, y: float, c: int) -> float:
	var fx := x * float(c)
	var fy := y * float(c)
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	# smoothstep 插值，避免格子棱
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var v00 := _rand01(_wrapi(x0, c), _wrapi(y0, c))
	var v10 := _rand01(_wrapi(x0 + 1, c), _wrapi(y0, c))
	var v01 := _rand01(_wrapi(x0, c), _wrapi(y0 + 1, c))
	var v11 := _rand01(_wrapi(x0 + 1, c), _wrapi(y0 + 1, c))
	var a := lerpf(v00, v10, tx)
	var b := lerpf(v01, v11, tx)
	return lerpf(a, b, ty)


func _wrapi(v: int, m: int) -> int:
	return ((v % m) + m) % m


## 确定性哈希 → 0..1（同一个格点永远同一个值，贴图可重复生成）
func _rand01(ix: int, iy: int) -> float:
	var h := ix * 374761393 + iy * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)
