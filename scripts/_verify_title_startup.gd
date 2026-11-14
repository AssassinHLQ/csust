extends SceneTree
## 回归：播放不允许同步读图；未导入图片、缺图和预热仍能完成。

class NonBlockingIntro:
	extends "res://scripts/title_intro.gd"
	var sync_reads := 0
	func _load_texture(_path: String) -> Texture2D:
		sync_reads += 1
		return null

var _pass := 0
var _fail := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	root.size = Vector2i(1600, 900)
	var intro := NonBlockingIntro.new()
	root.add_child(intro)
	intro._slides.assign(["user://startup_raw.png", "user://startup_missing.png"])
	intro._tex_cache.resize(2)
	var began := Time.get_ticks_usec()
	_check(intro._slide_texture(0) == null, "未就绪图片立即返回 null")
	_check(Time.get_ticks_usec() - began < 10000, "缓存未命中不会等待 I/O")
	_check(intro.sync_reads == 0, "缓存未命中不调用同步读图")
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.5, 0.9, 1.0))
	img.save_png("user://startup_raw.png")
	intro._playing = true
	await intro._prefetch_slides()
	_check(intro._prefetch_done, "未导入图片预载正常结束")
	_check(intro._slide_texture(0) != null, "未导入 PNG 在线程中解码为纹理")
	_check(intro._slide_texture(1) == null, "缺失图片保持为空")
	_check(intro._raw_jobs.is_empty(), "完成的解码线程已回收")
	_check(intro.sync_reads == 0, "预载全程没有回退主线程读图")
	intro._kind = "pv"
	intro._black_only()
	intro._build_backdrop()
	intro._slides.assign(["user://startup_raw.png", "user://startup_missing.png"])
	await intro._warm_up_shader()
	await process_frame
	_check(intro.get_node_or_null("MediaWarmUp") == null, "离屏预热画布用完释放")
	intro._slides.assign(["user://startup_missing.png"])
	intro._tex_cache.clear()
	intro._tex_cache.resize(1)
	intro._slideshow_gen = 1
	intro._loop_slides(1)
	for i in 5:
		await process_frame
	_check(intro.sync_reads == 0, "全缺图播放让出主线程，不忙循环、不读盘")
	intro._playing = false
	await process_frame
	intro.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://startup_raw.png"))
	print("[title_startup] %d PASS / %d FAIL" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
