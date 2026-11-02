extends SceneTree
## 出图：609 桌上那十颗 9950X3D 的近景（不进 609 泼溅，单看模型）。
##   _tools/run_shot.sh res://scripts/_probe_cpu_shot.gd
const OUT := "res://_arisu_captures/_cpu"


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.7
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.6
	root.add_child(sun)

	var cpus := (load("res://scenes/room609_cpus.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(cpus)
	var center := cpus.global_position + Vector3(0.12, 0.02, 0.0)

	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.01
	cam.far = 50.0
	cam.current = true
	root.add_child(cam)
	cam.global_position = center + Vector3(3.2, 2.6, 3.2)
	cam.look_at(center + Vector3(0.0, 0.6, 0.0), Vector3.UP)
	await _wait(12)
	root.get_texture().get_image().save_png(OUT + "/01_desk_cpus.png")

	cam.global_position = center + Vector3(0.85, 0.55, 0.85)
	cam.look_at(center + Vector3(-0.15, 0.0, -0.3), Vector3.UP)
	await _wait(6)
	root.get_texture().get_image().save_png(OUT + "/02_close.png")
	print("[cpu-shot] 存图 %s/01_desk_cpus.png / 02_close.png" % OUT)
	quit(0)
