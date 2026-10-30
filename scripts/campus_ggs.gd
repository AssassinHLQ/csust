extends Node3D
## GGS 校园：GGS 渲染到纹理，全屏 quad 把「校园 + 同款全景天空」画在场景背景上；
## 大厅/玩家/广场按深度画在前面。没有 Compositor，所以保持 70+ fps。
##
## 2026-10-30 起**默认启用**（打包后也是这套），要回退 GDGS Compute：
##   -- --ggs-campus=off   或   -- --no-ggs-campus
## 1.4 GB 的 packed bin 现在放在项目里（res://campus_ggs.bin），导出才会带上；
## 项目里没有时退回开发机上的老绝对路径。

const BIN := "res://campus_ggs.bin"
const BIN_DEV := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/campus_ggs.bin"
const PlyFileScript := preload("res://addons/ggs_campus/ply_file.gd")
const Rasterizer := preload("res://addons/ggs_campus/gaussian_splatting_rasterizer.gd")

var rasterizer
var cam: Camera3D
var player: Node3D
var quad: MeshInstance3D
var tex := Texture2DRD.new()
var panorama: Texture2D
var _ready_done := false
var _gdgs_sc: Node
var _overlay: CanvasLayer
var _overlay_label: Label
var _total := 0
var _active := false
var _want_size := Vector2i.ZERO
## 泼溅光栅化纹理的最大宽度（可用 `--ggs-max-w=1600` 改）
var max_render_w := 1920.0
var _bin_path := BIN

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--ggs-campus=off" or a == "--no-ggs-campus":
			set_process(false)
			return
		if a.begins_with("--ggs-max-w="):
			max_render_w = maxf(640.0, float(a.substr(12)))
	# headless（探针/自检）没有渲染设备，GGS 跑不起来，也别去读 1.4 GB 的 bin
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	if not FileAccess.file_exists(BIN) and FileAccess.file_exists(BIN_DEV):
		_bin_path = BIN_DEV
		push_warning("[campus_ggs] 项目里没有 campus_ggs.bin，退回开发机路径")
	# 两处都没有就别硬撑：不碰 GDGS，让老泼溅照常工作（否则校园会整片消失）
	if not FileAccess.file_exists(_bin_path):
		push_error("[campus_ggs] 找不到 %s，回退 GDGS 泼溅" % _bin_path)
		set_process(false)
		return
	var level := get_parent()
	_gdgs_sc = get_node_or_null("/root/SplatCompositor")
	if _gdgs_sc != null:
		_gdgs_sc.set_process(false)
	var campus := level.get_node_or_null("Campus")
	if campus != null:
		campus.set("auto_start", false)
		campus.set_process(false)
		# auto_start 是在子节点 _ready 里判的，这里已经晚了：那条「等 8 s 再解码」
		# 的协程已经在跑。直接释放 GDGS 那份校园，省 16 s 解码 + 一块显存，
		# 也避免两套渲染器同时用 RenderingDevice 打架（实测掉到 23 fps）。
		campus.queue_free()
	player = level.get_node_or_null("Player") as Node3D
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null and we.environment.sky != null:
		var mat = we.environment.sky.sky_material
		if mat != null and mat is PanoramaSkyMaterial:
			panorama = (mat as PanoramaSkyMaterial).panorama
	if panorama == null:
		panorama = load("res://assets/sky/sky_pink.jpg")
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)
	_overlay_label = Label.new()
	_overlay_label.text = "校园渲染器加载中..."
	_overlay_label.add_theme_font_size_override("font_size", 30)
	_overlay_label.position = Vector2(80, 80)
	_overlay.add_child(_overlay_label)
	set_process(true)

func _exit_tree() -> void:
	if _gdgs_sc != null and is_instance_valid(_gdgs_sc):
		_gdgs_sc.set_process(true)

func _make_bundle() -> bool:
	cam = get_viewport().get_camera_3d()
	if cam == null:
		return false
	# 不要 Compositor：GGS 走全屏 quad，Compositor 会把光栅器拖到个位数帧率。
	if cam.compositor != null:
		cam.compositor = null
	var f := FileAccess.open(_bin_path, FileAccess.READ)
	if f == null:
		push_error("[campus_ggs] 打不开 bin: %s" % _bin_path)
		return false
	var count := int(f.get_length() / 240)
	_total = count
	f.close()
	var ply = PlyFileScript.new()
	ply.size = count
	rasterizer = Rasterizer.new(ply, get_viewport().get_size(), tex, cam)
	rasterizer.bin_path = _bin_path
	rasterizer.model_scale[0] = 1.0

	_ready_done = true
	return true

func _make_quad() -> void:
	quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	qm.flip_faces = true
	quad.mesh = qm
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.extra_cull_margin = 16384.0
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FileAccess.get_file_as_string("res://addons/ggs_campus/shaders/main_sky.gdshader")
	sm.shader = sh
	sm.set_shader_parameter("render_texture", tex)
	sm.set_shader_parameter("panorama", panorama)
	quad.material_override = sm
	add_child(quad)
	quad.visible = false
	print("[campus_ggs] %d 点，quad + 天空已就绪" % _total)
	quad.visible = false

func _process(_dt: float) -> void:
	if not _ready_done and not _make_bundle():
		return
	if cam == null or not is_instance_valid(cam):
		_ready_done = false
		return
	if cam.compositor != null:
		cam.compositor = null
	# 4K 最大化窗口会按 3504×2049 光栅化，实测只有 28 fps。泼溅纹理封顶 1920 宽，
	# 剩下的交给全屏 quad 线性放大（3× 的泼溅本来就糊，肉眼几乎看不出差别）。
	var vs: Vector2i = get_viewport().get_size()
	if _want_size != vs:
		_want_size = vs
		var sc := minf(1.0, max_render_w / maxf(float(vs.x), 1.0))
		rasterizer.render_scale = [sc]
		rasterizer.texture_size = vs
	rasterizer.update_camera_matrices()
	if rasterizer.is_loaded:
		RenderingServer.call_on_render_thread(rasterizer.rasterize)
	else:
		RenderingServer.call_on_render_thread(rasterizer.pump_load)
	# ⚠️ 窗口尺寸一变，rasterizer 会**新建**一个 Texture2DRD（旧 RID 被释放），
	#    我们手里这个 tex 必须跟着换，否则 quad 指着已释放的贴图：
	#    校园整片不画，还会每帧刷 "Uniforms supplied for set (3)"。
	if rasterizer.render_texture != null 			and tex.texture_rd_rid != rasterizer.render_texture.texture_rd_rid:
		tex.texture_rd_rid = rasterizer.render_texture.texture_rd_rid
	if quad == null and tex.texture_rd_rid.is_valid() 			and panorama != null and panorama.get_rid().is_valid():
		_make_quad()
	if _overlay != null and _overlay.visible:
		var loaded := int(rasterizer.num_splats_loaded[0])
		_overlay_label.text = "校园渲染器加载中... %d%%" % (0 if _total == 0 else int(100.0 * loaded / _total))
		if rasterizer.is_loaded:
			_overlay.visible = false
	_active = player != null and player.global_position.z < -74.0 and rasterizer.is_loaded
	if quad != null:
		quad.visible = _active
