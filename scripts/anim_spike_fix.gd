class_name AnimSpikeFix
extends RefCounted
## 修动作里的**孤点关键帧**（一个 key 偏离前后两个 key 的插值路径太远）。
##
## ── 现象 ──
## 用户 2026-11-03：「25-45 这个，抬起来太突兀了，导致射击总是莫名其妙抬起来」。
##
## ── 实测（`tools/glb_curve.py`，Arisu_ext.glb / Normal_Attack_Ing，24 fps）──
## `Bip001 R UpperArm` 在帧 24 / 25 / 26 的四元数：
##     f24  (−0.307, −0.421, +0.238, 0.820)
##     f25  (−0.069, −0.556, −0.220, 0.799)   ← 离群
##     f26  (−0.276, −0.316, +0.276, 0.865)
## 判定「绕路 vs 直连」：
##     f24→f25 = 61.9°，f25→f26 = 68.9°，而 **f24→f26 只有 14.2°**
## 也就是手臂在 f24 和 f26 基本没动，却在 f25 甩出去 ~62° 又甩回来 —— 一帧抽搐。
## 同一帧离群的形变骨（绕路多出多少度）：R Forearm 142.2、R UpperArm 116.5、
## B_R Deltoid 89.9、L UpperArm 79.7、R Hand 64.0、B_L Deltoid 58.6。
## 脊柱/胸那一帧完全平静（0.3~0.8°/帧），所以「抬起来」**不是身体，是手臂**。
##
## 站桩开火用 `FIRE_SPEED = 2.5` 倍速播，f25 落在开火后约 **0.42 s**，
## 正好是「打着打着枪莫名抬一下」的时机。
##
## ── 为什么在 Godot 侧改而不是回 Blender 重导 ──
## 和 `pose_fix.gd` 同理：修正量是一个纯数字（把离群 key 换成前后两 key 的 slerp），
## 而重导一轮要开 Blender、重跑烘焙再导出；且 `models/` 不入仓库，
## 改代码能跟着工程走，改 GLB 只有本机有效。
##
## ── 两条纪律 ──
##   1. **只修白名单里的动作**（默认只有 `Normal_Attack_Ing`）。
##      别的动作里也有 45° 以上的「绕路」（`Vital_Death` 上有 25 根骨、
##      `Exs` 系列有 8 根），但那些是真实的快速动作或 VFX 辅助骨，
##      一律平滑会把死亡动画和挥砍改坏。
##   2. **幂等**：改过的动作打 `meta` 标记，重复调用直接跳过。

## 绕路比直连多出多少度才算孤点。
## 定 25° 的依据：`Normal_Attack_Ing` 里真正坏的 key 绕路 60~142°，而同一条动作里
## **正常的快速动作**（抬枪那一下）单跳最多 ~30°、绕路不到 20°。25° 卡在两者之间。
## 加新动作进 `CLIPS` 之前，先用 `tools/glb_curve.py` 看一遍它的绕路分布。
const SPIKE_DEG := 25.0

## 只修这些动作。要加新动作时，先用 `tools/glb_curve.py` 看一遍那一条
## 到底是「数据坏了」还是「本来就该转这么快」。
const CLIPS := ["Normal_Attack_Ing"]

## 这些骨是特效 / 道具辅助骨，它们的「大跳」通常是刻意的（弹匣甩出、枪口闪）。
const SKIP_KEYWORDS := ["muzzle", "railgun", "magazine", "deco", "vfx", "fx_"]

## 这些是**二次动态骨**（头发 / 裙摆 / 挂饰 / 链条），本来就会甩得很猛，
## 而且甩起来是「连续几帧都快」，不是「一帧突兀」。25° 门槛套上去会把它们磨平，
## 实测拿掉这层排除后，一位同伴的 `Normal_Attack_Ing` 会被改掉 85 个 key。
const SKIP_SECONDARY := ["hair", "skirt", "chain", "hooh", "ribbon", "tail", "cloth"]

const META_DONE := "_spike_fixed"


static func fix(ap: AnimationPlayer) -> Dictionary:
	var keys := 0
	var clips: Array = []
	var bones := {}
	var times := {}
	for clip_name in CLIPS:
		if not ap.has_animation(clip_name):
			continue
		var a := ap.get_animation(clip_name)
		if a == null or a.has_meta(META_DONE):
			continue
		var n := _fix_animation(a, bones, times)
		a.set_meta(META_DONE, true)
		if n > 0:
			keys += n
			clips.append(clip_name)
	var names: Array = bones.keys()
	names.sort()
	var ts: Array = times.keys()
	ts.sort()
	return {"keys": keys, "clips": clips, "bones": names, "times": ts}


## 供自检用：统计一个动作里还剩多少孤点（不做修改）。
static func count_spikes(ap: AnimationPlayer, clip_name: String) -> Dictionary:
	if not ap.has_animation(clip_name):
		return {"spikes": -1, "worst_deg": 0.0, "worst_bone": ""}
	var a := ap.get_animation(clip_name)
	return _scan(a, false, {})


static func _fix_animation(a: Animation, touched: Dictionary, times_out: Dictionary) -> int:
	var res := _scan(a, true, touched, times_out)
	return int(res["spikes"])


static func _scan(a: Animation, do_fix: bool, touched: Dictionary,
		times_out: Dictionary = {}) -> Dictionary:
	var spikes := 0
	var worst := 0.0
	var worst_bone := ""
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := _bone_name(a, t)
		if bone.is_empty() or _skipped(bone):
			continue
		var n := a.track_get_key_count(t)
		if n < 3:
			continue
		for k in range(1, n - 1):
			var qa: Quaternion = a.track_get_key_value(t, k - 1)
			var qb: Quaternion = a.track_get_key_value(t, k)
			var qc: Quaternion = a.track_get_key_value(t, k + 1)
			var via := qa.angle_to(qb) + qb.angle_to(qc)
			var direct := qa.angle_to(qc)
			var detour := rad_to_deg(via - direct)
			if detour <= SPIKE_DEG:
				continue
			spikes += 1
			if detour > worst:
				worst = detour
				worst_bone = bone
			if do_fix:
				# 用前后两个 key 的中点替换离群 key —— 这一步只消掉「多出来的绕路」，
				# 相邻两 key 之间本来的动作幅度一点不改。
				a.track_set_key_value(t, k, qa.slerp(qc, 0.5))
				touched[bone] = true
				times_out[snappedf(a.track_get_key_time(t, k), 0.001)] = true
	return {"spikes": spikes, "worst_deg": worst, "worst_bone": worst_bone}


static func _skipped(bone: String) -> bool:
	var lower := bone.to_lower()
	for kw in SKIP_KEYWORDS:
		if lower.contains(kw):
			return true
	for kw in SKIP_SECONDARY:
		if lower.contains(kw):
			return true
	return false


static func _bone_name(a: Animation, track: int) -> String:
	var p := a.track_get_path(track)
	# 轨道路径形如 `Skeleton3D:Bip001 R UpperArm`，骨骼名在 subnames 里
	return String(p.get_concatenated_subnames())
