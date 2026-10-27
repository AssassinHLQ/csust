extends SceneTree
## 量：子弹实际落点 vs 准星中心射线，差多少（世界米 + 屏幕像素）。
##   _tools/run_shot.sh res://scripts/_probe_aim_offset.gd -- --splat=off --no-capture
##
## 做法：同一条相机中心射线独立打一次（= 准星真正压着的点），再让 Weapon 开一枪，
## 从 `_in_flight` 里取实际落点，两者相减。关掉散布，只留几何误差。

const Companion := preload("res://scripts/companion.gd")


func _initialize() -> void:
	_run.call_deferred()


func _aim_and_measure(tag: String, game: Node, player: Node3D, weapon: Node, pitch_deg: float) -> void:
	player.set("_pitch", deg_to_rad(pitch_deg))
	for _i in 90:
		await physics_frame
	await process_frame

	var cam := player.get("cam") as Camera3D
	var cam_dir: Vector3 = player.call("camera_forward")
	var space := player.get_world_3d().direct_space_state

	var q := PhysicsRayQueryParameters3D.create(
		cam.global_position, cam.global_position + cam_dir * 300.0)
	q.collide_with_areas = false
	q.collision_mask = 0xFFFFFFFF & ~Companion.LAYER
	q.exclude = [player.get_rid()]
	var ideal := space.intersect_ray(q)
	print("[%s] 相机 %s  朝向 %s  射线 %s → %s"
		% [tag, str(cam.global_position.snappedf(0.01)), str(cam_dir.snappedf(0.001)),
			str(cam.global_position.snappedf(0.01)),
			str((cam.global_position + cam_dir * 300.0).snappedf(0.01))])
	if ideal.is_empty():
		print("[%s] 相机中心射线没打到任何东西，跳过" % tag)
		return

	var before := (weapon.get("_in_flight") as Array).size()
	weapon.call("_fire_raycast")
	var flight: Array = weapon.get("_in_flight")
	if flight.size() <= before:
		print("[%s] 没有生成弹丸，跳过" % tag)
		return
	var impact: Vector3 = flight[flight.size() - 1][2]

	var p_ideal: Vector2 = cam.unproject_position(ideal.position)
	var p_impact: Vector2 = cam.unproject_position(impact)
	var px := p_impact - p_ideal
	var d_ideal := cam.global_position.distance_to(ideal.position)
	var d_impact := cam.global_position.distance_to(impact)
	print("[%s] 相机 %s  朝向 %s" % [tag, str(cam.global_position.snappedf(0.01)),
		str(cam_dir.snappedf(0.001))])
	print("[%s] 准星点 %s（距相机 %.2f m）" % [tag, str(ideal.position.snappedf(0.001)), d_ideal])
	print("[%s] 实际落点 %s（距相机 %.2f m）" % [tag, str(impact.snappedf(0.001)), d_impact])
	print("[%s] 世界差 (%.3f, %.3f, %.3f) m ｜ 屏幕差 (%.1f, %.1f) px ｜ 屏幕距离 %.1f px"
		% [tag, impact.x - ideal.position.x, impact.y - ideal.position.y,
			impact.z - ideal.position.z, px.x, px.y, px.length()])


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false

	var player := game.get_node_or_null("Player") as Node3D
	var weapon := game.get_node_or_null("Player/Weapon")
	weapon.set("spread_hip", 0.0)
	weapon.set("spread_aim", 0.0)
	print("散布已归零：hip=%.4f aim=%.4f" % [weapon.get("spread_hip"), weapon.get("spread_aim")])

	# 平视：打到房间远处那面墙
	await _aim_and_measure("平视", game, player, weapon, 0.0)
	# 俯视 45°：打到脚边的地板（近处，偏移在屏幕上会被放得更大）
	await _aim_and_measure("俯视45°", game, player, weapon, -45.0)

	quit(0)
