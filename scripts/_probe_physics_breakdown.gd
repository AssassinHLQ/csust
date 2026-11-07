extends SceneTree
## 把物理成本放大到看得清：物理步频拉到 240 Hz（每帧 8 步），再逐项拆。
##   _tools/run_shot.sh res://scripts/_probe_physics_breakdown.gd -- --splat=off --story=off
##
## 8 步/帧时帧时间基本就是「8 × 每步成本」，差异不会被渲染噪声盖住。


const SPOT := Vector3(54.87, 0.6, 3.38)
const WARM := 90
const SAMPLE := 30


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _measure(tag: String) -> float:
	await _wait(WARM)
	var f0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
	var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
	var steps := float(Engine.get_physics_frames() - f0) / float(SAMPLE)
	var ms := dt / float(SAMPLE) * 1000.0
	print("[bd] %-24s 帧=%7.2fms 步/帧=%.2f 每步≈%5.2fms fps=%5.1f" % [
		tag, ms, steps, ms / maxf(steps, 0.001), float(SAMPLE) / maxf(dt, 0.0001)])
	return ms


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(180)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = 240   # 放大器：每帧尽量跑满 8 步
	Engine.max_physics_steps_per_frame = 8

	var player := game.get_node_or_null("Player") as Node3D
	if player == null:
		print("[bd] 缺 Player")
		quit(1)
		return
	player.global_position = SPOT
	player.set("velocity", Vector3.ZERO)

	var comps: Array = []
	for c in game.get_children():
		if c is CharacterBody3D and String(c.name).begins_with("Companion"):
			comps.append(c)
	print("[bd] 同伴 %d 个；物理步频 240 Hz（放大用）" % comps.size())

	await _measure("A 基线")

	for c in comps:
		(c as Node).set_physics_process(false)
	await _measure("B 关同伴物理")
	for c in comps:
		(c as Node).set_physics_process(true)

	var cs := game.get_node_or_null("GameDevRoom/Model/Collision/Mesh") as CollisionShape3D
	var body := game.get_node_or_null("GameDevRoom/Model/Collision") as StaticBody3D
	if body != null:
		var old_layer := body.collision_layer
		body.collision_layer = 0
		await _measure("C 关部室碰撞")
		body.collision_layer = old_layer
	else:
		print("[bd] 找不到部室碰撞体（%s）" % str(cs))

	for c in comps:
		var cb := c as CharacterBody3D
		cb.set_meta("old_layer", cb.collision_layer)
		cb.set_meta("old_mask", cb.collision_mask)
		cb.collision_layer = 0
		cb.collision_mask = 0
	await _measure("D 同伴碰撞也关")
	for c in comps:
		var cb := c as CharacterBody3D
		cb.collision_layer = int(cb.get_meta("old_layer"))
		cb.collision_mask = int(cb.get_meta("old_mask"))

	await _measure("E 全部还原")
	quit(0)