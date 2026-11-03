extends SceneTree
## 验证游戏开发部活动室：模型在 / 不在，场景都得能加载。
##
##   _tools/run_probe.sh res://scripts/_verify_gamedev_optional.gd
##
## 模型由 scripts/gamedev_room.gd 在 _ready() 里运行时加载，
## 所以缺模型时「只少一栋房子的网格」，不会让 game.tscn 跟着起不来。

const SCENE := "res://scenes/gamedev_room.tscn"
const MODEL := "res://models/gamedev_room/gamedev_room.glb"

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var exists := ResourceLoader.exists(MODEL)
	print("[gdopt] 模型在不在：%s" % ("在" if exists else "不在（模拟克隆后）"))

	var ps := load(SCENE) as PackedScene
	if ps == null:
		print("[gdopt] FAIL: 场景加载失败（这就是改之前的行为）")
		quit(1)
		return

	var inst := ps.instantiate()
	if inst == null:
		print("[gdopt] FAIL: 实例化失败")
		quit(1)
		return

	root.add_child(inst)
	await process_frame
	await process_frame

	var model := inst.get_node_or_null("Model") as Node3D
	if model == null:
		print("[gdopt] FAIL: 找不到 Model 节点")
		quit(1)
		return

	var room_mesh := model.get_node_or_null("RoomMesh")
	var mesh_count := 0
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			mesh_count += 1

	print("[gdopt] Model 子节点数：%d" % model.get_child_count())
	print("[gdopt] RoomMesh 在不在：%s" % ("在" if room_mesh != null else "不在"))
	print("[gdopt] 场景内带网格的 MeshInstance3D：%d 个" % mesh_count)
	print("[gdopt] 招牌/灯/碰撞还在：Sign=%s LightA=%s Collision=%s"
		% [model.has_node("Sign"), model.has_node("LightA"), model.has_node("Collision")])

	if exists and room_mesh == null:
		print("[gdopt] FAIL: 模型在，但没挂上")
		_fail += 1
	if (not exists) and room_mesh != null:
		print("[gdopt] FAIL: 模型不在，却挂上了")
		_fail += 1
	# 不管模型在不在，这些都必须还在
	for nm in ["Sign", "LightA", "LightB", "Collision"]:
		if not model.has_node(nm):
			print("[gdopt] FAIL: %s 丢了" % nm)
			_fail += 1

	print("[gdopt] 结果：%s" % ("OK" if _fail == 0 else "FAIL %d" % _fail))
	quit(1 if _fail > 0 else 0)
