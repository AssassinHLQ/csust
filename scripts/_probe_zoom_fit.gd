extends SceneTree
## 量「滚轮拉近到底能看清多少爱丽丝」：每个距离拍一张图，
## 同时把**头顶 / 脚底**投影到屏幕坐标 —— 直接看有没有被切出画面、占了多少画幅。
##
##   _tools/run_shot.sh res://scripts/_probe_zoom_fit.gd -- --splat=off --story=off --tag=before
##
## 出图：_arisu_captures/_zoomfit/<tag>/zoom_XX.png
## ⚠️ 走的是**真实代码路径**：只改 `_zoom_distance`，让 `player.gd::_apply_camera()`
##    自己去算 spring_length / rig 高度 / 肩偏移，所以量到的就是玩家滚动滚轮的效果。


const OUT_ROOT := "res://_arisu_captures/_zoomfit"
const DISTS := [1.1, 1.3, 1.6, 2.0, 2.4, 3.0, 3.4, 4.2, 6.0]

var _tag := "shot"
## `--shoulders=0.10,0.20,0.30` 额外做一轮「肩偏移扫描」：近景把她摆多偏才
## 不压在准星上，一次跑完、出几张图人眼挑，不用来回改数字重跑。
var _shoulders: Array[float] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--shoulders="):
			for s in a.substr(12).split(",", false):
				_shoulders.append(float(s))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	const OffWin := preload("res://scripts/offscreen_window.gd")
	await OffWin.apply(self, Vector2i(960, 540))
	root.size = Vector2i(960, 540)

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(150)

	var player := game.get_node_or_null("Player") as Node3D
	if player == null:
		print("[zf] 没有 Player")
		quit(1)
		return
	var cam := player.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
	var spring := player.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	var rig := player.get_node_or_null("CameraRig") as Node3D
	var model_root := player.get_node_or_null("Arisu") as Node3D
	if cam == null or spring == null or rig == null or model_root == null:
		print("[zf] 相机 / 相机臂 / rig / Arisu 缺件")
		quit(1)
		return

	# 角色包围盒（全局）：判断「全身有没有进画面」用它，而不是猜模型多高
	var box := AABB()
	var first := true
	for m in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	if first:
		print("[zf] Arisu 没有可见网格")
		quit(1)
		return
	# ⚠️ 网格 AABB 不可信（蒙皮网格的盒子是静止姿势，实测沉到地下 0.6 m），
	#    真正量身高的是 `_probe_body_extent.gd` 的骨骼结果，这里直接用 player 上那两个数。
	var foot_y: float = player.global_position.y + float(player.get("body_bottom"))
	var head_y: float = player.global_position.y + float(player.get("body_top"))
	print("[zf] ===== 现状测量（tag=%s）=====" % _tag)
	print("[zf] 网格 AABB y %.3f → %.3f（**仅参考**）" % [box.position.y, box.end.y])
	print("[zf] 取景用身高：脚底 %.3f  头顶(含光环) %.3f  fov=%.1f°（垂直）  hip_height=%.2f" % [
		foot_y, head_y, cam.fov, float(player.get("hip_height"))])
	print("[zf] 公式最近距离 min_zoom_for_full_body() = %.2f m" % float(player.call("min_zoom_for_full_body")))
	print("[zf] 现状肩偏移：近景 zoom_shoulder_close=%.2f  远景 hip_shoulder=%.2f" % [
		float(player.get("zoom_shoulder_close")), float(player.get("hip_shoulder"))])

	var out_dir := "%s/%s" % [OUT_ROOT, _tag]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	for d in DISTS:
		player.set("_zoom_distance", float(d))
		await _wait(45)  # cam_lerp 12/s，45 帧足够收敛
		await _shot(cam, spring, rig, model_root, foot_y, head_y, float(d), out_dir)

	# 肩偏移扫描（`--shoulders=a,b,c`）：近景把她摆多偏才「不压在准星上」。
	# 只改 `zoom_shoulder_close` 这个 export，其余全走真实代码路径。
	if not _shoulders.is_empty():
		print("[zf] ----- 肩偏移扫描 d=1.1 / 1.6 -----")
		var keep_s: float = float(player.get("zoom_shoulder_close"))
		for s in _shoulders:
			player.set("zoom_shoulder_close", s)
			for d in [1.1, 1.6]:
				player.set("_zoom_distance", d)
				await _wait(45)
				await _shot(cam, spring, rig, model_root, foot_y, head_y, d, out_dir,
					"sh%02d" % int(round(s * 100.0)))
		player.set("zoom_shoulder_close", keep_s)
		player.set("_zoom_distance", float(DISTS[0]))
		await _wait(45)

	# 正面全身：「欣赏」看的是脸。把角色转过来（走 `_facing_yaw`，否则物理帧会转回去）
	print("[zf] ----- 转过来看正面 -----")
	player.set("_facing_yaw", float(player.get("_facing_yaw")) + PI)
	await _wait(60)
	for d in [1.1, 1.3, 1.6, 2.0]:
		player.set("_zoom_distance", float(d))
		await _wait(45)
		await _shot(cam, spring, rig, model_root, foot_y, head_y, float(d), out_dir, "front")

	# 正面肩偏移扫描：背景那张是头发墙，判断不了构图，真正的「欣赏」视角是这张。
	if not _shoulders.is_empty():
		print("[zf] ----- 正面肩偏移扫描 d=1.1 / 1.6 / 2.4 -----")
		var keep_f: float = float(player.get("zoom_shoulder_close"))
		for s in _shoulders:
			player.set("zoom_shoulder_close", s)
			for d in [1.1, 1.6, 2.4]:
				player.set("_zoom_distance", float(d))
				await _wait(45)
				await _shot(cam, spring, rig, model_root, foot_y, head_y, d, out_dir,
					"fsh%02d" % int(round(s * 100.0)))
		player.set("zoom_shoulder_close", keep_f)

	print("[zf] DONE")
	quit(0)


func _shot(cam: Camera3D, spring: SpringArm3D, rig: Node3D, model_root: Node3D,
		foot_y: float, head_y: float, d: float, out_dir: String, prefix := "zoom") -> void:
	var vp := root.get_visible_rect().size
	var head := Vector3(model_root.global_position.x, head_y, model_root.global_position.z)
	var foot := Vector3(model_root.global_position.x, foot_y, model_root.global_position.z)
	var hp := cam.unproject_position(head)
	var fp := cam.unproject_position(foot)
	var h := vp.y
	var ok_head := hp.y >= 0.0 and hp.y <= h
	var ok_foot := fp.y >= 0.0 and fp.y <= h
	var frac := (fp.y - hp.y) / h
	print("[zf] 滚轮 %.1f m → 实际臂长 %.2f  支点高 %.2f  肩偏移 %+.2f  头 y=%.0f%s  脚 y=%.0f%s  占画幅 %3.0f%%  居中偏移 %.2f" % [
		d, spring.spring_length, rig.position.y, spring.position.x,
		hp.y, "✓" if ok_head else "✗切出",
		fp.y, "✓" if ok_foot else "✗切出",
		frac * 100.0,
		(hp.x + fp.x) * 0.5 - vp.x * 0.5])
	var img: Image = root.get_texture().get_image()
	var path := "%s/%s_%04d.png" % [out_dir, prefix, int(round(d * 10.0))]
	img.save_png(path)
	print("[zf]   出图 %s" % path)
