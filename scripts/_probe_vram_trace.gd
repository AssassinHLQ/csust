extends SceneTree
## 跟踪显存**什么时候涨上去**：离屏真窗口，从第 0 帧起每 15 帧记一次。
##
##   _tools/run_shot.sh res://scripts/_probe_vram_trace.gd -- [场景] [--splat=off]
##
## 为什么要这个：静态清点说「场景几何 14 MiB + 贴图 60 MiB」，可实测一进场景就 3 GB。
## 到底是「引擎/UI/灯光一次性申请」还是「某一帧蹭地涨上来」，只能看时间线。

const DEFAULT_SCENE := "res://scenes/game.tscn"
const STEP := 15
const FRAMES := 900


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var t := create_timer(180.0, true)
	t.timeout.connect(func():
		print("[trace] !! 看门狗超时")
		quit(1))
	_run.call_deferred()


func _vram() -> float:
	return float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0


## Godot 把显存拆成「纹理」和「缓冲」两项，直接读它们就能定位大头在哪边
func _tex_mem() -> float:
	return float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0


func _buf_mem() -> float:
	return float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0


func _breakdown() -> String:
	return "纹理 %7.0f / 缓冲 %7.0f MiB" % [_tex_mem(), _buf_mem()]


func _run() -> void:
	GameSettings.set_value("vsync", false)
	GameSettings.set_value("fps_limit", 0.0)
	var which := DEFAULT_SCENE
	for a in OS.get_cmdline_user_args():
		if not String(a).begins_with("--"):
			which = String(a)
	root.size = Vector2i(1920, 1080)
	print("[trace] 场景 %s" % which)

	# 先量「还没加场景」的空引擎地板
	for _i in 5:
		await process_frame
	print("[trace] frame %4d  显存 %7.0f MiB（空引擎，场景还没加）" % [0, _vram()])

	var game := (load(which) as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game

	var last := _vram()
	print("[trace] frame %4d  显存 %7.0f MiB（刚加进场景树）｜物体 %d｜draw %d" % [
		0, last, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	for f in range(STEP, FRAMES + 1, STEP):
		await _wait(STEP)
		var v := _vram()
		var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		# 只打「有变化」的行，免得 900 帧刷屏
		if absf(v - last) >= 8.0 or f % 150 == 0:
			print("[trace] frame %4d  显存 %7.0f MiB（%+7.0f）｜%s｜物体 %5d｜draw %5d" % [
				f, v, v - last, _breakdown(), objs, draws])
			last = v
	print("[trace] 结束：显存 %.0f MiB｜%s" % [_vram(), _breakdown()])
	quit(0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
