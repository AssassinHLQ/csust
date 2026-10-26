extends SceneTree
## 判图：三种楼梯碰撞形式的侧面剖视 —— 看「倒角」到底被搭成了什么形状。
##   godot --path . --script res://scripts/_probe_stair_shapes_shot.gd -- --splat=off
## 输出：_arisu_captures/_stairs/{plain,chamfer,ramp}.png
func _initialize() -> void:
	_run.call_deferred()


const STEPS := 6          # 只搭 6 级，看得清剖面
const RISE := 0.21
const RUN := 0.35
const Z0 := -3.0
## 实验台摆在商店门前的空地上（世界 x = LAB_X）；x=0 那一带在画室609 的墙里，拍不到。
const LAB_X := 28.0


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	return m


func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material,
		basis := Basis.IDENTITY) -> void:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(basis, center)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, center)
	body.add_child(cs)
	parent.add_child(body)


func _build_plain(p: Node3D) -> void:
	var m := _mat(Color(0.75, 0.75, 0.78))
	for i in range(1, STEPS + 1):
		var top := RISE * float(i)
		_box(p, Vector3(LAB_X, top * 0.5, Z0 + RUN * float(i - 1) + RUN * 0.5),
			Vector3(1.2, top, RUN + 0.02), m)


func _build_chamfer(p: Node3D, deg: float) -> void:
	var ang := deg_to_rad(deg)
	var c := RISE / tan(ang)
	var nrm := Vector3(0.0, cos(ang), -sin(ang))
	var basis := Basis(Vector3(1.0, 0.0, 0.0), -ang)
	var slope_len := sqrt(c * c + RISE * RISE)
	var m_step := _mat(Color(0.75, 0.75, 0.78))
	var m_slope := _mat(Color(0.90, 0.35, 0.30))
	for i in range(1, STEPS + 1):
		var top := RISE * float(i)
		var z_r := Z0 + RUN * float(i - 1)
		_box(p, Vector3(LAB_X, top * 0.5, z_r + RUN * 0.5), Vector3(1.2, top, RUN + 0.02), m_step)
		var mid := Vector3(LAB_X, top - RISE * 0.5, z_r - c * 0.5)
		_box(p, mid - nrm * 0.15, Vector3(1.2, 0.30, slope_len), m_slope, basis)


func _build_ramp(p: Node3D) -> void:
	var ang := atan2(RISE, RUN)
	var nrm := Vector3(0.0, cos(ang), -sin(ang))
	var basis := Basis(Vector3(1.0, 0.0, 0.0), -ang)
	var len_z := RUN * float(STEPS)
	var rise := RISE * float(STEPS)
	var slope_len := sqrt(len_z * len_z + rise * rise)
	var mid := Vector3(LAB_X, rise * 0.5, Z0 + len_z * 0.5)
	_box(p, mid - nrm * 0.15, Vector3(1.2, 0.30, slope_len), _mat(Color(0.30, 0.55, 0.90)), basis)


func _shoot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])


func _run() -> void:
	root.size = Vector2i(900, 500)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 90:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_stairs")
	DirAccess.make_dir_recursive_absolute(out)
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)

	var holder := Node3D.new()
	game.add_child(holder)

	# 侧面剖视：相机在 +X 侧很远处，看向楼梯
	for spec in [["plain", 0.0], ["chamfer", 38.0], ["ramp", -1.0]]:
		var nm: String = spec[0]
		var deg: float = spec[1]
		for c in holder.get_children():
			c.queue_free()
		await process_frame
		if deg < 0.0:
			_build_ramp(holder)
		elif deg == 0.0:
			_build_plain(holder)
		else:
			_build_chamfer(holder, deg)
		await process_frame
		cam.global_position = Vector3(LAB_X + 5.5, 0.75, Z0 + 1.0)
		cam.look_at(Vector3(LAB_X, 0.62, Z0 + 1.0), Vector3.UP)
		await _shoot(cam, out, nm)
	print("[截图] %s" % out)
	quit(0)
