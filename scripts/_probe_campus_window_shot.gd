extends SceneTree
## 出图验收「10×10 分块 + 3×3 窗口」：同样的机位分别拍「分块窗口」和「全量」，
## 让肉眼判断 3×3 窗口外的远景到底缺了多少。
##
##   # 分块模式（chunks.json 在）
##   _tools/run_shot.sh res://scripts/_probe_campus_window_shot.gd -- --tag=win
##
##   # 全量模式（先把清单挪走，campus_ggs 自动退回 campus_ggs.bin）
##   mv splatdata/campus_chunks10/chunks.json /tmp/ck.json && \
##   _tools/run_shot.sh res://scripts/_probe_campus_window_shot.gd -- --tag=full
##   mv /tmp/ck.json splatdata/campus_chunks10/chunks.json
##
## ⚠️ 取景必须用**玩家自己的相机**：`campus_ggs._make_bundle()` 把
##    `get_viewport().get_camera_3d()` 传给光栅器并**一直持有**那个引用，
##    光栅器 `update_camera_matrices()` 读的就是它。新建一个 Camera3D 设成 current
##    只能改变 3D 后处理，泼溅视图纹丝不动（实测两张不同朝向的图 sha256 一样）。
##    所以这里改 `player._yaw` / `player._pitch`，让玩家脚本自己去转 rig / spring。
##
## 判据：窗口 3×3 ≈ 60×50 m，校园本体 ≈ 200×150 m。
## 玩家视线越过窗口边界后，那边应该只剩黑 —— 这张图就是证据。

## 机位：p = 玩家位置（决定选哪 9 块），look = 看向哪。
const SPOTS := [
	{"n": "east_along", "p": Vector3(60.0, 1.0, -150.0), "look": Vector3(-40.0, 0.0, -196.0)},
	{"n": "east_out", "p": Vector3(60.0, 1.0, -150.0), "look": Vector3(140.0, 0.0, -150.0)},
	{"n": "deep_along", "p": Vector3(-40.0, 1.0, -200.0), "look": Vector3(60.0, 0.0, -150.0)},
	{"n": "plaza_axis", "p": Vector3(0.0, 1.0, -88.0), "look": Vector3(0.0, 0.0, -200.0)},
	{"n": "boundary", "p": Vector3(38.0, 1.0, -131.0), "look": Vector3(-38.0, 0.0, -131.0)},
	## 抬头看天：判断「窗外是黑的」到底是缺远处的点，还是天空这条路径本身就没画
	{"n": "sky_up", "p": Vector3(60.0, 1.0, -150.0), "look": Vector3(60.0, 80.0, -150.0)},
]

var _tag := "win"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			_tag = a.substr(6)
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://_log/win_%s_%s.png" % [_tag, name])
	root.get_texture().get_image().save_png(out)
	print("[shot] %s" % out)


## 让玩家看向 look：相机前向 = -(sin(_yaw), 0, cos(_yaw))，见 player.gd 那段注释。
func _aim(p: Node3D, look: Vector3) -> void:
	var eye: Vector3 = p.global_position + Vector3(0.0, 1.6, 0.0)
	var d := (look - eye).normalized()
	var yaw := atan2(-d.x, -d.z)
	var pitch := clampf(asin(clampf(d.y, -1.0, 1.0)), -1.15, 1.15)
	# 写私有量（玩家 _process 每帧会拿它覆盖 rig/spring），同时**直接**写节点，
	# 因为 `_apply_camera()` 是在 `_physics_process` 链上被调的，本探针把物理关了。
	p.set("_yaw", yaw)
	p.set("_pitch", pitch)
	var rig := p.get_node_or_null("CameraRig") as Node3D
	if rig != null:
		rig.rotation.y = yaw
	var spring := p.get_node_or_null("CameraRig/SpringArm3D") as Node3D
	if spring != null:
		spring.rotation.x = pitch


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await _wait(30)

	var ggs := level.get_node_or_null("CampusGGS")
	if ggs == null:
		await _wait(120)
		ggs = level.get_node_or_null("CampusGGS")
	if ggs == null:
		print("!! 没找到 CampusGGS")
		quit(1)
		return
	var p := level.get_node_or_null("Player") as Node3D
	if p == null:
		print("!! 没找到 Player")
		quit(1)
		return
	var pcam := p.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
	if pcam == null:
		print("!! 玩家没有相机")
		quit(1)
		return

	var use_chunks := bool(ggs.get("_use_chunks"))
	print("[shot] 模式 = %s（%d 块清单）｜panorama=%s｜相机=%s" % [
		("分块 %d×%d" % [int(ggs.get("window_side")), int(ggs.get("window_side"))]) if use_chunks else "全量",
		(ggs.get("_chunk_list") as Array).size(),
		str(ggs.get("panorama") != null), str(root.get_camera_3d() == pcam)])

	# 干净出图：HUD / 遮罩全部藏起来；玩家不落地、不走路
	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	p.set_physics_process(false)

	for s in SPOTS:
		var spot: Dictionary = s
		var before: PackedStringArray = ggs.get("_window_names")
		p.global_position = spot["p"]
		_aim(p, spot["look"])

		# 跨窗口这一段全程计时：最坏一帧多长、画面空了几帧（= 玩家看到的「卡一下」）
		var t_switch := Time.get_ticks_usec()
		var worst_ms := 0.0
		var blank_frames := 0
		var frames := 0

		# 等窗口真正换过来
		if use_chunks:
			for _i in 400:
				var f0 := Time.get_ticks_usec()
				await process_frame
				frames += 1
				worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - f0) / 1000.0)
				var qq := ggs.get("quad") as MeshInstance3D
				if qq == null or not qq.visible:
					blank_frames += 1
				var now: PackedStringArray = ggs.get("_window_names")
				if now != before:
					break
		# 等新窗口上传完（这段也计时：这段里画面是空的）
		for _i in 900:
			var f1 := Time.get_ticks_usec()
			await process_frame
			frames += 1
			worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - f1) / 1000.0)
			var qq2 := ggs.get("quad") as MeshInstance3D
			if qq2 == null or not qq2.visible:
				blank_frames += 1
			var r = ggs.get("rasterizer")
			if r != null and bool(r.get("is_loaded")):
				break
		var switch_ms := float(Time.get_ticks_usec() - t_switch) / 1000.0
		# 落位 + 对准，再等几帧让光栅器吃到新相机矩阵
		p.global_position = spot["p"]
		_aim(p, spot["look"])
		await _wait(10)
		await _shot(String(spot["n"]))

		# 第一个机位顺便把两层拆开各拍一张（判断「粗层到底有没有东西」）
		if spot["n"] == "east_along":
			var sm := (ggs.get("quad") as MeshInstance3D)
			if sm != null:
				var mat := sm.material_override as ShaderMaterial
				if mat != null:
					mat.set_shader_parameter("debug_layer", 1)
					await _wait(3)
					await _shot("layer_coarse")
					mat.set_shader_parameter("debug_layer", 2)
					await _wait(3)
					await _shot("layer_fine")
					mat.set_shader_parameter("debug_layer", 0)
					await _wait(3)
					var cr = ggs.get("coarse_rasterizer")
					print("[shot] 粗层：rasterizer=%s loaded=%s 点=%s" % [
						str(cr != null),
						("-" if cr == null else str(cr.get("is_loaded"))),
						("-" if cr == null else str((cr.get("num_splats_loaded") as Array)[0]))])

		var r2 = ggs.get("rasterizer")
		var npts := 0
		if r2 != null:
			npts = int((r2.get("num_splats_loaded") as Array)[0])
		# 帧率：两份光栅器是**双份 compute**，必须量（MEMORY 里记过「两套渲染器打架」）
		var fps := 0.0
		var t0 := Time.get_ticks_usec()
		for _i in 90:
			await process_frame
		var dt := float(Time.get_ticks_usec() - t0) / 1e6
		if dt > 0.0:
			fps = 90.0 / dt
		var q := ggs.get("quad") as MeshInstance3D
		print("[shot] %-12s 窗口 %d 块 | 点 %d | VRAM %.0f MiB | quad=%s | %.0f fps" % [
			String(spot["n"]), (ggs.get("_window_names") as PackedStringArray).size(),
			npts, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			("-" if q == null else str(q.visible)), fps])
		print("[cost] %-12s 切换 %6.0f ms / %d 帧 | 最坏一帧 %5.1f ms | 画面空 %d 帧" % [
			String(spot["n"]), switch_ms, frames, worst_ms, blank_frames])

	quit(0)
