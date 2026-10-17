extends SceneTree
## 探针：**同相位侧视 A/B** —— 只跑 vs 跑打开火，看「后倾」到底在不在躯干上。
##
## 为什么要这一张：数据层已经证明躯干在过滤名单里（`_probe_fire_vs_run_bones.gd`），
## 运行时也证明 6.8 m/s 时用的是滤过躯干的 `UpperBodyMove`
## （`_probe_runfire_runtime.gd`）。但用户看着还是后倾 —— 那就把两种状态**冻在同一相位**
## 拍侧视图，用眼睛判：躯干角度一样就是枪/手臂的姿态问题，不一样就是过滤没生效。
##
## 手法：
##   · 关玩家物理、钉住位置与朝向（`model_root.rotation.y = 0` → 脸朝世界 +Z）；
##   · 基础层 `Move_Ing` 冻在 0.30 s（`speed_scale = 0`，每帧照写姿态）；
##   · 开火层用**运行时真的那个** `anim.upper_move`，冻在 0.40 s；
##     A 组不播它，B 组播 —— 两组唯一的差别就是"有没有开火"。
##
## 输出 `_arisu_captures/_runfire_side/montage.png`（左 A 右 B）
##
## 用法：godot --path <工程> --script res://scripts/_probe_runfire_side.gd -- --splat=off

const OUT_SUB := "_runfire_side"
const BASE_T := 0.30
const FIRE_T := 0.40
const CELL := Vector2i(560, 700)

var _cam: Camera3D
var _p: Player
var _anim: AnimDriver


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = CELL
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)

	for n in ["HUD", "SettingsMenu", "DialogueBox", "RoomProxy", "Parkour/ParkourHUD"]:
		var x: Node = game.get_node_or_null(n)
		if x is CanvasLayer:
			(x as CanvasLayer).visible = false
		elif x is CanvasItem:
			(x as CanvasItem).visible = false
		elif x is Node3D:
			(x as Node3D).visible = false
	for ch in game.get_children():
		if ch is Companion or ch is Boss:
			(ch as Node3D).visible = false

	_p = game.get_node_or_null("Player") as Player
	if _p == null:
		print("!! 没有 Player")
		quit(1)
		return
	_anim = _p.anim as AnimDriver
	if _anim == null:
		print("!! Player 上没有 AnimDriver")
		quit(1)
		return

	# 冻住：位置、朝向、物理都不许动
	_p.set_physics_process(false)
	_p.set_process_input(false)
	_p.velocity = Vector3.ZERO
	_p.global_position = Vector3(0, 0.05, 6)
	_p._yaw = 0.0
	_p._facing_yaw = 0.0
	_p.model_root.rotation.y = 0.0
	_anim.state = AnimDriver.State.LOCOMOTION
	_anim._auto_return = false

	_cam = Camera3D.new()
	_cam.fov = 30.0
	_cam.near = 0.05
	_cam.far = 100.0
	root.add_child(_cam)
	_cam.make_current()
	# 侧视：玩家脸朝 +Z，相机放 +X 侧
	_cam.global_position = _p.global_position + Vector3(5.4, 1.30, 0.0)
	_cam.look_at(_p.global_position + Vector3(0.0, 0.95, 0.0), Vector3.UP)

	# 场景的夕阳被墙挡住，侧拍会一片黑：自己补两盏
	var key := DirectionalLight3D.new()
	key.global_transform = Transform3D(Basis.looking_at(Vector3(-1, -0.35, 0), Vector3.UP),
		_p.global_position + Vector3(4, 4, 2))
	key.light_energy = 0.55
	key.shadow_enabled = false
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.global_transform = Transform3D(Basis.looking_at(Vector3(-1, -0.1, -0.6), Vector3.UP),
		_p.global_position + Vector3(4, 2, -2))
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	root.add_child(fill)

	var move_layer := _anim.upper_move
	print("[side] 移动层 = %s（轨道 %d 条；原始 %d 条）" % [
		"—" if move_layer == null else String(move_layer.name),
		-1 if move_layer == null else move_layer.get_animation("Normal_Attack_Ing").get_track_count(),
		_anim.player.get_animation("Normal_Attack_Ing").get_track_count()])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(out)
	var sheet := Image.create(CELL.x * 2, CELL.y, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.12))

	# ── A：只跑 ──
	await _pose(false)
	_report("A 只跑")
	sheet.blit_rect(await _shot(out.path_join("A_run.png")), Rect2i(Vector2i.ZERO, CELL),
		Vector2i(0, 0))

	# ── B：跑 + 开火（运行时那一层）──
	await _pose(true)
	_report("B 跑+开火")
	sheet.blit_rect(await _shot(out.path_join("B_runfire.png")), Rect2i(Vector2i.ZERO, CELL),
		Vector2i(CELL.x, 0))

	sheet.save_png(out.path_join("montage.png"))
	print("[side] 拼图 %s（左 A 只跑 / 右 B 跑打）" % out.path_join("montage.png"))
	quit(0)


func _pose(fire: bool) -> void:
	_anim.player.speed_scale = 0.0
	_anim.player.play("Move_Ing", -1.0, 1.0)
	_anim.player.seek(BASE_T, true)
	if fire and _anim.upper_move != null:
		_anim.upper_move.speed_scale = 0.0
		_anim.upper_move.play("Normal_Attack_Ing", -1.0, 1.0)
		_anim.upper_move.seek(FIRE_T, true)
	elif _anim.upper_move != null:
		_anim.upper_move.stop()
	await _wait(3)


func _report(tag: String) -> void:
	var sk := _anim.skeleton
	var parts: Array[String] = []
	for bn in ["Bip001 Spine1", "Bip001 Head", "Bip001 R Hand", "Bip001 L Foot"]:
		var i := sk.find_bone(bn)
		if i < 0:
			continue
		var pose := sk.get_bone_global_pose(i)
		if bn.contains("Hand") or bn.contains("Foot"):
			parts.append("%s %s" % [bn.get_slice(" ", 1), str(pose.origin.snappedf(0.01))])
		else:
			parts.append("%s 上轴 %s" % [bn.get_slice(" ", 1),
				str(pose.basis.y.normalized().snappedf(0.01))])
	print("  %-12s %s" % [tag, "   ".join(parts)])


func _shot(file: String) -> Image:
	await _wait(4)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(file)
	print("  [img] %s" % file)
	return img


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
