extends SceneTree
## 探针：同一个相机、同一帧，分别用 **Raster** 与 **Compute** 后端渲染，出图对比。
##
## 为什么要比这个：`project.godot` 里写死了 `gdgs/rendering/backend="Raster"`，
## 但插件自己的 `Auto` 在 Forward+ 上是**优先 Compute** 的。两条管线的合成空间不同：
##
##   Compute（runtime/compositor/shaders/gaussian_composite.glsl）
##       在**离屏缓冲区里按 sRGB(γ) 空间累加**，最后一次性 srgb_to_linear 再叠到场景上：
##           gsplat_straight = unpremultiply(color, alpha)
##           composited = srgb_to_linear(gsplat_straight) * alpha + scene * (1 - alpha)
##       这是参考实现（3DGS / SuperSplat）的做法 —— 训练时就是在 γ 空间累加的。
##
##   Raster（runtime/render/raster/materials/gaussian_raster.gdshader）
##       在 fragment() 里**逐高斯**先 srgb_to_linear，再走 Godot 的标准透明混合 ——
##       于是所有重叠都在**线性空间**里累加。γ→线性的凸性会把多层叠加的结果整体抬亮、
##       压平暗部对比，视觉上就是"发灰、发糊"。
##
## 另外排序也不同：Compute 是 GPU 基数排序（逐高斯精确），Raster 是组宽 32 的近似。
##
## 用法（必须分两次跑，因为后端选择是**会话内一次性**的）：
##   godot --path <工程> --script res://scripts/_probe_splat_backend.gd -- --backend=Raster
##   godot --path <工程> --script res://scripts/_probe_splat_backend.gd -- --backend=Compute
## 输出：…/_arisu_captures/_backend_ab/<backend>.png   + stdout 的帧率与相机位姿

const OUT_REL := "..\\_arisu_captures\\_backend_ab"
const WARMUP_FRAMES := 12
const MEASURE_FRAMES := 40
const COMPOSITOR_SCRIPT := "res://addons/gdgs/runtime/compositor/gaussian_compositor_effect.gd"
## 写死的取景 = 出生点正视角（实测玩家相机的收敛位姿）。
## 两次跑必须逐位一致，所以不能从玩家相机实时复制。
const CAM_POS := Vector3(-0.42, 1.788, 10.197)
const CAM_ROT_DEG := Vector3(-2.292, 0.0, 0.0)

var _backend := "Raster"
var _out_dir := ""
## 可选：覆盖 CompositorEffect 的 depth_bias（每帧取一次，直接改属性即生效）。
## 设成 1e6 就等于**关掉深度剔除**，用来判断地板上的黑洞是它造成的还是数据本身。
var _bias := -1.0
## 文件后缀，便于同一次后端跑多个变体。
var _tag := ""
## 是否藏掉游戏自带方盒地板的视觉网格（碰撞保留）。
var _hide_floor := false


func _initialize() -> void:
	# ⚠️ 必须在任何 GaussianSplatNode 出生**之前**写设置：后端选择是会话内
	#    一次性解析并静态缓存的（见 gaussian_backend_selector.gd 的头注释）。
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--backend="):
			_backend = a.substr(10)
		elif a.begins_with("--bias="):
			_bias = float(a.substr(7))
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a == "--hide-floor":
			_hide_floor = true
	ProjectSettings.set_setting("gdgs/rendering/backend", _backend)
	print("[ab] 本次会话强制后端 = %s  bias = %s  tag = %s" % [
		_backend, "默认" if _bias < 0.0 else "%.3f" % _bias, _tag])
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(2560, 1400)
	await process_frame
	await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	_out_dir = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_backend_ab")
	DirAccess.make_dir_recursive_absolute(_out_dir)

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)

	var room: Node = game.get_node_or_null("Room609")
	var deadline := Time.get_ticks_msec() + 200000
	while Time.get_ticks_msec() < deadline and room.get("splat_node") == null:
		await process_frame
	if room == null or room.get("splat_node") == null:
		push_error("画室609 没加载出来")
		quit(1)
		return

	var hud: Node = game.get_node_or_null("HUD")
	if hud != null:
		(hud as CanvasLayer).visible = false

	# 排序表要落地（Raster 第一帧用的是资源顺序；Compute 首帧要建 GPU 状态）。
	for i in 60:
		await process_frame

	# ⚠️ 取景必须**写死**。第一版是复制玩家相机的 global_transform，结果两次跑的
	#    相机差了 32° 偏航 / 0.7 m 高度（玩家相机是弹簧跟随 + 鼠标视角，同帧数下
	#    只因真实耗时不同就走了不同的相位），比出来的图根本不同一个取景。
	#    下面的位姿就是出生点的正视角（world_scale=4.25 / yaw=248.6 那套摆放）。
	var cam := Camera3D.new()
	cam.name = "ABProbeCam"
	cam.fov = 62.0
	cam.near = 0.05
	cam.far = 500.0
	root.add_child(cam)
	cam.global_position = CAM_POS
	cam.global_rotation_degrees = CAM_ROT_DEG
	cam.make_current()

	# 冻住会动的东西：两次跑的差异必须**只**来自后端。
	for c in game.get_children():
		var n := String(c.name)
		if n.begins_with("Companion") or n.begins_with("Target") \
				or n.begins_with("Boss") or n == "Player":
			(c as Node).process_mode = Node.PROCESS_MODE_DISABLED

	# 可选：藏掉游戏自带的方盒地板**视觉网格**（碰撞保留）。
	# 它的顶面正好在 y=0，和泼溅扫描出来的地板（y≈0.03）打架 —— Compute 的
	# 深度剔除会把它当成"场景不透明几何在前"，于是泼溅地板被剔掉、露出深色方盒，
	# 地板上就是一片黑洞。藏掉网格才能真正判断。
	if _hide_floor:
		var floor := game.get_node_or_null("Floor")
		var mi: Node = floor.get_node_or_null("Mesh") if floor != null else null
		if mi != null:
			(mi as MeshInstance3D).visible = false
			print("[ab] 已隐藏 Floor/Mesh（Floor/Collision 保留）")
		else:
			push_warning("找不到 Floor/Mesh")

	var vp := root
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = 1.0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(2560, 1334)
	for i in 20:
		await process_frame

	if _backend == "Compute":
		# autoload `SplatCompositor` 现在会自动给当前相机挂上，探针只做检查和覆盖偏置。
		if cam.compositor != null and not cam.compositor.compositor_effects.is_empty():
			var fx: Variant = cam.compositor.compositor_effects[0]
			if _bias >= 0.0:
				fx.depth_bias = _bias
			print("[ab] 相机已有 Compositor（autoload 挂的）：depth_bias=%.4f alpha_cutoff=%.4f" % [
				float(fx.depth_bias), float(fx.alpha_cutoff)])
		else:
			print("[ab] 相机上没有 Compositor，探针自己挂一个")
			_attach_compositor(cam)
	print("[ab] 相机 pos %s  rot %s  fov %.1f" % [
		str(cam.global_position.snappedf(0.001)),
		str(cam.global_rotation_degrees.snappedf(0.001)), cam.fov])
	print("[ab] scaling_3d_scale = %.3f  msaa = %d  渲染尺寸 %s" % [
		vp.scaling_3d_scale, vp.msaa_3d, str(root.size)])

	for i in WARMUP_FRAMES:
		await process_frame
	var t0 := Time.get_ticks_usec()
	for i in MEASURE_FRAMES:
		await RenderingServer.frame_post_draw
	var seconds := (Time.get_ticks_usec() - t0) / 1000000.0
	print("[ab] 帧率 %.1f fps（%d 帧 %.2f s）" % [
		MEASURE_FRAMES / maxf(seconds, 1e-6), MEASURE_FRAMES, seconds])

	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var stem := _backend.to_lower() + ("" if _tag == "" else "_" + _tag)
	var path := _out_dir.path_join("%s.png" % stem)
	img.save_png(path)
	print("[ab] 出图 %s" % path)
	quit(0)


## Compute 后端需要相机上挂一个 Compositor，里面放 GaussianCompositorEffect。
## Raster 后端走标准网格管线，不需要 —— 这正是「两条管线」的接线差别。
func _attach_compositor(cam: Camera3D) -> void:
	var script: Variant = load(COMPOSITOR_SCRIPT)
	if script == null or not (script is GDScript) or not (script as GDScript).can_instantiate():
		push_error("加载不了 gaussian_compositor_effect.gd")
		return
	var fx: Variant = (script as GDScript).new()
	if _bias >= 0.0:
		fx.depth_bias = _bias
	var effects: Array[CompositorEffect] = [fx]
	var comp := Compositor.new()
	comp.compositor_effects = effects
	cam.compositor = comp
	print("[ab] 已挂 Compositor + GaussianCompositorEffect（effect_callback_type=%d，depth_bias=%.4f，alpha_cutoff=%.4f，depth_test_min_alpha=%.4f）" % [
		int(fx.effect_callback_type), float(fx.depth_bias),
		float(fx.alpha_cutoff), float(fx.depth_test_min_alpha)])
