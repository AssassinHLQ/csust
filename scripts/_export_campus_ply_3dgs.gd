extends SceneTree
## 把 SOG 导成标准 3DGS PLY（62 个 float：xyz + 法线 + f_dc + f_rest + opacity + scale + rot），
## 给 2Retr0/GodotGaussianSplatting 的 GPU 光栅器做基准测试。
##   _tools/run_probe.sh res://scripts/_export_campus_ply_3dgs.gd -- --force
##
## 约定（对应 util/ply_file.gd）：
##   opacity = logit(p)，scale = log(linear)，rot = (w, x, y, z)
##   f_rest 按标准布局：前 15 个 R、再 15 个 G、再 15 个 B
## 坐标用 SOG 源坐标（不乘世界缩放），缩放由 viewer 的 model_scale 控制。

const SOG := "res://splatdata/school_playable.sogdata"
const OUT := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/campus_3dgs.ply"
const SogDecoder := preload("res://addons/gdgs/importers/decoders/sog_decoder.gd")
const CHUNK := 20000


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if FileAccess.file_exists(OUT) and not OS.get_cmdline_user_args().has("--force"):
		print("[ply3dgs] 已存在：%s" % OUT)
		quit(0)
		return
	var t0 := Time.get_ticks_msec()
	var decoded: Dictionary = SogDecoder.decode(SOG)
	if not decoded.get("ok", false):
		print("[ply3dgs] SOG 解码失败：%s" % str(decoded))
		quit(1)
		return
	var c: Dictionary = decoded["canonical"]
	var pos: PackedVector3Array = c["positions"]
	var scales: PackedVector3Array = c["scales_linear"]
	var rots: Array = c["rotations"]
	var opac: PackedFloat32Array = c["opacities"]
	var sh: PackedFloat32Array = c["sh_coeffs"]
	var n := pos.size()
	print("[ply3dgs] 解码 %d 点，%d ms" % [n, Time.get_ticks_msec() - t0])

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		print("[ply3dgs] 打不开输出")
		quit(1)
		return
	var props := PackedStringArray(["x", "y", "z", "nx", "ny", "nz",
		"f_dc_0", "f_dc_1", "f_dc_2"])
	for i in 45:
		props.append("f_rest_%d" % i)
	props.append_array(["opacity", "scale_0", "scale_1", "scale_2",
		"rot_0", "rot_1", "rot_2", "rot_3"])
	var header := "ply\nformat binary_little_endian 1.0\nelement vertex %d\n" % n
	for p in props:
		header += "property float %s\n" % p
	header += "end_header\n"
	f.store_buffer(header.to_utf8_buffer())

	var buf := PackedFloat32Array()
	var t1 := Time.get_ticks_msec()
	var i := 0
	while i < n:
		var count := mini(CHUNK, n - i)
		var need := count * 62
		if buf.size() != need:
			buf.resize(need)
		var b := 0
		for j in count:
			var k := i + j
			var p := pos[k]
			buf[b + 0] = p.x
			buf[b + 1] = p.y
			buf[b + 2] = p.z
			# 法线留 0（viewer 不用）
			var so := k * 48
			buf[b + 6] = sh[so + 0]
			buf[b + 7] = sh[so + 1]
			buf[b + 8] = sh[so + 2]
			# f_rest: R 15 / G 15 / B 15
			for m in 15:
				buf[b + 9 + m] = sh[so + 3 + m * 3]
				buf[b + 24 + m] = sh[so + 3 + m * 3 + 1]
				buf[b + 39 + m] = sh[so + 3 + m * 3 + 2]
			var op := clampf(opac[k], 1e-6, 1.0 - 1e-6)
			buf[b + 54] = log(op / (1.0 - op))
			var sc := scales[k]
			buf[b + 55] = log(maxf(sc.x, 1e-12))
			buf[b + 56] = log(maxf(sc.y, 1e-12))
			buf[b + 57] = log(maxf(sc.z, 1e-12))
			var q: Quaternion = rots[k]
			buf[b + 58] = q.w
			buf[b + 59] = q.x
			buf[b + 60] = q.y
			buf[b + 61] = q.z
			b += 62
		f.store_buffer(buf.to_byte_array())
		i += count
		if (i % 600000) == 0:
			print("[ply3dgs] %d / %d" % [i, n])
	f.close()
	print("[ply3dgs] 完成 %d 点，写出 %.1f MB，用时 %.1f s" % [n,
		float(FileAccess.get_file_as_bytes(OUT).size()) / 1048576.0,
		float(Time.get_ticks_msec() - t1) / 1000.0])
	print("[ply3dgs] 文件：%s" % OUT)
	quit(0)
