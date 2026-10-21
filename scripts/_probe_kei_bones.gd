extends SceneTree
## 探针：凯伊（`Kei_ext.glb`）的骨架里，有没有能当「眼睛连线」用的骨？
##
## 其余的同伴都有 `Bip001 eye_L / eye_R`，凯伊没有（`_probe_role_roll.gd` 报 ✘）。
## 这里把**头骨的子骨**和所有名字里带 eye / ear / 耳 的骨列出来，看能不能找到镜像的一对。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_kei_bones.gd

const MODEL := "res://models/companions/Kei_ext.glb"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var sk := _find(inst, "Skeleton3D") as Skeleton3D
	if sk == null:
		print("!! 没有骨架")
		quit(1)
		return
	print("骨总数 = %d" % sk.get_bone_count())
	var head := sk.find_bone("Bip001 Head")
	print("Bip001 Head = %d" % head)
	var cands: Array[String] = []
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		var low := n.to_lower()
		if low.contains("eye") or low.contains("ear") or low.contains("jaw"):
			cands.append("%s(#%d)" % [n, i])
	print("名字带 eye/ear/jaw 的骨：%s" % ", ".join(cands))

	if head >= 0:
		print("\n头骨的直接子骨：")
		for i in sk.get_bone_count():
			if sk.get_bone_parent(i) == head:
				var rest := sk.get_bone_rest(i).origin
				print("  %-24s #%d  rest=(%.3f, %.3f, %.3f)" % [
					sk.get_bone_name(i), i, rest.x, rest.y, rest.z])

	print("\n可能成对的骨（名字以 _L/_R 或 .L/.R 结尾，且 rest 位置互为镜像）：")
	var lefts := {}
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		var base := ""
		if n.ends_with("_L") or n.ends_with(".L") or n.ends_with("_l"):
			base = n.substr(0, n.length() - 2)
		elif n.ends_with("_R") or n.ends_with(".R") or n.ends_with("_r"):
			base = n.substr(0, n.length() - 2)
		else:
			continue
		if not lefts.has(base):
			lefts[base] = {}
		lefts[base][n.substr(n.length() - 1)] = i
	var pairs := 0
	for base in lefts:
		var pair: Dictionary = lefts[base]
		var li: int = pair.get("L", pair.get("l", -1))
		var ri: int = pair.get("R", pair.get("r", -1))
		if li < 0 or ri < 0:
			continue
		var a := sk.get_bone_rest(li).origin
		var b := sk.get_bone_rest(ri).origin
		if absf(a.x + b.x) > 0.02 or absf(a.y - b.y) > 0.02 or absf(a.z - b.z) > 0.02:
			continue
		pairs += 1
		if absf(a.y - b.y) < 0.02 and absf(a.x - b.x) > 0.02:
			print("  %-20s 左(%.3f,%.3f,%.3f) 右(%.3f,%.3f,%.3f)" % [
				base, a.x, a.y, a.z, b.x, b.y, b.z])
	print("镜像对共 %d 组" % pairs)
	quit(0)


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null
