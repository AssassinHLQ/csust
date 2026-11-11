extends SceneTree
## 探针：**炫彩霸王龙优香的彩虹流光** —— 出多帧图看它是不是真的在动。
##
## 用户 2026-11-11：「炫彩要动态的，像洛克王国一样」，选的是「彩虹流光（颜色随时间流转）」。
##
## 要证明两件事：
##   ① 效果本身好看（出图，人眼看）
##   ② **它是动态的**（同一机位隔几帧各拍一张，比较像素差异 —— 差异必须显著）
##
## 用法：& <godot_console.exe> --path . --script res://scripts/_probe_rainbow_trex.gd -- --splat=off --no-capture
## 出图：_arisu_captures/_rainbow_trex/{t0,t1,t2,t3}.png

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "_rainbow_trex"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	print("[焦点自检] %s" % str(OffWin.is_safe()))

	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _i in 200:
		await process_frame
	paused = false
	for _f in 40:
		await process_frame

	var target := level.get_node_or_null("TrexBossB") as Node3D
	if target == null:
		print("[错误] 没有 TrexBossB")
		quit(1)
		return

	# ⚠️⚠️ 关键：Boss 模型是 **BootGate 延迟建**的
	#    （`trex_yuuka_boss.tscn` 里 `boot_distance = 60.0` / `boot_max_wait = 20.0`）。
	#    探针不把玩家挪过去的话，模型永远不会建，`model` 就是 null
	#    —— 上一版探针统计出「ShaderMaterial 0 个」就是这个原因（不是 shader 没生效）。
	#    这里把玩家直接放到恐龙脚下，触发 `when_near` 的近距离条件。
	var player := level.get_node_or_null("Player") as Node3D
	if player != null:
		player.global_position = target.global_position + Vector3(0, 1.0, 12.0)
		for _f in 40:
			await process_frame
	var waited := 0
	while target.get("model") == null and waited < 120:
		await process_frame
		waited += 1
	print("等模型建成用了 %d 帧；model = %s"
		% [waited, "有" if target.get("model") != null else "仍是 null"])

	print("TrexBossB: display_name=%s  rainbow_flow=%s"
		% [str(target.get("display_name")), str(target.get("rainbow_flow"))])

	# 确认材质真的换成了 ShaderMaterial
	var model := target.get_node_or_null("ObjModel")
	if model == null:
		# 找第一个 Node3D 子节点当模型（模型可能是 PackedScene 实例）
		for c in target.get_children():
			if c is Node3D and c.name != "Collision":
				model = c
				break
	var n_shader := 0
	var n_std := 0
	if model != null:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for s in m.mesh.get_surface_count():
				var ov := m.get_surface_override_material(s)
				if ov is ShaderMaterial:
					n_shader += 1
				elif ov is StandardMaterial3D:
					n_std += 1
	print("材质统计：ShaderMaterial %d 个 / StandardMaterial3D %d 个" % [n_shader, n_std])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	# 相机：正对这只恐龙，拉近看身体
	var p := target.global_position
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 500.0
	cam.fov = 55.0
	root.add_child(cam)
	cam.global_position = p + Vector3(0, 8.0, 22.0)
	cam.look_at(p + Vector3(0, 4.0, 0), Vector3.UP)
	cam.make_current()

	# 同一机位连拍 4 张，间隔约 0.5 s，看颜色有没有流动
	var prev: Image = null
	for i in 4:
		# 等约 0.5 秒（30 帧 @60fps）
		for _f in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := "%s/t%d.png" % [out, i]
		img.save_png(path)
		var diff := ""
		if prev != null:
			diff = "  与前一张差异 %.2f%%" % (_diff_pct(prev, img))
		prev = img
		print("  t%d → %s%s" % [i, path, diff])

	print("\n[截图] %s" % out)
	quit(0)


## 两张图有多少像素不同（百分比）。用来证明"真的在动"。
func _diff_pct(a: Image, b: Image) -> float:
	var ia := a.duplicate() as Image
	var ib := b.duplicate() as Image
	ia.convert(Image.FORMAT_RGBA8)
	ib.convert(Image.FORMAT_RGBA8)
	var da := ia.get_data()
	var db := ib.get_data()
	var n := ia.get_width() * ia.get_height()
	var diff := 0
	for i in n:
		var o := i * 4
		# 任一通道差超过 6 就算"这颗像素变了"
		if absi(int(da[o]) - int(db[o])) > 6 \
				or absi(int(da[o + 1]) - int(db[o + 1])) > 6 \
				or absi(int(da[o + 2]) - int(db[o + 2])) > 6:
			diff += 1
	return 100.0 * float(diff) / float(n)
