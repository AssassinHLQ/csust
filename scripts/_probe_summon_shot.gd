extends SceneTree
## 探针：小屋里的「召唤同伴」金垫子 —— 位置对不对、踩上去同伴回不回来。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_summon_shot.gd -- --splat=off
## 输出：…/_arisu_captures/_summon/*.png

const OUT_SUB := "_summon"

var _cam: Camera3D
var _out: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 30:
		await process_frame
	var player := game.get_node_or_null("Player") as Player
	if player != null:
		player.set_process_input(false)
	for n in ["HUD", "SettingsMenu", "DialogueBox"]:
		var c := game.get_node_or_null(n)
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false

	var hut := game.get_node_or_null("MeshHut") as Node3D
	var pad := game.get_node_or_null("MeshHut/SummonPad") as SummonPad
	print("[summon] 小屋 = %s；垫子 = %s" % [
		"没有" if hut == null else str(hut.global_position.snappedf(0.01)),
		"没有" if pad == null else str(pad.global_position.snappedf(0.01))])
	if pad != null:
		print("[summon] 垫子上的字：「%s」" % pad.title_text())
		print("[summon] 同伴 %d 名" % game._companions.size())

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.near = 0.05
	_cam.far = 500.0
	root.add_child(_cam)
	_cam.make_current()

	# ① 人站到门口往里看：垫子应该在正前方地上
	if player != null:
		player.global_position = Vector3(11.2, 0.10, -15.5)
		player.velocity = Vector3.ZERO
		await _wait(10)
	await _shot("1_from_door", Vector3(11.0, 1.65, -15.5), Vector3(16.0, 0.4, -15.2))
	# 贴近平视：读一遍垫子上的字（斜俯视时透视会压扁字形，判断不了正反）
	await _shot("1b_close", Vector3(13.1, 1.15, -15.2), Vector3(15.0, 0.05, -15.2))
	await _shot("2_top", Vector3(14.2, 5.2, -15.2), Vector3(14.4, 0.0, -15.2))

	# ② 踩上去 → 召唤
	if player != null and pad != null:
		player.global_position = pad.global_position + Vector3.UP * 0.10
		player.velocity = Vector3.ZERO
		await _wait(12)
		print("[summon] 召唤后：")
		for c in game._companions:
			var comp := c as Companion
			print("    %-18s %s  离垫子 %.2f m  待命=%s" % [comp.name,
				str(comp.global_position.snappedf(0.01)),
				comp.global_position.distance_to(pad.global_position),
				str(comp.is_standby())])
		await _shot("3_summoned", Vector3(11.0, 1.75, -15.5), Vector3(16.0, 0.8, -15.0))
		await _shot("4_summoned_top", Vector3(14.2, 6.0, -15.2), Vector3(14.4, 0.0, -15.2))
	print("\n出图目录：%s" % _out)
	quit(0)


func _shot(name: String, pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	if Engine.get_frames_drawn() == before:
		print("  [img] 跳过 %s（4 s 内没有新帧）" % name)
		return
	await _wait(8)
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("[summon] %s ← 相机 %s" % [name, str(pos.snappedf(0.1))])


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
