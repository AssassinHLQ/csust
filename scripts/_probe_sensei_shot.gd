extends SceneTree
## 探针：给「老师」NPC 拍三张（正面 / 侧面 / 与学生的合影），确认朝向、比例、贴图。
##
## 用法（要真渲染）：godot --path <工程> --script res://scripts/_probe_sensei_shot.gd
## 输出：_arisu_captures/_sensei/{front,side,group}.png

const SHOT_DIR := "_arisu_captures/_sensei"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(720, 760)
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(45)

	var sensei := game.get_node_or_null("Sensei") as Node3D
	if sensei == null:
		print("!! 场景里没有 Sensei 节点")
		quit(1)
		return
	var model := sensei.get_child(0) if sensei.get_child_count() > 0 else null
	print("[sensei] 子节点 = %s" % (model.name if model else "（无，模型没加载进来）"))

	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.05
	cam.far = 200.0
	root.add_child(cam)
	cam.make_current()

	# 老师的「前方」由**眼睛骨**算，不靠节点基向量 —— 节点转了 180°，
	# 基向量和「脸朝哪」已经差了 180°，用基向量拍出来的「正面」其实是后脑勺（踩过）。
	var p := sensei.global_position
	var fwd := _face_forward(sensei)
	print("[sensei] 脸朝向 = %s（0=+X 90=−Z）" % str(fwd.snappedf(0.01)))

	var aabb := _visual_aabb(sensei)
	print("[sensei] 世界包围盒 size=%s  center=%s" % [
		str(aabb.size.snappedf(0.01)), str(aabb.get_center().snappedf(0.01))])

	await _shoot(cam, p + fwd * 3.0 + Vector3.UP * 1.15, p + Vector3.UP * 0.85,
		out.path_join("front.png"))
	await _shoot(cam, p + sensei.global_transform.basis.x * 3.0 + Vector3.UP * 1.15,
		p + Vector3.UP * 0.85, out.path_join("side.png"))
	# 合影：从玩家身后往老师那边看
	var player := game.get_node_or_null("Player") as Node3D
	var eye := (player.global_position if player else Vector3.ZERO) + Vector3(0, 1.7, 4.0)
	await _shoot(cam, eye, p + Vector3.UP * 0.9, out.path_join("group.png"))

	print("[sensei] 输出目录 %s" % out)
	quit(0)


## 用眼睛骨算「脸朝哪」：MMD 骨名是 左目 / 右目。找不到就退回节点 −Z。
func _face_forward(root: Node) -> Vector3:
	var sk := _find_skel(root)
	if sk != null:
		var l := sk.find_bone("左目")
		var r := sk.find_bone("右目")
		if l < 0:
			l = sk.find_bone("左目.L")
		if r < 0:
			r = sk.find_bone("右目.R")
		if l >= 0 and r >= 0:
			var pl: Vector3 = sk.global_transform * sk.get_bone_global_pose(l).origin
			var pr: Vector3 = sk.global_transform * sk.get_bone_global_pose(r).origin
			var right := (pr - pl).normalized()
			var f := Vector3.UP.cross(right).normalized()
			if f.length() > 0.5:
				return (f as Vector3)
	var n := root as Node3D
	return -n.global_transform.basis.z


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _shoot(cam: Camera3D, from: Vector3, at: Vector3, file: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("  [img] %s" % file)


func _visual_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			var box := vi.get_aabb()
			if box.size.length() > 0.0001:
				var b := Transform3D(vi.global_transform.basis, vi.global_transform.origin) * box
				out = b if first else out.merge(b)
				first = false
		for c in n.get_children():
			stack.append(c)
	return out


func _wait(frames: int) -> void:
	for _i in frames:
		await process_frame
