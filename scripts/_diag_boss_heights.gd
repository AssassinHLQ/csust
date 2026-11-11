extends SceneTree
## 量各 Boss **实例化之后**的真实包围盒高度，用来定 `attack_max_height`。
##
## 用户 2026-11-11：「飞起来还是打得到我,还有 boss 倭瓜也是」——
## 固定 6 m 的高度容差对低空平飞（1~2 m）形同虚设。
## 判据应改成按 Boss 体型走：猪 3 m 高打不到 5 m 的人，恐龙 8 m 高就该打到。
##
##   & <godot> --headless --path . --script res://scripts/_diag_boss_heights.gd

const BOSSES := [
	["pig_boss.gd", "飞猪优香"],
	["squash_boss.gd", "倭瓜优香"],
	["trex_boss.gd", "霸王龙"],
	["peroro_boss.gd", "佩洛洛斯拉"],
	["bina_boss.gd", "比纳"],
	["hod_boss.gd", "霍德"],
	["goliath_boss.gd", "哥利亚"],
]


func _initialize() -> void:
	_run.call_deferred()


func _collect_mesh(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_mesh(c, out)


func _run() -> void:
	print("========== Boss 真实包围盒 ==========")
	var stage := Node3D.new()
	root.add_child(stage)
	print("%-14s %10s %10s %10s %10s" % ["Boss", "本高(m)", "本宽(m)", "reach", "radius"])
	for entry in BOSSES:
		var path := "res://scripts/" + String(entry[0])
		if not ResourceLoader.exists(path):
			continue
		var script := load(path)
		if script == null:
			continue
		var boss = script.new()
		if boss == null:
			continue
		stage.add_child(boss)
		await process_frame
		var meshes: Array = []
		_collect_mesh(boss, meshes)
		var box := AABB()
		var first := true
		for m in meshes:
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var g: AABB = mi.global_transform * mi.get_aabb()
			if first:
				box = g
				first = false
			else:
				box = box.merge(g)
		print("%-14s %10.2f %10.2f %10.1f %10.1f%s" % [
			entry[1], box.size.y, maxf(box.size.x, box.size.z),
			float(boss.get("attack_reach")), float(boss.get("attack_radius")),
			"" if not first else "   （无网格）"])
		boss.queue_free()
		await process_frame
	print("")
	print("⇒ 高度容差建议 = max(本体高度 × 1.5, 3.0) m")
	quit(0)
