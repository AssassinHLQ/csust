@tool
extends Resource

const TILE_SIZE = 16
const PlyFileScript = preload("res://addons/ggs_campus/ply_file.gd")
const RenderContextScript = preload("res://addons/ggs_campus/render_context.gd")
const WORKGROUP_SIZE = 512 # Same as defined in `radix_sort_upsweep.glsl`
const RADIX = 256 # Same as defined in `radix_sort_upsweep.glsl`
const PARTITION_DIVISION = 8 # Same as defined in `radix_sort_upsweep.glsl`
const PARTITION_SIZE = PARTITION_DIVISION * WORKGROUP_SIZE # Same as defined in `radix_sort_upsweep.glsl`

signal loaded

var context
var shaders : Dictionary
var pipelines : Dictionary
var descriptors : Dictionary
var descriptor_sets : Dictionary

var point_cloud
var render_texture : Texture2DRD
var camera : Camera3D
var camera_projection : Projection
var camera_transform : Projection
var camera_push_constants : PackedByteArray

var tile_dims = Vector2i.ZERO
var texture_size : Vector2i :
	set(value):
		texture_size = (value * render_scale[0]).max(Vector2i.ONE)
		tile_dims = (texture_size + Vector2i.ONE*(TILE_SIZE - 1)) / TILE_SIZE
		if not descriptors.has('render_texture') or not context: return
		# Rebuild gsplat_boundaries and gsplat_render pielines (since those depend on texture size)
		# ⚠️ 2026-11-06 修：这里原来会 `render_texture = Texture2DRD.new()`
		#    （原注释写着 "FIXME: idk why I have to do this"）—— **不能这么做**。
		#    ① 每变一次尺寸就丢掉调用方（`campus_ggs.gd` 的 `tex`）持有的那个对象，
		#       调用方随即把自己的 `texture_rd_rid` 指过来，那一下会去释放一个
		#       已经被 `context.free()` 还掉的 RID ⇒ `ERROR: Attempted to free invalid ID`。
		#    ② 这里本来就只是「换了一张纹理」，**对象可以复用**：把新 RID 交给它即可。
		#    `campus_ggs.gd` 每帧会比对 `tex.texture_rd_rid` 与
		#    `render_texture.texture_rd_rid`，不同就同步，所以 quad 也不会指着旧纹理。
		context.deletion_queue.free_rid(context.device, descriptors['tile_bounds'].rid)
		context.deletion_queue.free_rid(context.device, descriptors['render_texture'].rid)
		
		# FIXME: ERM MEMORY LEAK?!
		#context.device.free_rid(pipelines['gsplat_boundaries'])
		#context.device.free_rid(pipelines['gsplat_render'])
		
		descriptors['tile_bounds'] = context.create_storage_buffer(tile_dims.x*tile_dims.y * 2*4)
		descriptors['render_texture'] = context.create_texture(texture_size, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
		
		var boundaries_set = context.create_descriptor_set([descriptors['histogram'], descriptors['sort_keys'], descriptors['tile_bounds']], shaders['boundaries'], 0)
		var render_set = context.create_descriptor_set([descriptors['culled_splats'], descriptors['sort_values'], descriptors['tile_bounds'], descriptors['tile_splat_pos'], descriptors['render_texture']], shaders['render'], 0)
		
		pipelines['gsplat_boundaries'] = context.create_pipeline([], [boundaries_set], shaders['boundaries'])
		pipelines['gsplat_render'] = context.create_pipeline([tile_dims.x, tile_dims.y, 1], [render_set], shaders['render'])
		# 同 `init_gpu()` 里的说明：换纹理前先摘掉旧 RID，避免释放无效 RID。
		if render_texture.texture_rd_rid.is_valid():
			render_texture.texture_rd_rid = RID()
		render_texture.texture_rd_rid = descriptors['render_texture'].rid

var load_thread = Thread.new()
var is_loaded = false
var should_enable_heatmap = [false]
var render_scale = [1.0]
var model_scale = [1.0]
## 椭球（协方差）的额外缩放，**不作用于位置**（见 shader 里 `cov_scale` 那段注释）。
##
## 用数组是为了和 `model_scale` 一致：调用方拿到的如果是值拷贝，
## 直接赋值改不到光栅器内部；数组是引用，改 `[0]` 就能生效。
## 默认 1.0 = 和以前完全一样的行为。
var cov_scale = [1.0]
## 逐点协方差钳制：`[cap, ref]`（单位 m² / 特征值）。
##   `cap` 单个点的最大特征值上限，0 = 不钳；
##   `ref` 中位数点的特征值，>0 时整体乘 1/ref。
## 详见 `shaders/gsplat_projection.glsl` 顶部那段推导（2026-11-09 修校园泼溅）。
## 用数组的理由同 `cov_scale`。默认 `[0, 0]` = 老行为。
var cov_limit = [0.0, 0.0]
var should_terminate_thread : Array[bool] = [false]
## 若设置，则直接从预打包的 60-float 世界坐标 bin 上传，跳过 PLY 解析/打包。
var bin_path := ""
var _bin_file: FileAccess
var _bin_total := 0
var _bin_uploaded := 0
var _bin_loading := false
var num_splats_loaded : Array[int] = [0]
var basis_override = Basis.IDENTITY

## ── 静止帧复用（2026-11-05，用户反馈「好卡」）──
##
## 相机和视口都没变的那一帧，投影 + 基数排序 + raster 的输出和上一帧**逐像素相同**
## （`gsplat_render.glsl` 对本块每个像素都 `imageStore`），所以整条 compute 链可以直接
## 不跑，把上一帧的纹理继续交给 `main_sky.gdshader` 合成。判据精确等价，不是近似。
##
## `campus_ggs.gd` 每帧的顺序是 `update_camera_matrices()` → `rasterize()`，
## 前者把「相机到底动了没有」记在 `_camera_changed` 里给后者用。
## 关掉对照：`-- --ggs-idle-skip=off`
var idle_skip := true
var _camera_changed := true
var _rendered_once := false
var _last_size := Vector2i.ZERO
## 入场动画结束的**引擎时刻**（毫秒）。`gsplat_projection.glsl` 算的是
## `splat_time = time - splat.time`，`ease_out_cubic(clamp(...,0,1))` 在 1 s 后恒为 1、
## `time_factor_late` 还多减 0.35 ⇒ **max(splat.time) + 1.35 s 之后时间不再影响画面**。
## 这个 max 在上传过程中顺手抽样读出来（见 `_pump_bin`），不是拍一个固定秒数 ——
## 拍短了会把入场动画冻在半透明状态，那是看得出来的 bug。
const INTRO_ANIM_SECONDS := 1.35
const INTRO_MARGIN_MS := 400
var intro_end_ms := 0
var _splat_time_max := 0.0

func _init(point_cloud, output_texture_size : Vector2i, render_texture : Texture2DRD, camera : Camera3D) -> void:
	self.point_cloud = point_cloud
	self.texture_size = output_texture_size
	self.render_texture = render_texture
	self.camera = camera

func init_gpu() -> void:
	var _t_alloc := Time.get_ticks_usec()
	assert(render_texture, 'An output Texture2DRD must be set!')
	# --- DEVICE/SHADER CREATION ---
	# We have to use `RenderingServer.get_rendering_device()` as Texture2DRD can only be used
	# on the main rendering device.
	context = RenderContextScript.create(RenderingServer.get_rendering_device())
	var projection_shader = context.load_shader('res://addons/ggs_campus/shaders/gsplat_projection.glsl')
	var radix_sort_upsweep_shader = context.load_shader('res://addons/ggs_campus/shaders/radix_sort_upsweep.glsl')
	var radix_sort_spine_shader = context.load_shader('res://addons/ggs_campus/shaders/radix_sort_spine.glsl')
	var radix_sort_downsweep_shader = context.load_shader('res://addons/ggs_campus/shaders/radix_sort_downsweep.glsl')
	shaders['boundaries'] = context.load_shader('res://addons/ggs_campus/shaders/gsplat_boundaries.glsl')
	shaders['render'] = context.load_shader('res://addons/ggs_campus/shaders/gsplat_render.glsl')
	
	# --- DESCRIPTOR PREPARATION ---
	var num_sort_elements_max = point_cloud.size * 10 # FIXME: This should not be a static value!
	var num_partitions = (num_sort_elements_max + PARTITION_SIZE - 1) / PARTITION_SIZE
	var block_dims : PackedInt32Array; block_dims.resize(2*3); block_dims.fill(1)
	
	# ── 大缓冲**不填零**（2026-11-05）──
	# 实测：`init_gpu` 分配 644 MB 要 **733 ms**、205 MB 要 364 ms —— 这就是「换窗口
	# 卡顿」的真正来源（不是上传，上传只要 1~6 帧、最坏单块 26 ms）。
	# 钱几乎全花在 `create_storage_buffer` 的**填零**上：它给每个缓冲都准备一份
	# 等长的零 `PackedByteArray` 再交给 `storage_buffer_create`，几百 MB 的
	# malloc+清零+上传纯属白做。下面四个缓冲在用之前都会被整份覆盖：
	#   · `splats`         ← `_pump_bin()` 把 bin 全部写进去
	#   · `culled_splats`  ← 投影着色器只写「发出的那些」条目
	#   · `sort_keys`      ← 投影着色器写；基数排序只读 `[0, element_count)`
	#   · `sort_values`    ← downsweep 只写 `[0, element_count)`
	# （`element_count` 取自 histogram 的首个 uint，每帧由 CPU 清 0。）
	descriptors['splats'] = context.create_storage_buffer(point_cloud.size * 60*4, [], 0, false)
	# 12 个 float × 4 字节 = **48**。std140 布局（见 `gsplat_projection.glsl` 的 Uniforms）：
	#   vec3 camera_pos(0..11) / float model_scale(12) / ivec2 dims(16..23) /
	#   float time(24) / float cov_scale(28) / vec2 cov_limit(32..39) / 两个 pad 到 48。
	# ⚠️ 曾经写成 8*4=32 与 10*4=40，都触发
	#    `Uniform buffer supplied (N) is smaller than size of shader uniform: (48)`，
	#    descriptor set 建不出来 ⇒ 投影 pass 整条不跑。
	descriptors['uniforms'] = context.create_uniform_buffer(12*4)
	descriptors['culled_splats'] = context.create_storage_buffer(point_cloud.size * 12*4, [], 0, false)
	descriptors['grid_dimensions'] = context.create_storage_buffer(2*3*4, block_dims.to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	descriptors['histogram'] = context.create_storage_buffer(4 + (1 + 4*RADIX + num_partitions*RADIX)*4)
	descriptors['sort_keys'] = context.create_storage_buffer(num_sort_elements_max*4*2, [], 0, false)
	descriptors['sort_values'] = context.create_storage_buffer(num_sort_elements_max*4*2, [], 0, false)
	descriptors['tile_bounds'] = context.create_storage_buffer(tile_dims.x*tile_dims.y * 2*4)
	descriptors['tile_splat_pos'] = context.create_storage_buffer(4*4)
	descriptors['render_texture'] = context.create_texture(texture_size, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
	# 新纹理在数据到位之前是**未初始化**的。上传改成分帧预算之后，「细层还没传完」
	# 会持续很多帧，所以这里必须先清成透明 —— 否则合成时细层会用垃圾像素盖掉粗层
	# （`main_sky.gdshader` 是按 alpha 把细层混在粗层上面的）。
	context.device.texture_clear(descriptors['render_texture'].rid, Color(0, 0, 0, 0), 0, 1, 0, 1)
	
	var projection_set = context.create_descriptor_set([descriptors['splats'], descriptors['culled_splats'], descriptors['histogram'], descriptors['sort_keys'], descriptors['sort_values'], descriptors['grid_dimensions'], descriptors['uniforms']], projection_shader, 0)
	var radix_sort_upsweep_set = context.create_descriptor_set([descriptors['histogram'], descriptors['sort_keys']], radix_sort_upsweep_shader, 0)
	var radix_sort_spine_set = context.create_descriptor_set([descriptors['histogram']], radix_sort_spine_shader, 0)
	var radix_sort_downsweep_set = context.create_descriptor_set([descriptors['histogram'], descriptors['sort_keys'], descriptors['sort_values']], radix_sort_downsweep_shader, 0)
	var boundaries_set = context.create_descriptor_set([descriptors['histogram'], descriptors['sort_keys'], descriptors['tile_bounds']], shaders['boundaries'], 0)
	var render_set = context.create_descriptor_set([descriptors['culled_splats'], descriptors['sort_values'], descriptors['tile_bounds'], descriptors['tile_splat_pos'], descriptors['render_texture']], shaders['render'], 0)
	
	# ⚠️ 2026-11-06：这里是把**同一个 Texture2DRD 对象**从「没有纹理」带到「有纹理」。
	#    如果它上面还挂着上一次（已被 `context.free()` 还掉的）RID，这次赋值就会去
	#    释放一个无效 RID ⇒ `Attempted to free invalid ID`（栈顶就是这一行）。
	#    先显式摘掉旧 RID 兜底 —— 任何没走 `cleanup_gpu()` 就重建的路径都不会再踩。
	if render_texture.texture_rd_rid.is_valid():
		render_texture.texture_rd_rid = RID()
	render_texture.texture_rd_rid = descriptors['render_texture'].rid
	
	# --- COMPUTE PIPELINE CREATION ---
	# 2026-11-05：把「分配缓冲」和「编译/建管线」分开计时 —— 实测换窗口卡顿的大头
	# 是分配（填零），见上面「大缓冲不填零」那段说明。
	var _t_buffers := Time.get_ticks_usec()
	pipelines['gsplat_projection'] = context.create_pipeline([ceili(point_cloud.size/256.0), 1, 1], [projection_set], projection_shader)
	pipelines['radix_sort_upsweep'] = context.create_pipeline([], [radix_sort_upsweep_set], radix_sort_upsweep_shader)
	pipelines['radix_sort_spine'] = context.create_pipeline([RADIX, 1, 1], [radix_sort_spine_set], radix_sort_spine_shader)
	pipelines['radix_sort_downsweep'] = context.create_pipeline([], [radix_sort_downsweep_set], radix_sort_downsweep_shader)
	pipelines['gsplat_boundaries'] = context.create_pipeline([], [boundaries_set], shaders['boundaries'])
	pipelines['gsplat_render'] = context.create_pipeline([tile_dims.x, tile_dims.y, 1], [render_set], shaders['render'])
	
	# 4.7: 主 RenderingDevice 的 buffer_update 不能从 WorkerThreadPool 调；
	# 这里在调用线程（Compositor/render thread）同步上传。加载会卡一下，先验证渲染。
	should_terminate_thread[0] = false
	num_splats_loaded[0] = 0
	# 2026-11-05：把「分配缓冲 + 编译着色器」这一段单独计时 ——
	# 换窗口的卡顿主要嫌疑就是它（每换一次要重建约 450 MB 的缓冲和 6 个着色器）。
	var mb := float(point_cloud.size) * 448.0 / 1048576.0
	print("[ggs] init_gpu：缓冲 %.0f MB 用 %.1f ms，管线用 %.1f ms，合计 %.1f ms" % [
		mb, float(_t_buffers - _t_alloc) / 1000.0,
		float(Time.get_ticks_usec() - _t_buffers) / 1000.0,
		float(Time.get_ticks_usec() - _t_alloc) / 1000.0])
	if bin_path != "":
		_begin_bin_load(point_cloud.size)
		is_loaded = false
	else:
		PlyFileScript.load_gaussian_splats(point_cloud, point_cloud.size / 1000,
			context.device, descriptors['splats'].rid, should_terminate_thread,
			num_splats_loaded, func(): pass)
		is_loaded = true

func _begin_bin_load(count : int) -> void:
	_bin_file = FileAccess.open(bin_path, FileAccess.READ)
	if _bin_file == null:
		push_error("[ggs] 打不开 bin: %s" % bin_path)
		return
	_bin_total = count * 240
	_bin_uploaded = 0
	_bin_loading = true
	num_splats_loaded[0] = 0
	_upload_chunk = 1 * 1024 * 1024
	_upload_worst_ms = 0.0
	_upload_frames = 0
	_upload_started_ms = Time.get_ticks_msec()
	_splat_time_max = 0.0
	intro_end_ms = 0
	print("[ggs] bin 开始分帧上传：%.0f MB（每帧预算 %.1f ms）" % [
		float(_bin_total) / 1048576.0, upload_budget_ms])

## 每帧最多上传 PER_FRAME；返回 true 表示还在加载。
func pump_load() -> void:
	if not context: init_gpu()
	if _bin_loading:
		_pump_bin(context.device, descriptors['splats'].rid)

## ── 分帧上传预算（2026-11-05）──
##
## 原来固定「每帧最多 64 MB」。一次换窗口要吐 100~280 MB，实测**单帧最坏 550 ms**
## —— 那一下就是用户说的「好卡」。现在改成**按时间给预算 + 自适应块大小**：
## 每帧只花大约 `upload_budget_ms` 毫秒上传，传不完下一帧接着传。
## 细层没传完时画面由粗层顶着（`init_gpu` 里已把新纹理清成透明），
## 所以「慢一点传完」远好过「一帧卡死」。
var upload_budget_ms := 4.0
## 起始块**故意取小**：实测「每帧的第一块」总是偏慢（驱动首次分配/预热，
## 4 MB 的第一块要 25~29 ms，而稳态吞吐是 1~2 MB/ms）。先给一小块量出真实吞吐，
## 控制器再按 `upload_budget_ms` 往上涨。
var _upload_chunk := 1 * 1024 * 1024
const UPLOAD_CHUNK_MIN := 256 * 1024
const UPLOAD_CHUNK_MAX := 64 * 1024 * 1024
## 实测统计：每次加载完打一行（判断预算还值不值得再调）
var _upload_worst_ms := 0.0
var _upload_frames := 0
var _upload_started_ms := 0

func _pump_bin(device, buffer) -> bool:
	if not _bin_loading or _bin_file == null:
		return false
	_upload_frames += 1
	while _bin_uploaded < _bin_total:
		var n := mini(_upload_chunk, _bin_total - _bin_uploaded)
		var data := _bin_file.get_buffer(n)
		if data.is_empty():
			break
		var t0 := Time.get_ticks_usec()
		device.buffer_update(buffer, _bin_uploaded, data.size(), data)
		var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		_upload_worst_ms = maxf(_upload_worst_ms, dt_ms)
		# 顺手抽样读 `time` 字段（每条 240 字节，第 3 个 float 在偏移 12），
		# 用来算「入场动画什么时候结束」。抽样 61 条取 1 条就够。
		# ⚠️ 只收 `t <= now`：数据里有些记录的时间字段是天文数字（实测会把
		#    `int()` 撑溢出，打出来是 `-9223372036854776 s`）。那些点在着色器里
		#    clamp 到 0，恒不可见、也永远不随时间变，不该把门卡到几百年后。
		var now_s := Time.get_ticks_msec() * 1e-3
		var off := 12
		while off + 4 <= data.size():
			var t := data.decode_float(off)
			if is_finite(t) and t <= now_s and t > _splat_time_max:
				_splat_time_max = t
			off += 240 * 61
		_bin_uploaded += data.size()
		num_splats_loaded[0] = _bin_uploaded / 240
		# 自适应：按这一块的实测吞吐，把块大小收到「一块 ≈ 一帧预算」附近。
		# 头几块会有点抖（第一次的驱动分配总是偏慢），很快就稳下来。
		var per_ms := float(data.size()) / maxf(dt_ms, 0.05)
		_upload_chunk = clampi(int(per_ms * upload_budget_ms), UPLOAD_CHUNK_MIN, UPLOAD_CHUNK_MAX)
		if _bin_uploaded < _bin_total and dt_ms >= upload_budget_ms:
			return true
	if _bin_uploaded >= _bin_total:
		_bin_file.close()
		_bin_file = null
		_bin_loading = false
		is_loaded = true
		intro_end_ms = int((_splat_time_max + INTRO_ANIM_SECONDS) * 1000.0) + INTRO_MARGIN_MS
		var secs := maxf(float(Time.get_ticks_msec() - _upload_started_ms) / 1000.0, 1e-3)
		print("[ggs] bin 上传完成：%d 点 / %.0f MB，%d 帧，最坏单块 %.1f ms，平均 %.0f MB/s，入场动画到 %.1f s" % [
			num_splats_loaded[0], float(_bin_total) / 1048576.0, _upload_frames,
			_upload_worst_ms, float(_bin_total) / 1048576.0 / secs,
			float(intro_end_ms) / 1000.0])
		return false
	return true

func _load_bin(device, buffer, count : int) -> void:
	var f := FileAccess.open(bin_path, FileAccess.READ)
	if f == null:
		push_error("[ggs] 打不开 bin: %s" % bin_path)
		return
	var total := count * 60 * 4
	var uploaded := 0
	var chunk := 4 * 1024 * 1024
	while uploaded < total:
		var n := mini(chunk, total - uploaded)
		var data := f.get_buffer(n)
		if data.is_empty():
			break
		device.buffer_update(buffer, uploaded, data.size(), data)
		uploaded += data.size()
		num_splats_loaded[0] = uploaded / 240
	f.close()
	print("[ggs] bin 上传完成：%d 点 / %.0f MB" % [num_splats_loaded[0],
		float(uploaded) / 1048576.0])

func cleanup_gpu():
	should_terminate_thread[0] = true
	if _bin_file != null:
		_bin_file.close()
		_bin_file = null
	if load_thread.is_started():
		load_thread.wait_to_finish()
	# ⚠️ 2026-11-06 修正顺序：**先把 Texture2DRD 的拥有权还掉，再释放 context**。
	#    原来反着来 —— `context.free()` 先把纹理 RID 释放了，随后
	#    `render_texture.texture_rd_rid = RID()` 又去释放同一个 RID，于是报
	#    `ERROR: Attempted to free invalid ID`。给 `texture_rd_rid` 赋值是
	#    **拥有权转移**（会释放原来持有的那个 RID），不是单纯改指针。
	if render_texture: render_texture.texture_rd_rid = RID()
	if context: context.free()

## 切场景专用：把 splats 缓冲**当帧**还给驱动。
##
## 为什么要单独一个函数（2026-11-07 用户：「进入第二场景不释放第一场景的显存」）：
## 光栅器整个对象会被 `campus_ggs.gd::_release_campus()` 丢掉、`context.free()`
## 也调了 —— 但 `context` 是 RefCounted，RID 攒在 `deletion_queue` 里等
## `NOTIFICATION_PREDELETE` 才 `free_rid`，真正落显存要等 GC。粗层那份
## 153 万点 = **656 MB**（`splats` 352 + `culled_splats` 70 + 两份 sort 各 117），
## 细层还要 1/3，加起来几百 MB 到一 GiB 都可能挂着。
##
## **必须在渲染线程调**。把 `splats` 换成 1 个元素的空缓冲并立刻还掉原来那块，
## 其余（culled / sort / 纹理）由 `release_all_now()` 在同一帧一并还掉。
func release_splats() -> void:
	if context == null or not descriptors.has('splats'):
		return
	var device = context.device
	var old = descriptors['splats']
	descriptors['splats'] = context.create_storage_buffer(4 * 4)
	if old != null and old.rid.is_valid():
		device.free_rid(old.rid)
		# 已经还掉了，别再让它留在队列里被 PREDELETE 顺手再还一次
		context.deletion_queue.queue.erase(old.rid)
	_bin_loading = false
	is_loaded = false
	num_splats_loaded[0] = 0
	print("[ggs] 切场景：splats 缓冲已提前还给驱动")

## 切场景专用：整份 context 立即释放。
## 顺序照 `cleanup_gpu()` 的教训：先把纹理拥有权还掉，再 flush RID 队列。
##
## **必须在渲染线程调**（`campus_ggs.gd` 走 `RenderingServer.call_on_render_thread`）：
## 这些 RID 正在被提交中的命令缓冲引用，主线程直接还掉会让 vulkan 层报
## 「正在使用的资源被释放」。
##
## `load_thread` 不在这里 join：它是**主线程**线程（`pump_load()` 在主线程驱动），
## 在渲染线程 join 会把自己卡死。调用方（`campus_ggs.gd::_release_campus`）在
## 主线程那边已经 `should_terminate = true` 并 `wait_to_finish()` 过了。
func release_all_now() -> void:
	should_terminate_thread[0] = true
	if _bin_file != null:
		_bin_file.close()
		_bin_file = null
	if render_texture:
		render_texture.texture_rd_rid = RID()
	var ctx = context
	context = null
	is_loaded = false
	_bin_loading = false
	descriptors.clear()
	shaders.clear()
	pipelines.clear()
	if ctx != null:
		ctx.release_all()
	print("[ggs] 切场景：光栅器 context 已当帧释放")

func rasterize() -> void:
	if not context: init_gpu()
	if _bin_loading:
		if _pump_bin(context.device, descriptors['splats'].rid):
			return
		# 刚上传完这一帧必须真算一次：数据变了
		_camera_changed = true
	if _can_reuse_last_frame():
		return
	
	var camera_pos = basis_override * camera.global_position
	context.device.buffer_update(descriptors['uniforms'].rid, 0, 12*4, RenderContextScript.create_push_constant([-camera_pos.x, -camera_pos.y, camera_pos.z, model_scale[0], texture_size.x, texture_size.y, Time.get_ticks_msec()*1e-3, cov_scale[0], cov_limit[0], cov_limit[1], 0.0, 0.0]))
	context.device.buffer_clear(descriptors['histogram'].rid, 0, 4 + 4*RADIX*4) # Clear the sort buffer size and reset global histogram
	context.device.buffer_clear(descriptors['tile_bounds'].rid, 0, tile_dims.x*tile_dims.y * 2*4) # Clear gsplat_boundaries buffer
	#context.device.buffer_update(descriptors['grid_dimensions'].rid, 0, 3*4*2, default_block_dims)
	# 每帧清成透明：合成器用 alpha 区分「没有 splat」的区域。
	context.device.texture_clear(descriptors['render_texture'].rid, Color(0, 0, 0, 0), 0, 1, 0, 1)
	is_loaded = not load_thread.is_alive()
	
	# Run the projection pipeline. This will return how many duplicated points
	# we will actually need to sort after culling.
	context.device.capture_timestamp('Start')
	var compute_list = context.compute_list_begin()
	pipelines['gsplat_projection'].call(context, compute_list, camera_push_constants)
	context.compute_list_end()
	context.device.capture_timestamp('Projection')
	
	# Then, run the sort and gsplat_rasterize pipelines with block sizes based on the
	# amount of points to sort determined in the projection pipeline.
	compute_list = context.compute_list_begin()
	var sort_n = point_cloud.size * 10
	for radix_shift_pass in range(4):
		var off_in = sort_n * (radix_shift_pass % 2)
		var off_out = sort_n * (1 - (radix_shift_pass % 2))
		# 4.7 会严格校验 push constant 字节数：upsweep 8、spine 4、downsweep 12。
		var pc_up = RenderContextScript.create_push_constant([radix_shift_pass, off_in])
		var pc_spine = RenderContextScript.create_push_constant([radix_shift_pass])
		var pc_down = RenderContextScript.create_push_constant([radix_shift_pass, off_in, off_out])
		pipelines['radix_sort_upsweep'].call(context, compute_list, pc_up, [], descriptors['grid_dimensions'].rid, 0)
		pipelines['radix_sort_spine'].call(context, compute_list, pc_spine)
		pipelines['radix_sort_downsweep'].call(context, compute_list, pc_down, [], descriptors['grid_dimensions'].rid, 0)
	context.compute_list_end()
	context.device.capture_timestamp('Sort')
	
	compute_list = context.compute_list_begin()
	pipelines['gsplat_boundaries'].call(context, compute_list, [], [], descriptors['grid_dimensions'].rid, 3*4)
	context.compute_list_end()
	context.device.capture_timestamp('Boundaries')
	
	compute_list = context.compute_list_begin()
	pipelines['gsplat_render'].call(context, compute_list, RenderContextScript.create_push_constant([float(should_enable_heatmap[0]), -1]))
	context.compute_list_end()
	context.device.capture_timestamp('Render')

	_rendered_once = true
	_last_size = texture_size


## 这一帧的输入和「上一次真正算过的那一帧」完全一样 ⇒ 输出逐像素相同 ⇒ 直接复用。
func _can_reuse_last_frame() -> bool:
	if not idle_skip or not _rendered_once or _camera_changed:
		return false
	if Time.get_ticks_msec() < intro_end_ms:
		return false
	if _last_size != texture_size:
		return false
	return true

func get_splat_position(screen_position : Vector2i) -> Vector3:
	var tile : Vector2i = screen_position * render_scale[0] / TILE_SIZE
	var tile_id = tile.y*tile_dims.x + tile.x
	
	var compute_list = context.compute_list_begin()
	pipelines['gsplat_render'].call(context, compute_list, RenderContextScript.create_push_constant([float(should_enable_heatmap[0]), tile_id]))
	context.compute_list_end()

	var splat_data = context.device.buffer_get_data(descriptors['tile_splat_pos'].rid, 0, 4*4).to_float32_array()
	return Vector3.INF if splat_data[3] == 0 else basis_override.inverse() * Vector3(-splat_data[0], -splat_data[1], splat_data[2])

## Returns whether the view and projection matrices had changed since the last time this function
## was called.
func update_camera_matrices() -> bool:
	var view = Projection(Transform3D(basis_override, Vector3.ZERO) * camera.get_camera_transform())
	var proj = camera.get_camera_projection()
	if view != camera_transform or proj != camera_projection:
		camera_transform = view
		camera_projection = proj
		camera_push_constants = RenderContextScript.create_push_constant([
			# --- View Matrix ---
			# Since (we assume) camera transform is orthonormal, the view matrix
			# (i.e., its inverse) is just the transpose.
			-view.x[0],  view.y[0], -view.z[0], 0.0, 
			-view.x[1],  view.y[1], -view.z[1], 0.0,
			 view.x[2], -view.y[2],  view.z[2], 0.0,
			-view.w.dot(view.x), -view.w.dot(-view.y), -view.w.dot(view.z), 1.0,
			# --- Projection Matrix ---
			proj.x[0], proj.x[1], proj.x[2], 0.0, 
			proj.y[0], proj.y[1], proj.y[2], 0.0,
			proj.z[0], proj.z[1], proj.z[2],-1.0,
			proj.w[0], proj.w[1], proj.w[2], 0.0 ])
		_camera_changed = true
		return true
	_camera_changed = false
	return false
