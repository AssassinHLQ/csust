extends SceneTree
## 探针：内存条市场里**地上躺着的**那几根（可拾取 → 资产）长什么样。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_ram_loot.gd
## 输出：…/_arisu_captures/_ramloot/*.png
##
## 只拍图，不碰玩家 / 不捡东西（`loot_enabled` 保持 true 也无所谓：这场景里没玩家）。

const OUT_SUB := "_ramloot"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var pk := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Parkour
	root.add_child(pk)
	for _i in 25:
		await process_frame

	var ram := pk.get_node_or_null("RamMarket") as RamMarket
	if ram == null:
		print("[loot] 没有 RamMarket")
		quit(1)
		return
	var ps := ram.ground_positions()
	print("[loot] 地上 %d 根；装饰 %d 根" % [ps.size(), ram.stick_count()])
	if ps.is_empty():
		quit(1)
		return
	for i in mini(3, ps.size()):
		var sp: Dictionary = ram.ground_specs()[i]
		print("[loot] #%d @ %s  %s  ¥%d" % [i, str(ps[i].snappedf(0.01)),
			RamSpec.describe(sp), RamSpec.price_yuan(sp)])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(out)

	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.35, 0.45, 0.62)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(1, 1, 1)
	we.environment.ambient_light_energy = 1.2
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	sun.light_energy = 1.5
	root.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.05
	cam.far = 600.0
	root.add_child(cam)
	cam.make_current()

	# ① 一根的特写：从台面斜上方 2.4 m 看下去（能看清「躺平 + 金圈」）
	var at: Vector3 = ps[0]
	await _shot(cam, out, "1_close", at + Vector3(1.9, 1.35, 1.9), at)
	# ② 贴着台面看：确认它没浮空、没插进台子里
	await _shot(cam, out, "2_ground", at + Vector3(2.6, 0.45, 2.6), at)
	# ③ 一段全景：整块台上几根 + 头顶吊架
	await _shot(cam, out, "3_wide", at + Vector3(9.0, 7.5, 9.0), at)
	# ④ 第二根（换块台子）—— 看随机朝向
	if ps.size() > 5:
		var at2: Vector3 = ps[5]
		await _shot(cam, out, "4_other", at2 + Vector3(2.0, 1.4, -2.0), at2)
	print("\n出图目录：%s" % out)
	quit(0)


func _shot(cam: Camera3D, out: String, name: String, pos: Vector3, look: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("[loot] %s ← %s" % [name, str(pos.snappedf(0.1))])
