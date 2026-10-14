extends SceneTree
## 贴图排列组合：3 张贴图 ↔ 3 个材质槽，共 6 种，各渲一张对比。
##
## 材质槽（FBX 里的原始名字）：
##   材质         → 身体（4 个 Tyrannosaurus4LOW* 网格共用）
##   2501_other  → 胸牌
##   材质.001     → 球（Esfera）
## 3 张贴图：other_BaseColor.png / 材质.001 Base Color.png / 身1.png
##
## 这次**不隐藏任何网格**：挂件按真实渲染尺度是合理的（光环在头顶 5.59 m 处）。
##
## 用法（要真渲染）：godot --path <工程> --script res://scripts/_probe_boss_texperm.gd

const SCENE := "res://models/boss/优香霸王龙.fbx"
const HEIGHT := 4.5
const OUT_SUB := "_boss"

## 槽位顺序：身体 / 胸牌 / 球
const SLOTS := ["材质", "2501_other", "材质.001"]
const TEXS := {
	"OTHER": "res://models/boss/tex/body_basecolor.png",
	"MAT001": "res://models/boss/tex/mat001_basecolor.png",
	"SHEN1": "res://models/boss/tex/shen1.png",
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(760, 620)
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	# 收集 3 个槽位的材质对象
	var by_name := {}
	for m in _all(scene, "MeshInstance3D"):
		var am := (m as MeshInstance3D).mesh as ArrayMesh
		if am == null:
			continue
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				by_name[sm.resource_name] = sm
	var slots: Array[StandardMaterial3D] = []
	for n in SLOTS:
		if not by_name.has(n):
			push_error("找不到材质槽 %s" % n)
			quit(1)
			return
		slots.append(by_name[n])
	print("槽位：身体=%s  胸牌=%s  球=%s" % [SLOTS[0], SLOTS[1], SLOTS[2]])

	# 归一化
	var skel := _first(scene, "Skeleton3D") as Skeleton3D
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in skel.get_bone_count():
		var p: Vector3 = skel.global_transform * skel.get_bone_global_pose(i).origin
		lo = lo.min(p)
		hi = hi.max(p)
	var box := AABB(lo, hi - lo)
	var s := HEIGHT / box.size.y
	scene.scale = Vector3(s, s, s)
	scene.position = Vector3(-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)
	await process_frame

	# 环境
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.21, 0.23, 0.28)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.68, 0.71, 0.82)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -125, 0)
	sun.light_energy = 1.05
	root.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.05
	cam.far = 500.0
	# 取景：头/胸附近（光环在 y≈5.6、胸牌/球在 y≈3.3~4.7、z≈2.6~4.5）
	cam.global_position = Vector3(5.0, 3.9, 7.6)
	root.add_child(cam)
	cam.make_current()
	cam.look_at(Vector3(0.0, 3.3, 2.4), Vector3.UP)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(out)

	var names: Array = TEXS.keys()
	var index := 0
	for a in names:
		for b in names:
			for c in names:
				if a == b or b == c or a == c:
					continue
				index += 1
				var assign := [a, b, c]
				for i in 3:
					var sm := slots[i]
					sm.albedo_texture = load(TEXS[assign[i]])
					sm.albedo_color = Color.WHITE
				await process_frame
				await process_frame
				var file := "90_p%d_body-%s_plate-%s_sphere-%s.png" % [index, a, b, c]
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out.path_join(file))
				print("  组合 %d：身体=%s  胸牌=%s  球=%s  → %s" % [index, a, b, c, file])

	print("[texperm] 输出目录：%s" % out)
	quit(0)


func _all(node: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		if n.is_class(cls):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _first(node: Node, cls: String) -> Node:
	var r := _all(node, cls)
	return r[0] if not r.is_empty() else null
