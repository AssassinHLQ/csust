extends SceneTree
## 探针：把七名同伴**排成一排、脸朝镜头**渲一张合影，用来一次看清两件事：
##   1. 每只模型的本体朝向对不对（Rig 补了 180° 之后，节点 +Z 应该是脸）
##   2. 脚有没有踩在地上（`model_y_offset` 是全局一个值，各模型原点高度不一样）
##
## 为什么用合影而不是逐只渲：逐只要看 7 张图，而朝向和接地都是「一眼的事」。
## 相机放 +Z 侧、同伴 rotation.y = 0 → 谁的脸朝我们，谁的朝向就是对的。
##
## 用法：godot --path <工程> --script res://scripts/_probe_companion_row.gd
## 输出：…/_arisu_captures/_companion/row_*.png

const CompanionScene := preload("res://scenes/companion.tscn")

## 名字 → 模型（顺序就是站位顺序）
const ROSTER := [
	["未花 Mika", "res://models/companions/Mika.glb", -0.035],
	["优香 Yuuka", "res://models/companions/Yuuka.glb", -0.035],
	["诺亚 Noa", "res://models/companions/Noa.glb", -0.035],
	["小桃 Momoi", "res://models/companions/Momoi.glb", -0.035],
	["小绿 Midori", "res://models/companions/Midori.glb", -0.035],
	["柚子 Yuzu", "res://models/companions/Yuzu.glb", -0.035],
	["凯伊 Kei", "res://models/companions/Kei.glb", -0.035],
]

var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	root.add_child(sun)

	# 地面：厚板，顶面正好在 y = 0（跟竞技场地面一致）
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(40, 1, 40)
	ground.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.34, 0.38)
	mat.roughness = 0.95
	ground.material_override = mat
	ground.position = Vector3(0, -0.5, 0)
	root.add_child(ground)

	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.02
	cam.far = 500.0
	root.add_child(cam)
	cam.make_current()

	var placed: Array[Node3D] = []
	var pitch := 1.45
	var i := 0
	for entry in ROSTER:
		var c: Node3D = CompanionScene.instantiate()
		c.name = "Row%d" % i
		c.set("display_name", entry[0])
		c.set("model_path", entry[1])
		c.set("model_y_offset", float(entry[2]))
		root.add_child(c)
		c.global_position = Vector3((i - 3.0) * pitch, 0.0, 0.0)
		c.rotation.y = 0.0            # 节点 +Z = 脸朝的方向 → 脸朝 +Z，也就是朝相机
		placed.append(c)
		i += 1
	for _f in 30:
		await process_frame

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_companion")
	DirAccess.make_dir_recursive_absolute(_out)

	print("========== 接地情况 ==========")
	print("⚠️ 别用蒙皮网格的 AABB 判接地：蒙皮网格的 get_aabb() 是**绑定姿态**的，")
	print("   跟实际姿态对不上（凯伊就因此报出「垂到 −0.665 m」，渲图里她明明站得好好的）。")
	print("   用**脚骨（Toe/Foot）的世界 y** 判最干净：脚踝大致贴地时它就是 0 附近。")
	print("%-12s %10s %10s %12s" % ["名字", "脚骨世界y", "当前偏移", "结论"])
	for c in placed:
		var skel := _best_skeleton(c)
		var foot_y := _lowest_foot_y(skel)
		var off := float(c.get("model_y_offset"))
		var verdict := "贴地 ✓"
		if foot_y < -0.15:
			verdict = "沉降 %.2f m" % -foot_y
		elif foot_y > 0.15:
			verdict = "浮空 %.2f m" % foot_y
		print("%-12s %10.3f %10.3f %12s" % [c.get("display_name"), foot_y, off, verdict])

	print("\n========== 动画有没有真的驱动骨架 ==========")
	print("（凯伊有 2 个 Skeleton3D，而 AnimDriver 取的是**树里第一个**，不是骨头最多的那个；")
	print("  所以这里不看它选了谁，看**骨骼姿态有没有随时间变**——README §1.8 的老规矩。）")
	for c in placed:
		var anim: Node = c.get("anim")
		var skel_a: Skeleton3D = anim.get("skeleton") if anim != null else null
		var ap: AnimationPlayer = anim.get("player") if anim != null else null
		if skel_a == null or ap == null:
			print("  %-12s ✗ 动画驱动不全（骨架 %s / 播放器 %s）" % [
				c.get("display_name"), str(skel_a), str(ap)])
			continue
		ap.play("Cafe_Walk", -1.0, 1.0)
		await process_frame
		var before := _pose_snapshot(skel_a)
		for _f in 20:
			await process_frame
		var after := _pose_snapshot(skel_a)
		var delta := 0.0
		for k in mini(before.size(), after.size()):
			delta = maxf(delta, rad_to_deg(before[k].angle_to(after[k])))
		print("  %-12s 用骨架「%s」(%d 骨) / 播放器「%s」 → 最大姿态变化 %.1f° %s" % [
			c.get("display_name"), skel_a.name, skel_a.get_bone_count(), ap.name,
			delta, "✓ 在动" if delta > 0.5 else "✗ **没动**"])

	print("\n========== 朝向：脸是不是真朝「节点 +Z」==========")
	print("（companion.gd 给 rig 补了 180°，并且把 rotation.y 设成移动方向 →")
	print("  节点 +Z 就是「她该朝的方向」。用**世界坐标**下的眼骨算脸方向来判：")
	print("  眼骨不乘 skeleton 的 global_transform 会得到错符号，上一轮就是栽在这。）")
	for c in placed:
		var skel := _best_skeleton(c)
		if skel == null:
			print("  %-12s 没有骨架，跳过" % c.get("display_name"))
			continue
		var face := _world_face(skel)
		if face.length() < 0.001:
			print("  %-12s 眼骨不全，判不了" % c.get("display_name"))
			continue
		var node_z := c.global_transform.basis.z.normalized()   # 节点 +Z（她该朝的方向）
		node_z.y = 0.0
		node_z = node_z.normalized()
		var d := face.dot(node_z)
		var verdict := "✅ 正脸朝节点 +Z" if d > 0.5 else (
			"❌ **反了：脸朝节点 −Z**（会倒着走）" if d < -0.5 else "⚠ 侧向，判不准")
		print("  %-12s 脸 %s · 节点+Z %s = %+.2f   %s" % [
			c.get("display_name"), str(face.snappedf(0.01)), str(node_z.snappedf(0.01)), d, verdict])

	# ① 正面：同伴 rotation.y = 0 → 节点 +Z 是脸朝的方向 → 相机放 +Z 侧就该看到正脸
	cam.global_position = Vector3(0.0, 1.05, 5.0)
	cam.look_at(Vector3(0.0, 0.75, 0.0), Vector3.UP)
	await _shot("row_front.png")

	# ② 背面：同一排从 −Z 侧看，应该全是后脑勺（与 ① 互为对照）
	cam.global_position = Vector3(0.0, 1.05, -5.0)
	cam.look_at(Vector3(0.0, 0.75, 0.0), Vector3.UP)
	await _shot("row_back.png")

	# ③ 贴地正视：相机压到 0.5 m 高，专门看脚下有没有浮空/埋地
	cam.global_position = Vector3(0.0, 0.5, 4.6)
	cam.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)
	await _shot("row_feet.png")

	# ④ 凯伊特写（她的视觉包围盒垂到 y=−0.665，是七只里唯一出问题的）
	cam.global_position = Vector3(4.35, 0.95, 2.6)
	cam.look_at(Vector3(4.35, 0.55, 0.0), Vector3.UP)
	await _shot("row_kei.png")

	print("[row] 输出目录：%s" % _out)
	quit(0)


## 脸在世界坐标下的方向：**必须**把骨骼点乘上 skeleton 的 global_transform。
## 上一轮的 _probe_companion.gd 漏了这一步，于是把「本体朝 −Z」判反了 —— 因为
## 这批 GLB 的 Skeleton3D 节点自带 180°，骨骼空间与模型空间正好差一个符号。
func _world_face(skel: Skeleton3D) -> Vector3:
	var eyes: Array[int] = []
	var head := -1
	for i in skel.get_bone_count():
		var low := skel.get_bone_name(i).to_lower()
		if low.contains("eye"):
			eyes.append(i)
		if head < 0 and low.contains("head"):
			head = i
	if eyes.size() < 2 or head < 0:
		return Vector3.ZERO
	var xf := skel.global_transform
	var mid := Vector3.ZERO
	for e in eyes:
		mid += xf * skel.get_bone_global_pose(e).origin
	mid /= float(eyes.size())
	var h: Vector3 = xf * skel.get_bone_global_pose(head).origin
	var d := mid - h
	d.y = 0.0
	return d.normalized() if d.length() > 0.0001 else Vector3.ZERO


## 最低的脚骨（Toe 优先，没有就 Foot）在世界坐标下的 y
func _lowest_foot_y(skel: Skeleton3D) -> float:
	if skel == null:
		return 0.0
	var xf := skel.global_transform
	var best := INF
	for i in skel.get_bone_count():
		var low := skel.get_bone_name(i).to_lower()
		if low.contains("toe") or low.contains("foot") or low.contains("ankle"):
			best = minf(best, (xf * skel.get_bone_global_pose(i).origin).y)
	return 0.0 if best == INF else best


## 每个骨骼的姿态旋转快照，用来判「动画到底有没有在动」
func _pose_snapshot(skel: Skeleton3D) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	for i in skel.get_bone_count():
		out.append(skel.get_bone_pose_rotation(i))
	return out


func _best_skeleton(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			var sk := n as Skeleton3D
			if best == null or sk.get_bone_count() > best.get_bone_count():
				best = sk
		for ch in n.get_children():
			stack.append(ch)
	return best


func _shot(name: String) -> void:
	for _f in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := _out.path_join(name)
	root.get_texture().get_image().save_png(path)
	print("  [img] %s" % path)


func _visual_aabb(node: Node3D) -> AABB:
	var to_local := node.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			if vi.visible and vi.get_aabb().size.length() > 0.0001:
				var b: AABB = to_local * (vi.global_transform * vi.get_aabb())
				out = b if first else out.merge(b)
				first = false
		for ch in n.get_children():
			stack.append(ch)
	return out
