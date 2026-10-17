extends SceneTree
## 探针：**右眼前面那层白，到底是头发还是眼睑** —— 逐层藏掉再看。
##
## 已经排除的：骨骼旋转（左右幅度一样）、三种镜像公式（渲图完全一样）、
## 蒙皮权重（左右结构、质心差 1~2 mm）。
## 剩下的嫌疑是**叠在眼睛前面的几何**：头发 / 眉毛 / 脸皮。
##
## 三格对照（正交正视图，t=0.93）：
##   ① 原样          ② 藏掉 Hair 面        ③ 再藏掉 Eyebrow 面
##
## 输出 `_arisu_captures/_eyelayers/montage.png`
##
## 用法：godot --path <工程> --script res://scripts/_probe_eye_layers.gd

const MODEL := "res://models/Arisu_ext.glb"
const BODY := "Aris_Original_Body_001"
const CLIP := "Normal_Idle"
const T := 0.93
const OUT_SUB := "_eyelayers"
const CELL := Vector2i(380, 300)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = CELL
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	for _i in 4:
		await process_frame
	var sk := _find_skel(inst)
	var ap := _find_anim(inst)
	var body := _find_mesh(inst, BODY)
	if sk == null or ap == null or body == null:
		print("!! 缺 Skeleton3D / AnimationPlayer / Body")
		quit(1)
		return

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.80, 0.82, 0.86)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.7
	env.environment = e
	root.add_child(env)

	ap.play(CLIP)
	ap.seek(T, true)
	for _i in 3:
		await process_frame

	var pL := _bone_world(sk, "eye_L_1")
	var pR := _bone_world(sk, "eye_R_1")
	var head := _bone_world(sk, "Bip001 Head")
	var mid := (pL + pR) * 0.5
	var key := DirectionalLight3D.new()
	key.global_transform = Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP),
		mid + Vector3(0, 0, 2.0))
	key.light_energy = 1.2
	key.shadow_enabled = false
	root.add_child(key)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.26          ## 正交高度：正好装下两只眼 + 一点鼻梁
	cam.near = 0.01
	cam.far = 50.0
	root.add_child(cam)
	cam.make_current()
	cam.global_position = mid + Vector3(0, 0, 2.0)
	cam.look_at(mid, Vector3.UP)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(out)
	var sheet := Image.create(CELL.x * 3, CELL.y, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.12))

	var cases := [
		["all", []],
		["no_hair", ["Hair"]],
		["no_hair_brow", ["Hair", "Eyebrow"]],
	]
	for i in cases.size():
		var tag := String(cases[i][0])
		var drop: Array = cases[i][1]
		_strip(body, drop)
		await _wait(4)
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png(out.path_join("%s.png" % tag))
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
		print("  [img] %s → %s" % [tag, out.path_join("%s.png" % tag)])
	sheet.save_png(out.path_join("montage.png"))
	print("[layers] 拼图 %s（左→右：原样 / 藏头发 / 再藏眉毛）" % out.path_join("montage.png"))
	quit(0)


## 重建 Body 网格，丢掉材质名里带 `drop` 关键字的面。
## ⚠️ Body 没有形态键（实测 blend=0），所以重建是安全的 —— 嘴那 10 块千万不要这么干。
func _strip(body: MeshInstance3D, drop: Array) -> void:
	if drop.is_empty():
		return
	var m := body.mesh as ArrayMesh
	if m == null:
		return
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		var name := "" if mat == null else mat.resource_name
		var skip := false
		for d in drop:
			if name.contains(String(d)):
				skip = true
		if skip:
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(s))
		out.surface_set_material(out.get_surface_count() - 1, mat)
	body.mesh = out


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _bone_world(sk: Skeleton3D, bone: String) -> Vector3:
	var i := sk.find_bone(bone)
	if i < 0:
		for b in sk.get_bone_count():
			if String(sk.get_bone_name(b)).to_lower().contains(bone.to_lower()):
				i = b
				break
	if i < 0:
		return Vector3.INF
	return sk.global_transform * sk.get_bone_global_pose(i).origin


func _find_mesh(n: Node, name_: String) -> MeshInstance3D:
	if n is MeshInstance3D and String(n.name) == name_:
		return n as MeshInstance3D
	for c in n.get_children():
		var r := _find_mesh(c, name_)
		if r != null:
			return r
	return null


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null
