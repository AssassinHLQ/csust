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
## 「前进」轴 —— 绕它转才是**左右侧倾**（roll）。
##
## ⚠️ 不能写成 `Vector3(0,0,1)`。这是 `sk.global_transform` 里的**骨架空间**，
##    而 glb 的根节点带一个 −90° X 旋转（Y-up ↔ Z-up），所以世界前进轴落到骨架空间里
##    是一根斜的向量。用 `_probe_head_roll.gd -- --calib` 标出来的实测值：
##      · 骨架 +X 转 10° → roll 变 6.6°（还掺了别的）
##      · 骨架 +Z 转 10° → roll 变 5.9°
##      · **本向量** 转 10° → roll 变 **9.76°**（≈1:1，干净的滚转，不掺俯仰）
##    「模型脸朝 +Z」说的是**世界空间**，不是骨架空间 —— 这两者以内的事差一个 90°。
const FWD_AXIS := Vector3(0.773744, 0.344725, 0.531494)

## 改过的动作在 `Animation` 上留的标记（幂等用）
const META_KEY := "pose_fix_lean"
const META_ROLL := "pose_fix_roll"
const META_LID := "pose_fix_lid"

## ── 跑步时头往**左**偏 ──
## 实测（`_probe_head_roll.gd`，判据 `roll = asin((eye_R − eye_L).y)`，右耳抬高为正）：
##     片段           roll 均值   范围
##     Normal_Idle    −0.91°    −5.58 ~ +7.47
##     Cafe_Walk      −0.02°    −3.96 ~ +3.93
##     Move_Ing      **+13.87°**  +10.88 ~ +18.22   ← 只有跑起来才歪
## 注意 `Move_Ing` 那 +13.87° 只是**原始数据**；`fix_run_lean()` 跑完之后会变成
## **−18.0°**（用户报「又变成右倾了」）—— 也就是说**「收前倾」那一步自己就注入了
## 约 32° 的侧倾**。原因：它用的 `Vector3(1,0,0)` 是**骨架空间**的 X，而骨架节点带
## −90° 旋转（世界 +Z 落到骨架空间是 `(0.774, 0.345, 0.531)`），那根轴不是世界的左右轴。
##
## 修法：绕标定轴 `FWD_AXIS`（见下）补 −18.6°。实测：
##     · `FWD_AXIS` 转 10° → roll 变 −9.76°（≈1:1，干净的滚转，不掺俯仰）
##     · 补 −18.6° 之后 Move_Ing 的 roll = **+0.26°**（范围 −1.91 ~ +2.26）
const ROLL_DEG := {
	"Bip001 Head": -18.6,
}

## ── 待机只有**右**眼睑在动 ──
## 实测 `Normal_Idle` 里 `Bip001 eye_R_1` 的姿势四元数 y 分量到 **−0.044**（≈5°），
## 而 `Bip001 eye_L_1` 全程 **0.000** —— 两条眼睑线对不上，就是用户说的「双眼皮打架」。
## 修法：按用户要求把右眼的数据**镜像**给左眼。
const EYELID_PAIRS := [
	["Bip001 eye_R_1", "Bip001 eye_L_1"],
	["Bip001 eye_R_2", "Bip001 eye_L_2"],
]
## 眼睑同步要覆盖的动作（所有会播的循环 + 一次性）
const LID_CLIPS := ["Normal_Idle", "Cafe_Walk", "Move_Ing"]


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


## 把「跑步时头往左偏 13.9°」掰正。和 `fix_run_lean` 同一套机制，只是轴换成前进轴。
static func fix_head_roll(sk: Skeleton3D, ap: AnimationPlayer) -> Dictionary:
	var report := {"applied": false, "bones": {}, "total": 0, "missing": [] as Array}
	if sk == null or ap == null or ROLL_DEG.is_empty():
		return report
	var changed := 0
	for clip in CLIPS:
		if not ap.has_animation(clip):
			report["missing"].append(clip)
			continue
		var a := ap.get_animation(clip)
		if a.has_meta(META_ROLL):
			continue
		for bone_name in ROLL_DEG:
			var idx := sk.find_bone(bone_name)
			if idx < 0:
				report["missing"].append(bone_name)
				continue
			var delta := _axis_delta(sk, idx, FWD_AXIS, float(ROLL_DEG[bone_name]))
			var keys := _apply_delta(a, bone_name, delta)
			if keys > 0:
				changed += keys
				report["bones"][bone_name] = {"deg": ROLL_DEG[bone_name], "axis": "Rz", "keys": keys}
		a.set_meta(META_ROLL, true)
	report["applied"] = changed > 0
	report["total"] = changed
	return report


## 把一只眼的眼睑旋转轨道**镜像**到另一只眼。
##
## ── ⚠️ 方向是可以反的，而且反了会白干 ──
## `from_right = true`（原来的默认）：右眼 → 左眼。这是用户最早要的
##   「按右眼的数据镜像给左眼」，当时左眼在偏。
## `from_right = false`：左眼 → 右眼。2026-10-17 用户报「右眼上眼睑掉下来半遮瞳孔，
##   镜像开也没感觉到」之后量的结论：**这份素材的眨眼动画只驱动左眼**，
##   右眼的眼睑轨道几乎是静止的（`_probe_eyelids.gd`，`Normal_Idle`：
##   左眼睑尖 y 从 +0.067 抬到 +0.077，右眼一直是 +0.066~0.068）。
##   于是「右→左」等于把左眼的动作抄成静止（用户「没感觉到」就是这么来的），
##   该反过来抄。方向验完再定默认值，别凭直觉。
##
## 镜像一个旋转（以 x=0 平面为镜）：轴 n → (−n.x, n.y, n.z) 且角度取反，
## 合成到四元数就是 `(x, −y, −z, w)`。
## ⚠️ 只有当左右两根骨的 rest 基**互为镜像**时这条才成立；如果两边 rest 基一样
##    （有些 MMD 绑法左右共用同一朝向），就直接照抄 `q`。这里按 `rest.x` 的点积自动判。
static func fix_eyelid_sync(sk: Skeleton3D, ap: AnimationPlayer,
		from_right := true) -> Dictionary:
	var report := {"applied": false, "pairs": 0, "keys": 0, "missing": [] as Array,
		"from_right": from_right}
	if sk == null or ap == null:
		return report
	# 两个方向各记各的 meta：同一条动画上跑两次不会互相挡住（A/B 对照要用）
	var meta := META_LID if from_right else META_LID + "_l2r"
	var total := 0
	for clip in LID_CLIPS:
		if not ap.has_animation(clip):
			continue
		var a := ap.get_animation(clip)
		if a.has_meta(meta):
			continue
		for pair in EYELID_PAIRS:
			var src := String(pair[0]) if from_right else String(pair[1])
			var dst := String(pair[1]) if from_right else String(pair[0])
			var li := sk.find_bone(dst)
			var ri := sk.find_bone(src)
			if li < 0 or ri < 0:
				report["missing"].append(src + "/" + dst)
				continue
			var mirrored := _rest_mirrored(sk, li, ri)
			var n := _copy_rotation_track(a, src, dst, mirrored)
			if n > 0:
				total += n
				report["pairs"] = int(report["pairs"]) + 1
		a.set_meta(meta, true)
	report["applied"] = total > 0
	report["keys"] = total
	return report


## ── 不眨眼了 ──
## 2026-10-17 用户：「眼睛那里停止算了，不要眨眼的动画了」。
##
## 做法是把这几根骨上的**所有轨道**从每个动作里整条删掉 —— 没有轨道，
## `AnimationPlayer` 就不写它们，骨永远停在 rest，眼睛彻底不动。
## 比「把关键帧压成常量」彻底：压常量还得挑一个值，删轨道不会挑错。
##
## 连 `_2`（下睑）一起删：上下睑是联动眨的，只留一边会变成「只有下眼皮在动」。
## 上一版 `fix_eyelid_sync()` 保留着不删（还有探针在拿它做 A/B）。
const BLINK_BONES := [
	"Bip001 eye_L_1", "Bip001 eye_L_2", "Bip001 eye_R_1", "Bip001 eye_R_2",
]
const META_BLINK := "pose_fix_blink"


## 报告：applied / tracks（删了几条）/ clips（动过哪些动作）/ missing（骨名对不上的）
static func freeze_eyelids(sk: Skeleton3D, ap: AnimationPlayer) -> Dictionary:
	var report := {"applied": false, "tracks": 0, "clips": [] as Array, "missing": [] as Array}
	if sk == null or ap == null:
		return report
	for b in BLINK_BONES:
		if sk.find_bone(String(b)) < 0:
			report["missing"].append(b)
	var removed := 0
	for clip in ap.get_animation_list():
		var a := ap.get_animation(String(clip))
		if a == null or a.has_meta(META_BLINK):
			continue
		var hit := 0
		# 倒着删，索引才不会挪
		for t in range(a.get_track_count() - 1, -1, -1):
			if BLINK_BONES.has(_bone_of(String(a.track_get_path(t)))):
				a.remove_track(t)
				hit += 1
		if hit > 0:
			removed += hit
			report["clips"].append(String(clip))
		a.set_meta(META_BLINK, true)
	report["applied"] = removed > 0
	report["tracks"] = removed
	return report


## 左右两根骨的 rest 基是否互为镜像（x 轴反向即为镜像）
static func _rest_mirrored(sk: Skeleton3D, left: int, right: int) -> bool:
	var bl := sk.get_bone_global_rest(left).basis.orthonormalized()
	var br := sk.get_bone_global_rest(right).basis.orthonormalized()
	return bl.x.dot(br.x) < 0.0


## 把 `from_bone` 的旋转轨道复制到 `to_bone`（可选镜像），返回写了多少帧。
## 目标轨道已存在就先清空 —— 眼睑骨的轨道帧率可能和源不一致，按帧取源更稳。
static func _copy_rotation_track(a: Animation, from_bone: String, to_bone: String,
		mirrored: bool) -> int:
	var src := _find_rotation_track(a, from_bone)
	if src < 0:
		return 0
	var dst := _find_rotation_track(a, to_bone)
	var path := String(a.track_get_path(src))
	var head := path.substr(0, path.rfind(":"))
	var target := head + ":" + to_bone
	if dst < 0:
		dst = a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(dst, NodePath(target))
	else:
		while a.track_get_key_count(dst) > 0:
			a.track_remove_key(dst, a.track_get_key_count(dst) - 1)
	var n := a.track_get_key_count(src)
	for k in n:
		var q: Quaternion = a.track_get_key_value(src, k)
		if mirrored:
			q = Quaternion(q.x, -q.y, -q.z, q.w)
		a.track_insert_key(dst, a.track_get_key_time(src, k), q.normalized())
	return n


static func _find_rotation_track(a: Animation, bone_name: String) -> int:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		if _bone_of(String(a.track_get_path(t))) == bone_name:
			return t
	return -1


## 骨架空间里绕任意 `axis` 转 `deg`，夹到这根骨的局部空间（夹逼基同 `_pitch_delta`）。
static func _axis_delta(sk: Skeleton3D, idx: int, axis: Vector3, deg: float) -> Quaternion:
	var g := Basis.IDENTITY
	var parent := sk.get_bone_parent(idx)
	if parent >= 0:
		g = sk.get_bone_global_rest(parent).basis.orthonormalized()
	var gq := g.get_rotation_quaternion()
	return (gq.inverse() * Quaternion(axis, deg_to_rad(deg)) * gq).normalized()


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
