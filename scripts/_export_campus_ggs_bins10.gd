extends SceneTree
## 把 10×10 分块的每一块，各导成一个 GGS 光栅器可上传的 .bin。
##
##   _tools/run_probe.sh res://scripts/_export_campus_ggs_bins10.gd -- --force
##
## 布局与 `_export_campus_ggs_bin.gd` **完全一致**（60 float / 点）：
##   0..2 position, 3 time, 4..9 covariance 上三角, 10 opacity, 11 pad, 12..59 SH
## 只变换 position 和 covariance（C' = R·C·Rᵀ·s²），opacity / SH 原样复制。
##
## 为什么按块导：全量一份 1.4 GB 没法流式加载。切块之后每块几十 MB，
## 运行时只上传玩家附近 3×3 那 9 块，其余根本不进显存。
##
## 分块场景由 `_split_sog.gd --nx=10 --nz=10` 生成（`scenes/campus_chunks10.tscn`），
## 每块是 `auto_place = false` + 共用 offset，所以 `global_transform` 拿到的就是
## 世界位置 —— 和全量那份逐块重合。

const SCENE := "res://scenes/campus_chunks10.tscn"
const OUT_DIR := "res://splatdata/campus_chunks10"
const CHUNK := 20000
const BYTES_PER_POINT := 240


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var force := OS.get_cmdline_user_args().has("--force")
	var level := (load(SCENE) as PackedScene).instantiate()
	if level == null:
		print("[bins] 打不开 %s" % SCENE)
		quit(1)
		return
	root.add_child(level)
	await process_frame

	var chunks := level.get_children()
	print("[bins] 分块 %d 个" % chunks.size())

	var total_pts := 0
	var total_bytes := 0
	var done := 0
	var t_all := Time.get_ticks_msec()

	for c in chunks:
		var nm := String(c.name)
		if not c.has_method("force_start"):
			continue
		c.call("force_start")
		var t0 := Time.get_ticks_msec()
		while not bool(c.call("is_ready")) and Time.get_ticks_msec() - t0 < 120000:
			await process_frame
		if not bool(c.call("is_ready")):
			print("[bins] %s 加载超时，跳过" % nm)
			continue

		var node := c.get("splat_node") as Node3D
		if node == null:
			print("[bins] %s 没有 splat_node，跳过" % nm)
			continue
		var res = node.get("gaussian")
		if res == null:
			print("[bins] %s 没有 gaussian，跳过" % nm)
			continue
		var n := int(res.get("point_count"))
		var src: PackedByteArray = res.get("point_data_byte")
		if n <= 0 or src.size() < n * BYTES_PER_POINT:
			print("[bins] %s 点数异常（%d），跳过" % [nm, n])
			continue

		var out_path := "%s/%s.bin" % [OUT_DIR, nm]
		if FileAccess.file_exists(out_path) and not force:
			print("[bins] %s 已存在，跳过（--force 覆盖）" % nm)
			continue

		var M := node.global_transform
		var R := M.basis.get_rotation_quaternion()
		var rb := Basis(R)
		var s := M.basis.get_scale().x

		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			print("[bins] 写不了 %s" % out_path)
			continue
		var written := 0
		var i := 0
		while i < n:
			var count := mini(CHUNK, n - i)
			var dst := PackedFloat32Array()
			dst.resize(count * 60)
			var b := 0
			for j in count:
				var o := (i + j) * BYTES_PER_POINT
				var p := Vector3(src.decode_float(o), src.decode_float(o + 4), src.decode_float(o + 8))
				p = M * p
				dst[b + 0] = p.x
				dst[b + 1] = p.y
				dst[b + 2] = p.z
				dst[b + 3] = 0.0
				var cc := Basis(
					Vector3(src.decode_float(o + 16), src.decode_float(o + 20), src.decode_float(o + 24)),
					Vector3(src.decode_float(o + 20), src.decode_float(o + 28), src.decode_float(o + 32)),
					Vector3(src.decode_float(o + 24), src.decode_float(o + 32), src.decode_float(o + 36)))
				var cw := rb * cc * rb.transposed() * (s * s)
				dst[b + 4] = cw.x[0]
				dst[b + 5] = cw.y[0]
				dst[b + 6] = cw.z[0]
				dst[b + 7] = cw.y[1]
				dst[b + 8] = cw.z[1]
				dst[b + 9] = cw.z[2]
				dst[b + 10] = src.decode_float(o + 40)
				dst[b + 11] = 0.0
				for k in 48:
					dst[b + 12 + k] = src.decode_float(o + 48 + k * 4)
				b += 60
			var narrow := dst.to_byte_array()
			f.store_buffer(narrow)
			written += narrow.size()
			i += count
		f.close()

		total_pts += n
		total_bytes += written
		done += 1
		print("[bins] %-14s %7d 点  %6.1f MB" % [nm, n, float(written) / 1048576.0])

		# 读完就放，别把 97 块的显存全攒着
		c.queue_free()
		await process_frame

	print("[bins] 完成 %d 块 / 合计 %d 点 / %.1f MB / 总耗时 %.1f s" % [
		done, total_pts, float(total_bytes) / 1048576.0,
		float(Time.get_ticks_msec() - t_all) / 1000.0])
	quit(0)
