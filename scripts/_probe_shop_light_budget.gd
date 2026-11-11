extends SceneTree
## 探针：**柴关电脑城到底亮在哪**——拆开算每一路光源的贡献。
##
## 背景：2026-11-11 用户「柴关电脑城晚上才开灯」。第一版把三盏 OmniLight 按 20:00/06:00
## 开关，读回的能量都对（白天 0、夜里 2.2），**但画面几乎没变**：
##   12:00 室内平均亮度 214.2/255
##   21:00 室内平均亮度 191.4/255
## 白天反而比夜里亮 —— 说明灯不是主力。这个探针把每一路单独打开看：
##
##   ① 现状（灯也开、环境光也开）
##   ② 只把三盏灯关掉（环境光留着）        → 灯到底占多少
##   ③ 只把环境光压到 0（灯留着）          → 环境光到底占多少
##   ④ 再把 `Sky` 的 `background_mode` 换掉看外面是不是"天亮了"假象
##
## 用法：& <godot_console.exe> --path . --script res://scripts/_probe_shop_light_budget.gd -- --splat=off --no-capture
## 出图：_arisu_captures/_shop_night/budget_*.png

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "_shop_night_budget"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false

	var shop := game.get_node_or_null("Shop") as Node3D
	var we := game.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if shop == null or we == null or we.environment == null:
		print("[错误] 缺 Shop / WorldEnvironment")
		quit(1)
		return
	var env := we.environment
	var tod := get_root().get_node_or_null("TimeOfDay")
	if tod != null:
		tod.call("set_day_minutes", 0.0)

	var lights: Array[Light3D] = []
	for n in shop.find_children("*", "OmniLight3D", true, false):
		lights.append(n as Light3D)
	var night_e: Array[float] = []
	for l in lights:
		night_e.append(l.light_energy)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	# 机位：店里正对货架（和 _probe_shop_night_lights 的室内机位一致，方便横向比）
	var sp := shop.global_position
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 500.0
	cam.fov = 72.0
	root.add_child(cam)
	cam.global_position = Vector3(sp.x, 1.62, sp.z + 6.0)
	cam.look_at(Vector3(sp.x, 1.4, sp.z - 3.0), Vector3.UP)

	print("\n环境：ambient_source=%d energy=%.2f｜tonemap=%d exposure=%.2f｜background_mode=%d"
		% [env.ambient_light_source, env.ambient_light_energy,
			env.tonemap_mode, env.tonemap_exposure, env.background_mode])
	if env.sky != null:
		print("天空：sky_material=%s energy_mult=%.2f"
			% [env.sky.sky_material.get_class() if env.sky.sky_material != null else "null",
				env.sky.sky_material.energy_multiplier if env.sky.sky_material != null else -1.0])

	for h in [12.0, 21.0]:
		if tod != null:
			tod.call("set_hours", h)
		for _f in 60:
			await process_frame
		print("\n── 游戏内 %02d:00 ──" % int(h))
		print("   环境 ambient_energy=%.2f  exposure=%.2f  太阳 energy=%.2f"
			% [env.ambient_light_energy, env.tonemap_exposure,
				(game.get_node_or_null("Sun") as DirectionalLight3D).light_energy
					if game.get_node_or_null("Sun") != null else -1.0])

		# ① 现状
		await _shot(cam, out, "%02d_1_now" % int(h), "① 现状")
		# ② 只关灯
		_set_lights(lights, 0.0)
		await _shot(cam, out, "%02d_2_lights_off" % int(h), "② 只关灯（环境光留着）")
		# ③ 灯回来 + 环境光压 0
		_set_lights_multi(lights, night_e)
		var saved_amb := env.ambient_light_energy
		env.ambient_light_energy = 0.0
		await _shot(cam, out, "%02d_3_ambient_off" % int(h), "③ 只关环境光（灯留着）")
		# ④ 两个都关
		_set_lights(lights, 0.0)
		await _shot(cam, out, "%02d_4_both_off" % int(h), "④ 灯 + 环境光都关")

		# 还原
		env.ambient_light_energy = saved_amb
		_set_lights_multi(lights, night_e)

	print("\n[截图] %s" % out)
	quit(0)


func _set_lights(lights: Array[Light3D], e: float) -> void:
	for l in lights:
		l.light_energy = e


func _set_lights_multi(lights: Array[Light3D], e: Array[float]) -> void:
	for i in lights.size():
		lights[i].light_energy = e[i]


func _shot(cam: Camera3D, out: String, nm: String, note: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, nm])
	print("   %-18s %-24s → %s" % [nm, note, _stats(img)])


func _stats(img: Image) -> String:
	var a := img.duplicate() as Image
	a.convert(Image.FORMAT_RGBA8)
	var data := a.get_data()
	var n := a.get_width() * a.get_height()
	var blown := 0
	var sum := 0.0
	for i in n:
		var o := i * 4
		var r := data[o]
		var g := data[o + 1]
		var b := data[o + 2]
		if r >= 245 and g >= 245 and b >= 245:
			blown += 1
		sum += 0.2126 * float(r) + 0.7152 * float(g) + 0.0722 * float(b)
	return "过曝 %.2f%%｜平均 %.1f" % [100.0 * float(blown) / float(n), sum / float(n)]
