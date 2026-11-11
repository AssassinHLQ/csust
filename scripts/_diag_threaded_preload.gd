extends SceneTree
## 诊断：`ResourceLoader.load_threaded_request()` 到底有没有把资源放进缓存。
##
## 背景（2026-11-11）：给「第一次变身卡顿」加预热时，本喵按文档调了
## `load_threaded_request()` + 状态轮询 + `load_threaded_get()`，但预热后
## `ResourceLoader.has_cached()` 仍是 false、`load()` 照样吃满时间。
## 这个探针把每一步的状态都打出来，看是哪一环没走通。
##
##   & <godot> --headless --path . --script res://scripts/_diag_threaded_preload.gd

const CARRIER := "res://models/Arisu_Battle_Carrier.glb"


func _initialize() -> void:
	_run.call_deferred()


func _status_name(s: int) -> String:
	match s:
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return "INVALID_RESOURCE"
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return "IN_PROGRESS"
		ResourceLoader.THREAD_LOAD_FAILED:
			return "FAILED"
		ResourceLoader.THREAD_LOAD_LOADED:
			return "LOADED"
	return "?(%d)" % s


func _run() -> void:
	print("========== threaded preload 诊断 ==========")
	print("exists = %s" % str(ResourceLoader.exists(CARRIER)))
	print("cached_before = %s" % str(ResourceLoader.has_cached(CARRIER)))

	var t0 := Time.get_ticks_msec()
	var err := ResourceLoader.load_threaded_request(CARRIER, "PackedScene", true)
	print("load_threaded_request err = %d (%s)" % [err, error_string(err)])

	var got = null
	for i in 40:
		await process_frame
		var st := ResourceLoader.load_threaded_get_status(CARRIER)
		if i % 4 == 0 or st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			print("  帧 %2d  status = %s" % [i, _status_name(st)])
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			got = ResourceLoader.load_threaded_get(CARRIER)
			print("  load_threaded_get() → %s（耗时 %d ms）"
				% [str(got != null), Time.get_ticks_msec() - t0])
			break
		if st == ResourceLoader.THREAD_LOAD_FAILED \
				or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			print("  ★ 状态是失败/无效，预热不成立")
			break

	print("cached_after_threaded = %s" % str(ResourceLoader.has_cached(CARRIER)))

	var t1 := Time.get_ticks_msec()
	var x = load(CARRIER)
	print("再 load() = %d ms  结果 %s" % [Time.get_ticks_msec() - t1, str(x != null)])

	# 对照：如果 threaded 那条路不管用，直接 load 一次要多久（这才是"真花钱"的数）
	var other := "res://models/Arisu_Battle.glb"
	print("")
	print("对照另一份（未预热）: cached=%s" % str(ResourceLoader.has_cached(other)))
	t1 = Time.get_ticks_msec()
	var y = load(other)
	print("  直接 load() = %d ms  结果 %s" % [Time.get_ticks_msec() - t1, str(y != null)])
	quit(0)
