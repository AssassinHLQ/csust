extends SceneTree
## 只量**真实场景**（game.tscn 里的 EsportsRoom），不造任何数据。
## 回答三个问题：
##   ① 房子的世界包围盒在哪、多高（判断有没有埋地下 / 倒立）
##   ② 本地 +Z（门）在世界里指向哪
##   ③ 和它并排的游戏开发部 GameDevRoom 相比，高度对不对

const GAME := "res://scenes/game.tscn"
const OffWin := preload("res://scripts/offscreen_window.gd")


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await OffWin.apply(self, Vector2i(640, 360))
	await _wait(2)
	var game: Node = load(GAME).instantiate()
	root.add_child(game)
	await _wait(25)

	for nm in ["EsportsRoom", "GameDevRoom", "LotEast", "MondrianHouse"]:
		var n := game.get_node_or_null(nm) as Node3D
		if n == null:
			print("[real] %s <不存在>" % nm)
			continue
		var box := AABB()
		var first := true
		for m in n.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
		if first:
			print("[real] %-14s 没有网格" % nm)
			continue
		var b := n.global_basis
		print("[real] %-14s pos=(%.2f,%.2f,%.2f)  size=(%.2f,%.2f,%.2f)  y范围[%.2f, %.2f]"
			% [nm, box.position.x, box.position.y, box.position.z,
			   box.size.x, box.size.y, box.size.z,
			   box.position.y, box.position.y + box.size.y])
		print("[real]    Y轴=(%.2f,%.2f,%.2f) y分量=%.2f %s   Z轴(门)=(%.2f,%.2f,%.2f)"
			% [b.y.x, b.y.y, b.y.z, b.y.y,
			   "✓朝上" if b.y.y > 0.5 else "✗倒立",
			   b.z.x, b.z.y, b.z.z])
	quit(0)
