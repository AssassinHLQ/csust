extends SceneTree
## 地板覆盖检测：在包围盒的地面上打一张网格射线，看**有多少比例真的有地板**。
##
## 为什么要量：渲染图里家具下面一片黑（虚空），需要区分两种可能 ——
##   ① 模型压根没有地板（Max 里分层导出时漏了）
##   ② 有地板，但只盖住了其中一部分
## 这决定「接进游戏时要不要自己补一层地板」。
##
## 用法：
##   _tools/run_probe.sh res://scripts/_probe_floor_cover.gd -- --model=res://models/xxx.glb

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			model = a.substr(8)
	var inst: Node = (load(model) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame

	var box := _aabb(inst)
	print("[floor] 包围盒 %s" % str(box.size.snappedf(0.1)))

	# 地面高度：取「最底部」再往上一点（地板的厚度很薄）
	var y_probe := box.position.y + 0.05
	var space := get_root().world_3d.direct_space_state

	const N := 24          # 24×24 = 576 个采样点
	var hits := 0
	var total := 0
	var hit_ys: Array[float] = []
	for ix in N:
		for iz in N:
			var x := box.position.x + box.size.x * (ix + 0.5) / N
			var z := box.position.z + box.size.z * (iz + 0.5) / N
			var from := Vector3(x, box.position.y + box.size.y + 10.0, z)
			var to := Vector3(x, box.position.y - 10.0, z)
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.collide_with_areas = false
			var hit := space.intersect_ray(q)
			total += 1
			if not hit.is_empty():
				hits += 1
				hit_ys.append((hit["position"] as Vector3).y)

	print("[floor] 射线 %d 条，命中 %d（%.1f%%）" % [hits, total, 100.0 * hits / maxi(total, 1)])
	if hits == 0:
		print("[floor] ⚠️ 一条都没命中 —— 这个模型**没有任何碰撞体**（GLB 默认不带碰撞）")
		print("[floor]    要判断有没有地板几何，得看顶点，不能用射线。")
	else:
		hit_ys.sort()
		print("[floor] 命中高度 最低 %.2f 中位 %.2f 最高 %.2f" % [
			hit_ys[0], hit_ys[hit_ys.size() / 2], hit_ys[-1]])

	# 换一种不依赖碰撞的判据：直接统计「水平面薄片」占包围盒 XZ 的比例
	print("[floor]")
	print("[floor] （改用几何判据：统计 Y 跨度很薄、XZ 很大的物件）")
	var covered := 0.0
	for mi in _meshes(inst):
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if b.size.y <= 0.5 and b.size.x > box.size.x * 0.3 and b.size.z > box.size.z * 0.3:
			covered += 1.0
			print("[floor]   薄片物件 %s  尺寸 %s  底面 y=%.2f" % [
				String(mi.name).substr(0, 28), str(b.size.snappedf(0.1)), b.position.y])
	if covered == 0.0:
		print("[floor]   没有找到覆盖 30% 以上平面的薄片 ⇒ 很可能**没有地板几何**")
	quit(0)


func _aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_walk(node, out)
	return out


func _walk(node: Node, out: Array[MeshInstance3D]) -> void:
	var mi := node as MeshInstance3D
	if mi != null:
		out.append(mi)
	for c in node.get_children():
		_walk(c, out)
