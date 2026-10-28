extends SceneTree
## 把 Campus 泼溅节点里已打包的 60-float 点数据变换到**世界坐标**，写成 GGS 光栅器
## 可直接上传的 .bin（6.15M × 60 × 4B ≈ 1.48 GB）。
##   _tools/run_probe.sh res://scripts/_export_campus_ggs_bin.gd -- --force
##
## 布局（和 addons/ggs_campus 的 std430 Splat 一致）：
##   0..2 position, 3 time, 4..9 covariance 上三角, 10 opacity, 11 pad, 12..59 SH
## 只变换 position 和 covariance（C' = R·C·Rᵀ·s²），opacity/SH 原样复制。

const OUT := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/campus_ggs.bin"
const CHUNK := 20000

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if FileAccess.file_exists(OUT) and not OS.get_cmdline_user_args().has("--force"):
		print("[bin] 已存在：%s" % OUT)
		quit(0)
		return
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var campus := level.get_node("Campus")
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	if not bool(campus.call("is_ready")):
		print("[bin] 校园没加载完")
		quit(1)
		return
	var node := campus.get("splat_node") as Node3D
	var res = node.get("gaussian")
	var n := int(res.get("point_count"))
	var src: PackedByteArray = res.get("point_data_byte")
	print("[bin] %d 点，源数据 %.1f MB" % [n, float(src.size()) / 1048576.0])

	var M := node.global_transform
	var R := M.basis.get_rotation_quaternion()
	var rb := Basis(R)
	var s := M.basis.get_scale().x
	print("[bin] 世界变换 scale=%.3f rot=%s" % [s, str(R)])

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		print("[bin] 打不开输出")
		quit(1)
		return
	var dst := PackedFloat32Array()
	var t1 := Time.get_ticks_msec()
	var i := 0
	while i < n:
		var count := mini(CHUNK, n - i)
		dst.resize(count * 60)
		var b := 0
		for j in count:
			var o := (i + j) * 240
			# 位置：splat 局部 → 世界
			var p := Vector3(src.decode_float(o), src.decode_float(o + 4), src.decode_float(o + 8))
			p = M * p
			dst[b + 0] = p.x
			dst[b + 1] = p.y
			dst[b + 2] = p.z
			dst[b + 3] = 0.0
			# 协方差：C' = R · C · Rᵀ · s²
			var c := Basis(
				Vector3(src.decode_float(o + 16), src.decode_float(o + 20), src.decode_float(o + 24)),
				Vector3(src.decode_float(o + 20), src.decode_float(o + 28), src.decode_float(o + 32)),
				Vector3(src.decode_float(o + 24), src.decode_float(o + 32), src.decode_float(o + 36)))
			var cw := rb * c * rb.transposed() * (s * s)
			dst[b + 4] = cw.x[0]
			dst[b + 5] = cw.y[0]
			dst[b + 6] = cw.z[0]
			dst[b + 7] = cw.y[1]
			dst[b + 8] = cw.z[1]
			dst[b + 9] = cw.z[2]
			dst[b + 10] = src.decode_float(o + 40)  # opacity
			dst[b + 11] = 0.0
			for k in 48:
				dst[b + 12 + k] = src.decode_float(o + 48 + k * 4)
			b += 60
		f.store_buffer(dst.to_byte_array())
		i += count
		if (i % 600000) == 0:
			print("[bin] %d / %d" % [i, n])
	f.close()
	print("[bin] 完成：%d 点，%.1f MB，%.1f s" % [n,
		float(FileAccess.get_file_as_bytes(OUT).size()) / 1048576.0,
		float(Time.get_ticks_msec() - t1) / 1000.0])
	quit(0)
