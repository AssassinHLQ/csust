extends SceneTree
## 量爱丽丝的真实身高：**用骨骼**（头顶 / 脚趾）而不是网格包围盒。
##
##   godot --headless --path . --script res://scripts/_probe_body_extent.gd -- --splat=off --story=off
##
## 为什么不用 AABB：glTF 蒙皮网格的 `mesh.get_aabb()` 是**静止姿势**的盒子，
## 实测整套合起来是 y = -0.605 … 1.002，比真人矮一截还沉到地下 0.6 m，
## 拿它算「看得见全身」会算错。

const CANDIDATES := ["Head", "head", "Foot", "foot", "Toe", "toe", "Hips", "hips",
	"Neck", "neck", "Spine"]


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(120)

	var player := game.get_node_or_null("Player") as Node3D
	if player == null:
		print("[body] 没有 Player")
		quit(1)
		return
	var model := player.get_node_or_null("Arisu") as Node3D
	var skel: Skeleton3D = null
	if model != null:
		for s in model.find_children("*", "Skeleton3D", true, false):
			skel = s as Skeleton3D
			break
	if skel == null:
		print("[body] 没有 Skeleton3D")
		quit(1)
		return

	print("[body] Player 原点 y=%.3f   Arisu 节点 y=%.3f" % [
		player.global_position.y, model.global_position.y])
	print("[body] 骨骼 %d 根，匹配到的关键骨：" % skel.get_bone_count())
	var lo := INF
	var hi := -INF
	for i in skel.get_bone_count():
		var nm := skel.get_bone_name(i)
		var gp := skel.global_transform * skel.get_bone_global_pose(i).origin
		var hit := false
		for c in CANDIDATES:
			if nm.to_lower().contains(c.to_lower()):
				hit = true
				break
		if hit:
			print("   %-28s y=%.3f  x=%.3f z=%.3f" % [nm, gp.y, gp.x, gp.z])
		# 全身最高/最低点：只统计明显属于身体的骨（排除武器挂点）
		var low := nm.to_lower()
		if low.contains("weapon") or low.contains("prop") or low.contains("attach"):
			continue
		lo = minf(lo, gp.y)
		hi = maxf(hi, gp.y)
	print("[body] 骨骼点 y 范围：%.3f … %.3f（相对 Player 原点）" % [
		lo - player.global_position.y, hi - player.global_position.y])

	# 逐个网格看 AABB，找出那个沉到地下的东西是谁
	print("[body] 网格 AABB（全局 y 范围）：")
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.get_aabb()
		print("   %-42s y %.3f … %.3f   visible=%s" % [
			mi.name, a.position.y - player.global_position.y,
			a.end.y - player.global_position.y, str(mi.is_visible_in_tree())])
	quit(0)
