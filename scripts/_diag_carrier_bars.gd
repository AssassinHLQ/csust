extends SceneTree
## 定位：机甲身上那条**白色粗长条**到底是哪个节点。
##
## 用户 2026-11-10（附截图）：「这个喷出来的条还是没有去掉,你是去错了吗」
## 本喵上一轮删了 _ribbons / _rings / _speed_lines，但白条还在 ⇒ 删错了对象。
##
## 本探针把机甲下**所有可见 MeshInstance3D** 列出来，按「世界尺寸里最长的那一维」
## 排序，并打印颜色，找出符合"细长 + 白色"特征的节点。
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_diag_carrier_bars.gd

const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("========== 机甲白色长条定位 ==========")
	var level := (load(GAME) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 20:
		await process_frame

	var player := level.get_node_or_null("Player")
	var carrier := player.get_node_or_null("Arisu/CarrierForm") if player else null
	if carrier == null:
		push_error("[diag] 没有 CarrierForm")
		quit(1)
		return
	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	MechStateScript.call("set_carrier_for_test", true)
	carrier.call("set_form", true)
	for _i in 30:
		await process_frame

	# 给点推力，让飞行特效全都出现
	Input.action_press("jump")
	for _i in 60:
		await physics_frame

	var cnode := carrier.get("_carrier") as Node3D
	if cnode == null:
		push_error("[diag] 没有载具节点")
		quit(1)
		return

	# 收集所有可见 mesh
	var rows: Array = []
	var stack: Array[Node] = [cnode]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		var aabb := mi.get_aabb()
		# 世界尺寸：用全局缩放乘 aabb.size
		var gs := mi.global_transform.basis.get_scale()
		var ws := Vector3(aabb.size.x * absf(gs.x), aabb.size.y * absf(gs.y),
			aabb.size.z * absf(gs.z))
		var longest := maxf(maxf(ws.x, ws.y), ws.z)
		# 细长判据：最长维 > 1.0 m，且最短维不到最长的 1/10
		var shortest := minf(minf(ws.x, ws.y), ws.z)
		var slender := longest > 1.0 and shortest < longest * 0.12
		# 颜色
		var col := Color(1, 1, 1)
		if mi.material_override is StandardMaterial3D:
			col = (mi.material_override as StandardMaterial3D).albedo_color
		elif mi.mesh != null and mi.mesh.get_surface_count() > 0 \
				and mi.mesh.surface_get_material(0) is StandardMaterial3D:
			col = (mi.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color
		var whiteish := col.r > 0.7 and col.g > 0.7 and col.b > 0.7
		rows.append({
			"name": String(mi.name),
			"path": str(mi.get_path()).replace(str(cnode.get_path()), ""),
			"longest": longest, "size": ws, "col": col,
			"slender": slender, "white": whiteish,
		})

	Input.action_release("jump")
	rows.sort_custom(func(a, b): return float(a["longest"]) > float(b["longest"]))

	print("\n── 所有可见 mesh（按最长边降序）──")
	print("%-26s %-8s %-22s %-14s %s" % ["名字", "最长边", "世界尺寸", "颜色", "标记"])
	var suspects: Array = []
	for r in rows:
		var tag := ""
		if bool(r["slender"]) and bool(r["white"]):
			tag = "  ★★★ 细长+白色 = 嫌疑"
			suspects.append(r)
		elif bool(r["slender"]):
			tag = "  ★ 细长"
		var c: Color = r["col"]
		print("%-26s %7.2f %-22s (%.2f,%.2f,%.2f) %s" % [
			String(r["name"]).substr(0, 26), float(r["longest"]),
			str((r["size"] as Vector3).snappedf(0.01)), c.r, c.g, c.b, tag])

	print("\n── 嫌疑节点 %d 个 ──" % suspects.size())
	for r in suspects:
		print("  %s  尺寸 %s  颜色 (%.2f,%.2f,%.2f)" % [
			str(r["path"]), str((r["size"] as Vector3).snappedf(0.01)),
			(r["col"] as Color).r, (r["col"] as Color).g, (r["col"] as Color).b])
	quit(0)
