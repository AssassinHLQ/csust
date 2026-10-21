extends SceneTree
## 渲图探针：**店面**（北立面）拍两张 —— 正面一张、斜侧一张。
##
## 用户 2026-10-22 那张截图就是站在店门口往上看：门头以上原来是一整块灰的实心横梁。
## 现在要求改成玻璃幕墙，这里就用同一类机位验收。
##
## 用法：godot --path <工程> --script res://scripts/_probe_shop_facade.gd -- --splat=off
## 输出：_arisu_captures/_shop/{front,three_quarter}.png

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")

	var shop := game.get_node_or_null("Shop") as Node3D
	if shop == null:
		print("!! 找不到 Shop")
		quit(1)
		return
	var L := float(shop.get("shop_len"))
	var D := float(shop.get("shop_depth"))
	var H := float(shop.get("shop_height"))
	var back_z := shop.global_position.z - D * 0.5      # 北墙（店面）在 -D/2 一侧
	print("[facade] 店面：长 %.2f 高 %.2f，北墙 z=%.2f" % [L, H, back_z])

	var cam := Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)
	cam.make_current()

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_shop")
	DirAccess.make_dir_recursive_absolute(out)

	var centre := Vector3(shop.global_position.x, H * 0.55, back_z)
	var shots := {
		# 正面：站在店外 13 m、1.8 m 高，抬头看整面幕墙（用户那张截图的角度）
		"front": [Vector3(centre.x, 1.8, back_z + 13.0), Vector3(centre.x, H * 0.52, back_z)],
		# 斜侧：看门柱与幕墙的关系
		"three_quarter": [Vector3(centre.x - 9.0, 2.1, back_z + 9.5),
			Vector3(centre.x, H * 0.45, back_z)],
	}
	for name in shots:
		var pos: Vector3 = shots[name][0]
		var look: Vector3 = shots[name][1]
		cam.global_position = pos
		cam.look_at(look, Vector3.UP)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var file := "%s/%s.png" % [out, name]
		root.get_texture().get_image().save_png(file)
		print("  [img] %s（机位 %s）" % [file, str(pos.snappedf(0.01))])
	quit(0)
