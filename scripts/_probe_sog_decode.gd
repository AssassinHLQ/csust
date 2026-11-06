extends SceneTree
## 只解码 `.sogdata`（主线程），逐步打印解码阶段 —— 用来定位导出包里崩在第几步。
##
## 背景（2026-11-06）：导出包内 `SogRuntime.load_sog("res://splatdata/room609.sogdata")`
## 必崩 0xC0000005，而同一个调用在编辑器里正常（277 万点 / 24.3 s / ok）。
## 已排除：同伴模型、缺 .glsl、Compute 后端、工作线程、user:// 写不进去、脚本字节码。
##
## ⚠️ 进度回调里**不要用局部变量做去重**：GDScript 的 lambda 按值捕获，局部变量
##    改了外面看不到，会变成「每次回调都打印」把日志刷爆（踩过一次）。
##
## 用法（导出包内也可跑）：
##   arisu.exe --script res://scripts/_probe_sog_decode.gd -- --cache=off

const SogRuntime := preload("res://scripts/sog_runtime.gd")

var _last_phase := ""
var _t0 := 0
var _marks: Array[String] = []


func _initialize() -> void:
	var source := "res://splatdata/room609.sogdata"
	var cache_mode := "off"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sog="):
			source = a.substr(6)
		elif a.begins_with("--cache="):
			cache_mode = a.substr(8)
	print("[decode] source=%s cache=%s" % [source, cache_mode])
	_t0 = Time.get_ticks_msec()
	# 手工「分段」：先自己确认文件能读、能开 ZIP，再调 load_sog
	print("[decode] ① file_exists=%s" % FileAccess.file_exists(source))
	var raw := FileAccess.get_file_as_bytes(source)
	print("[decode] ② 读到 %d 字节" % raw.size())
	var zip := ZIPReader.new()
	var err := zip.open(source)
	print("[decode] ③ ZIP open err=%d files=%s" % [
		err, str(zip.get_files()) if err == OK else "<打不开>"])
	if err == OK:
		zip.close()
	print("[decode] ④ 开始 load_sog（cache=%s）" % cache_mode)
	var r: Dictionary = SogRuntime.load_sog(source, {"cache": cache_mode, "progress": _on_progress})
	print("[decode] ⑤ ok=%s count=%s ms=%d msg=%s" % [
		r.get("ok"), r.get("count"), Time.get_ticks_msec() - _t0, r.get("message")])
	print("[decode] 阶段历史: %s" % ", ".join(_marks))
	quit()


## ⚠️ 用成员变量去重（lambda 按值捕获局部变量，去重会失效）
func _on_progress(phase: String, done: int, total: int) -> void:
	if phase == _last_phase:
		return
	_last_phase = phase
	var line := "%s %d/%d t=%dms" % [phase, done, total, Time.get_ticks_msec() - _t0]
	_marks.append(line)
	print("[decode:phase] " + line)
