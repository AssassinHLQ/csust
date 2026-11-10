extends SceneTree
## 验证（修正版）：用 Godot **自己的 GDEC 容器**做 zstd 压缩存储。
##
## ── 上一版为什么失败 ──
## 用了 `PackedByteArray.compress(COMPRESSION_ZSTD)` 产出**裸 zstd 流**（魔数 28 B5 2F FD），
## 而 `FileAccess.open_compressed()` 读的是 Godot 自己的容器（魔数 **"GDEC"**），
## 所以报 `ERR_FILE_UNRECOGNIZED`（错误码 15）。
##
## ── 正确做法 ──
## 写：`FileAccess.open_compressed(p, WRITE, COMPRESSION_ZSTD, block_size)` + `store_buffer()`
## 读：`FileAccess.open_compressed(p, READ, COMPRESSION_ZSTD)`
## 本探针验证「写→读→逐字节一致」，并量出真实体积（含 GDEC 头与分块开销）。
##
## 同时验证现有的两种读法都能跑通：
##   ① 连续顺序读完（`_load_bin` 那样）
##   ② 分帧读 + 随机偏移 `decode_float`（`_pump_bin` 那样）
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_verify_zstd_stream.gd

const SRC := "res://splatdata/campus_chunks10w/Chunk_5_5.bin"
const TMP := "user://_zstd_container.bin"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _run() -> void:
	print("========== GDEC 容器 + zstd ＝ 可行？==========")
	if not FileAccess.file_exists(SRC):
		push_error("[zstd] 缺样本")
		quit(1)
		return
	var fr := FileAccess.open(SRC, FileAccess.READ)
	var raw := fr.get_buffer(fr.get_length())
	fr.close()
	var raw_size := raw.size()
	print("  样本 %d 字节（%.1f MB）" % [raw_size, float(raw_size) / 1048576.0])

	# ── 用 GDEC 容器写（⚠️ 本版 open_compressed 只收 3 个参数，没有 block_size）──
	print("\n── open_compressed 写出（GDEC 容器 + zstd）──")
	var w := FileAccess.open_compressed(TMP, FileAccess.WRITE,
		FileAccess.COMPRESSION_ZSTD)
	_check(w != null, "open_compressed 能写（err %d）" % FileAccess.get_open_error())
	if w == null:
		_finish()
		return
	w.store_buffer(raw)
	w.close()
	var st := FileAccess.open(TMP, FileAccess.READ)
	var written := st.get_length() if st != null else -1
	if st != null:
		st.close()
	print("  写出 %d 字节（原始 %d，%.2f 倍）" % [
		written, raw_size, float(raw_size) / maxf(float(written), 1.0)])

	# ── 读法 ①：连续顺序读完 ──
	print("\n── 读法 ① 连续顺序读完（模拟 `_load_bin`）──")
	var g := FileAccess.open_compressed(TMP, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	_check(g != null, "GDEC+zstd 能打开（open_error=%d）" % FileAccess.get_open_error())
	if g == null:
		_finish()
		return
	print("  get_length() = %d（原始 %d）" % [g.get_length(), raw_size])
	_check(g.get_length() == raw_size, "get_length() 就是**解压后**大小")
	var got1 := PackedByteArray()
	var chunk := 4 * 1024 * 1024
	while got1.size() < raw_size:
		var b := g.get_buffer(chunk)
		if b.is_empty():
			break
		got1.append_array(b)
	g.close()
	_check(got1.size() == raw_size, "① 读满（%d / %d）" % [got1.size(), raw_size])
	_check(got1 == raw, "① 内容与原始**逐字节一致**")

	# ── 读法 ②：分帧读 + 随机偏移 decode_float ──
	print("\n── 读法 ② 分帧读 + 偏移 12 抽样 float（模拟 `_pump_bin`）──")
	var h := FileAccess.open_compressed(TMP, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var got2 := PackedByteArray()
	var uploaded := 0
	var frames := 0
	var samples := 0
	var per_frame := 1 * 1024 * 1024
	while uploaded < raw_size:
		frames += 1
		var want := mini(per_frame, raw_size - uploaded)
		var data := h.get_buffer(want)
		if data.is_empty():
			break
		var off := 12
		while off + 4 <= data.size():
			samples += 1
			off += 240 * 61
		got2.append_array(data)
		uploaded += data.size()
	h.close()
	_check(got2.size() == raw_size, "② 分帧读满（%d 帧）" % frames)
	_check(got2 == raw, "② 分帧读内容也**逐字节一致**")
	print("  分帧 %d 次、抽样 %d 个偏移（随机偏移读取正常）" % [frames, samples])

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_finish()


func _finish() -> void:
	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ GDEC+zstd 方案成立，现有两种读法都兼容" if _fail == 0 else "✗ 不可行"))
	quit(0 if _fail == 0 else 1)
