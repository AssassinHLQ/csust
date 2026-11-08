extends SceneTree
## 一次性**出图**探针：把机甲飞行态渲出来，肉眼确认「喷气 + 蓝色火焰」长什么样。
##
## 跑法（**要窗口，不要 headless**）：
##   & <godot> --path . --script res://scripts/_probe_carrier_shot.gd -- --no-capture
##
## 出图目录：`_arisu_captures/_carrier/`（已被 .gitignore 排除）
##   · 0_ground.png   站在地面（待机，火焰很弱）
##   · 1_takeoff.png  刚起飞（推力拉满）
##   · 2_hover.png    悬停
##   · 3_side.png     侧面 45°，看火焰长度和推进器位置
##
## ⚠️ 用独立相机（不复用玩家肩上的那个），不然镜头在背后看不见腿上的推进器。

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

const OUT_DIR := "res://_arisu_captures/_carrier/"

var _player: Player
var _cf: CarrierForm
var _cam: Camera3D


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	MechState.set_carrier_for_test(true)

	var scene := Node3D.new()
	scene.name = "ShotStage"
	root.add_child(scene)

	# 一块地面（不然看不出「离地」）
	var floor_body := StaticBody3D.new()
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.28, 0.27, 0.26)
	floor_mesh.material_override = fmat
	floor_body.add_child(floor_mesh)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.4, 40)
	col.shape = box
	col.position.y = -0.2
	floor_body.add_child(col)
	scene.add_child(floor_body)

	_player = PlayerScene.instantiate() as Player
	_player.global_position = Vector3(0, 0.6, 0)
	scene.add_child(_player)
	await process_frame
	await process_frame

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	scene.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.10, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.52, 0.62)
	e.ambient_light_energy = 0.55
	e.glow_enabled = true
	e.glow_intensity = 0.5
	env.environment = e
	scene.add_child(env)

	_cam = Camera3D.new()
	_cam.fov = 46.0
	scene.add_child(_cam)
	_cam.current = true

	_cf = _player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	if _cf == null:
		push_error("[Shot] 没有 CarrierForm")
		quit(1)
		return
	if not _cf.set_form(true):
		push_error("[Shot] 变形失败（模型不在？）")
		quit(1)
		return
	print("[Shot] 变形成功，开始出图")

	# ── 0. 地面待机 ──
	_aim(Vector3(3.2, 1.9, 4.4), Vector3(0, 1.0, 0))
	await _settle(30)
	await _shot("0_ground")

	# ── 1. 起飞（推力拉满）──
	_cf.call("_take_off")
	_cf.set("_vert_want", 1.0)
	_player.global_position.y = 1.2
	await _settle(36)
	_aim(Vector3(3.6, 2.6, 4.8), Vector3(0, 1.5, 0))
	await _settle(6)
	await _shot("1_takeoff")

	# ── 2. 悬停（空中，推力中档）──
	_player.global_position.y = 3.0
	_player.velocity = Vector3(0, 0, 0)
	_cf.set("_vert_want", 0.0)
	_cf.set("_hold_y", 3.0)
	await _settle(40)
	_aim(Vector3(3.8, 3.9, 5.0), Vector3(0, 3.0, 0))
	await _settle(6)
	await _shot("2_hover")

	# ── 3. 侧面：看推进器与火焰的关系 ──
	_player.global_position.y = 2.6
	_cf.set("_vert_want", 1.0)
	await _settle(24)
	_aim(Vector3(5.6, 3.0, 1.2), Vector3(0, 2.6, 0))
	await _settle(6)
	await _shot("3_side")

	# ── 4. 正视（确认朝向没躺倒）：相机放 +Z 正前方 ──
	_player.global_position.y = 1.6
	_cf.set("_vert_want", 0.0)
	_cf.set("_hold_y", 1.6)
	await _settle(30)
	_aim(Vector3(0.0, 1.9, 4.6), Vector3(0, 1.6, 0))
	await _settle(6)
	await _shot("4_front")

	# ── 5. 地面正视图（最直观地看「站姿 + 朝向」）──
	_cf.call("_land")
	_player.global_position.y = 0.6
	_cf.call("_sync_face")
	await _settle(24)
	_aim(Vector3(0.0, 1.75, 4.4), Vector3(0, 1.0, 0))
	await _settle(6)
	await _shot("5_ground_front")

	# ── 6. 机甲开火：双炮齐射，看炮口蓝焰 ──
	var wpn := _player.get_node_or_null("Weapon") as Weapon
	if wpn != null:
		_player.global_position = Vector3(0, 0.6, 0)
		_cf.call("_sync_face")
		_cf.call("_push_cannon_muzzles")
		await _settle(4)
		# 从**侧前方**看：正前方看不清炮口（炮口朝前，焰沿视线方向被压扁）
		_aim(Vector3(3.0, 1.7, 3.4), Vector3(0, 1.2, 0))
		await _settle(4)
		# 连开几发，让焰口保持点亮
		for i in 6:
			wpn.set("_cooldown", 0.0)
			wpn.current_ammo = wpn.magazine_size
			wpn.shoot()
			_cf.call("_run_effects", 1.0 / 60.0)
		await RenderingServer.frame_post_draw
		await _shot("6_fire_side")

		# 再来一张：**正侧面**。炮口焰朝前喷，正侧面才能看见焰柱的完整长度
		# （正前方看是「正对镜头」，被压成一个圆点；侧后方被肩甲翼片挡住）。
		for i in 6:
			wpn.set("_cooldown", 0.0)
			wpn.current_ammo = wpn.magazine_size
			wpn.shoot()
			_cf.call("_run_effects", 1.0 / 60.0)
		_aim(Vector3(3.0, 1.5, -0.3), Vector3(0, 1.2, -0.3))
		await _settle(2)
		await _shot("7_fire_side")

		# 正上方俯视：看两门炮是不是左右对称
		for i in 6:
			wpn.set("_cooldown", 0.0)
			wpn.current_ammo = wpn.magazine_size
			wpn.shoot()
			_cf.call("_run_effects", 1.0 / 60.0)
		_aim(Vector3(0.0, 4.6, 1.2), Vector3(0, 1.0, -0.3))
		await _settle(2)
		await _shot("8_fire_top")

		# ── 9. 激光大炮：从侧后方看整条光束（用户 2026-11-08：「炮是激光大炮」）──
		# 相机拉远到 9 m、抬到 3 m，让机甲和光束同框。
		_player.global_position = Vector3(0, 0.6, 2.0)
		_cf.call("_sync_face")
		await _settle(4)
		wpn.set("_cooldown", 0.0)
		wpn.current_ammo = wpn.magazine_size
		wpn.shoot()
		await _settle(1)
		_aim(Vector3(7.0, 3.2, 6.5), Vector3(0, 1.0, -8.0))
		await process_frame
		await _shot("9_beam")

	MechState.set_carrier_for_test(false)
	print("[Shot] 出图完成 → %s" % OUT_DIR)
	quit(0)


func _aim(from: Vector3, to: Vector3) -> void:
	_cam.look_at_from_position(from, to, Vector3.UP)


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR + name_ + ".png")
	var err := img.save_png(path)
	print("  %s → %s（%dx%d）err=%d" % [
		name_, path, img.get_width(), img.get_height(), err])
