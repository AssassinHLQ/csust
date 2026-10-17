extends SceneTree
## 探针：**眨眼到底是谁在动**。
##
## 用户 2026-10-18：「最后为什么眼皮还在动，之前不是都删眼睛那儿的动画了吗」。
##
## `PoseFix.freeze_eyelids()` 只删了 **骨** 轨道（`Bip001 eye_L/R_1/2`），
## `_verify_blink.gd` 也确认真播 2 秒时那四根骨的局部旋转一动不动。
## 那眼皮还在动就只剩两种可能：
##   ① 眨眼走的是 **blend shape（形态键）** 轨道，不是骨 —— 删骨轨道当然没用；
##   ② 动的不是那四根骨，而是别的骨（睫毛 / 眉 / 眼白…）。
##
## 这个探针把每个动作里**每一种轨道类型**列出来，并把形态键轨道、以及名字里带
## eye / lid / mabuta / brow / face 的骨轨道全部点名，让答案自己浮出来。
##
## 用法（无渲染即可）：
##   godot --path <工程> --headless --script res://scripts/_probe_blink_src.gd
##
## 只读，不写文件。

const MODEL := "res://models/Arisu_ext.glb"
## 名字里带这些片段的骨 / 形态键都点名（手写清单，别指望拼写）
const WATCH := ["eye", "lid", "mabuta", "brow", "lash", "kao", "face", "mouth", "blink", "close"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(640, 360)
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	for _i in 4:
		await process_frame
	var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
	var sk := _find(inst, "Skeleton3D") as Skeleton3D
	if ap == null:
		print("!! 没有 AnimationPlayer")
		quit(1)
		return
	print("=== 动作 %d 个；骨架 %s ===" % [ap.get_animation_list().size(),
		"有" if sk != null else "**没有**"])

	var total_by_type := {}
	var blend_all := []
	var watch_bones := {}
	for clip in ap.get_animation_list():
		var a := ap.get_animation(String(clip))
		var hist := {}
		var named := []
		for t in a.get_track_count():
			var ty := a.track_get_type(t)
			hist[ty] = int(hist.get(ty, 0)) + 1
			total_by_type[ty] = int(total_by_type.get(ty, 0)) + 1
			var p := String(a.track_get_path(t))
			if ty == Animation.TYPE_BLEND_SHAPE:
				var key := "%s | %s" % [String(clip), p]
				blend_all.append(key)
			var low := p.to_lower()
			for w in WATCH:
				if low.contains(String(w)):
					named.append("%s%s" % [p, "" if ty != Animation.TYPE_BLEND_SHAPE else "  [形态键]"])
					var bn := p.substr(p.rfind(":") + 1)
					watch_bones[bn] = int(watch_bones.get(bn, 0)) + 1
					break
		var parts: Array[String] = []
		for ty in hist.keys():
			parts.append("%s=%d" % [_type_name(int(ty)), int(hist[ty])])
		print("\n[%s] %.3f s  轨道 %d 条  %s" % [String(clip), a.length,
			a.get_track_count(), " ".join(parts)])
		if not named.is_empty():
			for s in named.slice(0, 40):
				print("      · %s" % String(s))

	print("\n=== 全部动作的轨道类型合计 ===")
	for ty in total_by_type.keys():
		print("  %-12s %d" % [_type_name(int(ty)), int(total_by_type[ty])])
	print("  形态键轨道总数 = %d" % blend_all.size())

	print("\n=== 被点名的「眼 / 脸」相关骨（按出现次数）===")
	if watch_bones.is_empty():
		print("  （一条都没有）")
	for k in watch_bones.keys():
		print("  %-32s %d 条" % [String(k), int(watch_bones[k])])

	if sk != null:
		print("\n=== 骨架里名字带 watch 的骨 ===")
		var n := 0
		for i in sk.get_bone_count():
			var nm := sk.get_bone_name(i)
			var low := nm.to_lower()
			for w in WATCH:
				if low.contains(String(w)):
					print("  [%3d] %s  (parent=%d)" % [i, nm, sk.get_bone_parent(i)])
					n += 1
					break
		if n == 0:
			print("  （没有）")
	quit(0)


func _type_name(ty: int) -> String:
	match ty:
		Animation.TYPE_VALUE:
			return "TYPE_VALUE"
		Animation.TYPE_POSITION_3D:
			return "POSITION_3D"
		Animation.TYPE_ROTATION_3D:
			return "ROTATION_3D"
		Animation.TYPE_SCALE_3D:
			return "SCALE_3D"
		Animation.TYPE_BLEND_SHAPE:
			return "BLEND_SHAPE"
		Animation.TYPE_METHOD:
			return "METHOD"
		Animation.TYPE_BEZIER:
			return "BEZIER"
		_:
			return "type%d" % ty


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
