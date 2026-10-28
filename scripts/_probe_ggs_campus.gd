extends SceneTree
## 4.7.1 移植验证：用 addons/ggs_campus 的 GPU 光栅器直接渲染校园 PLY。
##   _tools/run_shot.sh res://scripts/_probe_ggs_campus.gd -- --ms=3
## 出图：_arisu_captures/_ggs_471_ms3.png；加载后 10 s 自动退出。

const PLY := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/campus_3dgs.ply"
const PlyFileScript := preload("res://addons/ggs_campus/ply_file.gd")
const Rasterizer := preload("res://addons/ggs_campus/gaussian_splatting_rasterizer.gd")

var rasterizer
var cam: Camera3D
var tex := Texture2DRD.new()
var loaded_at := 0
var last := 0
var shot := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1600, 900)
	var sc := root.get_node_or_null("SplatCompositor")
	if sc != null:
		sc.queue_free()
	cam = Camera3D.new()
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	qm.flip_faces = true
	quad.mesh = qm
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FileAccess.get_file_as_string("res://addons/ggs_campus/shaders/main.gdshader")
	mat.shader = sh
	mat.set_shader_parameter("render_texture", tex)
	quad.material_override = mat
	root.add_child(quad)

	print("[ggs471] 解析 PLY...")
	var t0 := Time.get_ticks_msec()
	var ply = PlyFileScript.new(PLY)
	print("[ggs471] %d 点，%d ms" % [ply.size, Time.get_ticks_msec() - t0])
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var step := maxi(1, ply.size / 200000)
	var i := 0
	while i < ply.size:
		var b := i * 62
		var v := Vector3(ply.vertices[b], ply.vertices[b + 1], ply.vertices[b + 2])
		lo = lo.min(v)
		hi = hi.max(v)
		i += step
	var c := (lo + hi) * 0.5
	var ext := hi - lo
	print("[ggs471] 盒 %s..%s 中心 %s" % [str(lo.snappedf(0.01)), str(hi.snappedf(0.01)), str(c.snappedf(0.01))])

	var ms := 3.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ms="):
			ms = float(a.substr(5))
	rasterizer = Rasterizer.new(ply, root.size, tex, cam)
	rasterizer.model_scale[0] = ms
	cam.global_position = (c + Vector3(ext.x, ext.y * 1.2, ext.z) * 0.65) * ms
	cam.look_at(c * ms)
	print("[ggs471] ms=%.0f 相机 %s" % [ms, str(cam.global_position.snappedf(0.01))])
	rasterizer.loaded.connect(func():
		loaded_at = Time.get_ticks_msec()
		print("[ggs471] 加载完成"))

func _process(_dt: float) -> bool:
	if rasterizer == null:
		return false
	rasterizer.update_camera_matrices()
	RenderingServer.call_on_render_thread(rasterizer.rasterize)
	if loaded_at == 0 and rasterizer.is_loaded:
		loaded_at = Time.get_ticks_msec()
		print("[ggs471] 加载完成（同步）")
	if loaded_at == 0:
		if Time.get_ticks_msec() - last > 3000:
			last = Time.get_ticks_msec()
			print("[ggs471] 加载中 %d" % rasterizer.num_splats_loaded[0])
		return false
	var now := Time.get_ticks_msec()
	if now - last > 2000:
		last = now
		var vram := 0.0
		if rasterizer.context:
			vram = float(rasterizer.context.device.get_memory_usage(RenderingDevice.MEMORY_TOTAL)) / 1048576.0
		print("[ggs471] fps=%d vram=%.0fMB" % [Engine.get_frames_per_second(), vram])
	if now - loaded_at > 10000:
		quit()
		return true
	return false
