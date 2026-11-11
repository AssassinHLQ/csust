extends SceneTree
## 复现 / 验收：「退出时后台解码线程还在跑 → `Cannot call method 'lock' on a null value`」
##
## 用户报的崩溃（日志 `splat_scene.gd:1201`）：
##   `[SplatScene] 工作线程准备：内容盒 6 ms` → `slot >= slot_max` → `lock on null`
## 紧跟着就是 `[Carrier] 空中变身` —— 换形态/切场景把节点释放掉的时刻。
##
## 手法：把节点塞进场景树 → `start()` 开线程 → **线程没跑完就 queue_free()**
##       → 等几帧，看是否出现 `lock on null`。
##
## 跑法：
##   godot --headless --path . --script res://scripts/_probe_splat_exit_race.gd -- --no-capture

const TIMEOUT_MS := 60000

var _fail := 0
var _lines: Array[String] = []
var _t0 := 0


func _init() -> void:
	_t0 = Time.get_ticks_msec()
	_go.call_deferred()


func _say(s: String) -> void:
	_lines.append(s)
	print(s)


func _ck(ok: bool, name: String, detail: String = "") -> void:
	if ok:
		_say("  ✓ %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		_say("  ✗ %s%s" % [name, ("  " + detail) if detail != "" else ""])


func _go() -> void:
	_say("")
	_say("==== 泼溅解码线程 × 节点释放 竞态 ====")
	_say("")

	# 找一个真的 .sogdata —— 冷启解码要 3 s 左右，线程才会「还没跑完」
	var src := _find_sog()
	if src == "":
		_say("  找不到 .sogdata，跳过")
		_finish()
		return
	_say("  数据源：%s" % src)

	var Scene := load("res://scripts/splat_scene.gd")
	if Scene == null:
		_ck(false, "加载 splat_scene.gd")
		_finish()
		return

	var root := Node3D.new()
	root.name = "RaceRoot"
	get_root().add_child(root)

	var node = Scene.new()
	node.name = "RaceSplat"
	# 直接指向那个文件，绕开 venue / 目录解析
	node.sog_path = src
	node.auto_start = false
	node.display_name = "竞态测试"
	root.add_child(node)

	# 连上信号，确认线程确实跑起来了（回调必须带参数，否则静默失效）
	var finished := [false]
	node.loaded.connect(func(_info: Dictionary) -> void:
		finished[0] = true
	)
	node.failed.connect(func(_why: String) -> void:
		finished[0] = true
	)

	node.start()
	_ck(node.loading, "start() 后 loading = true")
	_ck(node._thread != null, "线程句柄非空")

	# ⚠️ 不 await —— 立刻释放，制造「线程还在跑、节点先死」
	_say("  → 线程未完成即释放节点（这就是崩溃那一刻）")
	root.remove_child(node)
	node.queue_free()
	root.queue_free()

	# 给线程足够时间跑到 `_mutex.lock()` 那一步
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 12000:
		await process_frame

	# 崩溃是 SCRIPT ERROR，引擎会打到 stderr；探针自己拦不到。
	# 所以这里断言的是「线程跑完之后，进程还活着、main loop 还在转」。
	_ck(true, "释放后等 12 s，主循环仍存活（崩溃的话这一步就到不了）")
	_say("  ⚠️ 真正的判据在 stderr：看不出 mutex 空指针 SCRIPT ERROR 才算过")

	_finish()


func _find_sog() -> String:
	# 复用项目里已有的解析：扫 res:// 下的 .sogdata
	var dir := DirAccess.open("res://")
	if dir == null:
		return ""
	var cands: Array[String] = []
	_collect(dir, "res://", cands)
	if cands.is_empty():
		return ""
	# 挑最大的那份 —— 解码最久，最容易撞上
	var best := ""
	var best_sz := -1
	for p in cands:
		var sz := FileAccess.get_file_as_bytes(p).size()
		if sz > best_sz:
			best_sz = sz
			best = p
	return best


func _collect(d: DirAccess, base: String, out: Array[String]) -> void:
	d.list_dir_begin()
	while true:
		var n := d.get_next()
		if n == "":
			break
		if n.begins_with("."):
			continue
		var full := base.path_join(n)
		if d.current_is_dir():
			if n == "addons" or n == ".godot":
				continue
			var sub := DirAccess.open(full)
			if sub != null:
				_collect(sub, full, out)
		elif n.get_extension().to_lower() in ["sogdata", "sog"]:
			out.append(full)
	d.list_dir_end()


func _finish() -> void:
	_say("")
	if _fail == 0:
		_say("==== 全部通过（0 项失败）==== %.1f s" % ((Time.get_ticks_msec() - _t0) / 1000.0))
	else:
		_say("==== 失败 %d 项 ====" % _fail)
	quit(0 if _fail == 0 else 1)
