extends SceneTree
## 探针：蒙德里安大楼**室内**亮度 A/B —— 定最终灯能量。
##
## 起因（用户 2026-11-11）：「为什么蒙德里安大楼这么亮堂，瞎死我了」+ 一张室内截图。
## 截图里的东西对上了 `mondrian_house.gd::_build_interior()` 的**二层**：
##   左边黄色柜子 = `Cabinet`（_mat["yellow"]，0.55×0.90×3.20，贴东墙）
##   右边带腿长桌 = `DeskTop` + `DeskLeg`（x = −1.20）
##   正对面高处小窗 = 南墙窗 x 2.50~6.50 / y 5.00~7.20（比二层地面高 0.80，所以显得高）
##   右边黑斜面 = `RailE` 黑栏杆 + 西侧楼梯井
## ⇒ 人站在二层、面朝南（+Z）。+X（东）在左手边 → 黄柜子在左，全对。
##
## 为什么亮爆（量出来的，不是猜的）：
##   四盏 OmniLight3D、`light_energy = 2.4`、`omni_range = 13.0`、`shadow_enabled = false`。
##   · 天花板：离 Light2W/E 只有 **0.11 m** → 衰减系数 0.99，两盏各给 2.38，**合计 4.8**，
##     再叠上 Light1W/E（在二层楼板下面，距天花板 4.0 m，系数 0.69，再给 1.66×2）
##     → 天花板拿到 ~8 个光单位，配 0.945 的近白反照率 = 必爆。
##   · 二层地面：Light2W/E 在正上方 3.69 m（系数 0.72）→ 1.72×2 = 3.4，也爆。
##   · 一层那两盏**没有阴影**，会直接穿楼板照上来，给二层天花板补刀。
##
## 用法（**必须真窗口**才能出图）：
##   & <godot_console.exe> --path . --script res://scripts/_probe_mondrian_bright.gd -- --splat=off --story=off --no-capture
## 出图：_arisu_captures/_mondrian_light/*.png

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "_mondrian_light"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	print("[焦点自检] %s" % str(OffWin.is_safe()))

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame

	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false

	var house := game.get_node_or_null("MondrianHouse") as Node3D
	if house == null:
		print("[错误] 场景里没有 MondrianHouse")
		quit(1)
		return
	var hp := house.global_position
	print("\nMondrianHouse 世界原点 %s" % str(hp))

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var we := game.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var e := we.environment
		print("[环境] ambient_source=%d energy=%.2f｜tonemap=%d exposure=%.2f"
			% [e.ambient_light_source, e.ambient_light_energy,
				e.tonemap_mode, e.tonemap_exposure])
		print("[环境] glow=%.2f｜ssao=%.2f｜fog=%.4f"
			% [e.glow_intensity, e.ssao_intensity, e.fog_density])

	var lights: Array[OmniLight3D] = []
	for n in house.find_children("*", "OmniLight3D", true, false):
		lights.append(n as OmniLight3D)
	print("\n[灯] MondrianHouse 下 %d 盏" % lights.size())
	for l in lights:
		var lp := l.global_position
		print("  %-10s 局部 %-22s energy=%.2f range=%.1f shadow=%s"
			% [l.name, str((lp - hp).round()), l.light_energy, l.omni_range,
				str(l.shadow_enabled)])

	# 灯管自发光（天花板那两块亮斑的来源）
	var tube_mats: Array[StandardMaterial3D] = []
	for mi in house.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for si in m.get_surface_count():
			var mat := m.surface_get_material(si)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
				var sm := mat as StandardMaterial3D
				if not tube_mats.has(sm):
					tube_mats.append(sm)
					print("  自发光材质 #%d energy_mult=%.2f emission=%s"
						% [tube_mats.size(), sm.emission_energy_multiplier,
							str(sm.emission)])

	# ── 相机：二层，面朝南（+Z），复刻用户那张图 ──
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 500.0
	cam.fov = 72.0
	root.add_child(cam)

	# ── 一层视角：从大门里侧往里看 ──
	var cam1 := Camera3D.new()
	cam1.near = 0.05
	cam1.far = 500.0
	cam1.fov = 72.0
	root.add_child(cam1)
	cam1.global_position = hp + Vector3(0.0, 1.62, -5.2)
	cam1.look_at(hp + Vector3(0.0, 1.30, 4.5), Vector3.UP)

	cam.global_position = hp + Vector3(2.0, 5.82, -3.0)
	cam.look_at(hp + Vector3(0.4, 5.35, 5.5), Vector3.UP)

	# ── A：**复现用户那张图**（把灯强行拨回旧值 2.4 / 13.0 / 灯管 2.0）──
	_apply(lights, 2.4, 13.0, 2.0, tube_mats, 2.0)
	await _shot2(cam, cam1, out, "A_old", "旧值：四盏 2.4 / range 13 / 灯管自发光 2.0（= 用户截图）")

	# ── B：**现在提交的那一版**（照场景里的真值，不写死，改常量之后这张图会跟着变）──
	_reload(lights, tube_mats)
	await _shot2(cam, cam1, out, "B_new", "现在的场景值（mondrian_house.gd::LIGHT_*）")

	# ── B2：**只降二层那两盏**，一层仍留旧值 2.4 ──
	#    用来验证代码注释里那句「一层那两盏没有阴影、会穿过楼板照到二层」到底成不成立。
	#    如果 B2 ≈ B，说明**一层那两盏根本没参与**，那句注释就是错的，得删。
	_reload(lights, tube_mats)
	for l in lights:
		if String(l.name).begins_with("Light1"):
			l.light_energy = 2.4
			l.omni_range = 13.0
	await _shot2(cam, cam1, out, "B2_2fonly", "诊断：只降二层两盏（一层仍 2.4）")

	# ── 参考档：想再调的话照着这两个数改 ──
	_reload(lights, tube_mats)
	_apply(lights, 1.05, 10.0, 1.2, tube_mats, 1.6)
	await _shot2(cam, cam1, out, "C_brighter", "参考：四盏 1.05 / range 10 / 门灯 1.2 / 灯管 1.6（比现在亮一档）")
	_apply(lights, 0.65, 8.5, 0.9, tube_mats, 1.1)
	await _shot2(cam, cam1, out, "D_darker", "参考：四盏 0.65 / range 8.5 / 门灯 0.9 / 灯管 1.1（比现在暗一档）")

	# ── 室外：确认改室内灯没把外面的观感搞坏（外面靠 Sun，本来就不该变）──
	_reload(lights, tube_mats)
	var camext := Camera3D.new()
	camext.near = 0.05
	camext.far = 500.0
	camext.fov = 46.0
	root.add_child(camext)
	camext.global_position = Vector3(hp.x, 11.0, hp.z - 24.0)
	camext.look_at(Vector3(hp.x, 4.2, hp.z), Vector3.UP)
	await _shoot(camext, out, "Z_outside", "室外（对照）")

	print("\n[截图] %s" % out)
	quit(0)


## 从场景里重新读一遍真值（探针改过之后再还原，别拿被改过的状态当"现状"）
func _reload(lights: Array[OmniLight3D], tube_mats: Array[StandardMaterial3D]) -> void:
	var src := (load("res://scenes/mondrian_house_baked.tscn") as PackedScene).instantiate()
	var src_lights: Array[OmniLight3D] = []
	for n in src.find_children("*", "OmniLight3D", true, false):
		src_lights.append(n as OmniLight3D)
	for l in lights:
		for s in src_lights:
			if String(s.name) == String(l.name):
				l.light_energy = s.light_energy
				l.omni_range = s.omni_range
	# 灯管自发光：材质是 shared 的，从源码包里那一份读回来
	var mult := 1.0
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for si in m.get_surface_count():
			var mat := m.surface_get_material(si)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
				mult = (mat as StandardMaterial3D).emission_energy_multiplier
	src.free()
	for m in tube_mats:
		m.emission_energy_multiplier = mult


## 四盏天花板灯 + 门灯一把改掉。
func _apply(lights: Array[OmniLight3D], energy: float, rng: float,
		door_energy: float, tube_mats: Array[StandardMaterial3D],
		tube_mult: float) -> void:
	for l in lights:
		var nm := String(l.name)
		if nm.begins_with("Light1") or nm.begins_with("Light2"):
			l.light_energy = energy
			l.omni_range = rng
		elif nm == "DoorLight":
			l.light_energy = door_energy
			l.omni_range = minf(rng, 7.5)
	for m in tube_mats:
		m.emission_energy_multiplier = tube_mult


func _shot2(cam: Camera3D, cam1: Camera3D, out: String, nm: String, note: String) -> void:
	print("\n%s —— %s" % [nm, note])
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var a := root.get_texture().get_image()
	a.save_png("%s/%s_2f.png" % [out, nm])
	print("  二层 %s" % _stats(a))
	cam1.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var b := root.get_texture().get_image()
	b.save_png("%s/%s_1f.png" % [out, nm])
	print("  一层 %s" % _stats(b))


func _shoot(cam: Camera3D, out: String, nm: String, note: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, nm])
	print("  %-12s %s → %s" % [nm, note, _stats(img)])


## 过曝占比 + 平均亮度。`get_data()` 给的是**紧凑**格式（这里 RGB8 = 3 字节/像素），
## 先转 RGBA8 再解包 —— 上一版直接按 4 字节索引，越界崩了 4 次。
func _stats(img: Image) -> String:
	var a := img.duplicate() as Image
	a.convert(Image.FORMAT_RGBA8)
	var data := a.get_data()
	var n := a.get_width() * a.get_height()
	var blobs := 0
	var sum := 0.0
	for i in n:
		var o := i * 4
		var r := data[o]
		var g := data[o + 1]
		var b := data[o + 2]
		if r >= 245 and g >= 245 and b >= 245:
			blobs += 1
		sum += 0.2126 * float(r) + 0.7152 * float(g) + 0.0722 * float(b)
	return "过曝 %.2f%%｜平均亮度 %.1f/255" % [100.0 * float(blobs) / float(n), sum / float(n)]
