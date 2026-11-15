extends SceneTree
## Check export filtering plus actual PCK mounting and random-access stream IO.
const Pack := preload("res://addons/gdgs/runtime/stream/gaussian_stream_pack.gd")
const MANIFEST := "res://splatdata/campus_stream/campus.manifest.json"
const PAYLOAD := "res://splatdata/campus_stream/campus.nodes.bin"
var _failures := 0
var _passed := 0

func _initialize() -> void:
	var config := ConfigFile.new()
	_check(config.load("res://export_presets.cfg") == OK, "export preset loads")
	for path in [MANIFEST, PAYLOAD]:
		_check(_matches(path.trim_prefix("res://"), str(config.get_value("preset.0", "include_filter", ""))), "included in export: " + path)
		_check(not _matches(path.trim_prefix("res://"), str(config.get_value("preset.0", "exclude_filter", ""))), "not excluded from export: " + path)
	var source := Pack.new()
	_check(source.load_from(MANIFEST) == OK, "local pack loads")
	if not source.is_loaded():
		quit(1)
		return
	var last := source.node_count - 1
	var file := FileAccess.open(PAYLOAD, FileAccess.READ)
	_check(file.get_length() == source.byte_offset[last] + source.payload_bytes(last), "all node bytes present through final node")
	file.close()
	var directory := "res://_tools/_tmp/gsplat_stream/"
	DirAccess.make_dir_recursive_absolute(directory)
	var packer := PCKPacker.new()
	_check(packer.pck_start(directory + "campus_pack_check.pck") == OK, "PCK writer starts")
	_check(packer.add_file("res://_campus_pack_check/campus.manifest.json", MANIFEST) == OK, "manifest added to PCK")
	_check(packer.add_file("res://_campus_pack_check/campus.nodes.bin", PAYLOAD) == OK, "payload added to PCK")
	_check(packer.flush() == OK, "PCK writer finishes")
	_check(ProjectSettings.load_resource_pack(directory + "campus_pack_check.pck"), "PCK mounts")
	var mounted := Pack.new()
	_check(mounted.load_from("res://_campus_pack_check/campus.manifest.json") == OK, "relative payload resolves inside PCK")
	var packaged_file := FileAccess.open(mounted.nodes_bin_path, FileAccess.READ)
	var local_file := FileAccess.open(source.nodes_bin_path, FileAccess.READ)
	var bytes_match := true
	for node in range(0, source.node_count, 17):
		packaged_file.seek(mounted.byte_offset[node])
		local_file.seek(source.byte_offset[node])
		if packaged_file.get_buffer(source.payload_bytes(node)) != local_file.get_buffer(source.payload_bytes(node)):
			bytes_match = false
			break
	_check(bytes_match, "115 random-access node reads match local bytes inside PCK")
	packaged_file.close()
	local_file.close()
	print("[stream-pack] RESULT %d passed / %d failed" % [_passed, _failures])
	quit(0 if _failures == 0 else 1)

func _matches(path: String, filters: String) -> bool:
	for pattern in filters.split(","):
		if not pattern.strip_edges().is_empty() and path.matchn(pattern.strip_edges()):
			return true
	return false

func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
	else:
		_failures += 1
	print("[stream-pack] %s %s" % ["PASS" if ok else "FAIL", label])
