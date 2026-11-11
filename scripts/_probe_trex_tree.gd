extends SceneTree
## 探针：搞清楚 TrexBossB 的模型树到底长什么样、材质挂在哪。
##
## 上一版 `_probe_rainbow_trex.gd` 统计出「ShaderMaterial 0 / Standard 0」，
## 说明本喵猜的路径（`ObjModel` + surface override）不对。先把真相打出来。

const NEXT := "res://scenes/next_level.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load(NEXT) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _i in 200:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame

	var t := level.get_node_or_null("TrexBossB") as Node3D
	if t == null:
		print("没找到")
		quit(1)
		return

	print("=== TrexBossB 子节点树（深度 4）===")
	_dump(t, 0, 4)

	print("\n=== 所有 MeshInstance3D 的材质情况 ===")
	var n := 0
	for mi in t.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		n += 1
		if n > 6:
			continue
		print(" Mesh: %s（父 %s）" % [String(m.name), String(m.get_parent().name)])
		print("   material_override = %s" % str(m.material_override))
		if m.mesh == null:
			print("   mesh = null")
			continue
		for s in m.mesh.get_surface_count():
			var base := m.mesh.surface_get_material(s)
			var ov := m.get_surface_override_material(s)
			print("   surface %d：base=%s(%s)  override=%s"
				% [s, base.get_class() if base != null else "null",
					(base.resource_name if base != null and base is Material else "?"),
					ov.get_class() if ov != null else "null"])
	print("（共 %d 个 MeshInstance3D）" % n)

	print("\n=== model 变量指向谁 ===")
	var model = t.get("model")
	print("  model = %s（%s）" % [str(model),
		(model.get_class() if model != null else "null")])

	quit(0)


func _dump(n: Node, d: int, max_d: int) -> void:
	if d > max_d:
		return
	var extra := ""
	if n is MeshInstance3D:
		var m := n as MeshInstance3D
		extra = "  [Mesh surfaces=%d override=%s]" % [
			m.mesh.get_surface_count() if m.mesh != null else -1,
			m.material_override.get_class() if m.material_override != null else "null"]
	print("%s%s (%s)%s" % ["  ".repeat(d), String(n.name), n.get_class(), extra])
	for c in n.get_children():
		_dump(c, d + 1, max_d)
