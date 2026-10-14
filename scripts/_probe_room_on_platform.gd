extends SceneTree
## 探针：把「画室 609」按给定缩放/朝向摆到悬浮平台上，用**游戏自己的相机**
## 渲出真实观感，用来定 world_scale / yaw / 下沉量。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_room_on_platform.gd -- \
##         --sog=res://splatdata/room609.sogdata --scale=7.2 --yaw=18.1 \
##         --anchor=0.022,-0.333,-0.121 --floor=0.05 --margin=0.5 --maxscale=0.5
## 输出：…/_arisu_captures/_room/*.png
##
## 说明：本探针用 --splat=off 起场景（不加载校园那份 615 万点），再手动挂房间节点，
## 所以渲出来的就是玩家真正会看到的画面。

const SplatSceneScript := preload("res://scripts/splat_scene.gd")

var _scale := 7.2
var _yaw := 18.1
var _anchor := Vector3(0.022, -0.333, -0.121)
var _floor := 0.05
var _margin := 0.5
var _max_scale := 0.5
var _source := "res://splatdata/room609.sogdata"
var _tag := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sog="):
			_source = a.substr(6)
		elif a.begins_with("--scale="):
			_scale = float(a.substr(8))
		elif a.begins_with("--yaw="):
			_yaw = float(a.substr(6))
		elif a.begins_with("--floor="):
			_floor = float(a.substr(8))
		elif a.begins_with("--margin="):
			_margin = float(a.substr(9))
		elif a.begins_with("--maxscale="):
			_max_scale = float(a.substr(11))
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--anchor="):
			var parts := a.substr(9).split(",")
			if parts.size() == 3:
				_anchor = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

	root.size = Vector2i(1600, 900)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _frames(10)

	var room: Node3D = SplatSceneScript.new()
	room.name = "Room609Probe"
	room.set("sog_path", _source)
	room.set("world_scale", _scale)
	room.set("yaw_degrees", _yaw)
	room.set("auto_place", false)
	room.set("use_anchor", true)
	room.set("anchor_source", _anchor)
	room.set("anchor_world", Vector3(0.0, _floor, 0.0))
	room.set("crop_enabled", true)
	room.set("crop_margin", _margin)
	room.set("crop_max_scale", _max_scale)
	room.set("cache_mode", "auto")
	room.set("auto_start", false)
	game.add_child(room)
	room.call("load_now", Callable(self, "_on_progress"))
	if not room.call("is_ready"):
		push_error("房间泼溅没建立起来")
		quit(1)
		return

	var box: AABB = room.call("content_world_aabb")
	var top := float(room.call("content_top_y"))
	print("[rom] scale=%.2f yaw=%.1f  世界包围盒 pos %s size %s  顶面 y=%.2f  平台 40×40" % [
		_scale, _yaw, str(box.position.snappedf(0.1)), str(box.size.snappedf(0.1)), top])
	print("[rom] 裁剪 %s" % str(room.get("crop_stats")))

	var player: Player = game.get_node("Player")
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_room")
	DirAccess.make_dir_recursive_absolute(out)
	var prefix := "%s%04d" % [_tag, int(round(_scale * 10.0))]

	var views := [
		# [名字, 玩家位置, 相机绕角, 俯仰, 说明]
		["spawn", Vector3(0.0, 0.05, 6.0), 0.0, -0.04, "出生点平视"],
		["lookdown", Vector3(0.0, 0.05, 6.0), 0.0, -0.45, "出生点低头 26°"],
		["inside", Vector3(0.0, 0.05, -2.0), 0.0, -0.10, "走进房间中央"],
		["high", Vector3(0.0, 0.05, 6.0), 0.0, -1.05, "出生点低头 60°"],
	]
	for v in views:
		player.global_position = v[1]
		player.velocity = Vector3.ZERO
		player._yaw = v[2]
		player._facing_yaw = player._yaw + PI
		player.model_root.rotation.y = player._facing_yaw
		player.rig.rotation.y = player._yaw
		player._pitch = v[3]
		await _frames(30)
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var path: String = out.path_join("%s_%s.png" % [prefix, v[0]])
		img.save_png(path)
		print("  [img] %-8s %s  %s" % [v[0], path.get_file(), v[4]])

	# 顺便量一下：玩家站在房间中央时，脚下地板与眼睛的高度关系
	player.global_position = Vector3(0.0, 0.05, 0.0)
	await _frames(20)
	print("[rom] 玩家在房间中心：y=%.2f，房间里地板世界 y=%.2f，相对眼高 %.2f m" % [
		player.global_position.y, _floor, player.hip_height + 0.05])
	quit(0)


func _frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _on_progress(phase: String, done: int, total: int) -> void:
	if done >= total:
		print("  [加载] %s 完成" % phase)
