extends SceneTree
## 查 Godot 4.7 到底有没有「布料」能力，别凭记忆答。
##   · Godot 3 有个 `Cloth` 节点，4.x 删掉了 —— 确认一下
##   · `SoftBody3D` 在不在、有没有 pin / 碰撞相关属性、能不能当布用
##   · 顺带看 `MeshInstance3D` 上有没有和软体/布料相关的入口
##
## 用法：_tools/run_probe.sh res://scripts/_probe_cloth_caps.gd


func _initialize() -> void:
	print("[cloth] Godot %s" % Engine.get_version_info()["string"])

	print("── ① 有没有 Cloth 节点（Godot 3 的东西）──")
	for name in ["Cloth", "SoftBody3D", "RigidBody3D", "GPUParticles3D"]:
		print("     %-14s -> %s" % [name, "有" if ClassDB.class_exists(name) else "没有"])

	print("── ② SoftBody3D 继承链 ──")
	var chain: Array[String] = []
	var cur := "SoftBody3D"
	while cur != "":
		chain.append(cur)
		cur = ClassDB.get_parent_class(cur)
	print("     %s" % " <- ".join(chain))

	print("── ③ SoftBody3D 的属性 ──")
	var props: Array[Dictionary] = []
	for p in ClassDB.class_get_property_list("SoftBody3D", true):
		props.append(p)
	for p in props:
		print("     %-28s %s" % [String(p.get("name", "")), str(p.get("type", ""))])

	print("── ④ SoftBody3D 的方法（只看和 pin / 碰撞 / 模拟有关的）──")
	var names: Array[String] = []
	for m in ClassDB.class_get_method_list("SoftBody3D", true):
		var nm := String(m.get("name", ""))
		if nm.contains("pin") or nm.contains("point") or nm.contains("collision") \
				or nm.contains("simul") or nm.contains("mesh"):
			names.append(nm)
	names.sort()
	print("     %s" % ", ".join(names))

	print("── ⑤ MeshInstance3D 上有没有软体入口 ──")
	var mi: Array[String] = []
	for m in ClassDB.class_get_method_list("MeshInstance3D", true):
		var nm2 := String(m.get("name", ""))
		if nm2.contains("soft") or nm2.contains("cloth") or nm2.contains("blend"):
			mi.append(nm2)
	print("     %s" % (", ".join(mi) if not mi.is_empty() else "（没有）"))

	print("── ⑥ 有没有渲染端的软体/布料相关类 ──")
	for name2 in ["SoftBody3D", "MeshInstance3D", "SkeletonModifier3D", "PhysicalBoneSimulator3D"]:
		print("     %-24s %s" % [name2, "存在" if ClassDB.class_exists(name2) else "不存在"])

	quit()
