extends SceneTree
## 探针：同伴的**碰撞胶囊**和**模型**在水平方向上对不对齐。
##
## 用户 2026-10-21：「凯伊的碰撞有问题，右偏了两个身位」。
## 不加载 `game.tscn`（画室609 的代理盒会把镜头挡在一片灰里），自己搭一块地面、
## 按主场景里的配置把七名同伴摆上去，量三样东西（全部世界坐标，只看 x/z）：
##   ① 胶囊轴线（`Companion/Collision` 的 global_position）
##   ② 模型整体 AABB 的中心（蒙皮网格 AABB 是绑定姿态，只当参考）
##   ③ 胯骨（Hips / Pelvis / …）的世界位置 —— 站姿里「人真的在哪」
## ②③ 各自减 ① 就是偏移。打开 `debug_collisions_hint` 把胶囊画出来一起拍。
##
## 用法：godot --path <工程> --script res://scripts/_probe_kei_collision.gd
## 输出：`_arisu_captures/_companion/95_kei_top.png` / 96 正 / 96b 侧 / 97 全排俯视

const CompanionScene := preload("res://scenes/companion.tscn")
const OUT := "_companion"

## 与 `scenes/game.tscn` 里的七名同伴一致（名字 → 模型）
const ROSTER := [
	["小雪", "res://models/companions/Koyuki.glb"],
	["优香", "res://models/companions/Yuuka.glb"],
	["诺亚", "res://models/companions/Noa.glb"],
	["小桃", "res://models/companions/Momoi.glb"],
	["小绿", "res://models/companions/Midori.glb"],
	["柚子", "res://models/companions/Yuzu.glb"],
	["凯伊", "res://models/companions/Kei_ext.glb"],
]
const HIPS_CANDIDATES := ["Hips", "Pelvis", "hip", "Root", "Bip01 Pelvis",
	"bone_Hips", "pelvis", "spine"]


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
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	root.add_child(sun)

	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(40, 1, 40)
	ground.mesh = box
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.32, 0.36)
	gm.roughness = 0.95
	ground.material_override = gm
	ground.position = Vector3(0, -0.5, 0)
	root.add_child(ground)

	var placed: Array = []
	for i in ROSTER.size():
		var c := CompanionScene.instantiate() as Node3D
		c.name = "Row%d" % i
		c.set("display_name", ROSTER[i][0])
		c.set("model_path", ROSTER[i][1])
		c.set("model_y_offset", -0.035)
		root.add_child(c)
		c.global_position = Vector3((float(i) - 3.0) * 1.5, 0.05, 0.0)
		c.rotation.y = 0.0
		placed.append(c)
	for _i in 30:
		await process_frame
	debug_collisions_hint = true

	print("\n%-6s %-22s %-20s %-20s %8s %8s %8s" % [
		"名字", "胶囊轴线(x,z)", "模型AABB中心", "胯骨", "AABB偏移", "胯骨偏移", "胶囊底y"])
	print("-".repeat(100))
	var worst := ""
	var worst_d := 0.0
	for c in placed:
		var cap := c.get_node_or_null("Collision") as CollisionShape3D
		var model := c.get("model") as Node3D
		var cx := cap.global_position.x
		var cz := cap.global_position.z
		var sh := cap.shape as CapsuleShape3D
		var cap_bottom := cap.global_position.y - sh.height * 0.5
		var aabb := _world_aabb(model)
		var ac := aabb.get_center()
		var skel := _best_skeleton(model)
		var hips := Vector3.ZERO
		var hi := -1
		if skel != null:
			hi = _hips_index(skel)
			if hi >= 0:
				hips = skel.global_transform * skel.get_bone_global_pose(hi).origin
		var d_aabb := Vector2(ac.x - cx, ac.z - cz).length()
		var d_hips := Vector2(hips.x - cx, hips.z - cz).length() if hi >= 0 else -1.0
		print("%-6s (%7.3f,%7.3f) (%7.3f,%7.3f) %-20s %8.3f %8.3f %8.3f" % [
			c.get("display_name"), cx, cz, ac.x, ac.z,
			("(%7.3f,%7.3f)" % [hips.x, hips.z]) if hi >= 0 else "— 无胯骨",
			d_aabb, d_hips, cap_bottom])
		print("       胶囊 r=%.2f h=%.2f ｜ 骨架 %s ｜ AABB %.2f×%.2f×%.2f" % [
			sh.radius, sh.height,
			"%d 骨「%s」" % [skel.get_bone_count(), _hip_name(skel, hi)] if skel != null else "无",
			aabb.size.x, aabb.size.y, aabb.size.z])
		if d_hips > worst_d:
			worst_d = d_hips
			worst = String(c.get("display_name"))

	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)

	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.05
	cam.far = 300.0
	root.add_child(cam)
	cam.make_current()

	var kei: Node3D = null
	for c in placed:
		if String(c.get("display_name")) == "凯伊":
			kei = c
	if kei != null:
		var p := kei.global_position
		# 用一个半透明红胶囊**站在碰撞盒的位置**：红胶囊和人错开多少，就是碰撞偏多少。
		_add_capsule_stand_in(kei)
		# 俯视：相机正上方，up 用 FORWARD（用 UP 会和视线共线）
		cam.global_position = p + Vector3(0.0, 3.4, 0.01)
		cam.look_at(p + Vector3(0.0, 0.0, 0.0), Vector3.FORWARD)
		await _shot(out_dir.path_join("95_kei_top.png"))
		# 四分之三侧视：最能看出「胶囊在哪儿、人在哪儿」
		cam.global_position = p + Vector3(2.2, 1.6, 2.6)
		cam.look_at(p + Vector3(0.0, 0.7, 0.6), Vector3.UP)
		await _shot(out_dir.path_join("96_kei_quarter.png"))
		cam.global_position = p + Vector3(-2.6, 1.5, 1.2)
		cam.look_at(p + Vector3(0.0, 0.7, 0.6), Vector3.UP)
		await _shot(out_dir.path_join("96b_kei_quarter.png"))

	cam.global_position = Vector3(0.0, 7.0, 0.0)
	cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	cam.rotation_degrees.x = -90.0
	await _shot(out_dir.path_join("97_row_top.png"))

	print("\n出图：%s" % out_dir)
	if worst_d > 0.0:
		print("最大胯骨偏移：%s %.3f m" % [worst, worst_d])
	quit(0)


## 把碰撞胶囊画成一个半透明红壳，摆在 `Companion/Collision` 的位置上：
## 红壳和身体错开多少，就是碰撞偏多少（纯视觉证据，不参与物理）
func _add_capsule_stand_in(c: Node3D) -> void:
	var cap := c.get_node_or_null("Collision") as CollisionShape3D
	if cap == null or not (cap.shape is CapsuleShape3D):
		return
	var sh := cap.shape as CapsuleShape3D
	var cm := CapsuleMesh.new()
	cm.radius = sh.radius + 0.015
	cm.height = sh.height
	var mi := MeshInstance3D.new()
	mi.name = "CapsuleStandIn"
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.18, 0.12, 0.32)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	root.add_child(mi)
	mi.global_transform = cap.global_transform


func _shot(path: String) -> void:
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	for _i in 6:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("[shot] %s" % path.get_file())


func _world_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	if node == null:
		return out
	for n in _all(node, "GeometryInstance3D"):
		var gi := n as GeometryInstance3D
		if not gi.visible:
			continue
		var box := gi.global_transform * gi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _all(node: Node, cls: String) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out


func _best_skeleton(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for n in _all(node, "Skeleton3D"):
		var s := n as Skeleton3D
		if best == null or s.get_bone_count() > best.get_bone_count():
			best = s
	return best


func _hips_index(skel: Skeleton3D) -> int:
	for want in HIPS_CANDIDATES:
		for i in skel.get_bone_count():
			if skel.get_bone_name(i).to_lower() == String(want).to_lower():
				return i
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i).to_lower()
		if n.contains("hip") or n.contains("pelvis") or n.contains("waist"):
			return i
	return -1


func _hip_name(skel: Skeleton3D, i: int) -> String:
	return "<无>" if i < 0 else skel.get_bone_name(i)
