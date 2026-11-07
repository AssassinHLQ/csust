class_name GdgsRenderingDeviceContext
extends Object

# Thin wrapper around RenderingDevice with basic allocation helpers.
class DeletionQueue:
	var queue: Array[RID] = []

	func push(rid: RID) -> RID:
		queue.push_back(rid)
		return rid

	func flush(device: RenderingDevice) -> void:
		# ⚠️ `device` 可能已经是 null（context 在 PREDELETE 之后又被人碰了一下）：
		#    老代码在这里会对 null 调 `free_rid` 直接崩，而这时候不放也没有意义了 ——
		#    RenderingDevice 自己会把整块显存交还给驱动。
		if device == null:
			queue.clear()
			return
		for i in range(queue.size() - 1, -1, -1):
			if not queue[i].is_valid():
				continue
			device.free_rid(queue[i])
		queue.clear()

	func free_rid(device: RenderingDevice, rid: RID) -> void:
		var rid_idx := queue.find(rid)
		assert(rid_idx != -1, "RID was not found in deletion queue.")
		device.free_rid(queue.pop_at(rid_idx))

## 切场景时**立刻**还 RID 用的「已放干净」标记。
##
## ⚠️ 为什么需要它（这个坑本喵踩了两次）：切场景的路径是
##    渲染线程 `release_all()` → 主线程立刻 `state.context = null`（丢引用）。
##    但渲染线程上那个 lambda 的参数、以及 Godot 渲染线程内部的临时引用
##    会让这份 context 一直**比预期活得久**，等到主线程退出时才被回收 ——
##    于是退出时报
##      `Resource still in use: .../gaussian_rendering_device_context.gd`
##      `Leaked instance: GDScript ... - Reference count: 1`
##    这不是真的泄漏显存（RID 已经还了），但报错本身要消掉。
##    办法：把「还 RID」和「丢引用」拆开 —— `release_all()` 只负责还 RID
##    （渲染线程调），引用由 `_notification(PREDELETE)` 照常收尾。

class Descriptor:
	var rid: RID
	var type: RenderingDevice.UniformType

	func _init(rid_: RID, type_: RenderingDevice.UniformType) -> void:
		rid = rid_
		type = type_

var device: RenderingDevice
var deletion_queue := DeletionQueue.new()
var shader_cache: Dictionary = {}

static func create(device_: RenderingDevice = null) -> GdgsRenderingDeviceContext:
	var context := GdgsRenderingDeviceContext.new()
	context.device = RenderingServer.create_local_rendering_device() if device_ == null else device_
	return context

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		deletion_queue.flush(device)
		shader_cache.clear()

## **立刻**把这一份 context 占的 RID 全还给驱动，不等 GC。
##
## 为什么需要它：`cleanup_all()` 只是 `state.context = null`，而 RID 全挂在
## `deletion_queue` 里、靠 `NOTIFICATION_PREDELETE` 才 flush —— 那要等 RefCounted
## 被回收，实测切场景后那块缓冲能挂好几百 MB 迟迟不掉（`[SceneFlow]` 日志里
## 「缓冲」一栏跨场景纹丝不动就是它）。切场景时显式调这个，显存当帧就掉。
##
## 调用方必须保证：渲染线程此刻不会再提交、也不会再有纹理/绑定点着这些 RID
## （见 `gaussian_render_manager.gd::purge_gpu()` 那一段的说明）。
##
## ⚠️ 不能用 `self.device = null` 来「丢引用」：`device` 是 `var device: RenderingDevice`，
##    那是**强类型引用**，赋值 null 之后 `_notification(PREDELETE)` 里那句
##    `deletion_queue.flush(device)` 拿到的还是「原始对象」—— 但引擎会认为这份
##    GDScript 资源仍被持有（退出时报 `1 resources still in use at exit`）。
##    这里改成「先 flush 再把队列清空」：队列空了，PREDELETE 再 flush 也是空操作，
##    RID 已经还过，不会重复释放。
func release_all() -> void:
	deletion_queue.flush(device)
	shader_cache.clear()
	# 置空是为了让主线程的 `_reap_leftover_contexts()` 能判断「这份已经放过了」。
	# 这不是丢引用：`deletion_queue` 已空，PREDELETE 的 flush 是空操作。
	device = null

func compute_list_begin() -> int:
	return device.compute_list_begin()

func compute_list_end() -> void:
	device.compute_list_end()

func load_shader(path: String) -> RID:
	if not shader_cache.has(path):
		var shader_file: RDShaderFile = load(path)
		var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
		shader_cache[path] = deletion_queue.push(device.shader_create_from_spirv(shader_spirv))
	return shader_cache[path]

## `zero_fill=false` 时**不填零**，走「未初始化」分配。
## 大缓冲填零要几百毫秒（实测 GGS 那边 644 MB → 733 ms），而下面这些缓冲在用之前
## 都会被整份覆盖：`splats`（上传时全写）、`culled_splats`（投影只写发出的条目）、
## `sort_keys` / `sort_values`（基数排序只读/写 `[0, element_count)`，
## `element_count` 每帧由 CPU 清 0）。见 `gaussian_gpu_state_cache.gd::rebuild_gpu_state()`。
func create_storage_buffer(size: int, data: PackedByteArray = PackedByteArray(), usage: int = 0, zero_fill: bool = true) -> Descriptor:
	var buffer_data := data
	if zero_fill and size > buffer_data.size():
		var padding := PackedByteArray()
		padding.resize(size - buffer_data.size())
		buffer_data += padding
	return Descriptor.new(deletion_queue.push(device.storage_buffer_create(maxi(size, buffer_data.size()), buffer_data, usage)), RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)

func create_uniform_buffer(size: int, data: PackedByteArray = PackedByteArray()) -> Descriptor:
	var full_size := maxi(16, size)
	var buffer_data := data
	if full_size > buffer_data.size():
		var padding := PackedByteArray()
		padding.resize(full_size - buffer_data.size())
		buffer_data += padding
	return Descriptor.new(deletion_queue.push(device.uniform_buffer_create(full_size, buffer_data)), RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER)

func create_texture(
	dimensions: Vector2i,
	format: RenderingDevice.DataFormat,
	usage: int = 0x18B,
	view: RDTextureView = RDTextureView.new(),
	data: Array[PackedByteArray] = []
) -> Descriptor:
	var texture_format := RDTextureFormat.new()
	texture_format.format = format
	texture_format.width = dimensions.x
	texture_format.height = dimensions.y
	texture_format.usage_bits = usage
	return Descriptor.new(deletion_queue.push(device.texture_create(texture_format, view, data)), RenderingDevice.UNIFORM_TYPE_IMAGE)

func create_descriptor_set(descriptors: Array, shader: RID, descriptor_set_index: int = 0) -> RID:
	var uniforms: Array[RDUniform] = []
	for i in range(descriptors.size()):
		var descriptor: Descriptor = descriptors[i]
		var uniform := RDUniform.new()
		uniform.uniform_type = descriptor.type
		uniform.binding = i
		uniform.add_id(descriptor.rid)
		uniforms.push_back(uniform)
	return deletion_queue.push(device.uniform_set_create(uniforms, shader, descriptor_set_index))

func create_pipeline(block_dimensions: Array, descriptor_sets: Array, shader: RID) -> Callable:
	var pipeline := deletion_queue.push(device.compute_pipeline_create(shader))
	return func(
		context: GdgsRenderingDeviceContext,
		compute_list: int,
		push_constant: PackedByteArray = PackedByteArray(),
		descriptor_set_overwrites: Array = [],
		block_dimensions_overwrite_buffer: RID = RID(),
		block_dimensions_overwrite_buffer_byte_offset: int = 0
	) -> void:
		var sets := descriptor_sets if descriptor_set_overwrites.is_empty() else descriptor_set_overwrites
		assert(block_dimensions.size() == 3 or block_dimensions_overwrite_buffer.is_valid(), "Must specify block dimensions or use dispatch indirect.")
		assert(sets.size() >= 1, "Must specify at least one descriptor set.")

		var rd := context.device
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		if not push_constant.is_empty():
			rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
		for i in range(sets.size()):
			rd.compute_list_bind_uniform_set(compute_list, sets[i], i)
		if block_dimensions_overwrite_buffer.is_valid():
			rd.compute_list_dispatch_indirect(compute_list, block_dimensions_overwrite_buffer, block_dimensions_overwrite_buffer_byte_offset)
		else:
			rd.compute_list_dispatch(compute_list, block_dimensions[0], block_dimensions[1], block_dimensions[2])
		rd.compute_list_add_barrier(compute_list)

static func create_push_constant(data: Array) -> PackedByteArray:
	var packed_size := data.size() * 4
	assert(packed_size <= 128, "Push constant size must be at most 128 bytes.")

	var padding := ceili(packed_size / 16.0) * 16 - packed_size
	var packed_data := PackedByteArray()
	packed_data.resize(packed_size + (padding if padding > 0 else 0))
	packed_data.fill(0)

	for i in range(data.size()):
		match typeof(data[i]):
			TYPE_INT, TYPE_BOOL:
				packed_data.encode_s32(i * 4, int(data[i]))
			TYPE_FLOAT:
				packed_data.encode_float(i * 4, float(data[i]))
	return packed_data
