extends SceneTree
## 探针：新 Boss「霍德」「佩洛洛斯拉」装进 `game.tscn` 之后对不对 —— 出图 + 打印绑定。
##
## 查五件事：
##   1. 场上一共几位 Boss（`game.gd` 按类型收集）
##   2. 模型载入 + 量尺寸走的是「骨架」还是「网格」
##   3. 每个材质的贴图有没有绑上（`texture_map` 的键对不对）
##   4. 朝向：正面图应该看到脸 / 光环，不是后脑勺
##   5. 佩洛洛斯拉的表情变体只留一张
##
## 用法：godot --path <工程> --script res://scripts/_probe_boss_pair_shot.gd -- --splat=off
## 输出：`_arisu_captures/_boss/80_hod_front.png` / `81_hod_quarter.png`
##       `_arisu_captures/_boss/82_peroro_front.png` / `83_peroro_quarter.png`

const TARGETS := [
	["BossHod", "80_hod_front.png", "81_hod_quarter.png"],
	["BossPeroro", "82_peroro_front.png", "83_peroro_quarter.png"],
]

var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame
	for n in ["HUD", "SettingsMenu", "DialogueBox", "Parkour/ParkourHUD"]:
		var c := game.get_node_or_null(n) as CanvasLayer
		if c != null:
			c.visible = false
	var bosses: Array = []
	for ch in game.get_children():
		if ch is Boss:
			bosses.append(ch)
	print("[probe] 场上 Boss %d 位：%s"
		% [bosses.size(), ", ".join(bosses.map(func(b): return (b as Boss).display_name))])

	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_boss")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_cam.near = 0.05
	_cam.far = 300.0
	root.add_child(_cam)
	_cam.make_current()

	for t in TARGETS:
		var boss := game.get_node_or_null(t[0]) as Boss
		if boss == null:
			print("!! 场景里没有 %s" % t[0])
			continue
		print("\n===== %s（%s）=====" % [boss.display_name, t[0]])
		print("  血量 %.0f/%.0f  身高 %.2f m（目标 %.2f）  量法：%s  骨 %d  视觉尺寸 %s"
			% [boss.health, boss.max_health, boss.visual_size.y, boss.height,
				boss.measure_kind, boss.bone_count, str(boss.visual_size.snappedf(0.01))])
		var live := 0
		for mi in _all(boss.model, "MeshInstance3D"):
			var m := mi as MeshInstance3D
			var am := m.mesh as ArrayMesh
			if am == null:
				continue
			var surf := 0
			var keys: Array[String] = []
			for s in am.get_surface_count():
				var mat := am.surface_get_material(s)
				var key := ""
				var tex := ""
				if mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					key = sm.resource_name
					if sm.albedo_texture != null:
						tex = sm.albedo_texture.resource_path.get_file()
					if sm.albedo_texture != null:
						surf += 1
				keys.append("「%s」→ %s" % [key, tex if tex != "" else "**无贴图**"])
			if m.visible:
				live += 1
			print("  %s %s（%s）：%s" % [
				"✔" if m.visible else "✘",
				m.name, "可见" if m.visible else "已藏", " / ".join(keys)])
		print("  可见网格 %d 个" % live)

		var c := boss.global_position + Vector3(0, boss.visual_size.y * 0.5, 0)
		var d := maxf(boss.visual_size.y * 1.7, boss.visual_size.length() * 0.9)
		_cam.global_position = c + Vector3(0, 0.2, -d)     # 它朝 -Z，从北侧看正面
		_cam.look_at(c, Vector3.UP)
		await _shot(out_dir.path_join(t[1]))
		_cam.global_position = c + Vector3(d * 0.7, d * 0.3, -d * 0.7)
		_cam.look_at(c, Vector3.UP)
		await _shot(out_dir.path_join(t[2]))

	print("\n出图目录：%s" % out_dir)
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


func _all(node: Node, cls: String) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out
