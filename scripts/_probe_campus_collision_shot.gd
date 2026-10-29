extends SceneTree
## 把校园点云（CampusPreview）+ 碰撞线框一起拍下来，肉眼核对碰撞准不准。
##   _tools/run_shot.sh res://scripts/_probe_campus_collision_shot.gd
## 产物：_arisu_captures/_collision_shot_1/2/3.png

const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_captures"

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var campus := level.get_node_or_null("Campus")
	if campus != null:
		campus.set("auto_start", false)
		campus.set_process(false)
	var prev := level.get_node_or_null("Campus/CampusPreview")
	if prev != null:
		prev.visible = true
		for c in prev.get_children():
			if c is MeshInstance3D:
				var mat := StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.vertex_color_use_as_albedo = true
				mat.disable_fog = true
				mat.use_point_size = true
				mat.point_size = 2.0
				(c as MeshInstance3D).material_override = mat

	# 显示碰撞线框（属性在 SceneTree 上，不在 Window 上）
	if "debug_collisions_hint" in self:
		set("debug_collisions_hint", true)
	else:
		print("[shot] 这个版本没有 debug_collisions_hint")

	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.near = 0.05
	cam.far = 2000.0
	level.add_child(cam)
	cam.current = true

	var shots := [
		["_collision_shot_1", Vector3(0, 3.2, -110), Vector3(0, 2.5, -260)],   # 校园主路往北
		["_collision_shot_2", Vector3(0, 40, -180), Vector3(0, 2, -330)],       # 中景俯看
		["_collision_shot_3", Vector3(0, 220, -320), Vector3(0, 0, -330)],      # 全校园俯视
	]
	for s in shots:
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var p := "%s/%s.png" % [OUT_DIR, s[0]]
		var err := img.save_png(p)
		print("[shot] %s err=%d" % [p, err])
	quit(0)
