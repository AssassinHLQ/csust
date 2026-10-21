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
## ── ⚠️ 2026-10-22：这里原来写死 `{"Bip001 Head": -18.6}`，只对 Arisu 成立 ──
## 那 −18.6° 是在 **Arisu_ext.glb** 上标出来的，但 `AnimDriver` 对**每一位同伴**都跑
## （柚子 / 小桃 / 小绿 / 诺亚 / 小雪 / 凯伊 各一份自己的 glb）。
## `_probe_role_roll.gd` 实测：收完前倾之后各自的侧倾是 **−15° ~ −32°**（各不相同），
## 套同一个 −18.6° 就变成「都朝同一侧歪」—— 正是用户说的
## 「柚子小绿小桃跑步时姿势错误，头右倾了」。
##
## 现在改成**每具骨架现场标定**（不再有写死的角度）：
##   ① 用 `AnimationPlayer.seek()` 把这条动作走一遍（`_probe_seek_sync.gd` 验过
##      seek + `force_update_all_bone_transforms()` **同一帧就能读到新姿势**，
##      所以 `_ready()` 里同步做完，不用等帧）；
##   ② 每 1/12 个周期采一点，用两只**眼骨**的世界坐标量 roll，取均值；
##   ③ 滚转轴**从几何现算**：`world_axis = (eye_R − eye_L) × UP`（= 角色正前方），
##      再乘 `global_transform.basis⁻¹` 换回骨架空间。不管模型朝哪、rig 有没有转
##      180°，这根轴都对。**不能**再写死 `FWD_AXIS`（那是 Arisu 一具骨架上的标定值，
##      在别的骨架上它可能跟真正的滚转轴几乎垂直 —— 实测那样会越修越歪，
##      还会发散到把脑袋拧 100° 以上）；
##   ④ 修正量**分摊**给脊柱/颈/头（权重按 `LEAN_DEG` 的角度比例 —— 侧倾是从各段的
##      错误轴里注入的，哪里注入就在哪里还回去，不然脑袋会在脖子上拧一圈）；
##   ⑤ 每转一次**重量残差**，超差再补一轮；单条动作总修正量封顶 `ROLL_MAX_DEG`。
## 结果按骨架实例记在 `_roll_cache` 里，`fix_extra_run_clip()` 复用同一份。
const HEAD_BONE := "Bip001 Head"
## 判 roll 用的眼骨。BA 这套 Biped 骨架都有；没有的（凯伊整具骨架只有 6 根骨）
## 就退回 `ROLL_FALLBACK_DEG`。
const EYE_L_BONE := "Bip001 eye_L"
const EYE_R_BONE := "Bip001 eye_R"
## 一条动作采几个点（和 `_probe_head_roll.gd` 一致）
const ROLL_SAMPLES := 12
## 残差小到这个程度就收手（1° 以内肉眼分不出来）
const ROLL_TOLERANCE := 0.6
## 最多修几轮（第一轮按几何解，后面几轮只补残差）
const ROLL_PASSES := 3
## 单条动作的总修正量上限（度）。实测要把注入的 −32° 还回去需要 30° 出头，
## 所以保险丝放在 45°：再大就说明标定在发散，宁可留一点歪也别把脖子拧断。
const ROLL_MAX_DEG := 45.0
## 修正量分摊给哪些骨 —— 和 `LEAN_DEG` 同一批（**不含骨盆**：转骨盆会把腿带着歪）。
## 权重直接取 `LEAN_DEG` 的度数比例，见上面 ④。
const ROLL_BONES := ["Bip001 Spine", "Bip001 Spine1", "Bip001 Neck", "Bip001 Head"]
## **量不出 roll 时**（没有眼骨的模型）退回的死数。
## ⚠️ 只对 Arisu_ext.glb 成立；正常路径已经不用它了，留作保险。
const ROLL_FALLBACK_DEG := {
	"Bip001 Head": -18.6,
}
## 骨架实例 id → 标定结果：
##     {"deg": 总角度, "axis": 骨架空间的滚转轴, "per": {骨名: 各修多少度}}
## `fix_extra_run_clip()` 要用**同一份**（那条跑打动作是用未修正的 `Move_Ing` 拼的）。
static var _roll_cache := {}

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


## 把「跑步时头往左偏」掰正 —— **每具骨架自己量、自己算**（见上面那段注释）。
##
## 报告字段（自检 / 日志用）：
##     applied       bool       有没有真的改
##     measured      bool       true = 用眼骨量出来了；false = 退回死数
##     roll_before   float      修之前这条动作的平均 roll（度）
##     roll_after    float      修之后（最后一轮实测）
##     deg           float      总共补了多少度（负 = 往另一侧）
##     passes        int        修了几轮
##     bones/total/missing       同 `fix_run_lean`
static func fix_head_roll(sk: Skeleton3D, ap: AnimationPlayer) -> Dictionary:
	var report := {"applied": false, "bones": {}, "total": 0, "missing": [] as Array,
		"measured": false, "roll_before": 0.0, "roll_after": 0.0, "deg": 0.0, "passes": 0}
	if sk == null or ap == null:
		return report

	# 要分摊的骨：名字 + 索引 + 权重（权重取 `LEAN_DEG` 的角度比例，见上面 ④）
	var targets: Array = []
	var weight_sum := 0.0
	for bone_name in ROLL_BONES:
		var idx := sk.find_bone(String(bone_name))
		if idx >= 0:
			var w := maxf(float(LEAN_DEG.get(bone_name, 1.0)), 0.1)
			targets.append([String(bone_name), idx, w])
			weight_sum += w
	if targets.is_empty():
		report["missing"].append(ROLL_BONES[0])
		return report

	var total := 0
	var deg_all := 0.0
	var per_all := {}
	var axis_all := Vector3.ZERO
	for clip in CLIPS:
		if not ap.has_animation(clip):
			report["missing"].append(clip)
			continue
		var a := ap.get_animation(clip)
		if a.has_meta(META_ROLL):
			continue
		var keys := 0
		var per := {}
		var m := _measure_roll(sk, ap, clip)      # {"roll": 度, "axis": 骨架空间向量}
		var roll := float(m["roll"])
		var axis: Vector3 = m["axis"]
		if is_nan(roll) or axis.length() < 0.5:
			# 量不出来（没有眼骨的模型）：退回死数，只动头
			var hi := sk.find_bone(HEAD_BONE)
			var fb := float(ROLL_FALLBACK_DEG.get(HEAD_BONE, 0.0))
			if hi >= 0 and not is_zero_approx(fb):
				keys += _apply_delta(a, HEAD_BONE, _axis_delta(sk, hi, FWD_AXIS, fb))
				deg_all += fb
				report["passes"] = maxi(int(report["passes"]), 1)
		else:
			report["measured"] = true
			report["roll_before"] = roll
			var passes := 0
			while passes < ROLL_PASSES:
				if absf(roll) <= ROLL_TOLERANCE or absf(deg_all) >= ROLL_MAX_DEG:
					break
				# 绕「角色正前方」转 −roll，眼睛连线就摆平（1:1）
				var deg := clampf(-roll, -ROLL_MAX_DEG, ROLL_MAX_DEG)
				for t in targets:
					var d := deg * float(t[2]) / weight_sum
					keys += _apply_delta(a, String(t[0]),
						_axis_delta(sk, int(t[1]), axis, d))
					per[String(t[0])] = float(per.get(String(t[0]), 0.0)) + d
				deg_all += deg
				passes += 1
				m = _measure_roll(sk, ap, clip)     # 改完重量，看还剩多少
				roll = float(m["roll"])
				axis = m["axis"]
				if axis.length() < 0.5:
					break
			report["roll_after"] = roll
			report["passes"] = maxi(int(report["passes"]), passes)
			per_all = per
			axis_all = axis
		if keys > 0:
			total += keys
			for t in targets:
				report["bones"][String(t[0])] = {"axis": "Rgeo"}
		a.set_meta(META_ROLL, true)

	report["deg"] = deg_all
	report["total"] = total
	report["applied"] = total > 0
	if report["applied"]:
		_roll_cache[sk.get_instance_id()] = {
			"deg": deg_all, "axis": axis_all, "per": per_all}
	return report


## 一条动作里头的**平均侧倾**，以及「该绕哪根轴转」—— `{roll: 度, axis: 骨架空间单位向量}`。
##
## ⚠️ 四个必须：
##   1. **同一帧就能读**：`seek(t, true)` + `force_update_all_bone_transforms()`
##      （`_probe_seek_sync.gd` 对照过「等一帧」和「不等」两种读法，差 < 0.01°）；
##   2. **换到世界空间**再算：glb 根节点带 −90° X 旋转，在骨架空间里跟「世界上」比
##      会量出 −36° / −77° 这种鬼数字（踩过）；
##   3. 轴**从几何现算**：`world_axis = (eye_R − eye_L) × UP`（= 角色正前方），
##      再乘 `global_transform.basis⁻¹` 换回骨架空间。符号错会越修越歪
##      （第一次写成 `UP × 眼睛连线` = 正后方，实测 −32° 被修到 −59°）；
##   4. 量完**把播放器原样放回去**（模式 / 动作 / 位置 / 速度），别在 `_ready()` 里
##      留下一个正在播 `Move_Ing` 的 AnimationPlayer。
##
## 量不出来（没有眼骨、或没有这条动作）时 `roll` 为 `NAN`、`axis` 是零向量。
static func _measure_roll(sk: Skeleton3D, ap: AnimationPlayer, clip: String) -> Dictionary:
	var out := {"roll": NAN, "axis": Vector3.ZERO}
	var eL := sk.find_bone(EYE_L_BONE)
	var eR := sk.find_bone(EYE_R_BONE)
	if eL < 0 or eR < 0 or not ap.has_animation(clip):
		return out
	var a := ap.get_animation(clip)
	var prev_mode: int = ap.playback_process_mode
	var prev_clip := ap.current_animation
	# ⚠️ 没有正在播的动作时读 `current_animation_position` 会刷一条
	#    "AnimationPlayer has no current animation" 错误（第一次进游戏必刷一屏）
	var prev_pos := 0.0
	if not prev_clip.is_empty():
		prev_pos = ap.current_animation_position
	var prev_speed := ap.speed_scale
	ap.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	ap.speed_scale = 1.0
	ap.play(clip)
	var sum := 0.0
	var axis_sum := Vector3.ZERO
	var n := maxi(ROLL_SAMPLES, 2)
	for i in n:
		ap.seek(a.length * float(i) / float(n), true)
		sk.force_update_all_bone_transforms()
		var xf := sk.global_transform
		var pl: Vector3 = xf * sk.get_bone_global_pose(eL).origin
		var pr: Vector3 = xf * sk.get_bone_global_pose(eR).origin
		var right := (pr - pl).normalized()
		sum += rad_to_deg(asin(clampf(right.y, -1.0, 1.0)))
		var w := right.cross(Vector3.UP)      # = 角色正前方
		if w.length() > 0.0001:
			axis_sum += w.normalized()
	# 还原播放器
	ap.playback_process_mode = prev_mode
	ap.speed_scale = prev_speed
	if prev_clip.is_empty():
		ap.stop()
	else:
		ap.play(prev_clip)
		ap.seek(prev_pos, true)
	sk.force_update_all_bone_transforms()
	out["roll"] = sum / float(n)
	if axis_sum.length() > 0.0001:
		out["axis"] = (sk.global_transform.basis.inverse() * axis_sum.normalized()).normalized()
	return out


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
##
## ── 2026-10-18 扩表：上一版**只删了四根**，眼皮照样在动 ──
## 用户：「最后为什么眼皮还在动，之前不是都删眼睛那儿的动画了吗」。
##
## 量出来的（`_probe_face_motion.gd`：每根骨相对头骨的最大旋转，播 150 帧）：
##   | 骨 | Normal_Idle |
##   |---|---|
##   | `Xtra_eyeblowL1` / `R1` | **19.71° / 19.70°** ← 四根里最大，正是还看得见的那一下 |
##   | `Xtra_eyeblowL2` / `R2` | 4.14° / 4.16° |
##   | `bone_eye_D_L/R`、`bone_eye_D_*_01/02` | ≤ 3.1° |
##   | `bone_Eyering_*` / `Xtra_eyeR/L` | ≤ 0.81° |
##   | `eye_L_1` / `eye_R_1`（上一版删掉的） | 0.87°（噪声级，已经不动了）✓ |
## 也就是说：素材里**眨眼的主轨道挂在 `Xtra_eyeblow*` 上**（名字像眉毛，实际带着
## 上睑那一圈；`eye_L_1/2` 只是眼球的附件），删了四根等于没删到点上。
##
## 所以整张「脸」一起冻：**眼球 + 眼睑** + 眉/睫毛圈 + 眼周装饰。它们是纯装饰骨，
## 冻掉之后脸上只剩头骨自己在动（说话口型走的是形态键，不受影响）。
##
## ⚠️ 2026-10-18 第三轮：**眼球骨的位置轨道**才是最后一个漏网（见下面 `eye_L/R` 那条）。
##    教训：判「有没有动」不能只量旋转 —— `R`（旋转）、`P`（平移）、`S`（缩放）
##    三类轨道里，眨眼在**不同素材**上可以挂在任意一类上。
const BLINK_BONES := [
	# 眼球 —— **位置轨道会平移 3.7~4.7 cm**，这才是「还在眨/还在动」的主犯
	# （2026-10-18 第二轮：只删眼睑骨时 `eye_L` 的旋转一直是 0.04°，但
	#   `get_bone_pose_position` 相对头骨摆了 **0.0472 m / 0.0371 m** ——
	#   只量旋转的探针会漏掉整整一类「滑动式眨眼」）
	"Bip001 eye_L", "Bip001 eye_R",
	# 眼睑（2026-10-17 那版）
	"Bip001 eye_L_1", "Bip001 eye_L_2", "Bip001 eye_R_1", "Bip001 eye_R_2",
	# 眉 / 上睑圈 —— **真正在动的那几根**
	"Bip001 Xtra_eyeblowL1", "Bip001 Xtra_eyeblowL2",
	"Bip001 Xtra_eyeblowR1", "Bip001 Xtra_eyeblowR2",
	# 眼周装饰（睫毛圈 / 眼影）
	# ⚠️ 这六根**没有 `Bip001 ` 前缀**（实测骨名就是 `bone_Eyering_R_03`），
	#    写成带前缀的查不到、`missing` 里会点名 —— 上一版就这么漏了 7 条轨道。
	"Bip001 Xtra_eyeL", "Bip001 Xtra_eyeR",
	"bone_Eyering_L_01", "bone_Eyering_L_02", "bone_Eyering_L_03",
	"bone_Eyering_R_01", "bone_Eyering_R_02", "bone_Eyering_R_03",
	"Bip001 bone_eye_D_L", "Bip001 bone_eye_D_L_01", "Bip001 bone_eye_D_L_02",
	"Bip001 bone_eye_D_R", "Bip001 bone_eye_D_R_01", "Bip001 bone_eye_D_R_02",
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


## ── 也给「单条跑打动作」补上同样的前倾 / 侧倾修正 ──
## 那条动作是在 Blender 里用**未修正的** `Move_Ing` 拼出来的（修正发生在 Godot 加载时），
## 所以不补的话它比 `Move_Ing` 多趴一截：实测跑打开火时胸椎离「只跑」的姿势集 **15.6°**
## （`_verify_attack_move.gd` §7，判据 8°）。补完 < 1°。
##
## 用的 delta 和 `fix_run_lean()` / `fix_head_roll()` 完全一样，只是作用在另一条动作上。
static func fix_extra_run_clip(sk: Skeleton3D, ap: AnimationPlayer, clip: String) -> Dictionary:
	var report := {"applied": false, "bones": [], "keys": 0}
	if sk == null or ap == null or not ap.has_animation(clip):
		return report
	var a := ap.get_animation(clip)
	var meta := META_KEY + "_x_" + clip
	if a.has_meta(meta):
		return report
	var total := 0
	for bone_name in LEAN_DEG:
		var idx := sk.find_bone(String(bone_name))
		if idx < 0:
			continue
		total += _apply_delta(a, String(bone_name), _pitch_delta(sk, idx, float(LEAN_DEG[bone_name])))
		report["bones"].append(String(bone_name))
	# 用这具骨架**实测**出来的「每根骨各修多少 + 绕哪根轴」
	# （`fix_head_roll()` 存进 `_roll_cache`）—— 这条动作和 `Move_Ing` 必须是同一个修正量。
	# 没标定过（例如这条动作在没有 `Move_Ing` 的模型上）才退回死数。
	var cal: Dictionary = _roll_cache.get(sk.get_instance_id(), {})
	var per: Dictionary = cal.get("per", {})
	var axis: Vector3 = cal.get("axis", Vector3.ZERO)
	if not per.is_empty() and axis.length() > 0.5:
		for bone_name in per:
			var idx2 := sk.find_bone(String(bone_name))
			if idx2 < 0:
				continue
			var deg := float(per[bone_name])
			if is_zero_approx(deg):
				continue
			total += _apply_delta(a, String(bone_name), _axis_delta(sk, idx2, axis, deg))
			report["bones"].append(String(bone_name))
	else:
		for bone_name in ROLL_FALLBACK_DEG:
			var idx3 := sk.find_bone(String(bone_name))
			if idx3 < 0:
				continue
			total += _apply_delta(a, String(bone_name),
				_axis_delta(sk, idx3, FWD_AXIS, float(ROLL_FALLBACK_DEG[bone_name])))
			report["bones"].append(String(bone_name))
	a.set_meta(meta, true)
	report["applied"] = total > 0
	report["keys"] = total
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
