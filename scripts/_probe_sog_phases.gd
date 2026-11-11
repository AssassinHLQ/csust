extends SceneTree
## 量：校园 SOG 解码 40 秒里，**每一段各占多少**。
##
## 用户 2026-11-11：「测量一下看看」——目标是判断「搬到 C# 值不值」。
##
## `load_sog()` 的流程（见 `scripts/sog_runtime.gd`）：
##   ① ZIP 打开 + `_read_meta`            —— Godot C++ 侧
##   ② `_decode_textures`（图像解码）      —— Godot C++ 侧
##   ③ 第一遍：遍历 6.15M 点算算术均值中心 —— GDScript 循环
##   ④ 第二遍：逐点反量化 + 组装 60 float  —— GDScript 循环（最重）
##   ⑤ `points.to_byte_array()` 打包       —— C++ 侧大拷贝
##   ⑥ `_make_resource`
##
## 切开办法（不改 `sog_runtime.gd` 一个字）：
##   · ①② 单独调用静态函数计时；
##   · ④⑤⑥ = 带 `center` 跑一次（跳过 ③）再减去 ①②；
##   · ③ = 不带 center 减 带 center。
##
## 只解码、**不写盘**（cache = "off"）。
##
##   godot --headless --script res://scripts/_probe_sog_phases.gd

const SogRuntime := preload("res://scripts/sog_runtime.gd")

const SCHOOL := "res://splatdata/school_playable.sogdata"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	get_root().get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("[ph] !! 超时（900 s）")
		quit(3))

	if not FileAccess.file_exists(SCHOOL):
		print("[ph] !! 找不到 %s" % SCHOOL)
		quit(1)
		return

	print("[ph] ==== 校园 SOG 解码分段计时（只解码，不写盘）====")
	print("[ph] 静态内存起点: %.1f MB" % (OS.get_static_memory_usage() / 1048576.0))

	# ---------- ①② 前置：ZIP 打开 + meta + 纹理解码 ----------
	var t0 := Time.get_ticks_msec()
	var arch := ZIPReader.new()
	var err := arch.open(SCHOOL)
	var t_open := Time.get_ticks_msec() - t0
	if err != OK:
		print("[ph] !! 打不开归档 err=%d" % err)
		quit(1)
		return

	t0 = Time.get_ticks_msec()
	var meta: Dictionary = SogRuntime._read_meta(arch)
	var t_meta := Time.get_ticks_msec() - t0
	if not bool(meta.get("ok", false)):
		print("[ph] !! meta 失败")
		quit(1)
		return
	var info: Dictionary = meta["info"]

	t0 = Time.get_ticks_msec()
	var tex: Dictionary = SogRuntime._decode_textures(arch, info)
	var t_tex := Time.get_ticks_msec() - t0
	arch.close()
	if not bool(tex.get("ok", false)):
		print("[ph] !! 纹理解码失败")
		quit(1)
		return
	print("[ph] ①② ZIP+meta：%d ms    纹理解码：%d ms" % [t_open + t_meta, t_tex])
	# 纹理字节块很占内存，量完立刻放掉
	# ⚠️ 类型化 Dictionary 不能赋 null，只能 clear()（GDScript 会报 Parse Error）
	tex.clear()

	# ---------- 完整跑一遍（含 ③ 第一遍）----------
	t0 = Time.get_ticks_msec()
	var full: Dictionary = SogRuntime.load_sog(SCHOOL, {"cache": "off"})
	var t_full := Time.get_ticks_msec() - t0
	if not bool(full.get("ok", false)):
		print("[ph] !! load_sog 失败：%s" % str(full.get("message", "?")))
		quit(1)
		return
	var count := int(full.get("count", 0))
	var center_hint: Vector3 = full.get("center", Vector3.ZERO)
	print("[ph] 完整解码：%d ms（%d 点）  center=%s"
		% [t_full, count, str(center_hint.snappedf(0.01))])
	# ⚠️ 必须放掉再跑第二遍：它自己就占 1.4 GB，留着会双倍吃内存
	full.clear()

	# ---------- 带 center 再跑一遍（跳过 ③）----------
	t0 = Time.get_ticks_msec()
	var hinted: Dictionary = SogRuntime.load_sog(SCHOOL,
			{"cache": "off", "center": center_hint})
	var t_hint := Time.get_ticks_msec() - t0
	if not bool(hinted.get("ok", false)):
		print("[ph] !! 第二次 load_sog 失败")
		quit(1)
		return
	hinted.clear()

	# ---------- 汇总 ----------
	var t_front := t_open + t_meta + t_tex
	var t_pass1 := t_full - t_hint            # ③ 第一遍：算中心
	var t_rest := t_hint - t_front            # ④⑤⑥ 第二遍 + 打包 + 组装
	if t_pass1 < 0:
		t_pass1 = 0

	print("")
	print("[ph] ==== 分段结果（总 %d ms）====" % t_full)
	_row("① ZIP 打开", t_open, t_full)
	_row("② 读 meta", t_meta, t_full)
	_row("③ 纹理解码（图像）", t_tex, t_full)
	_row("④ 第一遍：算中心", t_pass1, t_full)
	_row("⑤ 第二遍+打包+组装", t_rest, t_full)

	var cpp := t_front
	var gd := t_pass1 + t_rest
	print("")
	print("[ph] ── 按「谁在执行」归类 ──")
	_row("C++ 侧（①②③）", cpp, t_full)
	_row("GDScript 循环（④⑤）", gd, t_full)
	print("[ph] ⚠️ 注意：⑤ 里混了 `to_byte_array()` 和 `_make_resource`（C++ 侧大拷贝），")
	print("[ph]    它们算不进 ④⑤ 分开，所以「GDScript 占比」是**上限**。")
	print("[ph]    room609 的 ③ 第一遍同比例可参照本条推算。")

	var out_mb := count * 240.0 / 1048576.0
	print("")
	print("[ph] 解出字节数 %.1f MB（240 B/点，要写进 _cache 的量）" % out_mb)
	print("[ph] 静态内存终点: %.1f MB（⚠️ 这只是**结束时刻**，峰值更高）"
		% (OS.get_static_memory_usage() / 1048576.0))
	print("[ph] ==== 完 ====")
	quit(0)


func _row(name: String, ms: int, total: int) -> void:
	var pct := 0.0 if total <= 0 else float(ms) * 100.0 / float(total)
	print("[ph]   %-22s %7d ms   %5.1f%%" % [name, ms, pct])
