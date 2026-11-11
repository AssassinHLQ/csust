extends SceneTree
## 量一个模型在不同「全局 LOD 阈值」下的**实绘图元数**并出图。
##
## 背景（2026-11-11，用户）：「调整角色 lod，让角色不要被 lod 影响，
## 角色面数本来就少再 lod 就糊了」。
##
## 复现条件：存档 `settings.cfg` 里 `lod_threshold_px = 8.0`（默认 1.0，滑条上限 8.0），
## 也就是**比默认早 8 倍**切到低模。角色模型全是 `meshes/generate_lods=true`，
## 所以离远了会掉到 LOD1/LOD2。
##
## 本探针把「一个模型 + 一台相机 + 一盏灯」摆成一个最小场景（不依赖关卡），
## 打印 `Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME`，并出图给人眼看。
##
## 用法（要真窗口）：
##   & <godot> --path . --position -4000,-4000 --resolution 1280x720 --windowed \
##       --audio-driver Dummy --script res://scripts/_probe_char_lod.gd -- \
##       --no-capture --model=res://models/companions/Yuzu.glb --dist=15 --px=8.0 \
##       --out=C:/.../_log/_charlod_xx.png

const OffWin := preload("res://scripts/offscreen_window.gd")

var _model := "res://models/companions/Yuzu.glb"
var _dist := 15.0
var _px := 8.0
var _out := "C:/Users/WY157/Desktop/GODOT/_arisu_learn/_log/_charlod.png"


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[clod] 缺 --no-capture，拒绝运行")
		quit(2)
		return
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--model="):
			_model = s.substr(8)
		elif s.begins_with("--dist="):
			_dist = float(s.substr(7))
		elif s.begins_with("--px="):
			_px = float(s.substr(5))
		elif s.begins_with("--out="):
			_out = s.substr(6)
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self)

	var world := Node3D.new()
	root.add_child(world)
	var ps := load(_model) as PackedScene
	if ps == null:
		push_error("[clod] 加载不了 %s" % _model)
		quit(1)
		return
	var inst := ps.instantiate()
	world.add_child(inst)

	# 环境：一盏灯 + 一点环境光，不然纯黑看不出糊不糊
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 1.0
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	sun.light_energy = 1.3
	world.add_child(sun)

	# 模型的包围盒（含骨骼网格的全局变换）
	var box := AABB()
	var first := true
	var meshes: Array = []
	_collect(inst, meshes)
	for mi in meshes:
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		var g: AABB = (mi as MeshInstance3D).global_transform * b
		if first:
			box = g
			first = false
		else:
			box = box.merge(g)
	if first:
		push_error("[clod] %s 里没有 MeshInstance3D" % _model)
		quit(1)
		return
	var center := box.position + box.size * 0.5

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = center + Vector3(0.0, box.size.y * 0.10, _dist)
	cam.look_at(center, Vector3.UP)
	cam.fov = 45.0
	cam.make_current()

	root.mesh_lod_threshold = _px
	print("[clod] 模型 %s" % _model.get_file())
	print("[clod] 包围盒 size %s｜相机距离 %.1f m｜mesh_lod_threshold = %.2f px"
		% [str(box.size.snappedf(0.01)), _dist, root.mesh_lod_threshold])
	for mi in meshes:
		var m := mi as MeshInstance3D
		print("[clod]   %s：面 %d｜lod_bias %s｜vis_end %s"
			% [m.name, m.mesh.get_surface_count() if m.mesh != null else -1,
				str(m.lod_bias), str(m.visibility_range_end)])

	var peak := 0
	for _i in 40:
		await process_frame
		peak = maxi(peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	print("[clod] 实绘图元数峰值 = %d" % peak)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(_out)
	print("[clod] 出图 → %s err=%d size=%s" % [_out, err, str(img.get_size())])
	var safe: Array = OffWin.is_safe()
	print("[clod] 窗口自检：%s" % ("OK" if bool(safe[0]) else "NG " + str(safe[1])))
	quit(0)


func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
