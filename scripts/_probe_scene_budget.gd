extends SceneTree
## 逐个副场景量显存：**离屏真窗口**，把第一场景拆开来算账。
##
##   _tools/run_shot.sh res://scripts/_probe_scene_budget.gd
##
## 做法：先摆一个只有相机的空场景当底座，然后**一个一个**把副场景实例化进去，
## 每加一个等 20 帧再读一次（纹理/缓冲/总显存），差值就是那个副场景的代价。
## 「空场里一进游戏就 3 GB」到底是谁的，看这张表就够了。
##
## ⚠️ 差值不完全可加：`ResourceLoader` 会缓存共享资源（同一张贴图只算第一次）。

const PARTS := [
	"res://scenes/mesh_hut.tscn",
	"res://scenes/parkour.tscn",
	"res://scenes/shop_baked.tscn",
	"res://scenes/mondrian_house_baked.tscn",
	"res://scenes/room609_proxy_baked.tscn",
	"res://scenes/lot_east.tscn",
	"res://scenes/gamedev_room.tscn",
	"res://scenes/esports_room.tscn",
	"res://scenes/hud.tscn",
	"res://scenes/player.tscn",
]


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var t := create_timer(240.0, true)
	t.timeout.connect(func():
		print("[budget] !! 看门狗超时")
		quit(1))
	_run.call_deferred()


func _v() -> Array:
	return [
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0,
	]


func _run() -> void:
	GameSettings.set_value("vsync", false)
	GameSettings.set_value("fps_limit", 0.0)
	root.size = Vector2i(1920, 1080)

	var base := Node3D.new()
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 0)
	cam.current = true
	base.add_child(cam)
	root.add_child(base)
	current_scene = base
	for _i in 30:
		await process_frame

	var prev := _v()
	print("[budget] 底座（空 Node3D + 相机）：总 %.0f｜纹理 %.0f｜缓冲 %.0f MiB" % prev)

	var all: Array = PARTS.duplicate()
	for p in all:
		if not ResourceLoader.exists(p):
			print("[budget] %-38s 场景不存在，跳过" % String(p).get_file())
			continue
		var ps := load(p) as PackedScene
		if ps == null:
			print("[budget] %-38s 载入失败" % String(p).get_file())
			continue
		var inst := ps.instantiate()
		base.add_child(inst)
		for _i in 20:
			await process_frame
		var now := _v()
		print("[budget] %-38s +总 %6.0f｜+纹理 %6.0f｜+缓冲 %6.0f MiB（累计 %.0f）" % [
			String(p).get_file(), float(now[0]) - float(prev[0]),
			float(now[1]) - float(prev[1]), float(now[2]) - float(prev[2]), float(now[0])])
		prev = now

	print("[budget] 全部副场景累计：总 %.0f｜纹理 %.0f｜缓冲 %.0f MiB" % _v())
	quit(0)
