extends SceneTree
## 验证部室新碰撞：① 24 块盒子在不在；② 门通、墙挡、地板站得住（射线判）；
## ③ 同一次运行里交替「盒子 / 旧 trimesh」量物理开销。
##   _tools/run_shot.sh res://scripts/_probe_gamedev_collision.gd -- --splat=off --story=off


const TRIMESH := "res://assets/collision/gamedev_room_trimesh.res"
const WARM := 60
const SAMPLE := 30


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


## 从 from 朝 dir 打一条射线，返回命中距离（不中返回 -1）
func _ray(from: Vector3, dir: Vector3) -> float:
	var st := root.world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * 60.0)
	q.collide_with_areas = false
	var hit := st.intersect_ray(q)
	return -1.0 if hit.is_empty() else from.distance_to(hit["position"])


func _measure(tag: String) -> void:
	await _wait(WARM)
	var f0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
	var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
	var steps := float(Engine.get_physics_frames() - f0) / float(SAMPLE)
	print("[gcol] %-16s fps=%6.1f 帧=%6.2fms 步/帧=%.2f" % [
		tag, float(SAMPLE) / maxf(dt, 0.0001), dt / float(SAMPLE) * 1000.0, steps])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(180)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var col := game.get_node_or_null("GameDevRoom/Model/Collision") as StaticBody3D
	if col == null:
		print("[gcol] 找不到部室 Collision")
		quit(1)
		return
	print("[gcol] Collision 下有 %d 块碰撞（旧 trimesh 为 1 块 21,892 面）" % col.get_child_count())

	var player := game.get_node_or_null("Player") as Node3D
	player.global_position = Vector3(52.0, 0.6, 3.0)
	player.set("velocity", Vector3.ZERO)
	await _wait(90)

	# ① 门：从门外朝东打，应该一路进到屋子最里面（约 14 m）
	var d_door := _ray(Vector3(43.5, 1.4, 3.48), Vector3.RIGHT)
	# ② 实体墙：门外朝东，应该立刻撞墙（西墙在世界 x≈45.17）
	var d_wall := _ray(Vector3(43.5, 1.4, 0.0), Vector3.RIGHT)
	# ③ 地板：从屋里朝下
	var d_floor := _ray(Vector3(52.0, 3.0, 0.0), Vector3.DOWN)
	# ④ 天花板：从屋里朝上
	var d_ceil := _ray(Vector3(52.0, 1.0, 0.0), Vector3.UP)
	# ⑤ 电视机（家具）：站在屋中央朝 CRT 方向
	var d_tv := _ray(Vector3(52.0, 1.2, 1.0), Vector3(57.8, 1.2, 1.0) - Vector3(52.0, 1.2, 1.0))
	print("[gcol] 射线：门洞 %.2f m（应≈14.5，说明通）｜实墙 %.2f m（应≈1.2）｜地板 %.2f m（应≈3.0）｜天花板 %.2f m（应≈5.6）｜朝家具 %.2f m" % [
		d_door, d_wall, d_floor, d_ceil, d_tv])

	# ③ 物理开销 A/B：同样一次运行里交替 盒子 / 旧 trimesh
	Engine.physics_ticks_per_second = 240      # 放大物理占比
	Engine.max_physics_steps_per_frame = 8
	await _measure("盒子（现状）")

	var shape := load(TRIMESH) as ConcavePolygonShape3D
	if shape == null:
		print("[gcol] 读不到旧 trimesh，跳过 A/B")
		quit(0)
		return
	var saved: Array = []
	for c in col.get_children():
		col.remove_child(c)
		saved.append(c)
	var old := CollisionShape3D.new()
	old.shape = shape
	col.add_child(old)
	await _measure("旧 trimesh")
	col.remove_child(old)
	for c in saved:
		col.add_child(c)
	await _measure("盒子（还原）")
	quit(0)