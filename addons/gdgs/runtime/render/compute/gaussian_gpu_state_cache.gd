@tool
extends RefCounted
class_name GaussianGpuStateCache

const RenderingDeviceContext := preload("res://addons/gdgs/runtime/render/compute/gaussian_rendering_device_context.gd")

const TILE_SIZE := 16
const WORKGROUP_SIZE := 512
const RADIX := 256
const PARTITION_DIVISION := 8
const PARTITION_SIZE := PARTITION_DIVISION * WORKGROUP_SIZE
## ── RenderState 缓存上限（2026-11-05 从 4 改成 2）──
##
## 为什么要改小：**每个 RenderState 都自带一整套泼溅 GPU 缓冲**，画室609 那 277 万点
## 一份就是 1.28 GB：
##     splats        2,769,855 × 60 × 4 = 665 MB
##     culled_splats 2,769,855 × 16 × 4 = 177 MB
##     sort_keys     2,769,855 × 10 × 8 = 221 MB
##     sort_values   2,769,855 × 10 × 8 = 221 MB
## 上限 4 ⇒ 最多留 **5.1 GB**，8 GB 的卡上直接爆。
##
## 实测复现（`_probe_render_states.gd`，RTX 4060 Laptop）：在「3D 缩放」上换几个值，
## 显存从 3052 MiB 一路涨到 **6857 MiB**，帧时间从 13 ms 崩到 102 ms
## —— 用户报的「显存 6918 MiB / 开 1 就 7 fps」就是这个。
##
## 2 份够用：正常游戏只有**一个**主视口尺寸，第二份用来扛「改分辨率/改缩放」的
## 过渡帧（改回上一次的值时还能直接复用）。再多就是纯粹的浪费。
const MAX_RENDER_STATES := 2
const FLOATS_PER_SPLAT := 60
const FLOATS_PER_CULLED_SPLAT := 16
const BYTES_PER_FLOAT := 4
const MAX_SORT_ELEMENTS_PER_SPLAT := 10
# Relighting. Must match gsplat_projection.glsl and gaussian_light_rig.gd.
const LIGHTING_BYTES_PER_SPLAT := 4
const RELIGHT_FLOATS_PER_INSTANCE := 8
const MAX_LIGHTS := 8
const LIGHT_RIG_FLOATS := MAX_LIGHTS * 16

const SHADER_PATH_PROJECTION := "res://addons/gdgs/runtime/render/compute/shaders/gsplat_projection.glsl"
const SHADER_PATH_RADIX_UPSWEEP := "res://addons/gdgs/runtime/render/compute/shaders/radix_sort_upsweep.glsl"
const SHADER_PATH_RADIX_SPINE := "res://addons/gdgs/runtime/render/compute/shaders/radix_sort_spine.glsl"
const SHADER_PATH_RADIX_DOWNSWEEP := "res://addons/gdgs/runtime/render/compute/shaders/radix_sort_downsweep.glsl"
const SHADER_PATH_BOUNDARIES := "res://addons/gdgs/runtime/render/compute/shaders/gsplat_boundaries.glsl"
const SHADER_PATH_RENDER := "res://addons/gdgs/runtime/render/compute/shaders/gsplat_render.glsl"

class RenderState:
	extends RefCounted

	var texture_size := Vector2i.ONE
	var tile_dims := Vector2i.ONE
	var camera_projection: Projection
	var camera_view: Projection
	var camera_push_constants := PackedByteArray()
	var camera_world_position := Vector3.ZERO
	var depth_capture_alpha := 0.5
	var needs_gpu_rebuild := true
	var needs_splat_upload := false
	var needs_instance_upload := false
	var needs_relight_upload := false
	var context: GdgsRenderingDeviceContext
	var shaders: Dictionary = {}
	var pipelines: Dictionary = {}
	var descriptors: Dictionary = {}
	# ── 静止帧复用（2026-11-05）──
	# 相机 / 视口 / 入场动画都没变的那一帧，整条 compute 链（投影 + 基数排序 +
	# 边界 + raster）的输出和上一帧**逐像素相同**，可以直接把上一帧的纹理交回去。
	# 依据见 `gaussian_renderer.gd::_can_reuse_last_frame()`。
	var rendered_once := false
	var first_render_ms := 0
	## 入场动画结束的**引擎时刻**（毫秒）。由 `upload_splats()` 从点数据里的 `time`
	## 字段算出来（= max(time) + 1.35 s + 余量），不是拍一个固定秒数 ——
	## 见 `gaussian_gpu_state_cache.gd::_intro_end_ms()` 的说明。
	var intro_end_ms := 0
	var last_view: Projection
	var last_projection: Projection
	var last_world_position := Vector3(INF, INF, INF)
	var last_depth_alpha := -1.0
	var last_texture_size := Vector2i.ZERO

var _render_states: Dictionary = {}
var _render_state_lru: Array = []
var _pending_gpu_cleanup := false

func has_render_states() -> bool:
	return not _render_states.is_empty()

func request_cleanup() -> void:
	_pending_gpu_cleanup = true

func flush_pending_cleanup() -> void:
	if _pending_gpu_cleanup:
		cleanup_all()

func get_or_create_render_state(texture_size: Vector2i):
	var state: RenderState = _render_states.get(texture_size, null)
	if state == null:
		# ⚠️ **先淘汰再新建**。原来建完才淘汰，于是峰值多出一整份（1.28 GB）：
		#    新 state 已经拿到显存、旧 state 还没放，`MAX_RENDER_STATES + 1` 份同时在。
		#    这里为「即将新建的这一份」预留一个位置。
		_enforce_render_state_cache_limit(1)
		state = RenderState.new()
		state.texture_size = texture_size
		state.tile_dims = (texture_size + Vector2i(TILE_SIZE - 1, TILE_SIZE - 1)) / TILE_SIZE
		_render_states[texture_size] = state
	_touch_render_state(texture_size)
	_enforce_render_state_cache_limit()
	return state

func mark_all_render_states_needs_gpu_rebuild() -> void:
	for state in _render_states.values():
		state.needs_gpu_rebuild = true

func mark_all_render_states_needs_splat_upload(value: bool) -> void:
	for state in _render_states.values():
		state.needs_splat_upload = value

func mark_all_render_states_needs_instance_upload(value: bool) -> void:
	for state in _render_states.values():
		state.needs_instance_upload = value

func mark_all_render_states_needs_relight_upload(value: bool) -> void:
	for state in _render_states.values():
		state.needs_relight_upload = value

func rebuild_gpu_state(state, point_count: int, unique_data_size: int, instance_count: int) -> void:
	cleanup_state(state)
	if point_count <= 0:
		return

	state.context = RenderingDeviceContext.create(RenderingServer.get_rendering_device())

	state.shaders["projection"] = state.context.load_shader(SHADER_PATH_PROJECTION)
	state.shaders["radix_upsweep"] = state.context.load_shader(SHADER_PATH_RADIX_UPSWEEP)
	state.shaders["radix_spine"] = state.context.load_shader(SHADER_PATH_RADIX_SPINE)
	state.shaders["radix_downsweep"] = state.context.load_shader(SHADER_PATH_RADIX_DOWNSWEEP)
	state.shaders["boundaries"] = state.context.load_shader(SHADER_PATH_BOUNDARIES)
	state.shaders["render"] = state.context.load_shader(SHADER_PATH_RENDER)

	var num_sort_elements_max := point_count * MAX_SORT_ELEMENTS_PER_SPLAT
	var num_partitions := (num_sort_elements_max + PARTITION_SIZE - 1) / PARTITION_SIZE
	var block_dims := PackedInt32Array()
	block_dims.resize(6)
	block_dims.fill(1)
	# Pre-size indirect dispatch dimensions on the CPU. On macOS/Metal, updating this
	# buffer from the projection pass can cause the entire GS pipeline to go blank.
	block_dims[0] = num_partitions
	block_dims[3] = ceili(num_sort_elements_max / 256.0)

	# Relighting buffers, sized off the same unique-splat and instance counts as
	# the data above. Always allocated (a minimum of one element) so the shader's
	# bindings stay valid even with nothing baked; the per-instance `enabled`
	# flag is what actually gates the maths.
	var unique_splat_count := maxi(1, unique_data_size / (FLOATS_PER_SPLAT * BYTES_PER_FLOAT))
	# ── 大缓冲**不填零**（2026-11-05）──
	# 填零（准备等长零数组 + 交给 `storage_buffer_create`）在几百 MB 上要几百毫秒：
	# GGS 那边实测 644 MB → 733 ms。这四个缓冲在用之前都会被整份覆盖，所以直接
	# 走「未初始化」分配：
	#   · `splats`               ← `upload_splats()` 全量写
	#   · `culled_splats`        ← 投影着色器只写「发出的那些」条目
	#   · `sort_keys`/`sort_values` ← 基数排序只读/写 `[0, element_count)`，
	#     `element_count` 取自 histogram 首个 uint，每帧由 CPU 清 0
	state.descriptors["splats"] = state.context.create_storage_buffer(unique_data_size, PackedByteArray(), 0, false)
	# ⚠️ `splat_lighting` **保持填零**：没烘光照时 `upload_splat_lighting()` 会因为
	#    空数组直接返回，缓冲里就会是「未初始化」的垃圾，着色器会拿它当光照用。
	state.descriptors["splat_lighting"] = state.context.create_storage_buffer(
		unique_splat_count * LIGHTING_BYTES_PER_SPLAT)
	state.descriptors["light_rig"] = state.context.create_storage_buffer(
		LIGHT_RIG_FLOATS * BYTES_PER_FLOAT)
	state.descriptors["instance_relight"] = state.context.create_storage_buffer(
		maxi(1, instance_count) * RELIGHT_FLOATS_PER_INSTANCE * BYTES_PER_FLOAT)
	state.descriptors["culled_splats"] = state.context.create_storage_buffer(
		point_count * FLOATS_PER_CULLED_SPLAT * BYTES_PER_FLOAT, PackedByteArray(), 0, false)
	state.descriptors["grid_dimensions"] = state.context.create_storage_buffer(6 * 4, block_dims.to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	state.descriptors["histogram"] = state.context.create_storage_buffer(4 + (1 + 4 * RADIX + num_partitions * RADIX) * 4)
	state.descriptors["sort_keys"] = state.context.create_storage_buffer(num_sort_elements_max * 4 * 2, PackedByteArray(), 0, false)
	state.descriptors["sort_values"] = state.context.create_storage_buffer(num_sort_elements_max * 4 * 2, PackedByteArray(), 0, false)
	state.descriptors["splat_instance_ids"] = state.context.create_storage_buffer(point_count * 4 * 2)
	state.descriptors["instance_transforms"] = state.context.create_storage_buffer(instance_count * 16 * BYTES_PER_FLOAT)
	state.descriptors["uniforms"] = state.context.create_uniform_buffer(8 * 4)
	state.descriptors["tile_bounds"] = state.context.create_storage_buffer(state.tile_dims.x * state.tile_dims.y * 2 * 4)
	state.descriptors["tile_splat_pos"] = state.context.create_storage_buffer(4 * 4)
	state.descriptors["render_texture"] = state.context.create_texture(state.texture_size, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
	state.descriptors["depth_texture"] = state.context.create_texture(state.texture_size, RenderingDevice.DATA_FORMAT_R32_SFLOAT)

	var projection_set: RID = state.context.create_descriptor_set([
		state.descriptors["splats"],
		state.descriptors["culled_splats"],
		state.descriptors["histogram"],
		state.descriptors["sort_keys"],
		state.descriptors["sort_values"],
		state.descriptors["grid_dimensions"],
		state.descriptors["splat_instance_ids"],
		state.descriptors["instance_transforms"],
		state.descriptors["uniforms"],
		# Bindings are assigned by position in create_descriptor_set, so these
		# three must stay last and in this order to match bindings 9/10/11.
		state.descriptors["light_rig"],
		state.descriptors["splat_lighting"],
		state.descriptors["instance_relight"]
	], state.shaders["projection"], 0)

	var radix_upsweep_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"],
		state.descriptors["sort_keys"]
	], state.shaders["radix_upsweep"], 0)

	var radix_spine_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"]
	], state.shaders["radix_spine"], 0)

	var radix_downsweep_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"],
		state.descriptors["sort_keys"],
		state.descriptors["sort_values"]
	], state.shaders["radix_downsweep"], 0)

	var boundaries_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"],
		state.descriptors["sort_keys"],
		state.descriptors["tile_bounds"]
	], state.shaders["boundaries"], 0)

	var render_set: RID = state.context.create_descriptor_set([
		state.descriptors["culled_splats"],
		state.descriptors["sort_values"],
		state.descriptors["tile_bounds"],
		state.descriptors["tile_splat_pos"],
		state.descriptors["render_texture"],
		state.descriptors["depth_texture"]
	], state.shaders["render"], 0)

	state.pipelines["gsplat_projection"] = state.context.create_pipeline([ceili(point_count / 256.0), 1, 1], [projection_set], state.shaders["projection"])
	state.pipelines["radix_sort_upsweep"] = state.context.create_pipeline([], [radix_upsweep_set], state.shaders["radix_upsweep"])
	state.pipelines["radix_sort_spine"] = state.context.create_pipeline([RADIX, 1, 1], [radix_spine_set], state.shaders["radix_spine"])
	state.pipelines["radix_sort_downsweep"] = state.context.create_pipeline([], [radix_downsweep_set], state.shaders["radix_downsweep"])
	state.pipelines["gsplat_boundaries"] = state.context.create_pipeline([], [boundaries_set], state.shaders["boundaries"])
	state.pipelines["gsplat_render"] = state.context.create_pipeline([state.tile_dims.x, state.tile_dims.y, 1], [render_set], state.shaders["render"])

	state.needs_gpu_rebuild = false
	state.needs_splat_upload = true
	state.needs_instance_upload = true
	state.needs_relight_upload = true

func upload_splats(state, point_data_byte: PackedByteArray, splat_instance_ids_byte: PackedByteArray) -> void:
	if state.context == null or point_data_byte.is_empty() or splat_instance_ids_byte.is_empty():
		return
	state.context.device.buffer_update(state.descriptors["splats"].rid, 0, point_data_byte.size(), point_data_byte)
	state.context.device.buffer_update(state.descriptors["splat_instance_ids"].rid, 0, splat_instance_ids_byte.size(), splat_instance_ids_byte)
	state.intro_end_ms = _intro_end_ms(point_data_byte)
	state.needs_splat_upload = false


## `gsplat_projection.glsl` 的入场动画：`splat_time = time - splat.time`，
## `ease_out_cubic(clamp(splat_time, 0, 1))` 在 1 s 后恒为 1，`time_factor_late`
## 还多减 0.35 ⇒ **max(splat.time) + 1.35 s 之后，时间就不再影响画面**。
##
## 所以「什么时候可以开始静止帧复用」必须**按数据算**：
##   · 拍短了 → 动画还没跑完就跳过，画面被冻在半透明的入场状态（看得出来的 bug）；
##   · 拍长了 → 只是白等几秒才享受到优化。
## 抽样读就够（`time` 是导出器写的一批值，不是逐点噪声）：满量程枚举 277 万次
## 在 GDScript 里要好几秒，抽 10 万个点 < 0.2 s，再留 400 ms 余量。
const INTRO_ANIM_SECONDS := 1.35
const INTRO_MARGIN_MS := 400


func _intro_end_ms(point_data_byte: PackedByteArray) -> int:
	var n := point_data_byte.size() / (FLOATS_PER_SPLAT * BYTES_PER_FLOAT)
	if n <= 0:
		return INTRO_MARGIN_MS
	var step := maxi(1, n / 100000)
	var now_s := Time.get_ticks_msec() * 1e-3
	var hi := 0.0
	var i := 0
	while i < n:
		var t := point_data_byte.decode_float(i * FLOATS_PER_SPLAT * BYTES_PER_FLOAT + 3 * BYTES_PER_FLOAT)
		# ⚠️ 只统计**已经开始播**的点（`t <= now`）。
		# 导出数据里有些记录的时间字段是天文数字（实测把 `int()` 撑溢出，
		# 打出来变成 `-9223372036854776.0 s`）。那些点在着色器里 `time - t < 0`
		# → clamp 到 0 → 恒不可见、也永远不随时间变，不该把门卡到几百年后。
		if is_finite(t) and t <= now_s and t > hi:
			hi = t
		i += step
	return int((hi + INTRO_ANIM_SECONDS) * 1000.0) + INTRO_MARGIN_MS

func upload_instance_transforms(state, instance_transforms_byte: PackedByteArray) -> void:
	if state.context == null or instance_transforms_byte.is_empty():
		return
	state.context.device.buffer_update(state.descriptors["instance_transforms"].rid, 0, instance_transforms_byte.size(), instance_transforms_byte)
	state.needs_instance_upload = false

## The baked per-splat records travel with the splat data (they change only when
## the scene's resources do), while the light rig and per-instance knobs move on
## their own cadence, so they upload separately.
func upload_splat_lighting(state, splat_lighting_byte: PackedByteArray) -> void:
	if state.context == null or splat_lighting_byte.is_empty():
		return
	state.context.device.buffer_update(state.descriptors["splat_lighting"].rid, 0, splat_lighting_byte.size(), splat_lighting_byte)

func upload_relight(state, light_rig_byte: PackedByteArray, instance_relight_byte: PackedByteArray) -> void:
	if state.context == null:
		return
	if not light_rig_byte.is_empty():
		state.context.device.buffer_update(state.descriptors["light_rig"].rid, 0, light_rig_byte.size(), light_rig_byte)
	if not instance_relight_byte.is_empty():
		state.context.device.buffer_update(state.descriptors["instance_relight"].rid, 0, instance_relight_byte.size(), instance_relight_byte)
	state.needs_relight_upload = false

func cleanup_state(state) -> void:
	if state == null:
		return
	if state.context != null:
		state.context.free()
		state.context = null
	state.shaders.clear()
	state.pipelines.clear()
	state.descriptors.clear()
	state.needs_gpu_rebuild = true
	state.needs_splat_upload = true
	state.needs_instance_upload = true
	state.needs_relight_upload = true
	state.rendered_once = false
	state.first_render_ms = 0
	state.last_world_position = Vector3(INF, INF, INF)
	state.last_depth_alpha = -1.0
	state.last_texture_size = Vector2i.ZERO

func cleanup_all() -> void:
	for state in _render_states.values():
		cleanup_state(state)
	_render_states.clear()
	_render_state_lru.clear()
	_pending_gpu_cleanup = false

func _touch_render_state(texture_size: Vector2i) -> void:
	var existing_index := _render_state_lru.find(texture_size)
	if existing_index != -1:
		_render_state_lru.remove_at(existing_index)
	_render_state_lru.push_back(texture_size)

## `reserve` = 给「马上要新建的那一份」腾位置（见 `get_or_create_render_state`）。
func _enforce_render_state_cache_limit(reserve: int = 0) -> void:
	while _render_state_lru.size() + reserve > MAX_RENDER_STATES:
		var stale_size = _render_state_lru[0]
		_render_state_lru.remove_at(0)
		var stale_state = _render_states.get(stale_size, null)
		if stale_state != null:
			cleanup_state(stale_state)
			_render_states.erase(stale_size)
