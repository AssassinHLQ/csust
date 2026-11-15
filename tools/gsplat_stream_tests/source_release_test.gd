extends SceneTree
## Real-GPU regression: room removal must retire every cached resolution even
## without another compositor callback, while preserving a campus stream.
## Run through tools/run_godot_private_desktop.py; never launch on the input desktop.

const OffWin := preload("res://scripts/offscreen_window.gd")
const Manager := preload("res://addons/gdgs/runtime/render/compute/gaussian_render_manager.gd")
const Fixture := preload("res://tools/gsplat_stream_tests/stream_pack_fixture.gd")
const Pack := preload("res://addons/gdgs/runtime/stream/gaussian_stream_pack.gd")
const Runtime := preload("res://addons/gdgs/runtime/stream/gaussian_stream_runtime.gd")
const Gaussian := preload("res://addons/gdgs/runtime/resources/gaussian_resource.gd")

class RoomSource extends Node3D:
	var gaussian: Resource
	var lighting: Resource
	var relight_enabled := false
	var relight_unlit_level := 1.0
	var relight_light_gain := 1.0
	var relight_dc_only := false
	var relight_ambient := Color.WHITE

class StreamSource extends Node3D:
	var stream_pack: Resource
	var runtime: RefCounted
	func get_stream_runtime() -> RefCounted:
		return runtime

signal gpu_done(stats: Dictionary)
var _manager: Node
var _checks := 0
var _fails := 0
var _camera := Transform3D(Basis.IDENTITY, Vector3(0, 0, 4))
var _projection := Projection.create_perspective(70, 16.0 / 9.0, 0.1, 100.0)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await OffWin.apply(self)
	if RenderingServer.get_rendering_device() == null:
		_check(false, "RenderingDevice required")
		quit(1)
		return
	_manager = Manager.new()
	root.add_child(_manager)
	DirAccess.make_dir_recursive_absolute("user://source_release_test")
	var prefix := "user://source_release_test/campus"
	var pack := Pack.new()
	_check(pack.load_from(Fixture.build(prefix, 0, 256, 1.0)) == OK, "synthetic campus loaded")
	var campus := StreamSource.new()
	campus.stream_pack = pack
	campus.runtime = Runtime.new()
	campus.runtime.configure(pack, 1)
	root.add_child(campus)
	_manager.register_stream_node(campus)
	var view_projection := _projection * Projection(_camera.affine_inverse())
	for frame in 60:
		campus.runtime.update(_camera.origin, view_projection, 385.0, 1.0 / 60.0)
		await process_frame
	_check(campus.runtime.resident_splats() == 256, "campus payload resident")
	for cycle in 3:
		var room := RoomSource.new()
		var data := Gaussian.new()
		data.point_count = 256
		data.packed_enabled = true
		data.packed_stride_words = 13
		data.sh_degree = 0
		data.sh_scale = 0.05
		data.point_data_byte = Fixture._records(Vector3.ZERO, 1.0, 256)
		room.gaussian = data
		root.add_child(room)
		_manager.register_splat_node(room)
		var before: Dictionary = await _render_sizes([Vector2i(320, 180), Vector2i(640, 360)])
		print("GPU before room exit: ", JSON.stringify(before))
		_check(before.render_states == 2 and before.total_bytes > 0, "cycle %d: two resolutions allocated" % cycle)
		_check(before.outputs_valid, "cycle %d: mixed room/campus render succeeds" % cycle)
		_manager.unregister_splat_node(room)
		room.free()
		# No compositor render between unregister and this measurement.
		var after: Dictionary = await _memory_stats()
		print("GPU after room exit: ", JSON.stringify(after))
		_check(after.total_bytes == 0 and after.render_states == 0 and after.workspaces == 0, "cycle %d: unused GPU states freed without rendering" % cycle)
		_check(_manager._scene_registry.has_stream_sources(), "cycle %d: campus registry preserved" % cycle)
		_check(_manager._scene_registry.get_point_count() == 0, "cycle %d: removed room data absent" % cycle)
		var remaining: Dictionary = await _render_sizes([Vector2i(320, 180)])
		_check(remaining.outputs_valid and remaining.total_bytes > 0, "cycle %d: remaining campus renders again" % cycle)
	_manager.unregister_stream_node(campus)
	var empty: Dictionary = await _memory_stats()
	print("GPU after last source: ", JSON.stringify(empty))
	_check(empty.total_bytes == 0 and empty.render_states == 0, "last source frees all GPU buffers")
	_check(not _manager._scene_registry.has_gpu_data(), "last source removes registry payload")
	campus.runtime.shutdown()
	campus.free()
	_manager.queue_free()
	await process_frame
	for suffix in [".manifest.json", ".nodes.bin"]:
		DirAccess.remove_absolute(prefix + suffix)
	print("SOURCE_RELEASE: %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)

func _render_sizes(sizes: Array) -> Dictionary:
	RenderingServer.call_on_render_thread(func():
		var valid := true
		for size in sizes:
			var rendered: Dictionary = _manager.render_for_compositor(size, _camera, _projection, _camera.origin)
			valid = valid and rendered.has("color_alpha_texture") and rendered["color_alpha_texture"].is_valid()
		var stats: Dictionary = _manager._gpu_state_cache.get_memory_stats()
		stats["outputs_valid"] = valid
		gpu_done.emit.call_deferred(stats))
	return await gpu_done

func _memory_stats() -> Dictionary:
	_manager.request_gpu_memory_stats(func(stats: Dictionary): gpu_done.emit(stats))
	return await gpu_done

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("PASS " if ok else "FAIL ") + label)
