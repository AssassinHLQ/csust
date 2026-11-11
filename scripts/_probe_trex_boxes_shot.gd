extends SceneTree
## 出图：霸王龙的碰撞盒到底贴不贴得住身体 —— **idle 与技能动画中各拍一张**。
##
##   _tools/run_shot.sh res://scripts/_probe_trex_boxes_shot.gd -- --splat=off
##   → _arisu_captures/_trex_boxes/01_idle.png
##     _arisu_captures/_trex_boxes/02_charge.png
##     _arisu_captures/_trex_boxes/03_tail_sweep.png
##
## 打开 `debug_collisions_hint`（引擎自带的绿色线框），所以图上能直接看见盒子。
## 2026-11-11 用户报「碰撞错了，而且碰撞没随着放技能改变」——这三张是给眼睛看的，
## 数字判据在 `_verify_trex_hitbox.gd`（77 项）。
##
## ⚠️ 要出图必须真窗口；窗口挪到屏幕外且不抢焦点（AGENTS.md 硬要求）。

const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")

const LEVEL := "res://scenes/next_level.tscn"
const BOSS := "TrexBossA"
const OUT_DIR := "_arisu_captures/_trex_boxes"
## 抄 `trex_yuuka_boss.gd::ATTACKS`
const CLIPS := ["charge", "tail_sweep"]
const IMPACTS := [1.08, 0.83]

## 每帧跟着 `_collisions` 刷的半透明盒子（和物理侧的盒子同尺寸同位置）
var _ghost_boxes: Array[MeshInstance3D] = []
var _collision_shapes: Array[CollisionShape3D] = []


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _out(name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR).path_join(name + ".png")


func _shot(name: String) -> void:
	_sync_ghosts()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _out(name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("[截图] %s" % path)


## 把「半透明示意盒」摆到物理盒子当前的尺寸/位置上
func _sync_ghosts() -> void:
	for i in mini(_ghost_boxes.size(), _collision_shapes.size()):
		var cs := _collision_shapes[i]
		var mi := _ghost_boxes[i]
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		# 物理盒子的变换是「boss 空间」里的（parent 就是 boss），所以直接用
		var bm := mi.mesh as BoxMesh
		bm.size = (cs.shape as BoxShape3D).size
		mi.transform = cs.transform


func _pin() -> void:
	for _i in 3:
		await OffWin.apply(self, Vector2i(1280, 720))
		if bool(OffWin.is_safe()[0]):
			return


func _run() -> void:
	await _pin()
	var old_mode := String(GameSettingsScript.value("window_mode", "maximized"))
	GameSettingsScript.set_value("window_mode", "windowed")

	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame

	var boss := level.get_node_or_null(BOSS)
	if boss == null:
		print("[boxes-shot] 找不到 %s" % BOSS)
		quit(1)
		return
	if not bool(boss.get("_booted")):
		boss.call("_boot")
	for _i in 30:
		await process_frame

	# 引擎自带的线框太淡，这里自己画**半透明实心盒**（绿），一眼能看出体积对不对
	debug_collisions_hint = false
	var ghosts: Array[MeshInstance3D] = []
	for cs in boss.get("_collisions"):
		var c := cs as CollisionShape3D
		if c == null or not (c.shape is BoxShape3D):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		(mi.mesh as BoxMesh).size = Vector3.ONE
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.15, 1.0, 0.45, 0.22)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true
		mi.material_override = mat
		boss.add_child(mi)
		ghosts.append(mi)
		_collision_shapes.append(c)
	_ghost_boxes = ghosts

	# 机位：按骨骼包围盒自动取景，斜上方看
	var bone := _bone_aabb(boss)
	var center := bone.get_center()
	var radius := maxf(bone.size.length() * 0.5, 4.0)
	var cam := Camera3D.new()
	level.add_child(cam)
	cam.global_position = center + Vector3(1.0, 0.55, 1.0).normalized() * radius * 1.35
	cam.look_at(center, Vector3.UP)
	cam.fov = 60.0
	cam.current = true
	print("[boxes-shot] 身体 %s，机位 %s" % [
		str(bone.size.snappedf(0.1)), str(cam.global_position.snappedf(0.1))])

	var anim := boss.get("_anim") as AnimationPlayer
	if anim != null:
		anim.play("idle")
	for _i in 20:
		await process_frame
	await _shot("01_idle")

	if anim == null:
		print("[boxes-shot] 没有 AnimationPlayer，只出 idle 那一张")
		GameSettingsScript.set_value("window_mode", old_mode)
		quit(0)
		return

	for i in CLIPS.size():
		anim.play(CLIPS[i])
		anim.seek(IMPACTS[i], true)
		# 跟随更新在 _physics_process 里，等一物理帧再拍
		await physics_frame
		await process_frame
		await _shot("%02d_%s" % [i + 2, CLIPS[i]])
	# 拍完复位，别让场景停在奇怪姿态
	anim.play("idle")

	GameSettingsScript.set_value("window_mode", old_mode)
	print("[boxes-shot] 出图完成")
	quit(0)


func _bone_aabb(boss: Node) -> AABB:
	var skel: Skeleton3D = boss.call("_best_skeleton", boss.get("model"))
	if skel == null:
		return AABB(boss.global_position, Vector3.ONE * 8.0)
	var xf := skel.global_transform
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in skel.get_bone_count():
		var p: Vector3 = xf * skel.get_bone_global_pose(i).origin
		lo = lo.min(p)
		hi = hi.max(p)
	if lo.x == INF:
		return AABB(boss.global_position, Vector3.ONE * 8.0)
	return AABB(lo, hi - lo)
