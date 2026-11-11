class_name EyeFix
extends RefCounted
## 去掉眼睛材质上的**实时清漆高光**（`clearcoat`），消掉「一只眼比另一只亮」。
##
## ── 现象（用户 2026-11-11）──
## 「为什么眼睛有时候右眼反光些？」
##
## ── 实测（`_probe_aris_reload_eyes.gd` 把材质参数全打出来）──
## 爱丽丝的左右眼**共用同一份材质** `Aris_Original_EyeMouth`
## （同一块网格 `Aris_Original_Body_001` 的 surface 2，393 个顶点、两只眼都在里面），
## 所以**不可能是「两份材质参数不一样」**。它的参数是：
##     metallic = 0.0    roughness = 0.85    metallic_specular = 0.5
##     **clearcoat = 1.0  clearcoat_roughness = 0.5**
##     rim_enabled = false   emission_enabled = false
##     albedo = `models/Arisu_ext_Aris_Original_EyeMouth.png`
##
## ── 为什么清漆会造成「左右不一样」──
## `clearcoat` 是覆盖在材质上的一层**独立镜面反射**（模拟车漆/指甲油那种「浮在表面」的高光），
## 它**不跟着贴图走，只跟着几何法线和光照/视角走**。
## 眼球是个球面，左右两只球的法线朝向不同 —— 头一转、或者视角一偏，
## 高光就落到其中一只上。所以现象是「**有时候**右眼反光些」而不是「右眼一直更亮」。
##
## 而 BA 的眼睛本来就**把高光画在 albedo 贴图里**（那几块白色亮斑）。
## 贴图上的高光 + 实时清漆高光 = 多出来一块会动的反光，看着像一只眼上了油。
##
## ── 修法 ──
## 把**眼睛**材质的 `clearcoat` 归零（其余参数一律不动，roughness/albedo/自发光原样）。
## 这样眼睛只剩「漫反射 + 贴图里画好的高光」，左右必然对称。
##
## ⚠️ 只动名字里带 `eye` 的材质。眉毛（`Aris_Original_Eyebrow`）也有 clearcoat=1.0，
##    但眉毛是平的、几乎不产生可分辨的高光，动了反而是没必要的改动。
## ⚠️ 只动 `clearcoat`。别顺手改 `roughness` / `metallic_specular` ——
##    那两个会影响皮肤整体的观感，用户没抱怨那里。

## 材质名里出现这些词 → 认为是**眼睛本体**
const EYE_KEYWORDS := ["eye"]
## 但这些词要排除。⚠️ 第一版只写了 `EYE_KEYWORDS = ["eye"]` 就收工，
## 结果 `Aris_Original_Eyebrow`（眉毛）、`Aris_Original_EyeMouth_Mouth_401`（嘴）
## 全被当成眼睛改了 —— 12 个材质一个不落。文档里写着「只动眼睛」而代码动了一大片，
## 这种「注释和行为不一致」比不改更糟，所以这里把排除项显式列出来：
##   · `brow` 眉毛 / `lash` 睫毛 —— 平的，几乎不出高光，改它没意义
##   · `_mouth` 嘴 —— 注意这里必须写**带下划线的 `_mouth`**：
##     独立嘴网格叫 `Aris_Original_EyeMouth_Mouth_401`（含 `_mouth`）要排除；
##     而眼睛本体那份材质的名字是 `Aris_Original_EyeMouth`（眼睛和嘴共用一张贴图集，
##     所以名字里有 `mouth` 但没有下划线），**不能被排除**。
##     ⚠️ 本喵第一版写的是 `"mouth"`，结果把眼睛本体也排掉了，`changed` 直接变 0 —— 
##        过滤条件写宽了和写窄了一样都是错，注释里写的规则必须就是代码里的规则。
const EYE_EXCLUDE := ["brow", "lash", "_mouth"]
const META_DONE := "_eye_clearcoat_off"


## 遍历整棵模型树，把眼睛材质的 clearcoat 归零。
## 返回 {materials: 改了几个, names: [材质名...], before: [原 clearcoat...]}
static func kill_eye_clearcoat(root: Node) -> Dictionary:
	var changed := 0
	var names: Array[String] = []
	var before: Array[float] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat == null or not (mat is BaseMaterial3D):
				continue
			if mat.has_meta(META_DONE):
				continue
			var nm := String(mat.resource_name).to_lower()
			var hit := false
			for kw in EYE_KEYWORDS:
				if nm.contains(kw):
					hit = true
					break
			if not hit:
				continue
			var skip := false
			for kw in EYE_EXCLUDE:
				if nm.contains(kw):
					skip = true
					break
			if skip:
				continue
			var b := mat as BaseMaterial3D
			if b.clearcoat <= 0.0:
				mat.set_meta(META_DONE, true)
				continue
			before.append(b.clearcoat)
			b.clearcoat = 0.0
			mat.set_meta(META_DONE, true)
			names.append(String(mat.resource_name))
			changed += 1
	return {"materials": changed, "names": names, "before": before}
