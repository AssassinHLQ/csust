extends SceneTree
## 拍电竞房室内（看灯够不够亮）。
##
##   godot --path . --windowed --script res://scripts/_probe_esports_light.gd
##
## ⚠️ 相机位置**照抄** `scripts/_probe_esports_new_glb.gd`（那个已知能拍对室内）：
##    室内在 **-Z** 侧，相机放 `c.z - s.z * 0.42` 往里看。
##    本喵前两版自己猜「门口在 +Z / -Z」都拍到墙外面了，别再猜。
##
## 输出：res://_arisu_captures/_esports_light/
##   11_inside.png   室内（主视角）
##   10_outside_nz.png / 10b_outside_pz.png   屋���
##   corner.png      屋内角落

const SCENE := "res://scenes/esports_room.tscn"
const OUT := "res://_arisu_captures/_esports_light"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	# 自建环境 + 太阳（照抄 _probe_esports_new_glb.gd）
	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.85)
	env.ambient_light_energy = 1.0
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_energy = 1.0
	world.add_child(sun)

	var room := (load(SCENE) as PackedScene).instantiate() as Node3D
	world.add_child(room)
	await _wait(60)

	# 量包围盒
	var box := AABB()
	var first := true
	for m in room.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	var c := box.position + box.size * 0.5
	var s := box.size
	print("[esp-light] 包围盒 pos=%s size=%s" % [str(c), str(s)])

	var cam := Camera3D.new()
	cam.far = 200.0
	cam.near = 0.05
	world.add_child(cam)
	cam.current = true

	# 照抄 _probe_esports_new_glb.gd 的相机位置
	await _shot(cam, Vector3(c.x, 1.6, c.z - s.z * 0.42), Vector3(c.x, 1.35, c.z), "11_inside.png", 62.0)
	await _shot(cam, Vector3(c.x, 1.7, c.z - s.z * 1.1), Vector3(c.x, 1.4, c.z), "10_outside_nz.png", 60.0)
	await _shot(cam, Vector3(c.x, 1.7, c.z + s.z * 1.1), Vector3(c.x, 1.4, c.z), "10b_outside_pz.png", 60.0)
	# 屋里往里深处看
	await _shot(cam, Vector3(c.x, 1.6, c.z - s.z * 0.30), Vector3(c.x, 1.3, c.z - s.z * 0.60), "deep.png", 62.0)
	# 屋内一角
	await _shot(cam, Vector3(c.x - 3.8, 2.0, c.z - s.z * 0.34), Vector3(c.x + 1.0, 1.0, c.z + s.z * 0.10), "corner.png", 65.0)

	var lights := 0
	var tris := 0
	for n in room.find_children("*", "Light3D", true, false):
		lights += 1
	for n in room.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh is ArrayMesh:
			for si in (mi.mesh as ArrayMesh).get_surface_count():
				var arr := (mi.mesh as ArrayMesh).surface_get_arrays(si)
				if arr.size() > Mesh.ARRAY_INDEX:
					var idx := arr[Mesh.ARRAY_INDEX] as PackedInt32Array
					tris += idx.size() / 3
	print("[esp-light] 灯 %d 盏、三角面 %d" % [lights, tris])
	quit(0)


func _shot(cam: Camera3D, pos: Vector3, target: Vector3, name: String, fov := 60.0) -> void:
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	cam.fov = fov
	await _wait(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "/" + name))
	print("[esp-light] 拍到 %s" % name)
