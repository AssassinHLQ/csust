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
	# 自发光：贴图当 emission 贴图，颜色给白，能量 0.8 —— 颜色全靠贴图，别自己染
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.8
	if mat.emission_texture == null and mat.albedo_texture != null:
		mat.emission_texture = mat.albedo_texture
	# 双面保持（环从下往上看也是环），但把「背光面黑」这件事彻底消掉：unshaded 已经解决
	return mat
