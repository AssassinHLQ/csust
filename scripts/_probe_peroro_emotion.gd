extends SceneTree
## 一次性探针：佩洛洛斯拉的五张「表情变体」到底哪张好看。
##
## 原 FBX 把五种脸（闭眼 / 张嘴 / 吐舌…）**叠在同一个位置**，靠开关切换。
## 这里把每个编号单独打开、其余全关，各出一张正面近照，人眼挑一个。
##
## 用法：godot --path <工程> --script res://scripts/_probe_peroro_emotion.gd -- --splat=off
## 输出：`_arisu_captures/_boss/90_emotion_0.png` .. `94_emotion_5.png`

var _cam: Camera3D
var _meshes: Array[MeshInstance3D] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(900, 600)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame
	for n in ["HUD", "SettingsMenu", "DialogueBox", "Parkour/ParkourHUD"]:
		var c := game.get_node_or_null(n) as CanvasLayer
		if c != null:
			c.visible = false
	var boss := game.get_node_or_null("BossPeroro") as Boss
	if boss == null:
		print("!! 没有 BossPeroro")
		quit(1)
		return
	for mi in _all(boss.model, "MeshInstance3D"):
		if (mi as MeshInstance3D).name.begins_with("Perorozilla_Emotion_"):
			_meshes.append(mi as MeshInstance3D)
	_meshes.sort_custom(func(a, b): return a.name < b.name)
	print("[probe] 表情网格 %d 个：%s"
		% [_meshes.size(), ", ".join(_meshes.map(func(m): return m.name))])

	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_boss")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.near = 0.05
	root.add_child(_cam)
	_cam.make_current()
	# 头部：身高 4 m 的鸟，脸大概在 0.72 高度处
	var c := boss.global_position + Vector3(0, boss.visual_size.y * 0.72, 0)
	_cam.global_position = c + Vector3(0, 0.5, -5.0)
	_cam.look_at(c, Vector3.UP)

	for k in range(0, _meshes.size() + 1):
		for i in _meshes.size():
			_meshes[i].visible = (i + 1 == k)
		await _shot(out_dir.path_join("%d_emotion_%d.png" % [90 + k, k]))
	print("\n出图目录：%s" % out_dir)
	quit(0)


func _shot(path: String) -> void:
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	for _i in 6:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("[shot] %s" % path.get_file())


func _all(node: Node, cls: String) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out
