extends SceneTree
## 量：校园 SOG 解码要多久、占多少内存。
##
## 目的（用户 2026-11-11）：「首页方案是发布只带 sogdata，首次运行解码+切块写 _cache」，
## 但**首次要玩家等多久**还没数 —— 这是唯一挡住决策的事实。
##
## 本探针**只解码，不写盘**（`cache` 模式 off），算完就退出，不留任何文件。
## 量的内容：
##   · school_playable.sogdata（校园本体，6.15M 点）→ 耗时 / 点数 / AABB / 内存增量
##   · room609.sogdata（2.77M 点，作对照 / 校准）
##   · 顺带验证 6.15M 点这件事（和 campus_chunks 总点数对账）
##
##   godot --headless --script res://scripts/_probe_sog_decode_time.gd

const SogRuntime := preload("res://scripts/sog_runtime.gd")

const SCHOOL := "res://splatdata/school_playable.sogdata"
const ROOM := "res://splatdata/room609.sogdata"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# 硬超时：GDScript 解码大文件可能很慢，超时就报告已知信息，别卡死。
	get_root().get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[dt] !! 超时（600 s）—— 解码太慢，这本身就是结论")
		quit(3))

	print("[dt] ==== 解码耗时实测（只解码，不写盘）====")
	print("[dt] 进程静态内存起点: %.1f MB" % (OS.get_static_memory_usage() / 1048576.0))

	_measure(ROOM, "room609")
	_measure(SCHOOL, "school_playable")

	print("[dt] ==== 完 ====")
	quit(0)


func _measure(path: String, tag: String) -> void:
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		print("[dt] %s：文件不存在 %s" % [tag, path])
		return
	var size_mb := 0.0
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		size_mb = f.get_length() / 1048576.0
		f.close()

	var mem0 := OS.get_static_memory_usage()
	var t0 := Time.get_ticks_msec()
	# cache = "off"：绝不写盘
	var r: Dictionary = SogRuntime.load_sog(path, {"cache": "off"})
	var dt := Time.get_ticks_msec() - t0
	var mem1 := OS.get_static_memory_usage()

	if not bool(r.get("ok", false)):
		print("[dt] %s：解码失败 —— %s" % [tag, str(r.get("message", "?"))])
		return

	var count := int(r.get("count", 0))
	var elapsed := int(r.get("elapsed_ms", dt))
	var aabb_min: Vector3 = r.get("aabb_min", Vector3.ZERO)
	var aabb_max: Vector3 = r.get("aabb_max", Vector3.ZERO)
	# 240 B/点 = 解出来要落盘的字节数
	var out_mb := count * 240.0 / 1048576.0

	print("[dt] %s：" % tag)
	print("[dt]   SOG 文件    : %.1f MB" % size_mb)
	print("[dt]   点数        : %d" % count)
	print("[dt]   解码耗时    : %d ms (%.2f s)" % [elapsed, elapsed / 1000.0])
	print("[dt]   内存增量    : %.1f MB" % ((mem1 - mem0) / 1048576.0))
	print("[dt]   解出字节数  : %.1f MB（240 B/点）→ 这就是要写进 _cache 的量" % out_mb)
	print("[dt]   解压比      : %.1f×" % (out_mb / maxf(size_mb, 0.01)))
	print("[dt]   AABB        : %s ~ %s" % [str(aabb_min.snappedf(0.1)), str(aabb_max.snappedf(0.1))])
	print("[dt]   速度        : %.0f 万点/秒" % (count / 10000.0 / maxf(elapsed / 1000.0, 0.001)))
