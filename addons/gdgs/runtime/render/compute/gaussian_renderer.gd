@tool
extends RefCounted
class_name GaussianRenderer

const RenderingDeviceContext := preload("res://addons/gdgs/runtime/render/compute/gaussian_rendering_device_context.gd")
const RADIX := 256
const MAX_SORT_ELEMENTS_PER_SPLAT := 10

## ── 静止帧复用（2026-11-05，用户反馈「好卡」）──
##
## 实测（2800×1171、0.5 缩放、RTX 4060 Laptop）：画室609 把每帧从 5.06 ms 推到
## 13.05 ms —— **泼溅一个人吃掉 8 ms / 占 61%**。而用户静止看画面时（读对话、
## 站定观察）这些钱是白花的：相机一个字都没动，重算投影 + 基数排序 + raster
## 得到的图和上一帧**逐像素相同**。
##
## 为什么可以「直接交回上一帧的纹理」而不是只跳一部分：
##   · `gsplat_render.glsl` 对 tile 内**每个像素**都 `imageStore`（颜色 + 深度），
##     所以 render_texture 是**全量重写**的，不存在「上一帧残留」；
##   · 唯一的非相机输入是 `uniforms.w = time`，而它只喂给
##     `gsplat_projection.glsl` 的入场动画（`time - splat.time` → ease_out_cubic
##     在 1.35 s 之后恒为 1）。等它落定就不再影响结果。
##
## 所以判据是**精确等价**，不是「近似」：
##   相机视图矩阵 / 投影 / 世界坐标 / 视口尺寸 / depth_capture_alpha 全等
##   且这一帧没有任何数据上传（splat / instance / relight）且入场动画已落定。
##
## ⚠️ 「入场动画已落定」的时刻由**数据里 `time` 字段的 max** 决定
##    （`gaussian_gpu_state_cache.gd::_intro_end_ms()`），不是拍一个固定秒数：
##    拍短了会把动画冻在半透明状态，那是看得出来的 bug。
## 关掉对照：`-- --gdgs-idle-skip=off`
var _idle_skip := true
var _idle_skip_read := false
## ⚠️ **只用于测量**：跳过 4 遍基数排序，把「排序」这一段从整帧里摘出来量。
## 画面是错的（`sort_values` 还是上一帧的排列，和新的 `culled_splats` 对不上），
## 所以它只能用来读时间，不能拿来出图。开法：`-- --gdgs-skip-sort`
var _skip_sort_debug := false
## ── 换场景后的「重新武装」（2026-11-07）──
##
## `purge_gpu()` 把注册表整份抹掉之后，`_last_point_data_size` 还是旧值，
## 于是新场景注册回来的那份点数据尺寸如果**恰好一样**（同一个房间二次进入、
## 或两个场景点数一致），`_sync_scene_resources()` 会认为「没变」而跳过上传，
## 新场景的泼溅就永远不显示。这里记一个标记，下一次渲染开始时先让缓存
## 「认为自己什么都没注入过」，强制整份重传一次。
var _rearm_requested := false

func request_rearm() -> void:
	_rearm_requested = true

func take_rearm() -> bool:
	var was := _rearm_requested
	_rearm_requested = false
	return was

func render_for_compositor(
	state_cache: GaussianGpuStateCache,
	scene_registry: GaussianSceneRegistry,
	texture_size: Vector2i,
	camera_transform: Transform3D,
	camera_projection: Projection,
	camera_world_position: Vector3,
	depth_capture_alpha: float = 0.5
) -> Dictionary:
	_read_idle_skip_setting()
	state_cache.flush_pending_cleanup()
	if take_rearm():
		# 切场景那一轮显式放掉 GPU 之后的第一次渲染：让缓存忘掉「已经注入过」，
		# 逼它把新场景的点数据整份重传（见 `_rearm_requested` 的说明）。
		state_cache.mark_all_render_states_needs_splat_upload(true)
		state_cache.mark_all_render_states_needs_instance_upload(true)
		state_cache.mark_all_render_states_needs_relight_upload(true)

	if not scene_registry.has_gpu_data():
		if state_cache.has_render_states():
			state_cache.cleanup_all()
		return {}

	var point_count := scene_registry.get_point_count()
	var safe_size := Vector2i(maxi(texture_size.x, 1), maxi(texture_size.y, 1))
	var state = state_cache.get_or_create_render_state(safe_size)
	_update_camera_from_transform(state, camera_transform, camera_projection)
	state.camera_world_position = camera_world_position
	state.depth_capture_alpha = clampf(depth_capture_alpha, 0.0, 1.0)

	var unique_data_size := scene_registry.get_point_data_byte().size()

	if state.context == null or state.needs_gpu_rebuild:
		state_cache.rebuild_gpu_state(state, point_count, unique_data_size, scene_registry.get_instance_count())
	if state.context == null:
		return {}

	var uploaded := false
	if state.needs_splat_upload:
		state_cache.upload_splats(state, scene_registry.get_point_data_byte(), scene_registry.get_splat_instance_ids_byte())
		state_cache.upload_splat_lighting(state, scene_registry.get_splat_lighting_byte())
		uploaded = true
	if state.needs_instance_upload:
		state_cache.upload_instance_transforms(state, scene_registry.get_instance_transforms_byte())
		uploaded = true
	if state.needs_relight_upload:
		state_cache.upload_relight(
			state, scene_registry.get_light_rig_byte(), scene_registry.get_instance_relight_byte()
		)
		uploaded = true

	if state.camera_push_constants.is_empty():
		return {}

	if _can_reuse_last_frame(state, safe_size, uploaded):
		return _result(state)

	_rasterize_state(state, point_count, scene_registry.get_light_count())

	state.rendered_once = true
	if state.first_render_ms == 0:
		state.first_render_ms = Time.get_ticks_msec()
	state.last_view = state.camera_view
	state.last_projection = state.camera_projection
	state.last_world_position = state.camera_world_position
	state.last_depth_alpha = state.depth_capture_alpha
	state.last_texture_size = safe_size
	return _result(state)


## 这一帧的输入和「上一次真正算过的那一帧」完全一样 ⇒ 输出逐像素相同 ⇒ 直接复用。
func _can_reuse_last_frame(state, size: Vector2i, uploaded: bool) -> bool:
	if not _idle_skip or not state.rendered_once or uploaded:
		return false
	if Time.get_ticks_msec() < state.intro_end_ms:
		return false
	if state.last_texture_size != size:
		return false
	if state.last_view != state.camera_view or state.last_projection != state.camera_projection:
		return false
	if state.last_world_position != state.camera_world_position:
		return false
	if not is_equal_approx(state.last_depth_alpha, state.depth_capture_alpha):
		return false
	return true


func _result(state) -> Dictionary:
	if state.descriptors.has("render_texture") and state.descriptors.has("depth_texture"):
		return {
			"color_alpha_texture": state.descriptors["render_texture"].rid,
			"depth_texture": state.descriptors["depth_texture"].rid
		}
	return {}


func _read_idle_skip_setting() -> void:
	if _idle_skip_read:
		return
	_idle_skip_read = true
	_idle_skip = bool(ProjectSettings.get_setting("gdgs/rendering/idle_skip", true))
	for a in OS.get_cmdline_user_args():
		if a == "--gdgs-idle-skip=off" or a == "--no-gdgs-idle-skip":
			_idle_skip = false
		elif a == "--gdgs-skip-sort":
			_skip_sort_debug = true

func _rasterize_state(state, point_count: int, light_count: int) -> void:
	if state.context == null:
		return

	var uniforms := RenderingDeviceContext.create_push_constant([
		state.camera_world_position.x,
		state.camera_world_position.y,
		state.camera_world_position.z,
		Time.get_ticks_msec() * 1e-3,
		state.texture_size.x,
		state.texture_size.y,
		point_count,
		# The trailing slot used to be padding; it now carries the active light
		# count, which is what bounds the projection shader's relight loop.
		light_count
	])
	state.context.device.buffer_update(state.descriptors["uniforms"].rid, 0, 8 * 4, uniforms)
	state.context.device.buffer_clear(state.descriptors["histogram"].rid, 0, 4 + 4 * RADIX * 4)
	state.context.device.buffer_clear(state.descriptors["tile_bounds"].rid, 0, state.tile_dims.x * state.tile_dims.y * 2 * 4)

	var compute_list: int = state.context.compute_list_begin()
	state.pipelines["gsplat_projection"].call(state.context, compute_list, state.camera_push_constants)
	state.context.compute_list_end()

	if not _skip_sort_debug:
		compute_list = state.context.compute_list_begin()
		for radix_shift_pass in range(4):
			var sort_push_constant := RenderingDeviceContext.create_push_constant([
				radix_shift_pass,
				point_count * MAX_SORT_ELEMENTS_PER_SPLAT * (radix_shift_pass % 2),
				point_count * MAX_SORT_ELEMENTS_PER_SPLAT * (1 - (radix_shift_pass % 2)),
				0
			])
			state.pipelines["radix_sort_upsweep"].call(state.context, compute_list, sort_push_constant, [], state.descriptors["grid_dimensions"].rid, 0)
			state.pipelines["radix_sort_spine"].call(state.context, compute_list, sort_push_constant)
			state.pipelines["radix_sort_downsweep"].call(state.context, compute_list, sort_push_constant, [], state.descriptors["grid_dimensions"].rid, 0)
		state.context.compute_list_end()

	compute_list = state.context.compute_list_begin()
	state.pipelines["gsplat_boundaries"].call(state.context, compute_list, PackedByteArray(), [], state.descriptors["grid_dimensions"].rid, 3 * 4)
	state.context.compute_list_end()

	compute_list = state.context.compute_list_begin()
	state.pipelines["gsplat_render"].call(
		state.context,
		compute_list,
		RenderingDeviceContext.create_push_constant([0.0, -1, state.depth_capture_alpha, 0.0])
	)
	state.context.compute_list_end()

func _update_camera_from_transform(state, camera_transform: Transform3D, camera_projection: Projection) -> void:
	var view := Projection(camera_transform.affine_inverse())
	if view != state.camera_view or camera_projection != state.camera_projection:
		state.camera_view = view
		state.camera_projection = camera_projection
		state.camera_push_constants = RenderingDeviceContext.create_push_constant(
			_projection_to_column_major_floats(view) + _projection_to_column_major_floats(camera_projection)
		)

func _projection_to_column_major_floats(matrix: Projection) -> Array:
	return [
		matrix.x[0], matrix.x[1], matrix.x[2], matrix.x[3],
		matrix.y[0], matrix.y[1], matrix.y[2], matrix.y[3],
		matrix.z[0], matrix.z[1], matrix.z[2], matrix.z[3],
		matrix.w[0], matrix.w[1], matrix.w[2], matrix.w[3]
	]
