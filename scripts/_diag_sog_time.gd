extends SceneTree
## 诊断：画室609 的 SOG 展开到底慢在哪一段、慢多久。
##
## 用户 2026-11-09：「打包为什么加载高斯这么久」（截图 94% / 2,621,440 / 2,774,116 点）。
##
## 逐段计时：读文件 → 解码 → 打包成 byte → 建资源。判断是「本来就慢」还是「打包后才慢」。
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_diag_sog_time.gd

const SOURCE := "res://splatdata/room609.sogdata"
## ⚠️ 必须 preload：`--script` 模式下解析不到 `class_name`（本项目栽过好几次）。
const SogRuntime := preload("res://scripts/sog_runtime.gd")

var _t0 := 0
var _last_phase := ""
var _phase_t := 0
var _marks: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _on_progress(phase: String, done: int, total: int) -> void:
	if phase != _last_phase:
		if _last_phase != "":
			_marks.append("  %-10s %6d ms" % [_last_phase, Time.get_ticks_msec() - _phase_t])
		_last_phase = phase
		_phase_t = Time.get_ticks_msec()
	# 只在每 25% 打一次，别刷屏
	if total > 0 and done % maxi(total / 4, 1) == 0:
		print("  [%s] %d / %d  (%.0f%%)  t=%.1f s" % [
			phase, done, total, 100.0 * float(done) / float(total),
			float(Time.get_ticks_msec() - _t0) / 1000.0])


func _run() -> void:
	print("========== 画室609 SOG 展开计时 ==========")
	if not FileAccess.file_exists(SOURCE):
		push_error("[diag] 找不到 %s" % SOURCE)
		quit(1)
		return
	var f := FileAccess.open(SOURCE, FileAccess.READ)
	var mb := float(f.get_length()) / 1048576.0
	f.close()
	print("源文件 %.1f MB" % mb)
	print("CPU 核数 %d，线程 %s" % [OS.get_processor_count(),
		"（解码在工作线程，不挡主线程）"])

	_t0 = Time.get_ticks_msec()
	_phase_t = _t0
	var result: Dictionary = SogRuntime.load_sog(SOURCE, {
		"cache": "auto",
		"progress": Callable(self, "_on_progress"),
	})
	if _last_phase != "":
		_marks.append("  %-10s %6d ms" % [_last_phase, Time.get_ticks_msec() - _phase_t])
	var total_ms := Time.get_ticks_msec() - _t0

	print("\n── 分段耗时 ──")
	for m in _marks:
		print(m)
	print("\n── 总计 ──")
	print("  总耗时 %.2f s" % (float(total_ms) / 1000.0))
	print("  ok = %s" % str(result.get("ok", false)))
	var cnt := int(result.get("point_count", 0))
	print("  点数 %d" % cnt)
	if cnt > 0:
		print("  单点 %.1f µs" % (float(total_ms) * 1000.0 / float(cnt)))
		print("  每秒约 %.0f 点" % (float(cnt) / maxf(float(total_ms) / 1000.0, 0.001)))
	quit(0)

