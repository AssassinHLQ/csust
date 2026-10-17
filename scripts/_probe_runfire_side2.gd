extends SceneTree
## 探针（要真渲染）：跑打到底「后仰」到什么程度 —— 侧视连拍。
##
## 为什么要连拍：一次性动作 `Normal_Attack_Ing` 开火时被 `seek()` 反复拉回开头，
## 单帧采样很可能正好落在还没摆开的位置上。这里每个状态拍 4 张，间隔 4 帧
## （≈0.07 s），整段 0.3 s 都看得到。
##
## 相机是**世界空间固定**的（+X 侧、略高），不跟随玩家，所以三组之间可以直接对比。
##
## 用法（要真渲染，别加 --headless）：
##   godot --path <工程> --script res://scripts/_probe_runfire_side2.gd -- --splat=off
## 输出：_arisu_captures/_runfire2/<状态>_<序号>.png

const OUT_DIR := "_arisu_captures/_runfire2"
const SIZE := Vector2i(720, 720)
const SPEED := 6.8


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = SIZE
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(40)

	var p := game.get_node_or_null("Player")
	if p == null:
		print("!! 没有 Player")
		quit(1)
		return
	var anim = p.get("anim")
	p.set_physics_process(false)

	# 玩家自己的相机让位，换成世界空间固定的侧视机位
	var cam := Camera3D.new()
	cam.name = "ProbeCam"
	cam.fov = 42.0
	root.add_child(cam)
	var base: Vector3 = p.global_position
	cam.global_position = base + Vector3(3.6, 1.15, 0.0)
	cam.look_at(base + Vector3(0.0, 0.95, 0.0), Vector3.UP)
	cam.make_current()
	print("[cam] 玩家 %s  相机 %s" % [
		str(base.snappedf(0.01)), str(cam.global_position.snappedf(0.01))])

	# ── ① 只跑 ──
	anim.call("set_locomotion", SPEED, true, 0.0)
	await _wait(20)
	for i in 4:
		anim.call("set_locomotion", SPEED, true, 0.0)
		await _wait(4)
		await _shot(out.path_join("run_%d.png" % i))
	_report(anim, "只跑")

	# ── ② 跑 + 开火（每 4 帧补一次 request_fire，模拟连续射击）──
	for i in 4:
		anim.call("set_locomotion", SPEED, true, 0.0)
		anim.call("request_fire")
		await _wait(4)
		await _shot(out.path_join("runfire_%d.png" % i))
		_report(anim, "跑打 #%d" % i)

	# ── ③ 站桩开火 ──
	anim.call("set_locomotion", 0.0, true, 0.0)
	await _wait(10)
	for i in 3:
		anim.call("request_fire")
		await _wait(4)
		await _shot(out.path_join("standfire_%d.png" % i))
	_report(anim, "站桩开火")

	print("[shot] 输出目录 %s" % out)
	quit(0)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)


func _report(anim, label: String) -> void:
	var sk: Skeleton3D = anim.get("skeleton")
	var up := -999.0
	if sk != null:
		var head := _bone_world(sk, "head")
		var hips := _bone_world(sk, "pelvis")
		var d := head - hips
		if d.length() > 0.0001:
			up = Vector3.UP.dot(d.normalized())
	print("[pose] %-10s 躯干 up=%.3f" % [label, up])


func _bone_world(sk: Skeleton3D, keyword: String) -> Vector3:
	var k := keyword.to_lower()
	for b in sk.get_bone_count():
		if String(sk.get_bone_name(b)).to_lower().contains(k):
			return sk.global_transform * sk.get_bone_global_pose(b).origin
	return Vector3.ZERO


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
