extends SceneTree
## 在画室609 的出生视角拍一张（离屏真窗口，不抢前台），用来肉眼比对
## 「覆盖率提实」前后的观感。
##
##   _tools/run_shot.sh res://scripts/_probe_room609_shot.gd -- --tag=after
##
## 对照：把 `addons/gdgs/.../gsplat_render.glsl` 的 COVERAGE_LIFT 改回 1.0，
## 用 `--tag=before` 再拍一张。

const SCENE := "res://scenes/game.tscn"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var t := create_timer(180.0, true)
	t.timeout.connect(func():
		print("[shot609] !! 看门狗超时")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	var tag := "after"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--tag="):
			tag = String(a).substr(6)
	root.size = Vector2i(1280, 720)
	var game := (load(SCENE) as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game

	# 等画室609 就绪
	var room := game.get_node_or_null("Room609")
	var waited := 0
	while waited < 900:
		await _wait(30)
		waited += 30
		if room != null and bool(room.call("is_ready")):
			break
	print("[shot609] 画室就绪=%s（等了 %d 帧）" % [
		"-" if room == null else str(room.call("is_ready")), waited])
	# 让泼溅的合成器跑几帧再拍
	await _wait(60)
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://_log/room609_%s.png" % tag)
	root.get_texture().get_image().save_png(out)
	print("[shot609] 截图 → %s" % out)
	print("[shot609] 显存 %.0f MiB" % (
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0))
	quit(0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
