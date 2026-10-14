@tool
extends RefCounted
## 运行时 SOG 加载器 —— 不经过 Godot 导入管线
##
## 背景：GDGS 插件通过 EditorImportPlugin 把 .sog 展开成 GaussianResource 并写进
## res://.godot/imported/*.res。一份 86 MB 的 SOG 展开后约 2.89 GB（6,150,154 点 ×
## 60 float × 4 B），导出时会被整份塞进 PCK，于是 exe 变成 3.15 GB。
##
## 本加载器在运行时直接读 .sog 归档并现场展开，导出包只带原始 86 MB，不再带导入产物。
##
## 与导入器的差异（有意为之，且经过逐项比对验证）：
##   1. 只产出渲染真正需要的字段：point_count / point_data_byte / xyz / aabb。
##      point_data_float 仅被编辑器的碰撞管线使用
##      （collision/pipeline/splat_source.gd），运行时不需要 —— 不生成它，
##      直接省掉 6.15M × 240 B ≈ 1.48 GB 的重复副本。
##   2. 解码与打包融合成同一遍循环，不保留 canonical 中间数组
##      （导入器里那份 sh_coeffs 单独就是 1.18 GB）。
##   3. 数学逐式对齐导入器（sog_decoder.gd + gaussian_resource_builder.gd），
##      产出与导入结果一致；scripts/_selftest_runtime.gd 会做自动化比对。
##
## 应用默认不读写 user:// 展开缓存，每次启动都从压缩 SOG 重建运行资源。
## 仅显式传入 opts = {"cache": "auto" 或 "refresh"} 时才启用开发期缓存。

const SH_FLOAT_COUNT := 48
const STRUCT_SIZE := 60
const BYTES_PER_SPLAT := STRUCT_SIZE * 4          # 240
const SH_COEFFS_PER_BAND := {1: 3, 2: 8, 3: 15}
const SQRT2 := 1.4142135623730951
const CHUNK := 262144                              # 进度回调粒度
const CACHE_DIR := "user://splat_cache"
const CACHE_MAGIC := "GDGSRT01"

const SOURCE_NAMES := [
	"school_playable.sogdata", "school_playable.sog",
	"school.sogdata", "school.sog",
]

# 预先解析，避免在工作线程里现 load()：线程里只做纯数据展开。
const GaussianResourceScript := preload("res://addons/gdgs/runtime/resources/gaussian_resource.gd")

## SOG 归档的默认文件名（按优先级依次查找）
static func find_source(explicit: String = "") -> String:
	var candidates: Array[String] = []

	if explicit != "":
		candidates.append(explicit)

	# 命令行覆盖：Godot ... -- --sog=D:/path/to/x.sogdata
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sog="):
			candidates.append(arg.substr(6))
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--sog="):
			candidates.append(arg.substr(6))

	# 发布版：可执行文件同级 splatdata/ （或直接同级）
	var exe_dir := OS.get_executable_path().get_base_dir()
	for n in SOURCE_NAMES:
		candidates.append(exe_dir.path_join("splatdata").path_join(n))
	for n in SOURCE_NAMES:
		candidates.append(exe_dir.path_join(n))

	# 用户目录，便于不想动安装目录的场景
	for n in SOURCE_NAMES:
		candidates.append("user://splatdata/".path_join(n))

	# 编辑器内：项目里的原始归档
	for n in SOURCE_NAMES:
		candidates.append("res://splatdata/".path_join(n))
	for n in SOURCE_NAMES:
		candidates.append("res://assets/".path_join(n))

	for c in candidates:
		if c != "" and FileAccess.file_exists(c):
			return c
	return ""


## 展开 .sog 为 GaussianResource。
##
## opts:
##   progress : Callable(phase: String, done: int, total: int)  —— 进度回调（可选）
##   cache    : "off"（默认）| "auto" | "refresh"；应用始终使用 off
##   center   : Vector3 —— 跳过中心化第一遍，直接用给定中心（仅显式缓存模式使用）
##
## 返回：{ok, resource, count, aabb, source, elapsed_ms, from_cache, message, error}
static func load_sog(sog_path: String, opts: Dictionary = {}) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var progress: Callable = opts.get("progress", Callable())
	var cache_mode := String(opts.get("cache", "off"))
	var center_hint: Variant = opts.get("center", null)

	if not FileAccess.file_exists(sog_path):
		return _fail(ERR_FILE_NOT_FOUND, "找不到 SOG 文件：%s" % sog_path)

	# ---- 元数据 ----
	var archive := ZIPReader.new()
	var open_error := archive.open(sog_path)
	if open_error != OK:
		return _fail(open_error, "无法打开 SOG 归档：%s" % sog_path)

	var meta := _read_meta(archive)
	if not bool(meta.get("ok", false)):
		archive.close()
		return meta
	var info: Dictionary = meta["info"]

	# ---- 缓存尝试：off 模式不探测、不创建缓存目录 ----
	var source_stamp: Dictionary = {}
	var cache_path := ""
	if cache_mode != "off":
		source_stamp = _source_stamp(sog_path)
		cache_path = _cache_path(sog_path, source_stamp)
		if cache_mode != "refresh":
			var cached := _read_cache(cache_path, info, source_stamp, progress)
			if bool(cached.get("ok", false)):
				archive.close()
				cached["source"] = sog_path
				cached["elapsed_ms"] = Time.get_ticks_msec() - t0
				cached["from_cache"] = true
				return cached

	# ---- 纹理解码 ----
	_emit(progress, "textures", 0, 1)
	var textures := _decode_textures(archive, info)
	archive.close()
	if not bool(textures.get("ok", false)):
		return textures
	_emit(progress, "textures", 1, 1)

	var count: int = info["count"]
	var means_l: PackedByteArray = textures["means_l"]
	var means_u: PackedByteArray = textures["means_u"]
	var scales_data: PackedByteArray = textures["scales"]
	var quats_data: PackedByteArray = textures["quats"]
	var sh0_data: PackedByteArray = textures["sh0"]
	var shn_centroids: PackedByteArray = textures["shn_centroids"]
	var shn_labels: PackedByteArray = textures["shn_labels"]
	var shn_centroid_width: int = textures["shn_centroid_width"]
	var coeffs_per_channel: int = textures["coeffs_per_channel"]
	var palette_count: int = textures["palette_count"]
	var mins: Vector3 = info["means_mins"]
	var maxs: Vector3 = info["means_maxs"]
	var scales_codebook: PackedFloat32Array = textures["scales_codebook"]
	var sh0_codebook: PackedFloat32Array = textures["sh0_codebook"]
	var shn_codebook: PackedFloat32Array = textures["shn_codebook"]

	# ---- 第一遍：算术均值中心（与导入器 builder 完全同序累加）----
	var center := Vector3.ZERO
	if center_hint is Vector3:
		center = center_hint
	else:
		var step := maxi(1, count / 64)
		for i in count:
			var o := i * 3
			var qx := (int(means_u[o + 0]) << 8) | int(means_l[o + 0])
			var qy := (int(means_u[o + 1]) << 8) | int(means_l[o + 1])
			var qz := (int(means_u[o + 2]) << 8) | int(means_l[o + 2])
			center += Vector3(
				_unlog(_lerp_range(mins.x, maxs.x, float(qx) / 65535.0)),
				_unlog(_lerp_range(mins.y, maxs.y, float(qy) / 65535.0)),
				_unlog(_lerp_range(mins.z, maxs.z, float(qz) / 65535.0))
			)
			if i % step == 0:
				_emit(progress, "center", i, count)
		center /= float(count)
	_emit(progress, "center", count, count)

	# ---- 第二遍：融合解码 + 打包 ----
	var points := PackedFloat32Array()
	points.resize(count * STRUCT_SIZE)
	var xyz := PackedVector3Array()
	xyz.resize(count)

	var aabb_min := Vector3(INF, INF, INF)
	var aabb_max := Vector3(-INF, -INF, -INF)
	var has_shn := coeffs_per_channel > 0

	for i in count:
		var rgb := i * 3
		var rgba := i * 4

		# --- 位置：means_l/means_u 合成 16 bit 后反 log ---
		var qx := (int(means_u[rgb + 0]) << 8) | int(means_l[rgb + 0])
		var qy := (int(means_u[rgb + 1]) << 8) | int(means_l[rgb + 1])
		var qz := (int(means_u[rgb + 2]) << 8) | int(means_l[rgb + 2])
		var pos := Vector3(
			_unlog(_lerp_range(mins.x, maxs.x, float(qx) / 65535.0)),
			_unlog(_lerp_range(mins.y, maxs.y, float(qy) / 65535.0)),
			_unlog(_lerp_range(mins.z, maxs.z, float(qz) / 65535.0))
		) - center

		# --- 尺度：codebook 查表后取指数 ---
		var scale_linear := Vector3(
			maxf(exp(scales_codebook[int(scales_data[rgb + 0])]), 1e-6),
			maxf(exp(scales_codebook[int(scales_data[rgb + 1])]), 1e-6),
			maxf(exp(scales_codebook[int(scales_data[rgb + 2])]), 1e-6)
		)

		# --- 旋转：SOG 只存 3 个分量，第 4 个由单位长度反解 ---
		var mode := int(quats_data[rgba + 3]) - 252
		if mode < 0 or mode > 3:
			return _fail(ERR_INVALID_DATA, "SOG 四元数打包模式非法（第 %d 个点）" % i)
		var rotation := _decode_quaternion(
			int(quats_data[rgba + 0]), int(quats_data[rgba + 1]), int(quats_data[rgba + 2]), mode
		).normalized()

		# --- 3D 协方差（与 builder 同式同序）---
		var scale_mat := Basis.from_scale(scale_linear)
		var rot_mat := Basis(rotation).transposed()
		var cov_3d := (scale_mat * rot_mat).transposed() * (scale_mat * rot_mat)

		var base := i * STRUCT_SIZE
		points[base + 0] = pos.x
		points[base + 1] = pos.y
		points[base + 2] = pos.z
		points[base + 3] = 0.0
		points[base + 4] = cov_3d.x[0]
		points[base + 5] = cov_3d.y[0]
		points[base + 6] = cov_3d.z[0]
		points[base + 7] = cov_3d.y[1]
		points[base + 8] = cov_3d.z[1]
		points[base + 9] = cov_3d.z[2]
		points[base + 10] = clampf(float(sh0_data[rgba + 3]) / 255.0, 0.0, 1.0)
		points[base + 11] = 0.0

		# --- 球谐：DC 项查 sh0 codebook ---
		var sh_off := base + 12
		points[sh_off + 0] = sh0_codebook[int(sh0_data[rgba + 0])]
		points[sh_off + 1] = sh0_codebook[int(sh0_data[rgba + 1])]
		points[sh_off + 2] = sh0_codebook[int(sh0_data[rgba + 2])]

		# --- 球谐：高阶项经调色板标签取质心 ---
		if has_shn:
			var label := int(shn_labels[rgba + 0]) | (int(shn_labels[rgba + 1]) << 8)
			if label >= palette_count:
				return _fail(ERR_INVALID_DATA, "SOG shN 标签越界（第 %d 个点）" % i)
			var centroid_y := int(label / 64)
			var centroid_x_base := (label % 64) * coeffs_per_channel
			var centroid_offset := (centroid_y * shn_centroid_width + centroid_x_base) * 3
			if centroid_offset < 0 or centroid_offset + coeffs_per_channel * 3 > shn_centroids.size():
				return _fail(ERR_INVALID_DATA, "SOG shN 质心纹理布局越界（第 %d 个点）" % i)
			for k in coeffs_per_channel:
				var texel_offset := centroid_offset + k * 3
				var dst := sh_off + 3 + k * 3
				points[dst + 0] = shn_codebook[int(shn_centroids[texel_offset + 0])]
				points[dst + 1] = shn_codebook[int(shn_centroids[texel_offset + 1])]
				points[dst + 2] = shn_codebook[int(shn_centroids[texel_offset + 2])]

		xyz[i] = pos
		aabb_min = aabb_min.min(pos)
		aabb_max = aabb_max.max(pos)

		if i % CHUNK == 0:
			_emit(progress, "decode", i, count)

	_emit(progress, "decode", count, count)

	# ---- 打包成 GPU 就绪的字节块（唯一的 float 副本在这里转成 byte）----
	# 先 to_byte_array() 再释放 float 数组：峰值 ≈ 3 GB，之后常驻 1.5 GB。
	# point_data_float 有意留空：运行时没有任何消费者。
	_emit(progress, "pack", 0, 1)
	var blob := points.to_byte_array()
	points = PackedFloat32Array()
	_emit(progress, "pack", 1, 1)

	var resource := _make_resource(count, blob, xyz, aabb_min, aabb_max)

	# ---- 写缓存（不影响本次结果）----
	if cache_mode != "off":
		_emit(progress, "cache", 0, 1)
		_write_cache(cache_path, info, source_stamp, blob, xyz, center)
		_emit(progress, "cache", 1, 1)

	return {
		"ok": true,
		"resource": resource,
		"count": count,
		"aabb": resource.aabb,
		"center": center,
		"source": sog_path,
		"elapsed_ms": Time.get_ticks_msec() - t0,
		"from_cache": false,
	}


## 只解出元数据与（可选的）中心，用于加载界面预热或诊断。
static func probe(sog_path: String) -> Dictionary:
	var archive := ZIPReader.new()
	var open_error := archive.open(sog_path)
	if open_error != OK:
		return _fail(open_error, "无法打开 SOG 归档：%s" % sog_path)
	var meta := _read_meta(archive)
	archive.close()
	return meta


static func cache_info(sog_path: String) -> Dictionary:
	var archive := ZIPReader.new()
	if archive.open(sog_path) != OK:
		return {"exists": false}
	var meta := _read_meta(archive)
	archive.close()
	if not bool(meta.get("ok", false)):
		return {"exists": false}
	var path := _cache_path(sog_path, _source_stamp(sog_path))
	return {"exists": FileAccess.file_exists(path), "path": path, "info": meta["info"]}


static func clear_cache() -> int:
	var dir := DirAccess.open(CACHE_DIR)
	if dir == null:
		return 0
	var removed := 0
	for f in dir.get_files():
		if dir.remove(f) == OK:
			removed += 1
	return removed


# ---------------------------------------------------------------- 元数据

static func _read_meta(archive: ZIPReader) -> Dictionary:
	var meta_bytes := archive.read_file("meta.json")
	if meta_bytes.is_empty():
		return _fail(ERR_FILE_NOT_FOUND, "SOG 归档缺少 meta.json")
	var parsed = JSON.parse_string(meta_bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail(ERR_INVALID_DATA, "SOG meta.json 不是合法 JSON")
	var meta: Dictionary = parsed
	if int(meta.get("version", -1)) != 2:
		return _fail(ERR_UNAVAILABLE, "只支持 SOG v2（该文件为 %s）" % str(meta.get("version")))
	var count := int(meta.get("count", 0))
	if count <= 0:
		return _fail(ERR_INVALID_DATA, "SOG meta.json 里没有合法的点数")

	var means_meta: Dictionary = meta.get("means", {})
	var means_files: Array = means_meta.get("files", [])
	if means_files.size() < 2:
		return _fail(ERR_INVALID_DATA, "SOG means 元数据不完整")

	var info := {
		"count": count,
		"means_l_file": String(means_files[0]),
		"means_u_file": String(means_files[1]),
		"means_mins": _to_vector3(means_meta.get("mins", [])),
		"means_maxs": _to_vector3(means_meta.get("maxs", [])),
	}

	var scales_meta: Dictionary = meta.get("scales", {})
	var scales_files: Array = scales_meta.get("files", [])
	if scales_files.is_empty():
		return _fail(ERR_INVALID_DATA, "SOG scales 元数据不完整")
	info["scales_file"] = String(scales_files[0])
	info["scales_codebook"] = _to_float_array(scales_meta.get("codebook", []))

	var quats_meta: Dictionary = meta.get("quats", {})
	var quats_files: Array = quats_meta.get("files", [])
	if quats_files.is_empty():
		return _fail(ERR_INVALID_DATA, "SOG quats 元数据不完整")
	info["quats_file"] = String(quats_files[0])

	var sh0_meta: Dictionary = meta.get("sh0", {})
	var sh0_files: Array = sh0_meta.get("files", [])
	if sh0_files.is_empty():
		return _fail(ERR_INVALID_DATA, "SOG sh0 元数据不完整")
	info["sh0_file"] = String(sh0_files[0])
	info["sh0_codebook"] = _to_float_array(sh0_meta.get("codebook", []))

	info["has_shn"] = false
	info["coeffs_per_channel"] = 0
	info["palette_count"] = 0
	info["shn_codebook"] = PackedFloat32Array()
	info["shn_centroids_file"] = ""
	info["shn_labels_file"] = ""

	if meta.has("shN"):
		var shn_meta: Dictionary = meta["shN"]
		var bands := int(shn_meta.get("bands", 0))
		if not SH_COEFFS_PER_BAND.has(bands):
			return _fail(ERR_INVALID_DATA, "SOG shN 的 bands=%d 不支持" % bands)
		var shn_files: Array = shn_meta.get("files", [])
		if shn_files.size() < 2:
			return _fail(ERR_INVALID_DATA, "SOG shN 元数据不完整")
		info["has_shn"] = true
		info["coeffs_per_channel"] = SH_COEFFS_PER_BAND[bands]
		info["bands"] = bands
		info["palette_count"] = int(shn_meta.get("count", 0))
		info["shn_codebook"] = _to_float_array(shn_meta.get("codebook", []))
		info["shn_centroids_file"] = String(shn_files[0])
		info["shn_labels_file"] = String(shn_files[1])
		if int(info["palette_count"]) <= 0:
			return _fail(ERR_INVALID_DATA, "SOG shN 调色板数量非法")

	return {"ok": true, "info": info}


# ---------------------------------------------------------------- 纹理

static func _decode_textures(archive: ZIPReader, info: Dictionary) -> Dictionary:
	var count: int = info["count"]

	var means_l := _load_image(archive, String(info["means_l_file"]), Image.FORMAT_RGB8)
	if not bool(means_l.get("ok", false)):
		return means_l
	var means_u := _load_image(archive, String(info["means_u_file"]), Image.FORMAT_RGB8)
	if not bool(means_u.get("ok", false)):
		return means_u
	var scales := _load_image(archive, String(info["scales_file"]), Image.FORMAT_RGB8)
	if not bool(scales.get("ok", false)):
		return scales
	var quats := _load_image(archive, String(info["quats_file"]), Image.FORMAT_RGBA8)
	if not bool(quats.get("ok", false)):
		return quats
	var sh0 := _load_image(archive, String(info["sh0_file"]), Image.FORMAT_RGBA8)
	if not bool(sh0.get("ok", false)):
		return sh0

	var dims := Vector2i(int(means_l["width"]), int(means_l["height"]))
	for other in [means_u, scales, quats, sh0]:
		if int(other["width"]) != dims.x or int(other["height"]) != dims.y:
			return _fail(ERR_INVALID_DATA, "SOG 各张纹理尺寸不一致")
	if count > dims.x * dims.y:
		return _fail(ERR_INVALID_DATA, "SOG 纹理图集装不下 %d 个点" % count)

	var scales_codebook: PackedFloat32Array = info["scales_codebook"]
	var sh0_codebook: PackedFloat32Array = info["sh0_codebook"]
	if scales_codebook.size() < 256 or sh0_codebook.size() < 256:
		return _fail(ERR_INVALID_DATA, "SOG codebook 必须各有 256 项")

	var result := {
		"ok": true,
		"means_l": means_l["data"],
		"means_u": means_u["data"],
		"scales": scales["data"],
		"quats": quats["data"],
		"sh0": sh0["data"],
		"scales_codebook": scales_codebook,
		"sh0_codebook": sh0_codebook,
		"shn_centroids": PackedByteArray(),
		"shn_labels": PackedByteArray(),
		"shn_centroid_width": 1,
		"coeffs_per_channel": 0,
		"palette_count": 0,
		"shn_codebook": PackedFloat32Array(),
	}

	if bool(info.get("has_shn", false)):
		var centroids := _load_image(archive, String(info["shn_centroids_file"]), Image.FORMAT_RGB8)
		if not bool(centroids.get("ok", false)):
			return centroids
		var labels := _load_image(archive, String(info["shn_labels_file"]), Image.FORMAT_RGBA8)
		if not bool(labels.get("ok", false)):
			return labels
		if int(labels["width"]) != dims.x or int(labels["height"]) != dims.y:
			return _fail(ERR_INVALID_DATA, "SOG shN 标签纹理尺寸与主图集不一致")
		var shn_codebook: PackedFloat32Array = info["shn_codebook"]
		if shn_codebook.size() < 256:
			return _fail(ERR_INVALID_DATA, "SOG shN codebook 必须含 256 项")
		result["shn_centroids"] = centroids["data"]
		result["shn_labels"] = labels["data"]
		result["shn_centroid_width"] = int(centroids["width"])
		result["coeffs_per_channel"] = int(info["coeffs_per_channel"])
		result["palette_count"] = int(info["palette_count"])
		result["shn_codebook"] = shn_codebook

	return result


static func _load_image(archive: ZIPReader, filename: String, target_format: int) -> Dictionary:
	var bytes := archive.read_file(filename)
	if bytes.is_empty():
		return _fail(ERR_FILE_NOT_FOUND, "SOG 归档缺少条目 '%s'" % filename)
	var image := Image.new()
	var load_error := image.load_webp_from_buffer(bytes)
	if load_error != OK:
		return _fail(load_error, "无法解码 WebP '%s'" % filename)
	if image.get_format() != target_format:
		image.convert(target_format)
	return {
		"ok": true,
		"width": image.get_width(),
		"height": image.get_height(),
		"data": image.get_data(),
	}


# ---------------------------------------------------------------- 资源 / 缓存

static func _make_resource(count: int, blob: PackedByteArray, xyz: PackedVector3Array, aabb_min: Vector3, aabb_max: Vector3) -> Resource:
	var resource: Resource = GaussianResourceScript.new()
	resource.set("point_count", count)
	resource.set("point_data_byte", blob)
	resource.set("xyz", xyz)
	# point_data_float 有意留空：运行时无消费者，留着等于再花 1.48 GB
	resource.set("aabb", AABB(aabb_min, aabb_max - aabb_min))
	return resource


static func _source_stamp(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var size := f.get_length() if f != null else -1
	if f != null:
		f.close()
	return {"size": size, "mtime": FileAccess.get_modified_time(path)}


static func _cache_path(source: String, stamp: Dictionary) -> String:
	var key := "%s-%s-%s" % [source.get_file().get_basename(), str(stamp["size"]), str(stamp["mtime"])]
	return CACHE_DIR.path_join("%s.gdgsrt" % key)


static func _write_cache(path: String, info: Dictionary, stamp: Dictionary, blob: PackedByteArray, xyz: PackedVector3Array, center: Vector3) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var header := {
		"source_size": int(stamp["size"]),
		"source_mtime": int(stamp["mtime"]),
		"count": int(info["count"]),
		"bytes_per_splat": BYTES_PER_SPLAT,
		"center": [center.x, center.y, center.z],
	}
	var header_bytes := JSON.stringify(header).to_utf8_buffer()
	var tmp := path + ".part"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(CACHE_MAGIC.to_ascii_buffer())
	f.store_32(header_bytes.size())
	f.store_buffer(header_bytes)
	f.store_buffer(blob)
	f.store_buffer(xyz.to_byte_array())
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)


static func _read_cache(path: String, info: Dictionary, stamp: Dictionary, progress: Callable) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false}

	_emit(progress, "cache", 0, 1)
	var magic := f.get_buffer(CACHE_MAGIC.length()).get_string_from_ascii()
	if magic != CACHE_MAGIC:
		f.close()
		return {"ok": false}
	var header_len := f.get_32()
	if f.get_length() < CACHE_MAGIC.length() + 4 + header_len:
		f.close()
		return {"ok": false}
	var header = JSON.parse_string(f.get_buffer(header_len).get_string_from_utf8())
	if typeof(header) != TYPE_DICTIONARY:
		f.close()
		return {"ok": false}
	var h: Dictionary = header
	var count: int = info["count"]
	if int(h.get("count", -1)) != count \
			or int(h.get("source_size", -1)) != int(stamp["size"]) \
			or int(h.get("source_mtime", -1)) != int(stamp["mtime"]) \
			or int(h.get("bytes_per_splat", -1)) != BYTES_PER_SPLAT:
		f.close()
		return {"ok": false}

	var blob_size := count * BYTES_PER_SPLAT
	var xyz_size := count * 12
	var expected := CACHE_MAGIC.length() + 4 + header_len + blob_size + xyz_size
	if f.get_length() != expected:
		f.close()
		return {"ok": false}

	var blob := f.get_buffer(blob_size)
	if blob.size() != blob_size:
		f.close()
		return {"ok": false}
	_emit(progress, "cache", 1, 2)

	var xyz_floats := f.get_buffer(xyz_size).to_float32_array()
	f.close()
	if xyz_floats.size() != count * 3:
		return {"ok": false}

	var xyz := PackedVector3Array()
	xyz.resize(count)
	var aabb_min := Vector3(INF, INF, INF)
	var aabb_max := Vector3(-INF, -INF, -INF)
	for i in count:
		var o := i * 3
		var p := Vector3(xyz_floats[o + 0], xyz_floats[o + 1], xyz_floats[o + 2])
		xyz[i] = p
		aabb_min = aabb_min.min(p)
		aabb_max = aabb_max.max(p)
	_emit(progress, "cache", 2, 2)

	var resource := _make_resource(count, blob, xyz, aabb_min, aabb_max)
	var cached_center := Vector3.ZERO
	var raw_center = h.get("center", null)
	if typeof(raw_center) == TYPE_ARRAY and raw_center.size() >= 3:
		cached_center = Vector3(float(raw_center[0]), float(raw_center[1]), float(raw_center[2]))
	return {
		"ok": true,
		"resource": resource,
		"count": count,
		"aabb": resource.aabb,
		"center": cached_center,
		"message": "缓存命中：%s" % path,
	}


# ---------------------------------------------------------------- 小工具

static func _emit(progress: Callable, phase: String, done: int, total: int) -> void:
	if progress.is_valid():
		progress.call(phase, done, total)


static func _to_vector3(values: Array) -> Vector3:
	return Vector3(
		float(values[0]) if values.size() > 0 else 0.0,
		float(values[1]) if values.size() > 1 else 0.0,
		float(values[2]) if values.size() > 2 else 0.0
	)


static func _to_float_array(values: Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(values.size())
	for i in values.size():
		result[i] = float(values[i])
	return result


static func _decode_quaternion(a: int, b: int, c: int, mode: int) -> Quaternion:
	var comps := [0.0, 0.0, 0.0, 0.0]
	var decoded := [
		(float(a) / 255.0 - 0.5) * SQRT2,
		(float(b) / 255.0 - 0.5) * SQRT2,
		(float(c) / 255.0 - 0.5) * SQRT2
	]
	var decoded_idx := 0
	var sum_sq := 0.0
	for component_idx in 4:
		if component_idx == mode:
			continue
		comps[component_idx] = decoded[decoded_idx]
		sum_sq += decoded[decoded_idx] * decoded[decoded_idx]
		decoded_idx += 1
	comps[mode] = sqrt(maxf(0.0, 1.0 - sum_sq))
	return Quaternion(comps[1], comps[2], comps[3], comps[0]).normalized()


static func _unlog(value: float) -> float:
	var sign_value := -1.0 if value < 0.0 else 1.0
	return sign_value * (exp(abs(value)) - 1.0)


static func _lerp_range(min_value: float, max_value: float, normalized: float) -> float:
	return min_value + (max_value - min_value) * normalized


static func _fail(code: Error, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}
