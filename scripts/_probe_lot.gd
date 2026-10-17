extends SceneTree
## 探针（要真渲染）：从平台边上看一眼「空地铺地砖」的效果。
##
## 只拍平台**里面**：用户 2026-10-18 交代过「场地最外面不要填上（影响跑酷）」，
## 所以这里也顺便断言「平台外没有任何新增的地面节点」。
##
## 用法（别加 --headless；带 --splat=off 省显存）：
##   godot --path <工程> --script res://scripts/_probe_lot.gd -- --splat=off
## 输出：`_arisu_captures/_lot/`

const OUT_DIR := "_arisu_captures/_lot"
const SIZE := Vector2i(800, 600)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = SIZE
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)

	# 断言：平台外不许有本工程加的地面
	var extra: Array = []
	for c in game.get_children():
		var n := String(c.name)
		if n.contains("Skirt") or n.contains("Lot"):
			extra.append(n)
	print("[lot] 平台外的附加地面节点：%s（应为空）" % str(extra))

	var cam := Camera3D.new()
	cam.name = "LotCam"
	cam.fov = 60.0
	cam.far = 300.0
	root.add_child(cam)
	cam.global_position = Vector3(15.5, 1.5, 11.0)
	cam.look_at(Vector3(0.0, 0.9, 2.0), Vector3.UP)
	cam.make_current()
	await _shot(out.path_join("1_platform.png"), "平台内侧")

	# 平台边缘往外看：应当直接是天空（不铺外面）
	cam.global_position = Vector3(18.0, 1.5, 18.0)
	cam.look_at(Vector3(34.0, 0.2, 34.0), Vector3.UP)
	await _shot(out.path_join("2_edge.png"), "冲着平台外沿")
	print("[lot] 输出目录 %s" % out)
	quit(0)


func _shot(file: String, tag: String) -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("[lot]   [img] %s（%s）" % [file, tag])


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
