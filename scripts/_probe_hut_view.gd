extends SceneTree
## 探针：**开始平台上那间小屋（`scenes/mesh_hut.tscn`）的门与屋顶**。
##
## 用户 2026-10-21 的两张截图 + 三句话：
##   ① 「门这里上面有破绽要去除」          → 门洞上方那道缝
##   ② 「我刚刚编辑器删了几个方块挡视野了，但是游戏里面看为什么还有碰撞」
##   ③ 「这个开始平台房子顶上的板子也要删掉」 → 门上方那块 `Canopy` 雨篷
##
## 这个探针干两件事：
##   A. 出图（门外正视 / 门框上方特写 / 屋里往外 / 斜俯视看屋顶 / 顶视）
##   B. **量缝**：从门外朝 +X 打一排射线，按高度看「哪里透 / 哪里实」，顺便把
##      `MeshHut` 底下所有 `CollisionShape3D` 的世界坐标形状列出来 —— 用户说的
##      「删了方块还有碰撞」如果属实，这里就能看见**没有网格的碰撞**。
##
## 用法：godot --path <工程> --script res://scripts/_probe_hut_view.gd [-- --splat=off]
## 出图：…/_arisu_captures/_hut/*.png

const OUT_SUB := "_hut"
## `game.tscn` 里 `MeshHut` 的落点
const HUT_X := 14.0
const HUT_Z := -15.5

var _cam: Camera3D
var _out: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 40:
		await process_frame
	var player := game.get_node_or_null("Player") as Player
	if player != null:
		player.set_process_input(false)
	for n in ["HUD", "SettingsMenu", "DialogueBox", "Parkour/ParkourHUD",
			"Parkour/Futures/FuturesHUD"]:
		var c := game.get_node_or_null(n)
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	# 人挪到屋外空地，免得贴图/泼溅因为玩家位置切来切去
	if player != null:
		player.global_position = Vector3(HUT_X, 0.4, HUT_Z + 6.0)
		player.velocity = Vector3.ZERO
		for _i in 20:
			await process_frame

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)
	_cam = Camera3D.new()
	_cam.fov = 68.0
	_cam.near = 0.05
	_cam.far = 500.0
	_cam.current = true
	root.add_child(_cam)

	var hut := game.get_node_or_null("MeshHut")
	if hut == null:
		print("[hut] 找不到 MeshHut")
		quit(1)
		return
	_dump_collisions(hut)
	_ray_gap(hut)

	# 门在局部 (−3.3, ·, 0) → 世界 x = 10.7
	var door_x := HUT_X - 3.3
	await _shot("1_door_front",
		Vector3(door_x - 3.2, 1.70, HUT_Z), Vector3(door_x, 1.45, HUT_Z))
	await _shot("2_door_top",
		Vector3(door_x - 1.8, 1.62, HUT_Z), Vector3(door_x, 2.45, HUT_Z))
	await _shot("3_door_angle",
		Vector3(door_x - 2.6, 3.10, HUT_Z + 2.6), Vector3(door_x, 1.90, HUT_Z))
	await _shot("4_inside_out",
		Vector3(HUT_X + 0.4, 1.60, HUT_Z), Vector3(door_x, 1.45, HUT_Z))
	await _shot("5_roof_above",
		Vector3(HUT_X + 2.0, 7.50, HUT_Z + 8.0), Vector3(HUT_X, 2.45, HUT_Z))
	print("\n出图目录：%s" % _out)
	quit(0)


## 把 hut 里所有碰撞体列出来：世界坐标 + 形状尺寸 + 有没有对应网格
func _dump_collisions(hut: Node) -> void:
	print("[hut] ── 碰撞体清单 ──")
	var n := 0
	for c in hut.find_children("*", "CollisionShape3D", true, false):
		var cs := c as CollisionShape3D
		if cs.shape == null:
			continue
		var d := ""
		if cs.shape is BoxShape3D:
			d = str((cs.shape as BoxShape3D).size)
		elif cs.shape is CylinderShape3D:
			d = "r%.2f h%.2f" % [(cs.shape as CylinderShape3D).radius,
				(cs.shape as CylinderShape3D).height]
		var body := cs.get_parent()
		print("  %-34s 世界 %s  %s  父=%s" % [
			str(hut.get_path_to(cs)), str(cs.global_position.snappedf(0.01)),
			d, body.name if body != null else "?"])
		n += 1
	print("[hut] 共 %d 个 CollisionShape3D；CSG 自带碰撞的节点：" % n)
	for c in hut.find_children("*", "CSGShape3D", true, false):
		var s := c as CSGShape3D
		if s.use_collision:
			print("  CSG %-20s use_collision=true  %s" % [s.name, str(s.global_position.snappedf(0.01))])


## 从门外沿 +X 打一排射线，看门洞上方到底是「洞」还是「实墙」
func _ray_gap(hut: Node) -> void:
	var space := (hut as Node3D).get_world_3d().direct_space_state
	var door_x := HUT_X - 3.3
	print("[hut] ── 门洞剖面（射线 x=%.2f → +X，z=%.2f）──" % [door_x - 2.0, HUT_Z])
	var y := 0.4
	while y <= 2.60:
		var from := Vector3(door_x - 2.0, y, HUT_Z)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(6.0, 0, 0))
		var hit := space.intersect_ray(q)
		var s := "透（没打到东西）"
		if not hit.is_empty():
			var hp: Vector3 = hit["position"]
			s = "打到 x=%.2f（%.2f m 后）" % [hp.x, hp.x - from.x]
		print("  y=%.2f  %s" % [y, s])
		y += 0.1


func _shot(name: String, pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	if Engine.get_frames_drawn() == before:
		print("  [img] 跳过 %s（3 s 内没有新帧）" % name)
		return
	for _i in 8:
		await process_frame
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("[hut] %s ← 相机 %s" % [name, str(pos.snappedf(0.1))])
