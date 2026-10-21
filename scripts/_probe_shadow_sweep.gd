extends SceneTree
## 一次性扫参数：同一机位、只改太阳的阴影参数，看哪一组**既有柔边又不噪**。
## （2026-10-21 用户：「阴影怎么感觉高质量比低质量还难看一点点」——
##   先按「远裁+角直径」改了一版，高挡 PCSS 1.6° 出现了明显颗粒，
##   所以这里把候选组合一次拍完，选一组再写回 `game.gd`。）
##
## 用法：godot --path <工程> --script res://scripts/_probe_shadow_sweep.gd -- --splat=off
## 输出：`_arisu_captures/_shadow/sweep_1..4.png`

const OUT := "_shadow"
## [远裁 m, 角直径 °, 模糊, 标签]
const COMBOS := [
	[40.0, 0.00, 0.60, "a_40m_hard"],
	[35.0, 0.60, 1.20, "b_35m_06"],
	[30.0, 1.00, 1.40, "c_30m_10"],
	[25.0, 1.20, 1.60, "d_25m_12"],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 30:
		await process_frame
	paused = false
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")
	var hud := game.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var player := game.get_node_or_null("Player") as Node3D
	if player != null:
		player.global_position = Vector3(24.0, 0.15, -14.0)
		player.rotation.y = -PI * 0.5

	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 300.0
	root.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(28.0, 2.2, -10.6)
	cam.look_at(Vector3(23.5, 0.15, -14.6), Vector3.UP)

	var sun: DirectionalLight3D = null
	for n in game.find_children("*", "DirectionalLight3D", true, false):
		sun = n as DirectionalLight3D
		break
	if sun == null:
		print("!! 场景里没有平行光")
		quit(1)
		return

	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)

	for c in COMBOS:
		sun.directional_shadow_max_distance = c[0]
		sun.light_angular_distance = c[1]
		sun.shadow_blur = c[2]
		sun.shadow_normal_bias = 0.9
		sun.shadow_bias = 0.03
		sun.directional_shadow_blend_splits = true
		for _i in 14:
			await process_frame
		print("[sweep] %-12s 远裁 %.0f m  angular %.2f°  blur %.2f" % [c[3], c[0], c[1], c[2]])
		await _shot(out_dir.path_join("sweep_%s.png" % c[3]))

	print("\n出图：%s" % out_dir)
	quit(0)


func _shot(path: String) -> void:
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	for _i in 6:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("[shot] %s" % path.get_file())
