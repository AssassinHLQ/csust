@tool
extends RefCounted

## CPU counting sort producing a back-to-front splat order for the Raster backend.
##
## Reads only positions (GaussianResource.xyz); it never touches the 60-float
## blob. The sort key is `dot(center, view_dir_local)` — the splat centre
## projected onto the camera forward direction expressed in the splat's local
## space (positions are the recentered local coordinates). Larger key = farther
## into the scene = drawn first, so the result is ordered far→near for standard
## "over" blending.
##
## A single 16-bit counting pass gives 65536 depth buckets across the scene's
## depth range — ample resolution for splatting, O(n + buckets), and cheap enough
## to run every frame the camera moves (on a worker thread; see raster_sort_job).
## Within a bucket, ties keep original index order (stable).
##
## The scatter writes indices straight in the layout the R32F order texture
## wants — float32, padded to the texture's texel count — so the main thread only
## ever hands finished bytes to Image.set_data. This is deliberate: converting
## int→float per splat on the main thread instead cost 23 ms at 1M splats every
## time a sort landed, i.e. a dropped frame per re-sort.
##
## ── 组顺序模式（为什么这个排序不是瓶颈）────────────────────────────────
## 逐高斯排序在 GDScript 里对 278 万点要 **812 ms**（实测 _probe_sort_cost.gd）。
## 后端双缓冲 + 「排序在飞时不重踢」，所以快速转身后有 800 ms 左右画面拿的是
## **转身前那张排序表** —— 深度顺序整体反了，远端几何最后画、盖住近端，
## 看起来就是「后面的高斯还没加载」。这是本文件最需要防的回归。
##
## 解法：源顺序本身有很强的空间局部性（locality_ratio 实测 0.0102），所以
## **只排「每 group 个一组」的组质心**就够了，组内按源顺序连排。排序量少
## group 倍 ⇒ 812 ms → 30 ms 上下，double-buffer 的陈旧窗口短到看不见。
## 着色器侧对应 gaussian_raster.gdshader 的 order_group。

const BUCKET_BITS := 16
const BUCKET_COUNT := 1 << BUCKET_BITS   # 65536

## Sort into a caller-provided buffer to avoid per-frame allocation. `out_order`
## is resized to `texel_count` — the order texture's padded texel count, or -1 for
## exactly xyz.size() — and its first xyz.size() entries are filled with splat
## indices far→near, stored as floats. Padding entries stay 0.0 and are never
## fetched: the shader only reads sorted positions below point_count. Returns the
## same array for convenience.
static func sort_into(xyz: PackedVector3Array, view_dir_local: Vector3, out_order: PackedFloat32Array, texel_count: int = -1) -> PackedFloat32Array:
	var n := xyz.size()
	var size := maxi(texel_count, n) if texel_count >= 0 else n
	if out_order.size() != size:
		out_order.resize(size)
	if n == 0:
		return out_order

	var dx := view_dir_local.x
	var dy := view_dir_local.y
	var dz := view_dir_local.z

	var keys := PackedFloat32Array()
	keys.resize(n)
	var kmin := INF
	var kmax := -INF
	for i in range(n):
		var p := xyz[i]
		var k := p.x * dx + p.y * dy + p.z * dz
		keys[i] = k
		if k < kmin:
			kmin = k
		if k > kmax:
			kmax = k

	if kmax <= kmin:
		for i in range(n):
			out_order[i] = float(i)
		return out_order

	var scale := float(BUCKET_COUNT - 1) / (kmax - kmin)

	var counts := PackedInt32Array()
	counts.resize(BUCKET_COUNT)   # zero-initialised
	for i in range(n):
		var b := int((keys[i] - kmin) * scale)
		b = clampi(b, 0, BUCKET_COUNT - 1)
		counts[b] += 1

	# Descending scatter offsets: bucket BUCKET_COUNT-1 (farthest) goes first.
	var offset := 0
	for b in range(BUCKET_COUNT - 1, -1, -1):
		var c := counts[b]
		counts[b] = offset
		offset += c

	for i in range(n):
		var b := int((keys[i] - kmin) * scale)
		b = clampi(b, 0, BUCKET_COUNT - 1)
		out_order[counts[b]] = float(i)
		counts[b] += 1

	return out_order

## Convenience wrapper that allocates a fresh order array.
static func sort(xyz: PackedVector3Array, view_dir_local: Vector3) -> PackedFloat32Array:
	return sort_into(xyz, view_dir_local, PackedFloat32Array())


## 把点按每 `group` 个一组求质心 —— 组顺序排序的排序键。
##
## 组内的高斯不参与排序，直接按源顺序连排，所以**组宽是精度与速度的旋钮**：
## 组越宽越快，但组内的深度乱序也越大。实测本工程两份扫描的组内离散度
## （质心到成员的平均距离）随组宽按 √group 增长，取 32 时约 0.023 源单位，
## 与相邻高斯的平均间距（0.022）同量级 —— 也就是组内乱序不到一个高斯间距。
##
## ⚠️ 只有源顺序有空间局部性时这个近似才成立，所以调用方必须先用
## locality_ratio() 验过（见 raster_render_backend.gd 的 _choose_order_group）。
static func block_centroids(xyz: PackedVector3Array, group: int) -> PackedVector3Array:
	var n := xyz.size()
	var g := maxi(group, 1)
	var out := PackedVector3Array()
	if g == 1:
		return xyz.duplicate()
	out.resize(int(ceil(float(n) / float(g))))
	var gi := 0
	var i := 0
	while i < n:
		var hi := mini(i + g, n)
		var acc := Vector3.ZERO
		for k in range(i, hi):
			acc += xyz[k]
		out[gi] = acc / float(hi - i)
		gi += 1
		i = hi
	return out


## 源顺序的**空间局部性**：相邻高斯平均距离 ÷ 随机高斯对平均距离。
##
## 约 1 ⇒ 源顺序和乱序没区别，分组排序不成立（此时组内乱序会退化成全随机）。
## ≪ 1 ⇒ 相邻的高斯在空间上挨着（SOG / splat-transform 之类的导出器普遍
## 按空间曲线重排过点），于是「组内按源顺序连排」几乎无损。
##
## 实测：room609.sogdata = 0.0102，相邻平均 0.0221 vs 随机 2.1626。
## 采样很少（默认 3000 对），因为只需要判「是 0.01 还是 0.5」这种量级。
static func locality_ratio(xyz: PackedVector3Array, samples: int = 3000) -> float:
	var n := xyz.size()
	if n < 4:
		return 1.0
	var rng := RandomNumberGenerator.new()
	# 固定种子：同一个资源每次判出来的组宽都一样，否则会出现「这次启动
	# 用了分组、下次启动没用」的随机行为。
	rng.seed = 0x5f3d1c
	var count := mini(samples, n - 1)
	var d_adj := 0.0
	for _s in count:
		var i := rng.randi_range(0, n - 2)
		d_adj += xyz[i].distance_to(xyz[i + 1])
	d_adj /= float(count)
	var d_rand := 0.0
	for _s in count:
		var a := rng.randi_range(0, n - 1)
		var b := rng.randi_range(0, n - 1)
		d_rand += xyz[a].distance_to(xyz[b])
	d_rand /= float(count)
	if d_rand <= 1e-9:
		return 1.0
	return d_adj / d_rand
