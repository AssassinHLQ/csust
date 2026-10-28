extends SceneTree
## 烘「编辑器专用」的校园低模点云预览：
##   _tools/run_probe.sh res://scripts/_bake_campus_preview.gd -- --force
## 产物：scenes/campus_preview.scn（挂在 Campus 下，坐标是 Campus 局部空间）
##
## 为什么需要：GaussianSplatNode 是运行时由 SplatScene 创建的，编辑器里没有它，
## 调碰撞时看不到校园。这里抽 ~25 万点、用 SH 直流项算颜色，存成 PRIMITIVE_POINTS
## 网格；campus_preview.gd 让它在编辑器里显示、运行时自动隐藏。
## 点云用的是 splat_node 的**局部**变换，所以跟着 Campus 节点一起动。

const OUT := "res://scenes/campus_preview.scn"
const PREVIEW_SCRIPT := "res://scripts/campus_preview.gd"
const SH_C0 := 0.28209479177387814
const TARGET_POINTS := 600000


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if FileAccess.file_exists(OUT) and not OS.get_cmdline_user_args().has("--force"):
		print("[preview] %s 已存在；覆盖请加 -- --force" % OUT)
		quit(0)
		return
	var venue := (load("res://scenes/campus_venue.tscn") as PackedScene).instantiate()
	root.add_child(venue)
	venue.set("world_scale", 75.0)
	# 必须和 next_level.tscn 里 Campus 实例的裁剪参数一致，否则预览会把离群点
	# 也算进来，包围盒歪出去上百米。
	venue.set("crop_enabled", true)
	venue.set("crop_margin", 0.5)
	venue.set("crop_max_scale", 0.5)
	venue.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(venue.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	if not bool(venue.call("is_ready")):
		print("[preview] 校园没加载完")
		quit(1)
		return
	var node := venue.get("splat_node") as Node3D
	var res = node.get("gaussian")
	var xyz: PackedVector3Array = res.get("xyz")
	var bytes: PackedByteArray = res.get("point_data_byte")
	var n := int(res.get("point_count"))
	var xf := node.transform          # 局部（Campus 空间）
	var step := maxi(1, int(round(float(n) / TARGET_POINTS)))
	print("[preview] %d 点，step=%d → 约 %d 点" % [n, step, n / step])

	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var i := 0
	while i < n:
		verts.append(xf * xyz[i])
		var off := i * 240
		var r := 0.5 + SH_C0 * bytes.decode_float(off + 12 * 4)
		var g := 0.5 + SH_C0 * bytes.decode_float(off + 13 * 4)
		var b := 0.5 + SH_C0 * bytes.decode_float(off + 14 * 4)
		cols.append(Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0),
			clampf(b, 0.0, 1.0)))
		i += step
	print("[preview] 采样完成：%d 点" % verts.size())

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 用每点 SH 直流项算出的真实颜色；disable_fog 之后远看也不会被雾洗白。
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.use_point_size = true
	mat.point_size = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	mat.disable_fog = true   # 编辑距离远时别被雾洗淡

	var mi := MeshInstance3D.new()
	mi.name = "Points"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var root_node := Node3D.new()
	root_node.name = "CampusPreview"
	var script: Variant = load(PREVIEW_SCRIPT)
	if script is GDScript:
		root_node.set_script(script)
	root_node.add_child(mi)
	mi.owner = root_node
	root.add_child(root_node)
	var ps := PackedScene.new()
	var err := ps.pack(root_node)
	if err != OK:
		print("[preview] pack 失败：%d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT)
	if err != OK:
		print("[preview] save 失败：%d" % err)
		quit(1)
		return
	print("[preview] %s ← %d 点（%.1f MB）" % [OUT, verts.size(),
		float(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(OUT)).size()) / 1048576.0])
	quit(0)
