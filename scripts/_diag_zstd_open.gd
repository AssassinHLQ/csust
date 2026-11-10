extends SceneTree
## 调试：为什么 `FileAccess.open_compressed(..., COMPRESSION_ZSTD)` 打不开？
##
## 上一版 `_verify_zstd_stream.gd` 在这一步就 FAIL 了。本探针把每一步都摊开：
##  ① 文件到底写出来没有（大小、路径）
##  ② `PackedByteArray.compress` 各种模式的实际压缩比
##  ③ `open_compressed` 对 zstd / gzip 各自的返回，以及 `get_open_error()`
##  ④ 直接读回前 16 字节，看文件头魔数（zstd = 28 B5 2F FD；gzip = 1F 8B）
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_diag_zstd_open.gd

const SRC := "res://splatdata/campus_chunks10w/Chunk_5_5.bin"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("========== open_compressed 调试 ==========")
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		push_error("[dbg] 读不到样本")
		quit(1)
		return
	var raw := f.get_buffer(f.get_length())
	f.close()
	print("样本 %d 字节" % raw.size())

	var modes := [
		{"name": "FASTLZ", "v": FileAccess.COMPRESSION_FASTLZ},
		{"name": "DEFLATE", "v": FileAccess.COMPRESSION_DEFLATE},
		{"name": "ZSTD", "v": FileAccess.COMPRESSION_ZSTD},
		{"name": "GZIP", "v": FileAccess.COMPRESSION_GZIP},
	]
	print("\n── PackedByteArray.compress 各模式 ──")
	for m in modes:
		var c := raw.compress(int(m["v"]))
		var head := ""
		for i in mini(4, c.size()):
			head += "%02X " % c[i]
		print("  %-8s → %10d 字节（%.2f 倍）  头 %s" % [
			String(m["name"]), c.size(), float(raw.size()) / maxf(float(c.size()), 1.0), head])

	# 落盘各写一份，然后试着 open_compressed
	print("\n── 落盘 + open_compressed ──")
	for m in modes:
		var c2 := raw.compress(int(m["v"]))
		var p := "user://_dbg_%s.bin" % String(m["name"]).to_lower()
		var w := FileAccess.open(p, FileAccess.WRITE)
		if w == null:
			print("  %-8s 写不出来（open_write 失败 %d）" % [String(m["name"]), FileAccess.get_open_error()])
			continue
		w.store_buffer(c2)
		w.close()
		var abs_path := ProjectSettings.globalize_path(p)
		var st := FileAccess.open(p, FileAccess.READ)
		var on_disk := st.get_length() if st != null else -1
		if st != null:
			st.close()
		print("  %-8s 磁盘上 %d 字节（内存里 %d）→ %s" % [
			String(m["name"]), on_disk, c2.size(), abs_path])

		# 试 open_compressed（只对 ZSTD / GZIP 合法）
		if String(m["name"]) == "ZSTD" or String(m["name"]) == "GZIP":
			var g := FileAccess.open_compressed(p, FileAccess.READ, int(m["v"]))
			if g == null:
				print("       open_compressed → **null**（open_error = %d）" % FileAccess.get_open_error())
			else:
				print("       open_compressed → OK，get_length() = %d（原始 %d）" % [
					g.get_length(), raw.size()])
				g.close()
		DirAccess.remove_absolute(abs_path)

	print("\n（zstd 魔数应为 28 B5 2F FD；gzip 为 1F 8B）")
	quit(0)
