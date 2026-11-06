extends SceneTree
## 复刻 `splat_scene.gd` 的做法：在**后台线程**里完整解码 room609（关缓存、不渲染泼溅）。
##
## 用途（2026-11-06）：导出包一开泼溅就 0xC0000005，而主线程解码的探针
## `_probe_sog_decode.gd` 完全正常（277 万点 / 24.3 s / ok）。两者唯一的差别就是
## **解码跑在主线程还是工作线程**，这个探针用来确认这一点。
##
## 用法（必须真窗口，要有 RenderingDevice）：
##   _tools/run_shot.sh res://scripts/_probe_threaded_decode.gd -- --no-capture

const SogRuntime := preload("res://scripts/sog_runtime.gd")

var _thread: Thread


func _initialize() -> void:
	var source := "res://splatdata/room609.sogdata"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sog="):
			source = a.substr(6)
	print("[tdecode] 启动后台线程解码 %s" % source)
	_thread = Thread.new()
	_thread.start(_worker.bind(source), Thread.PRIORITY_LOW)
	# 主线程只等着（不做事），保证工作线程跑完
	var t0 := Time.get_ticks_msec()
	while _thread.is_alive():
		OS.delay_msec(100)
		if Time.get_ticks_msec() - t0 > 180000:
			print("[tdecode] 超时 180 s，放弃")
			break
	_thread.wait_to_finish()
	print("[tdecode] 线程结束，总耗时 %d ms" % (Time.get_ticks_msec() - t0))
	quit()


func _worker(source: String) -> void:
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = SogRuntime.load_sog(source, {"cache": "off"})
	print("[tdecode] ok=%s count=%s ms=%d" % [
		r.get("ok"), r.get("count"), Time.get_ticks_msec() - t0])
