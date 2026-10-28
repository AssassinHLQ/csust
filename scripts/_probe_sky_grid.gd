extends SceneTree
## 给十张天空各出一张同机位图，方便挑一张好看的。
##   _tools/run_shot.sh res://scripts/_probe_sky_grid.gd -- --no-capture
## 输出：_arisu_captures/_sky_<key>.png

const SKIES := {
	"pink": "res://assets/sky/sky_pink.jpg",
	"day": "res://assets/sky/sky_day.jpg",
	"night": "res://assets/sky/sky_night.jpg",
	"dusk": "res://assets/sky/sky_dusk.jpg",
	"overcast": "res://assets/sky/sky_overcast.jpg",
	"space": "res://assets/sky/sky_space.jpg",
	"cartoon": "res://assets/sky/sky_cartoon.jpg",
	"coldnight": "res://assets/sky/sky_coldnight.jpg",
	"coldsunset": "res://assets/sky/sky_coldsunset.jpg",
	"bluesunset": "res://assets/sky/sky_bluesunset.jpg",
}
const FOG := {
	"pink": Color(0.62, 0.48, 0.55),
	"day": Color(0.55, 0.62, 0.72),
	"night": Color(0.10, 0.11, 0.18),
	"dusk": Color(0.26, 0.18, 0.20),
	"overcast": Color(0.54, 0.53, 0.52),
	"space": Color(0.08, 0.07, 0.08),
	"cartoon": Color(0.19, 0.31, 0.49),
	"coldnight": Color(0.05, 0.08, 0.13),
	"coldsunset": Color(0.55, 0.58, 0.60),
	"bluesunset": Color(0.36, 0.45, 0.57),
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 20:
		await process_frame
	var we := level.get_node("WorldEnvironment") as WorldEnvironment
	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var cam := Camera3D.new()
	cam.fov = 78.0
	level.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(40.0, 18.0, 60.0)
	cam.look_at(Vector3(0.0, 14.0, -140.0))
	for key in SKIES:
		var tex := load(SKIES[key]) as Texture2D
		var mat := PanoramaSkyMaterial.new()
		mat.panorama = tex
		mat.filter = true
		var sky := Sky.new()
		sky.sky_material = mat
		sky.process_mode = Sky.PROCESS_MODE_REALTIME
		sky.radiance_size = Sky.RADIANCE_SIZE_256
		we.environment.sky = sky
		we.environment.background_mode = Environment.BG_SKY
		we.environment.fog_sky_affect = 0.0
		we.environment.fog_light_color = FOG[key]
		for _i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
			.path_join("_arisu_captures").path_join("_sky_%s.png" % key)
		root.get_texture().get_image().save_png(out)
		print("[sky] %s" % key)
	quit(0)
