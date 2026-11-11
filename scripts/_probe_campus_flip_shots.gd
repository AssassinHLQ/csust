extends SceneTree
## 出图：校园泼溅 `use_default_orientation` 开/关的 A/B 对照（同一机位）。
##
##   godot --path . --script res://scripts/_probe_campus_flip_shots.gd -- --no-capture --flip=on
##   godot --path . --script res://scripts/_probe_campus_flip_shots.gd -- --no-capture --flip=off
##
## 背景：用户 2026-11-11「谁又把高斯泼溅倒过来了?!」
## 上一轮（fd13597）判定 180° 翻转是对的，把节点 y 降到 44.8、地面峰值对齐到 0.1 m；
## 但那只验证了「地面层的高度」，没验证「楼和树是往上长还是往下挂」。
## 这里用同一台相机、同一时刻，把两种朝向各拍一套，人眼一叠就知道。
##
## ⚠️ 幕外窗口，不抢用户前台（AGENTS.md 硬要求）。

const OffWin := preload("res://scripts/offscreen_window.gd")

const OUT_DIR := "res://_arisu_captures/_campusflip"
## 机位：都在内容附近 **60~85 m**（渲染距离 100 m 会裁远处的东西，别摆太远）。
## ⚠️ 第一次跑全是空画面，原因是 `hide_inside_aabb`：玩家还站在起始房间里
##    （关卡出生点 (−2, 0.55, 5.2) 落在 AABB(−17,−3,−11, 33,19,25) 内），
##    `_update_inside_hide()` 就把**整份校园泼溅**隐藏了。所以这里既把玩家挪到校园里，
##    也把 `hide_inside_aabb` 清成零。
const SHOTS := [
	{"name": "eye", "pos": Vector3(0.0, 1.7, -300.0), "look": Vector3(0.0, 1.4, -345.0), "fov": 75.0},
	{"name": "road", "pos": Vector3(0.0, 8.0, -200.0), "look": Vector3(0.0, 4.0, -280.0), "fov": 75.0},
	{"name": "wide", "pos": Vector3(60.0, 45.0, -230.0), "look": Vector3(0.0, 0.0, -300.0), "fov": 70.0},
	{"name": "trex", "pos": Vector3(-95.0, 10.0, -60.0), "look": Vector3(-95.0, 3.0, -100.0), "fov": 70.0},
]
## 玩家挪到主路上（离机位不远，顺便让 `hide_inside_aabb` 不再生效）
const PLAYER_SPOT := Vector3(0.0, 5.0, -300.0)

var _level: Node3D
var _out_abs := ""
## null = 不动场景里的设置（默认）；true/false = 临时覆盖做 A/B
var _flip: Variant = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var tag := "scene"
	for a in OS.get_cmdline_user_args():
		if a == "--flip=off":
			_flip = false
			tag = "off"
		elif a == "--flip=on":
			_flip = true
			tag = "on"
	print("=== flip=%s（%s）===" % [tag, "按场景里的设置" if _flip == null else "探针临时覆盖"])

	if DisplayServer.get_name() == "headless":
		print("[FAIL] 出图探针必须开真窗口")
		quit(1)
		return
	await OffWin.apply(self, Vector2i(1600, 900))
	for w in OffWin.is_safe():
		print("  [safe] %s" % w)

	_out_abs = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out_abs)

	_level = (load("res://scenes/next_level.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_level)
	await process_frame

	var campus: Node3D = _level.get_node_or_null("Campus")
	if campus == null:
		print("[FAIL] 没有 Campus")
		quit(1)
		return
	if _flip != null:
		campus.set("use_default_orientation", _flip)
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.set("preload_on_gate", false)
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	print("  就绪 %d ms" % (Time.get_ticks_msec() - t0))
	await process_frame
	await process_frame

	var node: Node3D = campus.get("splat_node")
	if node != null:
		print("  splat_node.global_transform.origin = %s" % str(node.global_transform.origin.snappedf(0.01)))

	# ⚠️ 玩家挪到校园里 + 清掉 `hide_inside_aabb`，否则泼溅整份被隐藏（见 SHOTS 注释）
	campus.set("hide_inside_aabb", AABB())
	var player := _level.get_node_or_null("Player") as Node3D
	if player != null:
		player.global_position = PLAYER_SPOT
		player.velocity = Vector3.ZERO
		print("  玩家挪到 %s" % str(PLAYER_SPOT))
	await process_frame
	await process_frame
	if node != null:
		print("  splat_node.visible = %s" % str(node.visible))

	for s in SHOTS:
		var cam := Camera3D.new()
		cam.fov = float(s["fov"])
		cam.far = 4000.0
		_level.add_child(cam)
		cam.global_position = s["pos"]
		cam.look_at(s["look"], Vector3.UP)
		cam.make_current()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var p := "%s/%s_%s.png" % [_out_abs, String(s["name"]), tag]
		root.get_texture().get_image().save_png(p)
		print("  [shot] %s" % p)

	print("出图完成 → %s" % _out_abs)
	quit(0)
