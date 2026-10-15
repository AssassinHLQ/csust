extends SceneTree
## 探针：「网页上看很清晰，进游戏糊一大截」到底损失在哪一步。
##
## 做法：加载真正的 `game.tscn`（画室609，277 万点），**不动相机**（就用玩家自己的
## Camera3D，所以取景和玩家截图一致），把 Boss/同伴/靶子冻住、藏掉 HUD，然后在
## **同一视角**下依次改设置渲四张图：
##
##   01_current      游戏当前状态（含 _fit_render_scale 算出来的 scaling_3d_scale）
##   02_native       只把 3D 渲染分辨率拉回 1.0（其余不动）
##   03_native_lin   再关掉 ACES 色调映射 / 辉光 / SSAO / 雾 / 调色
##   04_native_lin_nomsaa  再把 MSAA 也关掉（把省下的带宽全给分辨率）
##
## 每张图打印平均 fps，所以能同时看出「画质」和「代价」。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_splat_quality.gd
## 输出：…/_arisu_captures/_quality/*.png

const OUT_REL := "..\\_arisu_captures\\_quality"
const SHOT_FRAMES := 20
const WARMUP_FRAMES := 8

var _out_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# ⚠️ 复现玩家那台机器：2560×1440 屏幕 + 最大化窗口（标题栏吃掉约 40 px）。
	root.size = Vector2i(2560, 1400)
	await process_frame
	await process_frame

	_out_dir = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_quality")
	DirAccess.make_dir_recursive_absolute(_out_dir)

	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		push_error("打不开 game.tscn")
		quit(1)
		return
	var game: Node = packed.instantiate()
	root.add_child(game)

	# 等画室 609 解码完（cached 模式约 2 s；首跑约 21 s）。
	var room: Node = game.get_node_or_null("Room609")
	var t0 := Time.get_ticks_msec()
	var deadline := t0 + 200000
	while Time.get_ticks_msec() < deadline:
		if room != null and room.get("splat_node") != null:
			break
		await process_frame
	var splat_node: Node = room.get("splat_node") if room != null else null
	if splat_node == null:
		push_error("画室609 没加载出来（点数为 0 或解码失败）")
		quit(1)
		return
	print("[quality] 画室609 就绪：%d 点，等了 %.1f s" % [
		int(room.get("point_count")), (Time.get_ticks_msec() - t0) / 1000.0])

	# 冻住会动的东西，藏掉 HUD —— 四张图必须只有「设置」这一个变量。
	for c in game.get_children():
		var n := String(c.name)
		if n.begins_with("Companion") or n.begins_with("Target") or n.begins_with("Boss"):
			(c as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var hud: Node = game.get_node_or_null("HUD")
	if hud != null:
		(hud as CanvasLayer).visible = false

	# 等排序表落地（第一帧用的是资源顺序，不是排序结果）。
	for i in 30:
		await process_frame

	_dump_state(game, splat_node)

	var cam := root.get_camera_3d()
	if cam == null:
		push_warning("视口没有当前相机，自己去房间中央架一个")
		cam = Camera3D.new()
		cam.fov = 70.0
		cam.near = 0.05
		root.add_child(cam)
		var box: AABB = room.call("content_world_aabb")
		var c := box.position + box.size * 0.5
		cam.global_position = c + Vector3(0.0, 1.6 - box.size.y * 0.5, box.size.z * 0.42)
		cam.look_at(c + Vector3(0.0, 1.2 - box.size.y * 0.5, -box.size.z * 0.5), Vector3.UP)
		cam.make_current()
	print("[quality] 相机 pos %s  rot %s  fov %.1f" % [
		str(cam.global_position.snappedf(0.01)),
		str(cam.global_rotation_degrees.snappedf(0.1)), cam.fov])

	var vp := root
	var we: WorldEnvironment = game.get_node_or_null("WorldEnvironment")
	var env: Environment = we.environment if we != null else null

	# ---- 01 游戏当前状态 ----------------------------------------------------
	var current_scale := vp.scaling_3d_scale
	await _shot("01_current", "游戏当前（scale=%.3f, %s, MSAA %s）" % [
		current_scale, _env_tonemap_name(env), _enum_name("Viewport", "MSAA", vp.msaa_3d)])

	# ---- 02 只把 3D 分辨率拉回原生 -------------------------------------------
	vp.scaling_3d_scale = 1.0
	await _shot("02_native", "仅 scaling_3d_scale=1.0（%s, MSAA %s）" % [
		_env_tonemap_name(env), _enum_name("Viewport", "MSAA", vp.msaa_3d)])

	# ---- 03 再关掉后处理 -----------------------------------------------------
	_apply_env(env, Environment.TONE_MAPPER_LINEAR, false, false, false, false)
	await _shot("03_native_lin", "再关 ACES/辉光/SSAO/雾/调色（%s, MSAA %s）" % [
		_env_tonemap_name(env), _enum_name("Viewport", "MSAA", vp.msaa_3d)])

	# ---- 04 再把 MSAA 关掉 ---------------------------------------------------
	vp.msaa_3d = Viewport.MSAA_DISABLED
	await _shot("04_native_lin_nomsaa", "再关 MSAA（%s, MSAA %s）" % [
		_env_tonemap_name(env), _enum_name("Viewport", "MSAA", vp.msaa_3d)])

	# ---- 05 保留 ACES/辉光，只关 SSAO（拆开看到底是谁贵）----------------------
	_apply_env(env, Environment.TONE_MAPPER_ACES, true, false, true, true)
	await _shot("05_native_nossao", "原生 + ACES + 辉光，只关 SSAO")

	# ---- 06 再关辉光 --------------------------------------------------------
	_apply_env(env, Environment.TONE_MAPPER_ACES, false, false, true, true)
	await _shot("06_native_nossao_noglow", "原生 + ACES，关 SSAO/辉光")

	# ---- 07 推荐档：再关雾 + 线性色调 -----------------------------------------
	_apply_env(env, Environment.TONE_MAPPER_LINEAR, false, false, false, false)
	await _shot("07_recommend", "推荐档：原生 + 线性 + 关 SSAO/辉光/雾/MSAA")

	# ---- 08 / 09 走近看：软到底是「数据糊」还是「站太远」----------------------
	# 房间被 world_scale 放到 22.6 × 8.3 × 16.8 m（真实教室约 9 × 3.3 × 7），
	# 所以先按今天的相机往前挪几米，看细节会不会自己冒出来。
	var cam0: Vector3 = cam.global_position
	var fwd := -cam.global_basis.z
	for step in [6.0, 11.0]:
		cam.global_position = cam0 + fwd * step
		await _shot("0%d_close%.0fm" % [7 + int(step / 5.0), step],
			"同设置，相机前进 %.0f m（离黑板更近）" % step)
	cam.global_position = cam0

	print("[quality] 输出目录：%s" % _out_dir)
	quit(0)


## 一次性把环境设成某一档，避免上一档的残留影响下一档。
func _apply_env(e: Environment, tonemap: int, glow: bool, ssao: bool,
		fog: bool, adjust: bool) -> void:
	if e == null:
		return
	e.tonemap_mode = tonemap
	e.glow_enabled = glow
	e.ssao_enabled = ssao
	e.fog_enabled = fog
	e.adjustment_enabled = adjust


func _shot(shot_name: String, label: String) -> void:
	for i in WARMUP_FRAMES:
		await process_frame
	var t0 := Time.get_ticks_usec()
	for i in SHOT_FRAMES:
		await RenderingServer.frame_post_draw
	var seconds := (Time.get_ticks_usec() - t0) / 1000000.0
	print("  [%s] %s → %.1f fps（%d 帧 %.2f s）" % [
		shot_name, label, SHOT_FRAMES / maxf(seconds, 1e-6), SHOT_FRAMES, seconds])
	var img: Image = root.get_texture().get_image()
	img.save_png(_out_dir.path_join(shot_name + ".png"))


# --- 状态导出 ---------------------------------------------------------------

func _dump_state(game: Node, splat_node: Node) -> void:
	var vp := root
	print("[quality] ── 视口 ──")
	print("  root.size            = %s   （DisplayServer 窗口 %s，模式 %d）" % [
		str(vp.size), str(DisplayServer.window_get_size()),
		int(DisplayServer.window_get_mode())])
	print("  scaling_3d_scale     = %.4f" % vp.scaling_3d_scale)
	print("  scaling_3d_mode      = %s" % _enum_name("Viewport", "Scaling3DMode", vp.scaling_3d_mode))
	print("  msaa_3d              = %s（%d）" % [_enum_name("Viewport", "MSAA", vp.msaa_3d), vp.msaa_3d])
	print("  screen_space_aa      = %s" % _enum_name("Viewport", "ScreenSpaceAA", vp.screen_space_aa))
	print("  use_taa              = %s" % str(vp.use_taa))
	print("  use_debanding        = %s" % str(vp.use_debanding))
	print("  use_hdr_2d           = %s" % str(vp.use_hdr_2d))
	print("  投影后的 3D 渲染尺寸 = %s" % str(Vector2i(
		Vector2(vp.size) * vp.scaling_3d_scale)))
	print("[quality] ── 工程设置（rendering/*）──")
	for k in [
		"rendering/scaling_3d/mode", "rendering/scaling_3d/scale",
		"rendering/anti_aliasing/quality/msaa_3d",
		"rendering/anti_aliasing/quality/use_taa",
		"rendering/anti_aliasing/quality/screen_space_aa",
		"rendering/anti_aliasing/quality/use_debanding",
		"rendering/anti_aliasing/quality/use_taa",
		"rendering/textures/default_filters/texture_mipmap_bias",
		"rendering/environment/defaults/default_environment",
	]:
		print("  %-56s = %s" % [k, str(ProjectSettings.get_setting(k, "<未设置>"))])

	var we: WorldEnvironment = game.get_node_or_null("WorldEnvironment")
	if we == null or we.environment == null:
		print("[quality] ── 无 WorldEnvironment（引擎内置默认环境）──")
	else:
		var e := we.environment
		print("[quality] ── Environment（WorldEnvironment）──")
		print("  background_mode      = %s" % _enum_name("Environment", "BGMode", e.background_mode))
		print("  ambient_light_source = %s  energy %.2f" % [
			_enum_name("Environment", "AmbientSource", e.ambient_light_source),
			e.ambient_light_energy])
		print("  tonemap_mode         = %s（%d）  exposure %.2f  white %.2f" % [
			_env_tonemap_name(e), e.tonemap_mode, e.tonemap_exposure, e.tonemap_white])
		print("  ssao                 = %s  intensity %.2f  radius %.2f  power %.2f" % [
			str(e.ssao_enabled), e.ssao_intensity, e.ssao_radius, e.ssao_power])
		print("  glow                 = %s  intensity %.2f  strength %.2f  bloom %.2f  hdr_threshold %.2f  blend %s" % [
			str(e.glow_enabled), e.glow_intensity, e.glow_strength, e.glow_bloom,
			e.glow_hdr_threshold, _enum_name("Environment", "GlowBlendMode", e.glow_blend_mode)])
		print("  fog                  = %s  density %.4f  light_color %s  sky_affect %.2f" % [
			str(e.fog_enabled), e.fog_density, str(e.fog_light_color), e.fog_sky_affect])
		print("  adjustments          = %s  brightness %.2f  contrast %.2f  saturation %.2f" % [
			str(e.adjustment_enabled), e.adjustment_brightness,
			e.adjustment_contrast, e.adjustment_saturation])

	print("[quality] ── 泼溅材质实际用的着色器参数 ──")
	var mmi: Node = null
	for c in splat_node.get_children(true):
		if c is MultiMeshInstance3D:
			mmi = c
			break
	if mmi == null:
		print("  没找到后端的 MultiMeshInstance3D")
	else:
		var m: ShaderMaterial = (mmi as MultiMeshInstance3D).material_override
		print("  材质 render_priority = %d   节点 transparency = %.2f   instance_count = %d" % [
			m.render_priority, (mmi as GeometryInstance3D).transparency,
			(mmi as MultiMeshInstance3D).multimesh.instance_count])
		for p in [
			"point_count", "use_order", "order_group",
			"quad_extent", "alpha_cutoff", "min_pixel_size", "aa_compensation",
			"relight_enabled",
		]:
			print("  %-18s = %s" % [p, str(m.get_shader_parameter(p))])
		print("  可见 splat 数 ≈ %d（排序槽位数 %d）" % [
			(mmi as MultiMeshInstance3D).multimesh.instance_count * 128,
			int(m.get_shader_parameter("point_count"))])


func _env_tonemap_name(e: Environment) -> String:
	if e == null:
		return "<无环境>"
	return _enum_name("Environment", "ToneMapper", e.tonemap_mode)


func _enum_name(cls: String, enum_name: String, value: int) -> String:
	if not ClassDB.class_has_enum(cls, enum_name):
		return "?(无此枚举 %s.%s)" % [cls, enum_name]
	var keys := ClassDB.class_get_enum_constants(cls, enum_name)
	if value >= 0 and value < keys.size():
		return String(keys[value])
	return "?(越界 %d)" % value
