extends SceneTree
## 探针：`Normal_Attack_Ing`（开火动作）**到底动了哪些骨**。
##
## 起因（用户报）：
##   「开枪跑打时为什么角色脚不动，需要静止开枪不动，但是跑步开枪脚还是要动」
##   —— 现在一开火，整个身体都切到 `Normal_Attack_Ing`（站桩开火），腿也停了，
##      人在地上滑。要修有两种可能：
##        A. 攻击动作**本来就只动上半身** ⇒ 直接拿第二个 AnimationPlayer 叠上去就行；
##        B. 它也动下半身 ⇒ 得把下半身的轨道**滤掉**再当叠加层。
##      这个探针就是判 A/B 的。
##
## 量的东西（主角 + 两个同伴）：
##   · `Move_Ing` / `Normal_Idle` / `Normal_Attack_Ing`（+ 有的话 `Stand_Attack_Ing`）
##     各自的**轨道数与骨名清单**；
##   · 其中**下半身**（thigh / calf / foot / toe / leg / pelvis / hip / root）有几条；
##   · 攻击动作 ∩ 下半身 = 哪些骨（要滤的就是这些）。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_attack_clip.gd -- --splat=off

## 「下半身」的判据：这些骨一动，腿的姿势就跟着变（pelvis/root 会带动整条腿）
const LOWER := ["thigh", "calf", "foot", "toe", "leg", "pelvis", "hip", "root", "skirt"]
const MODELS := [
	{"who": "爱丽丝（主角）", "path": "res://models/Arisu_ext.glb"},
	{"who": "小桃", "path": "res://models/companions/Momoi.glb"},
	{"who": "优香", "path": "res://models/companions/Yuuka.glb"},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for m in MODELS:
		_dump(String(m["who"]), String(m["path"]))
	quit(0)


func _dump(who: String, path: String) -> void:
	print("\n========== %s（%s）==========" % [who, path.get_file()])
	if not ResourceLoader.exists(path):
		print("  !! 文件不在")
		return
	var scene := (load(path) as PackedScene).instantiate()
	var ap := _find(scene, "AnimationPlayer") as AnimationPlayer
	if ap == null:
		print("  !! 没有 AnimationPlayer")
		scene.free()
		return

	var sets := {}
	for clip in ["Normal_Idle", "Move_Ing", "Normal_Attack_Ing", "Stand_Attack_Ing",
			"Kneel_Attack_Ing", "Move_Jump"]:
		if not ap.has_animation(clip):
			continue
		var anim := ap.get_animation(clip)
		var bones := {}
		for t in anim.get_track_count():
			var b := _bone_of(String(anim.track_get_path(t)))
			if not b.is_empty():
				bones[b] = true
		sets[clip] = bones
		var lower: Array[String] = []
		for b in bones:
			if _is_lower(String(b)):
				lower.append(String(b))
		lower.sort()
		print("  %-20s 轨道 %3d 条，骨 %3d 根，其中**下半身 %2d 根**%s" % [
			clip, anim.get_track_count(), bones.size(), lower.size(),
			"" if lower.is_empty() else "：%s" % ", ".join(PackedStringArray(lower))])

	# 结论：攻击动作动了多少下半身
	for clip in ["Normal_Attack_Ing", "Stand_Attack_Ing"]:
		if not sets.has(clip) or not sets.has("Move_Ing"):
			continue
		var lower: Array[String] = []
		for b in sets[clip]:
			if _is_lower(String(b)):
				lower.append(String(b))
		print("  ⇒ %s 的下半身轨道 %d 条 —— %s" % [
			clip, lower.size(),
			"**只有上半身，可以直接叠加**" if lower.is_empty()
			else "**会动腿，叠加前必须把这些轨道滤掉**"])
		# 顺便看看「移动动作独有、攻击动作没有」的骨（这些骨在叠加时会保持移动姿势）
		var only_move: Array[String] = []
		for b in sets["Move_Ing"]:
			if not sets[clip].has(b):
				only_move.append(String(b))
		print("     移动有、攻击没有的骨 %d 根（叠加后由移动层负责）" % only_move.size())
	scene.free()


func _is_lower(name: String) -> bool:
	var low := name.to_lower()
	for k in LOWER:
		if low.contains(k):
			return true
	return false


## `Aris_Original_Mesh/bone_root/Bip001/Skeleton3D:bone_Railgunup_01` → `bone_Railgunup_01`
func _bone_of(path: String) -> String:
	var i := path.rfind(":")
	return path.substr(i + 1) if i >= 0 else ""


func _find(n: Node, cls: String) -> Node:
	if n == null:
		return null
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null
