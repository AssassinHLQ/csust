extends SceneTree
## 游戏内探针：加载 next_level（去掉 GDGS Campus），用 GGS 光栅器 + 世界坐标 bin
## 渲染校园；固定相机在校园里，验证帧率/显存/画面。
##   _tools/run_shot.sh res://scripts/_probe_ggs_game.gd
## 出图：_arisu_captures/_ggs_game.png；加载完成后 8 s 自动退出。

const BIN := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/campus_ggs.bin"
const PlyFileScript := preload("res://addons/ggs_campus/ply_file.gd")
const Rasterizer := preload("res://addons/ggs_campus/gaussian_splatting_rasterizer.gd")

var rasterizer
var cam: Camera3D
var tex := Texture2DRD.new()
var loaded_at := 0
var last := 0
var shot_done := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1600, 900)
	# 禁掉 GDGS 的自动合成器（会和 GGS 抢相机/显存）
	var sc := root.get_node_or_null("SplatCompositor")
	if sc != null:
		sc.free()
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	# 在进树前拆掉 Campus，避免 GDGS SOG 解码（8 s / 4.9 GB）
	var campus := level.get_node_or_null("Campus")
	if campus != null:
		campus.free()
	root.add_child(level)
	for _i in 30:
		await process_frame

	# 用一台独立相机，避免被玩家相机脚本覆盖
	for c in level.find_children("*", "Camera3D", true, false):
		(c as Camera3D).current = false
	cam = Camera3D.new()
	cam.fov = 70.0
	level.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0.0, 3.0, -78.0)
	cam.look_at(Vector3(0.0, 3.0, -340.0))

	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	qm.flip_faces = true
	quad.mesh = qm
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.extra_cull_margin = 16384.0
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FileAccess.get_file_as_string("res://addons/ggs_campus/shaders/main.gdshader")
	mat.shader = sh
	mat.set_shader_parameter("render_texture", tex)
	quad.material_override = mat
	level.add_child(quad)

	var f := FileAccess.open(BIN, FileAccess.READ)
	if f == null:
		print("[ggsgame] 打不开 bin")
		quit(1)
		return
	var count := int(f.get_length() / 240)
	f.close()
	print("[ggsgame] bin %d 点" % count)
	var ply = PlyFileScript.new()
	ply.size = count
	print("[ggsgame] 创建光栅器...")
	rasterizer = Rasterizer.new(ply, root.size, tex, cam)
	rasterizer.bin_path = BIN
	rasterizer.model_scale[0] = 1.0

func _process(_dt: float) -> bool:
	if rasterizer == null:
		return false
	rasterizer.update_camera_matrices()
	RenderingServer.call_on_render_thread(rasterizer.rasterize)
	if loaded_at == 0:
		if rasterizer.is_loaded:
			loaded_at = Time.get_ticks_msec()
			print("[ggsgame] 加载完成")
		elif Time.get_ticks_msec() - last > 3000:
			last = Time.get_ticks_msec()
			print("[ggsgame] 加载中 %d" % rasterizer.num_splats_loaded[0])
		return false
	var now := Time.get_ticks_msec()
	if now - last > 2000:
		last = now
		var vram := 0.0
		if rasterizer.context:
			vram = float(rasterizer.context.device.get_memory_usage(RenderingDevice.MEMORY_TOTAL)) / 1048576.0
		print("[ggsgame] fps=%d vram=%.0fMB" % [Engine.get_frames_per_second(), vram])
	if not shot_done and now - loaded_at > 2500:
		shot_done = true
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png("C:/Users/WY157/Desktop/GODOT/_arisu_captures/_ggs_game.png")
		print("[ggsgame] 截图")
	if now - loaded_at > 8000:
		quit()
		return true
	return false
