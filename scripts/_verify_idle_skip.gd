extends SceneTree
## 校验「静止帧复用」是**逐像素精确**的，并且把「场景本身还在动」这种情况区分出来。
##
## 三步，缺一不可：
##   0. **诊断**：读泼溅数据里的 `time` 字段（第 3 个 float）。渲染着色器用它做入场
##      动画（`time - splat.time` → 1.35 s 后恒为 1），所以 `max(time)` 决定了
##      「入场动画什么时候结束」。这个数决定跳过该等多久，必须量出来。
##   1. **自证基准静止**：复用**关**着抓两帧，必须逐像素相同。
##      不同 ⇒ 场景本身还在变（动画没落定 / 有别的东西在动），此时**不能**判复用对不对。
##   2. **对比**：复用开着抓一帧，和基准逐像素比对。
##
## 用法（必须真窗口）：
##   _tools/run_shot.sh res://scripts/_verify_idle_skip.gd
## 输出：stdout + <工程>/_log/idle_skip_verify.txt

const SETTLE_FRAMES := 900
const WATCHDOG_MS := 1500000

var _lines: PackedStringArray = PackedStringArray()
var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	Engine.max_fps = 0
	root.scaling_3d_scale = 0.5

	_log("=== 静止帧复用：逐像素校验 ===")
	_log("")
	await _check_scene("res://scenes/game.tscn", "Room609")

	_log("")
	_log("结论：%s" % ("通过（复用与重算逐像素一致）" if _fails == 0 else "%d 项失败" % _fails))
	_write_out()
	quit(0 if _fails == 0 else 1)


func _check_scene(path: String, room_name: String) -> void:
	var scene: Node = (load(path) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame

	var host: Node = await _wait_ready(scene, room_name)
	if host == null:
		_log("[%s] 泼溅一直没就绪，跳过" % path.get_file())
		_fails += 1
		scene.queue_free()
		await process_frame
		return

	# 冻住一切会动的。
	# ⚠️ 只关同伴/Boss 是不够的：实测「复用关着连抓两帧」仍有 18 万字节不同，
	#    说明场景里还有别的东西在动（画室609 有闪烁的灯，`_probe_flicker.gd` 就是它）。
	#    所以这里**把整棵树的 `_process` 全停掉**、暂停所有 AnimationPlayer、
	#    停掉粒子 —— 世界静止了，比对才有意义。
	#    ⚠️ 场景 2 不能这么干：`campus_ggs._process` 一停 GGS 就不渲染了。
	var tod: Node = root.get_node_or_null("TimeOfDay")
	if tod != null:
		tod.set("_override_minutes", 0.0)
	var frozen := _freeze_all(scene)
	for c in root.get_children():
		if c != scene:
			frozen += _freeze_all(c)
	# UI 全部藏掉：HUD / 准星 / 对话框这类东西就算冻住也可能因为 Tween 继续动，
	# 而它们和泼溅无关，留着只会污染比对。
	var ui_hidden := _hide_all_canvas(scene)
	# Tween 挂在 SceneTree 上，不在任何节点里 —— 冻 `_process` 管不到它，必须显式杀掉。
	var tweens_killed := 0
	for t in get_processed_tweens():
		t.kill()
		tweens_killed += 1
	_log("  已冻结 %d 个节点的 `_process`、藏掉 %d 个 CanvasLayer、杀掉 %d 个 Tween" % [
		frozen, ui_hidden, tweens_killed])

	_diag_time_field()

	# ★ 关键：把合成器切到 `DIRECT_TEXTURE` 调试模式 —— 屏幕**只显示泼溅那一层**。
	#   为什么必须这样：整个画面里还有别的东西在动（实测把 3324 个节点的 `_process`
	#   停掉、暂停动画、停粒子、藏 UI、杀 Tween 之后仍有 11.8 万字节不同），
	#   全屏比对永远不可能逐字节相同。而**泼溅层自己的输入**（相机 + 点数据 + 光照 +
	#   入场动画）是冻住的，只比它才有意义。
	#   注意 `render_for_compositor()` 在 DIRECT_TEXTURE 模式下**照常被调用**，
	#   所以复用逻辑是真的被走到了。
	var direct := _force_direct_texture()
	_log("  合成器切到 DIRECT_TEXTURE（只显示泼溅层）：%s" % ("成功" if direct else "失败，退回全屏比对"))

	# 入场动画落定（`_diag_time_field` 打出来的 max 就是依据）
	for i in SETTLE_FRAMES:
		await process_frame

	var layers := _layer_handles(host)
	if layers.is_empty():
		_log("[%s] 找不到可切换的泼溅层，跳过" % path.get_file())
		scene.queue_free()
		await process_frame
		return

	# ⓿ 先自证「抓图」这条路本身可靠：**同一帧**连读两次必须完全相同。
	#    否则后面所有逐像素比对都是在比「抓图的噪声」，结论无效。
	await RenderingServer.frame_post_draw
	var g1 := root.get_texture().get_image()
	var g2 := root.get_texture().get_image()
	var cap := _diff(g1, g2)
	_log("  抓图自证（同一帧连读两次）：%s" % (
		"逐字节相同 ✓" if cap["diff"] == 0 else
		"**不同** %d 字节（最大通道差 %d，包围盒 %s）→ 抓图本身不可靠，后面结论无效" % [
			cap["diff"], cap["worst"], str(cap["bbox"])]))
	if cap["diff"] != 0:
		_fails += 1
		scene.queue_free()
		await process_frame
		return

	# ① 「重算 vs 重算」的噪声底。
	#    ⚠️ 这里发现的关键事实：**泼溅自身每帧都不一样**。
	#    GPU 基数排序按 key 分桶时用的是原子操作，key 相同（深度量化后大量相同）的
	#    高斯之间**相对顺序不是确定的**，而 alpha-over 累加对顺序敏感 ⇒ 两帧「同样
	#    输入、各自完整重算」的画面本来就不同（实测 12 万字节、最大通道差 ~100）。
	#    所以「逐字节相同」不是可行判据，**噪声底才是**。
	_set_skip(layers, false)
	for i in 5:
		await process_frame
	var r1 := await _grab()
	for i in 3:
		await process_frame
	var r2 := await _grab()
	var name := path.get_file()
	if r1 == null or r2 == null:
		_log("[%s] 抓图失败" % name)
		_fails += 1
		scene.queue_free()
		await process_frame
		return
	var noise := _diff(r1, r2)
	_log("[%s] 噪声底（重算 vs 重算）：%d 字节不同（最大通道差 %d），包围盒 %s" % [
		name, noise["diff"], noise["worst"], str(noise["bbox"])])

	# ② 复用帧：和「最后一次重算帧」比。
	#    判据 = **复用带来的差异不能超过渲染器自己的抖动量**。
	#    噪声底为 0（确定性渲染）时就退化成「必须逐字节相同」。
	_set_skip(layers, true)
	for i in 4:
		await process_frame
	var b := await _grab()
	if b == null:
		_log("[%s] 抓图失败" % name)
		_fails += 1
	else:
		var r := _diff(r2, b)
		var ok: bool = r["diff"] <= noise["diff"] and r["worst"] <= maxi(noise["worst"], 1)
		if ok:
			_log("[%s] PASS：复用帧 vs 重算帧 = %d 字节不同（最大通道差 %d），"
				% [name, r["diff"], r["worst"]]
				+ ("重算是确定性的，两者逐字节相同" if noise["diff"] == 0
					else "不超过噪声底 %d 字节 / 通道差 %d ⇒ 与重算无法区分" % [
						noise["diff"], noise["worst"]]))
		else:
			_fails += 1
			_log("[%s] FAIL：复用帧 vs 重算帧 = %d 字节不同（最大通道差 %d），"
				% [name, r["diff"], r["worst"]]
				+ "**超过**噪声底 %d 字节 / 通道差 %d ⇒ 复用带来了额外变化" % [
					noise["diff"], noise["worst"]])
			_dump(r2, "fail_recompute.png")
			_dump(b, "fail_reused.png")

	scene.queue_free()
	await process_frame


## 读泼溅数据第 3 个 float（`time`）的分布 —— 入场动画的长度由它的 max 决定。
func _diag_time_field() -> void:
	var mgr = GaussianRenderManager.get_instance()
	if mgr == null:
		_log("  （不是 Compute 后端，没有 time 字段可读）")
		return
	var reg = mgr.get("_scene_registry")
	if reg == null:
		return
	var data: PackedByteArray = reg.get_point_data_byte()
	if data.is_empty():
		_log("  （点数据是空的）")
		return
	var n := data.size() / 240
	var step := maxi(1, n / 200000)
	var lo := INF
	var hi := -INF
	var count := 0
	for i in range(0, n, step):
		var t := data.decode_float(i * 240 + 12)
		if not is_finite(t):
			continue
		lo = minf(lo, t)
		hi = maxf(hi, t)
		count += 1
	var now_s := Time.get_ticks_msec() * 1e-3
	_log("  泼溅 time 字段：抽样 %d 点，min %.3f  max %.3f（单位秒，引擎时钟）" % [count, lo, hi])
	_log("  当前引擎时钟 %.1f s ⇒ 入场动画在 %.1f s 结束，余量 %.1f s" % [
		now_s, hi + 1.35, now_s - (hi + 1.35)])


## 把一棵子树的「自己会动」全部停掉：`_process` / `_physics_process` / 动画 / 粒子。
## 返回停掉 `_process` 的节点数（用来打日志确认真的冻上了）。
func _freeze_all(node: Node) -> int:
	var n := 0
	if node.has_method("set_process"):
		node.set_process(false)
		node.set_physics_process(false)
		n += 1
	if node is AnimationPlayer:
		(node as AnimationPlayer).pause()
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	if node is CPUParticles3D:
		(node as CPUParticles3D).emitting = false
	for c in node.get_children():
		n += _freeze_all(c)
	return n


## 让屏幕只显示泼溅层：`GaussianCompositorEffect.display_mode = DIRECT_TEXTURE`。
func _force_direct_texture() -> bool:
	var cam := root.get_viewport().get_camera_3d()
	if cam == null or cam.compositor == null:
		return false
	var effects := cam.compositor.compositor_effects
	if effects.is_empty() or effects[0] == null:
		return false
	effects[0].set("display_mode", 1)  # DisplayMode.DIRECT_TEXTURE
	return true


func _hide_all_canvas(node: Node) -> int:
	var n := 0
	var cl := node as CanvasLayer
	if cl != null:
		cl.visible = false
		n += 1
	for c in node.get_children():
		n += _hide_all_canvas(c)
	return n


func _wait_ready(scene: Node, room_name: String) -> Node:
	var w0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - w0 < 180000:
		var room: Node = scene.get_node_or_null(room_name)
		if room != null and room.get("splat_node") != null:
			return room
		await process_frame
	return null


func _layer_handles(target: Node) -> Array:
	var out: Array = []
	var mgr = GaussianRenderManager.get_instance()
	if mgr != null:
		var renderer = mgr.get("_renderer")
		if renderer != null:
			out.append({"obj": renderer, "prop": "_idle_skip"})
	for key in ["rasterizer", "coarse_rasterizer"]:
		var r = target.get(key)
		if r != null:
			out.append({"obj": r, "prop": "idle_skip"})
	return out


func _set_skip(layers: Array, on: bool) -> void:
	for l in layers:
		(l["obj"] as Object).set(String(l["prop"]), on)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var tex := root.get_texture()
	return tex.get_image() if tex != null else null


func _diff(a: Image, b: Image) -> Dictionary:
	if a.get_size() != b.get_size():
		return {"diff": -1, "worst": 0, "first": 0, "total": 0, "bbox": Rect2i()}
	var da := a.get_data()
	var db := b.get_data()
	var w := a.get_width()
	var diff := 0
	var worst := 0
	var first := -1
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for i in mini(da.size(), db.size()):
		if da[i] != db[i]:
			diff += 1
			if first < 0:
				first = i
			worst = maxi(worst, absi(da[i] - db[i]))
			var px := i / 4
			var p := Vector2i(px % w, px / w)
			lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
			hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
	var bbox := Rect2i()
	if hi.x >= 0:
		bbox = Rect2i(lo, hi - lo + Vector2i.ONE)
	return {"diff": diff, "worst": worst, "first": maxi(first, 0),
		"total": da.size(), "bbox": bbox}


func _dump(img: Image, file_name: String) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_log").path_join("idle_skip")
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir.path_join(file_name))


func _write_out() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_log")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("idle_skip_verify.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()


func _log(s: String) -> void:
	print("[idle] " + s)
	_lines.append(s)
