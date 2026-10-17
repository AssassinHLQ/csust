class_name PoseFix
extends RefCounted
## 运行时修**动作数据**里的姿态问题（不碰骨骼的每帧覆盖，不给 `AnimationPlayer` 打架）。
##
## ── 为什么在这里改，而不是回 Blender 重导 ──
## `Move_Ing` 的前倾已经用 `_blender_arisu/fix_lean.py` 在源数据上减过一轮
## （胸腔 +36.5° → +29.6°，README §5.4）。再减就得重开 Blender、重跑
## `build_anim.py`（它负责跳跃 / 落地 / 翻滚三条动作）再导出 —— 一轮十几分钟，
## 而**修正量是个纯数字**。所以这里在 `AnimationPlayer` 装载后、播放前
## 直接改写动作的关键帧四元数：效果和改源数据**完全一样**（`AnimationPlayer`
## 找不到「被覆盖」这回事，因为它读的就是这份数据），但调参是秒级的。
##
## ⚠️ 两条纪律：
##   1. **必须左乘** `delta * q`：`q` 是「相对 rest 的骨局部旋转」，
##      左乘相当于在 rest 坐标系里再转一下；右乘会跟着当前姿势转，越跑越歪。
##   2. **幂等**：改过的动作打上 `meta` 标记，重复调用直接跳过。
##      否则 `_ready()` 被调两次就会叠两遍修正量。
##
## ── 修正量是怎么定的（`_probe_run_lean.gd` 实测，Arisu_ext.glb）──
##    片段            骨盆→脊  脊→胸   胸→颈   颈→头
##    Normal_Idle     −0.8°    −0.3°   +0.7°   −2.2°
##    Move_Ing       +31.8°   +40.3°  +29.6°  +39.5°   ← 每一段都在往前趴
## 侧倾只有 +8.3°（还不如待机姿势的 +13.6°，那是正常的胯部重心偏移），
## 所以「看着斜」**不是左右歪，是整体前倾过大**，尤其**头低着 40°**在冲。
##
## 只修胸以上 + 头：**不动骨盆**。骨盆一转，大腿跟着转，跑步的抬腿就会整体
## 往后拖（看着像「站着滑」）。分到每根骨的度数见 `LEAN_DEG`。

## 骨名 → 绕「向后」轴要转多少度（正数 = 往回收、减少前倾）。
##
## 头上那两段（颈 / 头）收得最多：原来跑起来头低着 40°，像在盯着地面冲，
## 这是「斜」最扎眼的一处；收回来之后视线大约在正前方偏下 10°。
const LEAN_DEG := {
	"Bip001 Pelvis": 5.0,
	"Bip001 Spine": 8.0,
	"Bip001 Spine1": 8.0,
	"Bip001 Neck": 14.0,
	"Bip001 Head": 6.0,
}

## 要改的动作。`Cafe_Walk` 不动：它本来就后仰 11.7°，是这份素材里唯一「不拿枪」的
## 步态（见 `anim_driver.gd` 的 `CYCLE_SPEED` 那段），而且游戏里没在播。
const CLIPS := ["Move_Ing"]

## 「向后」在骨架空间里的方向。实测模型脸朝 +Z（README §1.4），所以向后 = −Z。
const BACK_AXIS := Vector3(0.0, 0.0, -1.0)

## 改过的动作在 `Animation` 上留的标记（幂等用）
const META_KEY := "pose_fix_lean"


## 就地改写 `ap` 里 `CLIPS` 的关键帧。返回报告，**不做任何断言**（自检自己判）。
##
## 报告字段：
##     applied      bool            —— 这次有没有真的改（false = 已经改过 / 没找到）
##     bones        Dictionary      —— 骨名 → {deg, axis, keys}（axis 是标定出来的轴）
##     total        int             —— 一共改了多少个关键帧
##     missing      Array[String]   —— 动作里找不到的骨
static func fix_run_lean(sk: Skeleton3D, ap: AnimationPlayer) -> Dictionary:
	var report := {"applied": false, "bones": {}, "total": 0, "missing": [] as Array}
	if sk == null or ap == null:
		return report
	var changed := 0
	for clip in CLIPS:
		if not ap.has_animation(clip):
			report["missing"].append(clip)
			continue
		var a := ap.get_animation(clip)
		if a.has_meta(META_KEY):
			continue
		for bone_name in LEAN_DEG:
			var idx := sk.find_bone(bone_name)
			if idx < 0:
				report["missing"].append(bone_name)
				continue
			var pick := _pitch_delta(sk, idx, float(LEAN_DEG[bone_name]))
			var keys := _apply_delta(a, bone_name, pick)
			if keys > 0:
				changed += keys
				report["bones"][bone_name] = {
					"deg": LEAN_DEG[bone_name],
					"axis": "Rx",
					"keys": keys,
				}
		a.set_meta(META_KEY, true)
	report["applied"] = changed > 0
	report["total"] = changed
	return report


## 标定「这根骨要往回收多少」：在**骨架空间**里构造一个绕 X 轴的旋转 R，
## 再夹到骨局部空间。
##
## ⚠️ 夹逼用的是**父骨**的 global rest 基，不是这根骨自己的 —— 这一步踩过：
## 第一版用 `G = 这根骨的 global rest`，脊椎 / 颈 / 头全都正常，
## 唯独**骨盆反着转**（pelvis→spine 从 +31.8° 变成 +36.0°，越修越趴）。
## 原因是 `AnimationPlayer` 写进 `Skeleton3D` 的姿势是
## `global = 父全局 × 姿势 × 本骨 rest`（姿势左乘在父空间），所以正确夹逼是
## `delta = P⁻¹ · R · P`。脊椎那些骨的 rest 基几乎就是单位阵，
## 两种夹法差得看不见，于是只有骨盆这一个「rest 基明显不朝上」的骨露了馅。
static func _pitch_delta(sk: Skeleton3D, idx: int, deg: float) -> Quaternion:
	var g := Basis.IDENTITY
	var parent := sk.get_bone_parent(idx)
	if parent >= 0:
		g = sk.get_bone_global_rest(parent).basis.orthonormalized()
	var gq := g.get_rotation_quaternion()
	var world := Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(deg))
	return (gq.inverse() * world * gq).normalized()


## 给 `a` 里属于 `bone_name` 的**旋转轨道**每个关键帧左乘 `delta`。
## 返回改了多少帧；找不到轨道返回 0。
static func _apply_delta(a: Animation, bone_name: String, delta: Quaternion) -> int:
	var n := 0
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		if _bone_of(String(a.track_get_path(t))) != bone_name:
			continue
		for k in a.track_get_key_count(t):
			var q: Quaternion = a.track_get_key_value(t, k)
			var qn := (delta * q).normalized()
			a.track_set_key_value(t, k, qn)
			n += 1
	return n


## `Arisu/.../Skeleton3D:Bip001 Spine` → `Bip001 Spine`
static func _bone_of(path: String) -> String:
	var i := path.rfind(":")
	return path.substr(i + 1) if i >= 0 else ""
