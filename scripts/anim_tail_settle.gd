class_name AnimTailSettle
extends RefCounted
## 让**一次性动作的末段**平滑收敛回待机姿势，消掉「收招那一帧姿势硬切」。
##
## ── 现象（用户 2026-11-11）──
## 「爱丽丝普通换弹动画最后一帧跳动幅度剧烈」。
## 逐帧量完（`_probe_aris_reload_eyes.gd`，记录全部 145 根骨的全局旋转）：
##   收招那一刻（叠加层 `stop()` 的那一帧）：**137 根骨动了 >0.5°，其中 62 根 ≥30°**，
##   而且——`Bip001 Head` **43.1°**、`Bip001 Spine` 4.1°、`Bip001 L UpperArm` 9.5°、
##   而 `Bip001` / `Bip001 Pelvis` / `Bip001 L Thigh` 全是 **0.0°**。
##   ⇒ **身体和腿没动，是「头」拧了 43°**，头发（挂在 head 下）整条链跟着一起 43°。
##
## ── 机理 ──
## 站桩换弹：基础层播 `Normal_Idle`，叠加层播 `Normal_Reload`（后写、后赢）。
## `Normal_Reload` 结尾还低着头看弹匣，**没有把头转回中位**；
## 收招时 `stop_upper_layer()` 一停，头立刻被 idle 的姿势接管 → 一帧 43°。
##
## ── 为什么在数据侧改，而不是改播放流程做 crossfade ──
## Godot 的 `AnimationPlayer` **没有跨播放器的交叉淡入**（两个播放器叠着写同一具骨架，
## 后写的赢，`stop()` 是瞬时的）。能真正做 crossfade 的路子只有「把动作挪到基础层播」，
## 但那会让**换弹期间腿被动作按住**（跑着换弹就废了）—— 见 `_setup_upper_layer()` 那三条。
## 所以改数据：让动作自己的末段收敛到「基础层待机」的姿势。
##
## ── 两个部分必须配合，缺一不可 ──
##   1. **本文件**：把 clip 最后 `SEC` 秒的旋转轨道 slerp 到 `TARGET`(**t=0**) 的姿势；
##   2. `anim_driver.gd::_return_to_locomotion(seek_idle=true)`：收招时把基础层
##      `playhead` 拨回 0 —— 这样「动作末帧姿势」和「基础层那一刻的姿势」**逐骨相等**，
##      硬切也看不出任何跳变。
##
##   只做 1 不做 2：基础层 idle 的相位是任意的，仍会有「idle 在这半个循环里走了多远」的残差。
##   只做 2 不做 1：动作末帧还是低头的，拨回 0 也还是跳。
##
## ── 纪律 ──
##   · **只改旋转轨道**。位置 / 缩放轨道一律不碰 —— 那些是模型根和武器骨，
##     改了会把模型整体挪走（`_make_overlay()` 里那段「根节点轨道把整个人掰歪」同理）。
##   · **幂等**：改过的动作打 `meta` 标记。
##   · 只对白名单 `CLIPS` 生效。加新动作前先用探针量一遍「末帧 vs 待机」差多少。

## 末段多长（**真实时间**，秒）用来收敛。取 0.16 s：约 10 帧，人眼看着是「收势」。
##
## ⚠️⚠️ 这个数**是真实时间，不是动作内时间** —— 必须除以播放倍速才是 clip 里要改多长。
##    为什么：一次一次性动作在叠加层上是按倍速播的（换弹 `RELOAD_SPEED`、开火 `FIRE_SPEED`）。
##    如果直接拿 0.16 s 当**动作内**长度，3.64 倍速下它就只剩 0.044 s 真实时间（约 3 帧），
##    收敛本身会变成新的「闪」——2026-11-11 把换弹从 1.9 提速到 3.64 之后就撞上这件事。
##    所以 `fix()` 收一张 `speed_by_clip`，内部换算 `sec_clip = SEC_REAL * speed`。
const SEC_REAL := 0.16
## 哪些动作用这招（一次性动作）
##
## ⚠️ 2026-11-11 补 `Normal_Attack_Ing`：用户「换弹修好了，但是**攻击动画总是闪一下**」。
##    同一个病根 —— 开火动作也是走站桩叠加层的，播完 `stop_upper_layer()` 硬切回 idle。
##    2× 攻速下「播完 → 闪 → 重播」每 0.4 s 一轮，所以是「**总是**闪」。
const CLIPS := ["Normal_Reload", "Normal_Attack_Ing"]
## 收敛的目标动作（基础层站桩待机）
const TARGET := "Normal_Idle"

const META_DONE := "_tail_settled"

## **整条动作里全程钉死**的骨（键值 = 骨名关键字）。
##
## 为什么需要（2026-11-11，用户：「**攻击动画总是闪一下**」）：
## 实测开火收招那一帧 `bone_magazine` 局部旋转跳 **132°**、`bone_Railgunup_part_04` 跳 58°。
## 再往下量发现：**攻击动作里这些枪零件的末姿势离 `Normal_Idle` 差 168°**。
## 于是「末段收敛」把 168° 压进 0.16 s 真实时间 → 弹匣在 0.16 秒里转 168°，
## 收敛本身变成了新的闪光（本喵第一版就是这个结果）。
##
## 根子：这些**枪零件**（弹匣 / 轨道炮分段 / 炮口）在开火动作里本来就没有该有的动画，
## 是重定向留下来的乱轨道 —— `AnimSpikeFix.SKIP_KEYWORDS` 里就有 `magazine`，
## 所以它们从来没被「孤点」清理碰过。开火姿势也不该让弹匣转 168°。
##
## 所以：**这条动作里把它们全程钉成目标动作 t=0 的值**，既不跳、也不转。
## 枪的主体 `Bip001_Weapon` **不在**这个表里 —— 它要跟着动作动，删了枪就不跟手了。
const FREEZE := {
	"Normal_Attack_Ing": ["magazine", "railgun", "muzzle", "point"],
}


## `speed_by_clip`：{clip 名: 播放倍速}。没给就按 1.0 算。
static func fix(ap: AnimationPlayer, speed_by_clip := {}) -> Dictionary:
	var clips: Array = []
	var tracks := 0
	var bones := {}
	var secs := {}
	if ap == null or not ap.has_animation(TARGET):
		return {"clips": clips, "tracks": 0, "bones": [], "seconds": SEC_REAL, "clip_secs": secs}
	var tgt: Animation = ap.get_animation(TARGET)
	for clip_name in CLIPS:
		if not ap.has_animation(clip_name):
			continue
		var a: Animation = ap.get_animation(clip_name)
		if a == null or a.has_meta(META_DONE):
			continue
		var speed := maxf(float(speed_by_clip.get(clip_name, 1.0)), 0.01)
		# 真实 0.16 s → clip 内多长
		var sec_clip := minf(SEC_REAL * speed, a.length * 0.5)
		var n := _settle(a, tgt, bones, sec_clip, FREEZE.get(clip_name, []))
		a.set_meta(META_DONE, true)
		if n > 0:
			tracks += n
			clips.append(clip_name)
			secs[clip_name] = sec_clip
	var names: Array = bones.keys()
	names.sort()
	return {"clips": clips, "tracks": tracks, "bones": names,
		"seconds": SEC_REAL, "clip_secs": secs}


## 供自检用：量一条动作「末帧 vs 目标 t=0」的最大角度差（不做修改）
static func measure_tail(ap: AnimationPlayer, clip_name: String) -> Dictionary:
	if ap == null or not ap.has_animation(clip_name) or not ap.has_animation(TARGET):
		return {"deg": -1.0, "bone": ""}
	var a: Animation = ap.get_animation(clip_name)
	var tgt: Animation = ap.get_animation(TARGET)
	var worst := 0.0
	var worst_bone := ""
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var ti := _find_rot(tgt, String(a.track_get_path(t)))
		if ti < 0:
			continue
		var qa: Quaternion = a.rotation_track_interpolate(t, a.length)
		var qb: Quaternion = tgt.rotation_track_interpolate(ti, 0.0)
		var d := rad_to_deg(qa.angle_to(qb))
		if d > worst:
			worst = d
			worst_bone = _bone(a, t)
	return {"deg": worst, "bone": worst_bone}


static func _settle(a: Animation, tgt: Animation, bones: Dictionary, sec_clip: float,
		freeze: Array = []) -> int:
	var L := a.length
	var t0 := maxf(L - sec_clip, 0.0)
	var touched := 0
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var path := String(a.track_get_path(t))
		var ti := _find_rot(tgt, path)
		if ti < 0:
			continue
		var qt: Quaternion = tgt.rotation_track_interpolate(ti, 0.0)
		var n := a.track_get_key_count(t)
		if n < 1:
			continue
		# ── 枪零件：整条动作全程钉成目标 t=0 的值（既不跳也不转，见 `FREEZE`）──
		if _matches(_bone(a, t), freeze):
			for k in n:
				a.track_set_key_value(t, k, qt)
			touched += 1
			bones[_bone(a, t)] = true
			continue
		var did := false
		for k in n:
			var tk := a.track_get_key_time(t, k)
			if tk < t0:
				continue
			var w := clampf((tk - t0) / maxf(sec_clip, 0.0001), 0.0, 1.0)
			var qk: Quaternion = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, qk.slerp(qt, w))
			did = true
		# 确保末帧严格等于目标（有些轨道最后一个 key 落在 L 之前，
		# 那之后是「隐式保持」，保持的是旧姿势 —— 必须补一个 key 在 L 上）
		var last_t := a.track_get_key_time(t, a.track_get_key_count(t) - 1)
		if last_t < L - 0.0001:
			a.track_insert_key(t, L, qt)
			did = true
		else:
			a.track_set_key_value(t, a.track_get_key_count(t) - 1, qt)
			did = true
		if did:
			touched += 1
			bones[_bone(a, t)] = true
	return touched


## 骨名是否命中关键字列表（小写子串匹配）
static func _matches(bone: String, kws: Array) -> bool:
	if bone.is_empty() or kws.is_empty():
		return false
	var low := bone.to_lower()
	for k in kws:
		if low.contains(String(k)):
			return true
	return false


static func _find_rot(a: Animation, path: String) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		if String(a.track_get_path(i)) == path:
			return i
	return -1


static func _bone(a: Animation, track: int) -> String:
	return String(a.track_get_path(track).get_concatenated_subnames())
