class_name HaloFix
extends RefCounted
## 把角色（含同伴 / 玩家 / Boss）头顶那圈**光环**修成像蔚蓝档案那样的「发光环」。
##
## ── 为什么需要这一步（2026-10-22 用户：「柚子的光环好像渲染出问题了」）──
## 导出的素材里光环是这样的（`_probe_halo_shot.gd` 实测）：
##     网格   `Yuzu_Original_Halo2`，0.274 × 0.202 × 0.170 m
##     材质   `Yuzu_Original_Halo`：albedo 纯白、`transparency=0`（不透明）、
##            `cull=2`（双面）、**`unshaded=false`、`emission=false`**
##     贴图   `Yuzu_Yuzu_Original_Halo.png` 只有 **32×32**、**没有 alpha 通道**
## 于是问题出在三处：
##   ① **受光**：它是个低模圆环（一圈平面片拼的），被场景灯光一照，每个面片亮度不同，
##      近看就是一格一格的棱 —— 这就是「渲染出问题」最扎眼的那个；
##   ② **不发光**：真正的光环是自发光体，游戏里开了辉光（glow）也不会亮；
##   ③ 还**投阴影**：一个发光体在头顶投一道硬阴影，非常出戏。
## 修法（只改材质，不动网格 / 不动贴图）。**三种做法都比过图**
## （`_probe_halo_shot.gd` → `_arisu_captures/_halo/`）：
##     before  受光、不发光、投阴影 —— 面片一格一格，像塑料片
##     after   完全 `UNSHADED`       —— 棱没了，但**整圈死平**，像个贴纸
##     lit     **受光 + 自发光 0.8** —— 有体积感、又真的在发光（选它）
## 所以最终用的是第三种：
##   · `emission_enabled` + `emission_texture = albedo_texture` + 能量 0.8
##     —— 颜色全靠贴图，别自己染色（各家光环颜色不同：柚子黄、小桃粉、小空蓝）；
##   · `cast_shadow = OFF` —— 发光体不投阴影；
##   · 保留受光（`PER_PIXEL`），别改 `UNSHADED`。
##
## ⚠️ 不透明那一条**故意不动**：贴图没有 alpha，改成透明只会得到一块半透的方片。
## ⚠️ 材质是 `StandardMaterial3D` 时才能这么改；别的着色器（自定义 shader）跳过。

## 名字里带这些词（小写比较）的网格就当成光环
const HINTS := ["halo", "光环"]

## 把所有光环网格改造一遍。返回报告：
##     meshes    int                 找到几个光环网格
##     applied   int                 真的改了几个材质
##     names     Array[String]       改到的网格名（日志用）
static func polish(root: Node3D) -> Dictionary:
	var report := {"meshes": 0, "applied": 0, "names": [] as Array}
	if root == null:
		return report
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if not _looks_like_halo(String(mi.name)):
			continue
		report["meshes"] = int(report["meshes"]) + 1
		# 一个网格可能有多个 surface（柚子这个是 1 个），逐个来
		var surfaces := mi.get_surface_override_material_count()
		if mi.mesh != null:
			surfaces = maxi(surfaces, mi.mesh.get_surface_count())
		for s in surfaces:
			var src := _material_of(mi, s)
			if src == null:
				continue
			var mat := _polish_material(src)
			if mat == null:
				continue
			mi.set_surface_override_material(s, mat)
			report["applied"] = int(report["applied"]) + 1
		# 光环不投阴影
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(report["names"] as Array).append(String(mi.name))
	return report


static func _looks_like_halo(name_lower: String) -> bool:
	var low := name_lower.to_lower()
	for hint in HINTS:
		if low.contains(String(hint)):
			return true
	return false


static func _material_of(mi: MeshInstance3D, surface: int) -> Material:
	var m := mi.get_surface_override_material(surface)
	if m != null:
		return m
	if mi.mesh == null or surface >= mi.mesh.get_surface_count():
		return null
	return mi.mesh.surface_get_material(surface)


## 返回**复制过**的新材质（原材质是 glb 导入出来的共享资源，直接改会波及所有实例）
static func _polish_material(src: Material) -> StandardMaterial3D:
	if not (src is StandardMaterial3D):
		return null
	var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	# ⚠️ 不要设成 UNSHADED：那会让环变成一张「死平的贴纸」（渲图比过，见文件头）。
	#    保留受光，再叠自发光，才有「有体积 + 在发亮」的观感。
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# ── 自发光：颜色必须**乘贴图**，不能是纯白（2026-11-10 修）──
	#
	# 用户：「光环自发光,把本来颜色全部遮掉了!」。
	# 原因：`emission = Color(1,1,1)` + `emission_texture = albedo`，
	# 而 StandardMaterial3D 的自发光是**加法**叠加在 albedo 之上，于是
	#     输出的颜色 ≈ 贴图 × (1 + 0.8) = 贴图 × 1.8
	# 柚子的光环贴图本身是**黄色** `(255, 207, 117)`，乘 1.8 后 R 通道直接
	# 饱和到 255、G/B 也被推高 ⇒ 看上去就是一团**白光**，黄色全丢了。
	# 小桃/小绿那些本来就是浅色的光环没那么明显，所以只有柚子特别扎眼。
	#
	# 改法：`emission` 用**贴图的主色调**去染，而不是纯白。
	# 但各家光环颜色不同（柚子黄 / 小桃粉 / 小空蓝），硬编码又会错。
	# ⇒ 直接从 albedo 贴图**采样平均色**当 emission 颜色，
	#   这样每一家的自发光都是"它自己的颜色在发光"，而不是一律白光。
	var tint := _average_color(mat.albedo_texture)
	if mat.emission_texture == null and mat.albedo_texture != null:
		mat.emission_texture = mat.albedo_texture
	mat.emission_enabled = true
	mat.emission = tint
	# 亮度也降下来：0.8 叠在自身颜色上仍然容易过曝，0.45 是"亮但不糊"的量级
	mat.emission_energy_multiplier = 0.45
	# 双面保持（环从下往上看也是环），但把「背光面黑」这件事彻底消掉：unshaded 已经解决
	return mat


## 采样贴图的**平均颜色**（跳过全透明像素）。
##
## 贴图只有 32×32，全量扫一遍也不到 1000 个像素，开销可以忽略。
## 返回的是「这个光环大概是什么颜色」——柚子得到偏黄、小桃偏粉。
##
## ⚠️ 贴图可能是压缩格式，`get_image()` 前必须先 `get_image()`（会从 GPU 取回，
##    headless 下也能用；万一取不到就退回白色，至少不会崩）。
static var _tint_cache := {}


static func _average_color(tex: Texture2D) -> Color:
	if tex == null:
		return Color(1.0, 1.0, 1.0)
	var key := tex.resource_path
	if key != "" and _tint_cache.has(key):
		return _tint_cache[key]

	# ── 两条取图路径 ──
	#
	# ⚠️ `tex.get_image()` 在 headless / 纹理还没上传时可能返回 null，
	#    结果是 `_average_color` 退回白色 —— 那又会把颜色遮掉。
	#    所以再走一条：**直接从磁盘读那张 PNG**。
	#    素材是本地的（`models/companions/*.png`），路径就在 `tex.resource_path` 里。
	# ⚠️ **必须优先从磁盘读 PNG**，不能先信 `tex.get_image()`。
	#
	# 实测（`_probe_halo_color.gd`）：headless 下 `tex.get_image()` 返回的是
	# **格式 17（压缩纹理，BPTC/S3TC）且所有像素都是 (0,0,0,1)** ——
	# 图"取得成功"，但内容是黑的。本喵第一版就是因为这个算出纯黑自发光，
	# 然后又把颜色问题伪装成"已修复"。
	# `Image.load_from_file()` 直接解 PNG，拿到的是真实像素（柚子 = 黄 205）。
	var img: Image = null
	var src_desc := ""
	if key != "":
		var loaded := Image.load_from_file(key)
		if loaded != null and loaded.get_width() > 0:
			img = loaded
			src_desc = "磁盘 PNG"
	if img == null:
		# 退而求其次：运行时纹理（可能是未压缩的）
		var t := tex.get_image()
		if t != null and _has_real_pixels(t):
			img = t
			src_desc = "运行时纹理"
	if img == null:
		print("[HaloFix] 取不到可用贴图 %s ⇒ 用兜底主色" % key)
		return _fallback_tint(key)
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return Color(1.0, 1.0, 1.0)
	# ⚠️ 必须用**独立 float 累加**，不能 += 到 Color 上：
	#    GDScript 的 Color 是**值类型**（struct），`acc.r += c.r` 改的是临时副本，
	#    累加器永远是 (0,0,0) —— 这正是本喵第一版算出"纯黑自发光"的原因。
	var ar := 0.0
	var ag := 0.0
	var ab := 0.0
	var n := 0
	# 最多采样 32×32（大贴图也够代表主色了）
	var step := maxi(1, maxi(w, h) / 32)
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			if c.a < 0.15:
				continue
			ar += c.r
			ag += c.g
			ab += c.b
			n += 1
	if n == 0:
		return _fallback_tint(key)
	var avg := Color(ar / float(n), ag / float(n), ab / float(n), 1.0)
	# 全黑 = 还是没解出真像素，退兜底色（绝不能返回纯黑，那会让光环不亮）
	if avg.r < 0.02 and avg.g < 0.02 and avg.b < 0.02:
		return _fallback_tint(key)
	# 稍微提亮：自发光要有点"在发亮"的意思，但别把颜色压淡
	avg = Color(minf(avg.r * 1.15, 1.0), minf(avg.g * 1.15, 1.0), minf(avg.b * 1.15, 1.0), 1.0)
	if key != "":
		_tint_cache[key] = avg
	return avg




## 取不到贴图时的兜底色。
##
## ⚠️ 绝不能返回纯白 —— 那正是「自发光遮掉本来的颜色」的成因。
## 这里按**文件名**给一个各家光环的主色（蔚蓝档案里这些角色的光环确实是这些色），
## 认不出来时给一个**暖白**（不是纯白，留一点温度）。
static func _fallback_tint(path: String) -> Color:
	var p := path.to_lower()
	if p.contains("yuzu"):
		return Color(1.00, 0.82, 0.46)   # 柚子：黄
	if p.contains("momoi"):
		return Color(1.00, 0.62, 0.78)   # 小桃：粉
	if p.contains("midori"):
		return Color(0.55, 0.95, 0.65)   # 小绿：绿
	if p.contains("aris"):
		return Color(0.70, 0.88, 1.00)   # 爱丽丝：淡蓝
	if p.contains("yuuka"):
		return Color(1.00, 0.72, 0.85)   # 优香：粉
	return Color(1.00, 0.95, 0.88)       # 兜底：暖白（不是纯白）


## 这个 Image 里有没有**真实像素**（不是全黑/全透明）。
##
## 用来识别「`tex.get_image()` 拿到压缩纹理但没解码」这种情况 ——
## 那时候图尺寸正常、像素全是 0，直接拿去平均会得到纯黑。
static func _has_real_pixels(img: Image) -> bool:
	if img == null:
		return false
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return false
	var step := maxi(1, maxi(w, h) / 16)
	var checked := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			checked += 1
			if c.r > 0.02 or c.g > 0.02 or c.b > 0.02:
				return true
	return false
