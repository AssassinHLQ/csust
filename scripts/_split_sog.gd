extends SceneTree
## 离线把一份 .sogdata 按源坐标的 XZ 网格切成 N 块，并生成分块场景（逐块视锥剔除用）。
##
##   _tools/run_probe.sh res://scripts/_split_sog.gd -- --input=res://splatdata/school_playable.sogdata
##   （先试运行看统计，不加 --write 不会写文件）
##   _tools/run_probe.sh res://scripts/_split_sog.gd -- --input=... --write
##
## 参数（都可省）：
##   --input=res://splatdata/school_playable.sogdata
##   --nx=3 --nz=3                     网格块数（x/z）
##   --out-dir=res://splatdata/campus_chunks
##   --scene=res://scenes/campus_chunks.tscn
##   --scale=25                        SplatScene.world_scale
##   --top-gap=12                      与 subdivision 前一致（campus_venue.tscn 的 top_gap）
##   --node=0,24.48,-155.56            分块根节点世界位置（与原 Campus 节点一致）
##   --stagger=1.2                     第 i 块的 start_delay = 8 + i*stagger
##   --max-distance=140                分块管理器的距离上限
##   --write                           真正写文件
##
## 原理：SOG v2 是「meta.json + 6~7 张 WebP 图集」，每个点在图集里占一个像素
## （i → (i % W, i / W)）。切分**不改 mins/maxs 与 codebook**，只把每个点的像素
## 按空间网格重新装箱 —— 所以解码出来的坐标/尺度/四元数/颜色与原文件逐位一致，
## 各块之间的相对位置也不会变。
##
## 对齐：各块的 SplatScene 用 `auto_place = false` + **同一个 offset**（下面按原
## 文件的中心/内容盒算），根节点位置与原 Campus 节点相同 ⇒ 拼起来和原来完全重合。

const BYTES_PER_POINT_RGB := 3
const BYTES_PER_POINT_RGBA := 4
## 裁剪参数（与 next_level.tscn 里原 Campus 节点一致）
const CROP_MARGIN := 0.5


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return fallback


func _unlog(value: float) -> float:
	var s := -1.0 if value < 0.0 else 1.0
	return s * (exp(absf(value)) - 1.0)


func _load_zip_image(z: ZIPReader, name: String, fmt: int) -> Image:
	var bytes := z.read_file(name)
	if bytes.is_empty():
		push_error("缺少 %s" % name)
		return null
	var img := Image.new()
	if img.load_webp_from_buffer(bytes) != OK:
		push_error("解不开 %s" % name)
		return null
	if img.get_format() != fmt:
		img.convert(fmt)
	return img


func _percentile_box(pos: PackedVector3Array, keep_mask: PackedByteArray) -> AABB:
	# 与 sog_runtime :: content_bounds 同法：2 万点采样 + 0.1‰/99.9‰ 分位
	var n := pos.size()
	var step := maxi(1, n / 20000)
	var xs: Array[float] = []
	var ys: Array[float] = []
	var zs: Array[float] = []
	var i := 0
	while i < n:
		if keep_mask.is_empty() or keep_mask[i] == 1:
			xs.append(pos[i].x)
			ys.append(pos[i].y)
			zs.append(pos[i].z)
		i += step
	if xs.is_empty():
		return AABB()
	xs.sort()
	ys.sort()
	zs.sort()
	var m := xs.size()
	var lo := int(m * 0.001)
	var hi := mini(int(m * 0.999), m - 1)
	var mn := Vector3(xs[lo], ys[lo], zs[lo])
	var mx := Vector3(xs[hi], ys[hi], zs[hi])
	return AABB(mn, mx - mn)


## 按连续段整段复制（和 `_crop_resource` 一个套路，比逐点 append 快一个量级）。
func _filter_tex(src: PackedByteArray, bpp: int, idx: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	var n := idx.size()
	if n == 0:
		return out
	var run_start := int(idx[0])
	var prev := run_start
	for k in range(1, n):
		var i := int(idx[k])
		if i == prev + 1:
			prev = i
			continue
		out.append_array(src.slice(run_start * bpp, (prev + 1) * bpp))
		run_start = i
		prev = i
	out.append_array(src.slice(run_start * bpp, (prev + 1) * bpp))
	return out


func _run() -> void:
	var input := _arg("input", "res://splatdata/school_playable.sogdata")
	var nx := maxi(1, int(_arg("nx", "3")))
	var nz := maxi(1, int(_arg("nz", "3")))
	var out_dir := _arg("out-dir", "res://splatdata/campus_chunks")
	var scene_path := _arg("scene", "res://scenes/campus_chunks.tscn")
	var world_scale := float(_arg("scale", "25"))
	var top_gap := float(_arg("top-gap", "12"))
	var node_pos := Vector3.ZERO
	var np := _arg("node", "0,24.48,-155.56").split(",")
	if np.size() == 3:
		node_pos = Vector3(float(np[0]), float(np[1]), float(np[2]))
	var stagger := float(_arg("stagger", "1.2"))
	var max_distance := float(_arg("max-distance", "140"))
	var write := OS.get_cmdline_user_args().has("--write")
	# 只重算偏移/重写场景，不动已经写好的 chunk 文件（保住它们的解码缓存戳）
	var reuse := OS.get_cmdline_user_args().has("--reuse")

	var z := ZIPReader.new()
	if z.open(input) != OK:
		push_error("打不开 %s" % input)
		quit(1)
		return
	var meta: Dictionary = JSON.parse_string(z.read_file("meta.json").get_string_from_utf8())
	if meta.is_empty() or int(meta.get("version", 0)) != 2:
		push_error("不是 SOG v2")
		quit(1)
		return
	var count := int(meta["count"])
	var means: Dictionary = meta["means"]
	var mins := Vector3(means["mins"][0], means["mins"][1], means["mins"][2])
	var maxs := Vector3(means["maxs"][0], means["maxs"][1], means["maxs"][2])
	print("[split] %s：%d 点，网格 %d × %d" % [input, count, nx, nz])

	var t0 := Time.get_ticks_msec()
	var ml := _load_zip_image(z, "means_l.webp", Image.FORMAT_RGB8)
	var mu := _load_zip_image(z, "means_u.webp", Image.FORMAT_RGB8)
	var scales := _load_zip_image(z, "scales.webp", Image.FORMAT_RGB8)
	var quats := _load_zip_image(z, "quats.webp", Image.FORMAT_RGBA8)
	var sh0 := _load_zip_image(z, "sh0.webp", Image.FORMAT_RGBA8)
	var has_shn := meta.has("shN")
	var labels: Image = null
	var centroids_bytes := PackedByteArray()
	if has_shn:
		labels = _load_zip_image(z, "shN_labels.webp", Image.FORMAT_RGBA8)
		centroids_bytes = z.read_file("shN_centroids.webp")
	print("[split] 解图集 %d ms" % (Time.get_ticks_msec() - t0))

	var ml_d := ml.get_data()
	var mu_d := mu.get_data()
	var t1 := Time.get_ticks_msec()
	# ── 解出所有点的源坐标（决定分块 + 中心/内容盒）──
	var pos := PackedVector3Array()
	pos.resize(count)
	var sum := Vector3.ZERO
	for i in count:
		var o := i * BYTES_PER_POINT_RGB
		var qx := (int(mu_d[o]) << 8) | int(ml_d[o])
		var qy := (int(mu_d[o + 1]) << 8) | int(ml_d[o + 1])
		var qz := (int(mu_d[o + 2]) << 8) | int(ml_d[o + 2])
		var p := Vector3(
			_unlog(mins.x + (maxs.x - mins.x) * float(qx) / 65535.0),
			_unlog(mins.y + (maxs.y - mins.y) * float(qy) / 65535.0),
			_unlog(mins.z + (maxs.z - mins.z) * float(qz) / 65535.0))
		pos[i] = p
		sum += p
	var center := sum / float(count)
	print("[split] 解坐标 %d ms" % (Time.get_ticks_msec() - t1))

	# ── 原内容盒（0.1‰~99.9‰）→ 裁剪（margin 0.5），与线上一致 ──
	var box := _percentile_box(pos, PackedByteArray())
	var crop_lo := box.position - Vector3.ONE * CROP_MARGIN
	var crop_hi := box.position + box.size + Vector3.ONE * CROP_MARGIN
	var keep := PackedByteArray()
	keep.resize(count)
	var kept := 0
	for i in count:
		var p := pos[i]
		var k: int = 1 if (p.x >= crop_lo.x and p.x <= crop_hi.x \
			and p.y >= crop_lo.y and p.y <= crop_hi.y \
			and p.z >= crop_lo.z and p.z <= crop_hi.z) else 0
		keep[i] = k
		kept += k
	print("[split] 裁剪盒 %s ~ %s → 留 %d / %d（丢 %d）"
		% [str(crop_lo.snappedf(0.01)), str(crop_hi.snappedf(0.01)), kept, count, count - kept])

	# 裁剪后的内容盒（分块 offset 要用它的 max.y）
	var kept_box := _percentile_box(pos, keep)
	print("[split] 裁剪后内容盒 pos %s size %s"
		% [str(kept_box.position.snappedf(0.01)), str(kept_box.size.snappedf(0.01))])
	# 单份泼溅的 auto_place 偏移（中心用**内容盒中心**，不是点的算术均值）
	var bc := kept_box.position + kept_box.size * 0.5
	var offset_single := Vector3(-bc.x * world_scale,
		-top_gap - (kept_box.position.y + kept_box.size.y) * world_scale,
		-bc.z * world_scale)
	# ⚠️ 关键：`SogRuntime.load_sog` 会把**每个文件**的点减去它自己的算术均值。
	#    所以每块的 offset 还要加回「本块均值 − 全文件均值」× scale，
	#    否则所有块都会以各自的均值为原点、挤在同一个位置（第一版就是这样）。
	var offset := offset_single
	print("[split] 统一 offset = %s（节点 %s）" % [str(offset), str(node_pos)])

	# ── 按裁剪盒的 XZ 网格分桶 ──
	var buckets: Array[PackedInt32Array] = []
	buckets.resize(nx * nz)
	for k in buckets.size():
		buckets[k] = PackedInt32Array()
	var gw := maxf(box.size.x, 0.001)
	var gd := maxf(box.size.z, 0.001)
	for i in count:
		if keep[i] == 0:
			continue
		var p := pos[i]
		var ix := clampi(int((p.x - box.position.x) / gw * float(nx)), 0, nx - 1)
		var iz := clampi(int((p.z - box.position.z) / gd * float(nz)), 0, nz - 1)
		var b := iz * nx + ix
		buckets[b].append(i)
	# 索引升序 → 连续段复制
	for b in buckets.size():
		buckets[b].sort()

	if not write:
		print("[split] 试运行结束（加 --write 才写文件）")
		for b in buckets.size():
			print("  块 %d：%d 点" % [b, buckets[b].size()])
		z.close()
		quit(0)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var meta_base: Dictionary = meta.duplicate(true)
	var chunk_files: Array[String] = []
	var chunk_offsets: Array[Vector3] = []
	chunk_offsets.resize(buckets.size())
	var t_write := Time.get_ticks_msec()
	for b in buckets.size():
		var idx := buckets[b]
		var n := idx.size()
		if n == 0:
			continue
		var ix := b % nx
		var iz := b / nx
		var w_f := int(ceil(sqrt(float(n))))
		var h_f := int(ceil(float(n) / float(w_f)))
		var need := w_f * h_f
		var chunk_meta: Dictionary = meta_base.duplicate(true)
		chunk_meta["count"] = n

		# 本块所有点的算术均值（= 游戏里 load_sog 会减去的 center）
		var csum := Vector3.ZERO
		for i in idx:
			csum += pos[int(i)]
		var c_i := csum / float(n)
		var chunk_offset: Vector3 = offset_single + (c_i - center) * world_scale
		chunk_offsets[b] = chunk_offset
		var out_path := ProjectSettings.globalize_path(out_dir).path_join("chunk_%d_%d.sogdata" % [ix, iz])
		if reuse and FileAccess.file_exists(out_path):
			chunk_files.append(out_path)
			print("[split] 复用 chunk_%d_%d：%d 点，offset %s" % [ix, iz, n, str(chunk_offset.snappedf(0.01))])
			continue
		var zp := ZIPPacker.new()
		if zp.open(out_path) != OK:
			push_error("写不了 %s" % out_path)
			continue
		# meta
		zp.start_file("meta.json")
		zp.write_file(JSON.stringify(chunk_meta, " ", false).to_utf8_buffer())
		zp.close_file()
		# 逐张图集过滤
		var tex_specs := [
			["means_l.webp", ml_d, BYTES_PER_POINT_RGB, Image.FORMAT_RGB8],
			["means_u.webp", mu_d, BYTES_PER_POINT_RGB, Image.FORMAT_RGB8],
			["scales.webp", scales.get_data(), BYTES_PER_POINT_RGB, Image.FORMAT_RGB8],
			["quats.webp", quats.get_data(), BYTES_PER_POINT_RGBA, Image.FORMAT_RGBA8],
			["sh0.webp", sh0.get_data(), BYTES_PER_POINT_RGBA, Image.FORMAT_RGBA8],
		]
		if has_shn:
			tex_specs.append(["shN_labels.webp", labels.get_data(), BYTES_PER_POINT_RGBA, Image.FORMAT_RGBA8])
		for spec in tex_specs:
			var data := _filter_tex(spec[1], int(spec[2]), idx)
			# 补齐到最后一行（图集必须 W×H 完整）
			if data.size() < need * int(spec[2]):
				data.resize(need * int(spec[2]))
			var img := Image.create_from_data(w_f, h_f, false, int(spec[3]), data)
			zp.start_file(str(spec[0]))
			zp.write_file(img.save_webp_to_buffer(false))   # 无损，像素逐位不变
			zp.close_file()
		if has_shn:
			# 调色板整张复制
			zp.start_file("shN_centroids.webp")
			zp.write_file(centroids_bytes)
			zp.close_file()
		zp.close()
		chunk_files.append(out_path)
		print("[split] 写 chunk_%d_%d：%d 点、%d×%d" % [ix, iz, n, w_f, h_f])
	print("[split] 写盘 %d ms" % (Time.get_ticks_msec() - t_write))

	# ── 生成分块场景 ──
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[gd_scene load_steps=%d format=3]" % (chunk_files.size() + 3))
	lines.append("")
	lines.append("; 由 scripts/_split_sog.gd 生成：%s 切成 %d × %d 块。" % [input.get_file(), nx, nz])
	lines.append("; 每块共用同一个 offset，拼起来与原校园节点完全重合。")
	lines.append("; 重新切分：_tools/run_probe.sh res://scripts/_split_sog.gd -- --write")
	lines.append("")
	lines.append('[ext_resource type="Script" path="res://scripts/campus_chunks.gd" id="1_mgr"]')
	lines.append('[ext_resource type="Script" path="res://scripts/splat_scene.gd" id="2_splat"]')
	lines.append("")
	lines.append('[node name="CampusChunks" type="Node3D"]')
	lines.append('script = ExtResource("1_mgr")')
	lines.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.2f, %.2f, %.2f)" % [node_pos.x, node_pos.y, node_pos.z])
	lines.append("max_distance = %.2f" % max_distance)
	var i_chunk := 0
	for b in buckets.size():
		var idx := buckets[b]
		if idx.size() == 0:
			continue
		var ix := b % nx
		var iz := b / nx
		lines.append("")
		lines.append('[node name="Chunk_%d_%d" type="Node3D" parent="."]' % [ix, iz])
		lines.append('script = ExtResource("2_splat")')
		lines.append('sog_path = "%s/chunk_%d_%d.sogdata"' % [out_dir, ix, iz])
		lines.append('display_name = "校园"')
		lines.append('venue = "campus"')
		lines.append('cache_mode = "auto"')
		lines.append("world_scale = %.2f" % world_scale)
		lines.append("yaw_degrees = 0.0")
		lines.append("auto_place = false")
		var co: Vector3 = chunk_offsets[b]
		lines.append("offset = Vector3(%.4f, %.4f, %.4f)" % [co.x, co.y, co.z])
		lines.append("crop_enabled = false")
		lines.append("use_default_orientation = false")
		lines.append("start_delay = %.2f" % (8.0 + float(i_chunk) * stagger))
		lines.append("start_distance = 0.0")
		lines.append("low_priority = true")
		lines.append("preload_on_gate = false")
		i_chunk += 1
	var scene_text := "\n".join(lines) + "\n"
	var f := FileAccess.open(scene_path, FileAccess.WRITE)
	if f != null:
		f.store_string(scene_text)
		f.close()
		print("[split] 场景 %s（%d 块）" % [scene_path, i_chunk])
	else:
		push_error("写不了 %s" % scene_path)
	z.close()
	quit(0)
