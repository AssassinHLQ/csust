extends SceneTree
## 出图：电竞房底座缩放 A/B（用户 2026-11-13 二次确认「在 0.95 上再 ×0.95」）。
## 同机位各拍上一版 (1.425, -1.5, -1.425) 与新版 (1.35375, -1.5, -1.35375)：
## 贴地斜视看台阶外沿、俯视看底座轮廓。运行时改 scale，不动场景文件。
##   _tools/run_shot.sh res://scripts/_probe_esports_base_shot.gd

const OFFWIN := preload("res://scripts/offscreen_window.gd")
const LEVEL := "res://scenes/game.tscn"
const OUT := "_arisu_captures/_esports_base_09025"
const OLD_SCALE := Vector3(1.425, -1.5, -1.425)
const NEW_SCALE := Vector3(1.35375, -1.5, -1.35375)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFFWIN.apply(self)
	root.size = Vector2i(1280, 720)
	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for i in 20:
		await process_frame
	var room := level.get_node_or_null("EsportsRoom") as Node3D
	if room == null:
		print("!! 无 EsportsRoom")
		quit(1)
		return
	room.visible = true
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	for i in 10:
		await process_frame

	var out := ProjectSettings.globalize_path("res://").path_join("..").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 3000.0
	root.add_child(cam)
	cam.make_current()
	await process_frame

	var centre := Vector3(53.26548, 0.0, 13.256798)
	var shots := [
		["edge", Vector3(40.0, 1.5, 0.0), Vector3(48.0, 0.5, 13.0)],
		["top", centre + Vector3(0, 45, 0), centre],
	]
	for tag_scale in [["old", OLD_SCALE], ["new", NEW_SCALE]]:
		var tag: String = tag_scale[0]
		room.scale = tag_scale[1]
		for i in 5:
			await process_frame
		for s in shots:
			var name: String = s[0]
			var eye: Vector3 = s[1]
			var look: Vector3 = s[2]
			cam.global_position = eye
			await process_frame
			var up: Vector3 = Vector3.FORWARD if absf((eye - look).normalized().y) > 0.95 else Vector3.UP
			cam.look_at(look, up)
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			if img != null:
				img.save_png(out.path_join("%s_%s.png" % [name, tag]))
			print("  %s_%s 相机 %s" % [name, tag, str(cam.global_position.snappedf(0.1))])

	print("[probe] 输出 %s" % out)
	quit(0)