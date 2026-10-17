extends SceneTree
## 探针：爱丽丝的 10 块 `Mouth_*` 网格**到底同时露出几块**。
##
## 用户说：「Mouth_* 应该是表情，换网格就是换表情，一般只出现一个吧」——
## 那就把每条循环动画里、每一帧的可见性 / morph_0 / 驱动骨的 scale 全打出来，
## 看是不是「好几块同时露着」把表情叠成了双层。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_mouth_vis.gd

const MODEL := "res://models/Arisu_ext.glb"
const CLIPS := ["Normal_Idle", "Move_Ing"]
const SAMPLES := 8


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var ap := _find_anim(inst)
	var mouths: Array[MeshInstance3D] = []
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).name.begins_with("Mouth_"):
			mouths.append(n as MeshInstance3D)
		for c in n.get_children():
			stack.append(c)
	print("[mouth] 找到 %d 块 Mouth_* 网格" % mouths.size())
	for mi in mouths:
		var p := mi.get_parent()
		print("   %-16s 父=%-22s 全局缩放=%s  aabb=%s" % [
			mi.name, (p.name if p else "?"),
			str(mi.global_transform.basis.get_scale().snappedf(0.001)),
			str(mi.get_aabb().size.snappedf(0.001))])
	if mouths.is_empty():
		quit(0)
		return
	if ap == null:
		print("!! 没有 AnimationPlayer")
		quit(1)
		return

	for clip in CLIPS:
		if not ap.has_animation(clip):
			continue
		var a := ap.get_animation(clip)
		ap.play(clip)
		print("\n===== %s（%.2f s）=====" % [clip, a.length])
		for i in SAMPLES:
			var t := a.length * float(i) / float(SAMPLES)
			ap.seek(t, true)
			await process_frame
			var shown: Array[String] = []
			var total := 0.0
			for mi in mouths:
				var m := 0.0
				if mi.mesh != null and mi.mesh.get_blend_shape_count() > 0:
					m = mi.get_blend_shape_value(0)
				total += m
				if mi.visible and m > 0.01:
					shown.append("%s(%.2f)" % [mi.name, m])
			print("  t=%.2f  露出 %d 块：%s   morph 总和 %.2f" % [
				float(t), shown.size(), ", ".join(shown) if not shown.is_empty() else "（无）", total])
	quit(0)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null
