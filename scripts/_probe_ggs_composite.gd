extends SceneTree
## 验证 B：next_level + --ggs-campus，玩家站在校园里，相机/合成器自然工作。
##   _tools/run_shot.sh res://scripts/_probe_ggs_composite.gd -- --ggs-campus
## 出图：_arisu_captures/_ggs_composite.png

var level
var player
var ggs
var rasterizer
var started := 0
var last := 0
var shot := false
var loaded_at := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame
	player = level.get_node_or_null("Player") as CharacterBody3D
	ggs = level.get_node_or_null("CampusGGS")
	print("[ggscomp] GGS 节点：%s" % str(ggs != null))
	if player != null:
		player.global_position = Vector3(0.0, 0.3, -120.0)
	started = Time.get_ticks_msec()

func _process(_dt: float) -> bool:
	if ggs == null:
		return false
	if rasterizer == null and ggs.get("rasterizer") != null:
		rasterizer = ggs.get("rasterizer")
	var now := Time.get_ticks_msec()
	if loaded_at == 0 and rasterizer != null and rasterizer.is_loaded:
		loaded_at = now
		print("[ggscomp] LOADED")
	if loaded_at > 0 and not shot and now - loaded_at > 10000:
		shot = true
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png("C:/Users/WY157/Desktop/GODOT/_arisu_captures/_ggs_composite.png")
		print("[ggscomp] 截图")
	if now - last > 2000:
		last = now
		var vram := 0.0
		if rasterizer != null and rasterizer.context:
			vram = float(rasterizer.context.device.get_memory_usage(RenderingDevice.MEMORY_TOTAL)) / 1048576.0
		var ts := Vector2i.ZERO
		if rasterizer != null:
			ts = rasterizer.texture_size
		print("[ggscomp] fps=%d vram=%.0fMB loaded=%s render=%s" % [
			Engine.get_frames_per_second(), vram,
			str(rasterizer != null and rasterizer.is_loaded), str(ts)])
	if loaded_at > 0 and now - loaded_at > 14000:
		quit()
		return true
	return false
