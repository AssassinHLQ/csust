extends "res://scripts/splat_scene.gd"
## Campus adapter for the project's modified godot-gsplat-stream fork.
## The pack already uses production world coordinates; never apply scale twice.
const StreamPack := preload("res://addons/gdgs/runtime/stream/gaussian_stream_pack.gd")
const StreamNode := preload("res://addons/gdgs/runtime/nodes/gaussian_stream_node.gd")

@export_file("*.json") var stream_manifest := "res://splatdata/campus_stream/campus.manifest.json"
@export_file("*.json") var full_detail_manifest := "res://splatdata/campus_stream/campus_full.manifest.json"
## Keep all source points by default. LOD is an explicit performance option.
@export var stream_lod_enabled := false
@export_range(8, 256, 1) var stream_budget_nodes := 96
@export_range(0.5, 64.0, 0.5) var stream_sse := 1.0
var _using_stream := false
var _pack: GaussianStreamPack
var _stream: GaussianStreamNode
var _stream_ready := false
var _stream_started_us := 0
var _ready_seconds := -1.0

func _ready() -> void:
	_using_stream = _wants_stream()
	if not _using_stream:
		super._ready()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg == "--campus-lod=on":
			stream_lod_enabled = true
		elif arg == "--campus-lod=off":
			stream_lod_enabled = false
		if arg.begins_with("--campus-stream-budget="):
			stream_budget_nodes = clampi(int(arg.trim_prefix("--campus-stream-budget=")), 8, 256)
	if auto_start:
		start()

func _wants_stream() -> bool:
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		return false
	for arg in OS.get_cmdline_user_args():
		if arg in ["--campus-renderer=gdgs", "--ggs-campus=on", "--splat=off", "--no-splat", "--campus-splat=off", "--no-campus-splat"]:
			return false
		if arg.begins_with("--venue=") and arg.substr(8) not in ["all", "campus"]:
			return false
	return true

func start() -> void:
	if not _using_stream:
		super.start()
		return
	if is_instance_valid(_stream) or loading:
		return
	_stream_started_us = Time.get_ticks_usec()
	_pack = StreamPack.new()
	var selected_manifest := stream_manifest if stream_lod_enabled else full_detail_manifest
	if _pack.load_from(selected_manifest) != OK:
		failed.emit("校园流式包不可用：" + selected_manifest)
		return
	loading = true
	load_ratio = 0.0
	load_phase = "加载校园"
	_stream = StreamNode.new()
	_stream.name = "GaussianStream"
	_stream.budget_nodes = stream_budget_nodes
	_stream.max_sse = stream_sse
	_stream.max_loads_per_frame = 2
	_stream.select_interval = 0.08
	_stream.stream_pack = _pack
	_stream.top_level = true
	add_child(_stream)
	_stream.global_transform = Transform3D.IDENTITY
	splat_node = _stream
	print("[CampusStream] godot-gsplat-stream: %d source points, %d nodes, %s SH%d, LOD=%s, budget=%d, SSE=%.1f; original world coordinates" % [_pack.source_splats, _pack.node_count, _pack.record_layout, _pack.sh_degree, stream_lod_enabled, stream_budget_nodes, stream_sse])

func force_start() -> void:
	if not _using_stream:
		super.force_start()
	else:
		start()

func is_ready() -> bool:
	return _stream_ready if _using_stream else super.is_ready()

func _process(delta: float) -> void:
	if not _using_stream:
		super._process(delta)
		return
	if not is_instance_valid(_stream):
		return
	var state := _stream.stats()
	if not _stream_ready and int(state.get("resident_splats", 0)) > 0:
		_stream_ready = true
		loading = false
		load_ratio = 1.0
		load_phase = "校园已就绪，继续按视角细化" if stream_lod_enabled else "校园已就绪"
		_ready_seconds = (Time.get_ticks_usec() - _stream_started_us) / 1000000.0
		print("[CampusStream] first residency ready in %.3f s" % _ready_seconds)
		point_count = _pack.source_splats
		elapsed_seconds = _ready_seconds
		loaded.emit({"point_count": point_count, "content_world": content_world_aabb(), "elapsed": elapsed_seconds, "source": _pack.manifest_path, "renderer": "godot-gsplat-stream"})
	var player := _player_node()
	if player != null and hide_inside_aabb.size != Vector3.ZERO:
		_stream.visible = not hide_inside_aabb.has_point(player.global_position)

func content_world_aabb() -> AABB:
	return _pack.world_aabb if _using_stream and _pack != null else super.content_world_aabb()

func content_top_y() -> float:
	return content_world_aabb().end.y if _using_stream else super.content_top_y()

func debug_state() -> Dictionary:
	if not _using_stream:
		return {"renderer": "gdgs_direct"}
	var state: Dictionary = _stream.stats() if is_instance_valid(_stream) else {}
	if is_instance_valid(_stream) and _stream.get_stream_runtime() != null:
		state["wanted_nodes"] = _stream.get_stream_runtime().wanted_count()
	state.merge({"renderer": "godot-gsplat-stream", "lod_enabled": stream_lod_enabled, "first_residency_seconds": _ready_seconds, "budget_nodes": stream_budget_nodes, "requested_sse": stream_sse, "effective_sse": preload("res://addons/gdgs/runtime/stream/gaussian_stream_lod.gd").last_threshold, "sh_degree": _pack.sh_degree if _pack != null else -1, "source_splats": _pack.source_splats if _pack != null else 0})
	if is_instance_valid(_stream):
		state["world_transform_identity"] = _stream.global_transform.is_equal_approx(Transform3D.IDENTITY)
	return state
