extends SceneTree
## 验证电竞房海报改成「可选贴图」之后的行为：
##   有图 → 贴上去；没图 → 场景照常加载、海报纯色、不报 Parse Error。
##
##   _tools/run_probe.sh res://scripts/_verify_optional_poster.gd
##
## 无图那轮由外部临时把 assets/story/gamedev_room.jpg 挪走再跑（见提交说明）。

const SCENE := "res://scenes/esports_room.tscn"
const TEX := "res://assets/story/gamedev_room.jpg"

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var exists := ResourceLoader.exists(TEX)
	print("[optposter] 图在不在：%s" % ("在" if exists else "不在（模拟克隆后）"))

	var ps := load(SCENE) as PackedScene
	if ps == null:
		print("[optposter] FAIL: 场景加载失败（这就是改之前的行为）")
		quit(1)
		return
	var inst := ps.instantiate()
	if inst == null:
		print("[optposter] FAIL: 实例化失败")
		quit(1)
		return
	root.add_child(inst)
	await process_frame
	await process_frame

	var poster := inst.get_node_or_null("PosterRoom") as MeshInstance3D
	if poster == null:
		print("[optposter] FAIL: 找不到 PosterRoom")
		quit(1)
		return

	var mat := poster.material_override as StandardMaterial3D
	var has := mat != null and mat.albedo_texture != null
	var albedo := "<无材质>" if mat == null else str(mat.albedo_color)

	print("[optposter] PosterRoom 贴图：%s" % ("有" if has else "无（纯色）"))
	print("[optposter] 底色：%s" % albedo)
	print("[optposter] 场景子节点数：%d" % inst.get_child_count())
	if has:
		print("[optposter] 贴的是：%s" % mat.albedo_texture.resource_path)

	if exists and not has:
		print("[optposter] FAIL: 图在，但没贴上")
		_fail += 1
	if (not exists) and has:
		print("[optposter] FAIL: 图不在，却贴上了")
		_fail += 1

	print("[optposter] 结果：%s" % ("OK" if _fail == 0 else "FAIL %d" % _fail))
	quit(1 if _fail > 0 else 0)
