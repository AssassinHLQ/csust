extends SceneTree
## 出图：从平台**下方**往上看，确认平台不是一张纸（用户 2026-11-11 的仰视图）。
##
## 用户原话：「我们的平台需要加高，往下扩张」。改的是 `next_level.tscn`：
##   Plaza 120×0.6×120 → **120×40×120**，中心 y −0.32 → **−20.02**（顶面仍在 −0.02）。
##
## 拍两个机位：
##   under  = 平台下方 25 m 往上看（复现用户截图那个角度）
##   side   = 平台侧面水平看（看厚度/侧壁）
##
##   _tools/run_shot.sh res://scripts/_probe_plaza_thickness_shot.gd -- --no-capture
## 输出 `_arisu_captures/_plaza_thick/{under,side}.png`
##
## ⚠️ `next_level.tscn` 不带泼溅，加载几秒就好。

const OffWin := preload("res://scripts/offscreen_window.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1600, 900))
	for _i in 3:
		await process_frame
	var lvl: Node = (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(lvl)
	for _i in 30:
		await process_frame
	paused = false

	# 把玩家挪开、关掉它的处理，免得相机被玩家逻辑抢走
	var player := lvl.get_node_or_null("Player")
	if player != null:
		player.set_physics_process(false)
		player.set_process(false)
		(player as Node3D).global_position = Vector3(0, 200, 300)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_plaza_thick")
	DirAccess.make_dir_recursive_absolute(out)

	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.far = 900.0
	lvl.add_child(cam)
	for shot in [
		{"name": "under", "pos": Vector3(30, -26, 30), "look": Vector3(20, -5, 20)},
		{"name": "side", "pos": Vector3(120, -18, 60), "look": Vector3(40, -12, 20)},
	]:
		cam.global_position = shot["pos"]
		cam.look_at(shot["look"], Vector3.UP)
		cam.make_current()
		for _i in 4:
			await process_frame
		cam.make_current()
		if DisplayServer.get_name() == "headless":
			print("⚠️ headless 拿不到渲染纹理")
			break
		await RenderingServer.frame_post_draw
		var f := out.path_join("%s.png" % String(shot["name"]))
		root.get_texture().get_image().save_png(f)
		print("[截图] %s" % f)

	# 顺带报一下几何，方便核对
	var plaza := lvl.get_node_or_null("Plaza") as Node3D
	if plaza != null:
		print("  Plaza 位置 %s" % str(plaza.global_position.snappedf(0.01)))
		var mi := plaza.get_node_or_null("Mesh") as MeshInstance3D
		if mi != null and mi.mesh != null:
			print("  Plaza 网格 AABB 尺寸 %s" % str(mi.get_aabb().size.snappedf(0.01)))
	quit(0)
