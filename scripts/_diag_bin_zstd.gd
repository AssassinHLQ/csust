extends SceneTree
## 测量：校园泼溅用 **zstd** 压缩后能到多少（决定"能不能压进 1 GB"）。
##
## 背景：当前 `splatdata/campus_chunks10w/*` 是**未压缩 float32**（每点 240 字节），
## 合计 1,406 MB，占了整个包的一半以上。
##
## 本探针用 **Godot 自带的 zstd**（`PackedByteArray.compress(COMPRESSION_ZSTD)`）——
## 这就是运行时 `FileAccess.open_compressed()` 会用的同一个编解码器，
## 所以量出来的数字可以直接当设计依据（不是拿外部工具估的）。
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_diag_bin_zstd.gd

## 抽几个有代表性的文件量（全量 1.4 GB 跑太久）
const SAMPLES := [
	"splatdata/campus_chunks10w/Chunk_6_7.bin",
	"splatdata/campus_chunks10w/Chunk_5_7.bin",
	"splatdata/campus_chunks10w/Chunk_5_5.bin",
	"campus_ggs_q4.bin",
	"splatdata/room609.sogdata",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("========== zstd 压缩率实测（引擎自带编解码器）==========")
	print("%-46s %10s %10s %8s" % ["文件", "原始 MB", "zstd MB", "压缩比"])

	var tot_raw := 0.0
	var tot_z := 0.0
	for p in SAMPLES:
		var path := "res://%s" % p
		if not FileAccess.file_exists(path):
			print("  %-44s （不存在）" % p)
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var raw := f.get_buffer(f.get_length())
		f.close()
		var t0 := Time.get_ticks_msec()
		var z := raw.compress(FileAccess.COMPRESSION_ZSTD)
		var ms := Time.get_ticks_msec() - t0
		var rmb := float(raw.size()) / 1048576.0
		var zmb := float(z.size()) / 1048576.0
		print("%-46s %10.1f %10.1f %7.1fx   （压缩耗时 %.0f ms）" % [
			p.get_file(), rmb, zmb, rmb / maxf(zmb, 0.001), float(ms)])
		# 只把校园那两类的量累加（room609/sog 不参与打包估算）
		if p.contains("campus_chunks10w") or p.contains("campus_ggs_q4"):
			tot_raw += rmb
			tot_z += zmb

	print("")
	print("── 校园部分（细层抽样 + 粗层）──")
	if tot_raw > 0.0:
		print("  原始 合计 %.1f MB → zstd 后 %.1f MB（%.1f 倍）" % [
			tot_raw, tot_z, tot_raw / maxf(tot_z, 0.001)])
		# 按这个比例外推到全量
		var full_raw := 1406.5 + 351.6
		var ratio := tot_raw / maxf(tot_z, 0.001)
		print("  外推到全量（细层 1406.5 + 粗层 351.6 = %.1f MB）" % full_raw)
		print("    ⇒ 压缩后约 **%.0f MB**（省 %.0f MB）" % [
			full_raw / ratio, full_raw - full_raw / ratio])

	print("\n（注：解压由引擎原生做，比 GDScript 逐点解码快得多）")
	quit(0)
