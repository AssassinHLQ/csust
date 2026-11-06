extends SceneTree
## 量「画室 609」到每个跑酷招牌的距离 —— 用来定 LABEL_NEAR_END 该给多少。
##
## 画室矩形用的是游戏日志里的实测值：
##   `[Game] 609 门内外切换：… 房间矩形 (10.71, 8.3, 20.64)，中心 (-0.5, 1.5, 3.54)`
## 玩家实际站位以房间为准，所以「房间盒子内的任意一点」都算 0 距离。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_label_distance.gd

const SCENE := "res://scenes/parkour.tscn"
const ROOM_CENTER := Vector3(-0.5, 1.5, 3.54)
const ROOM_SIZE := Vector3(10.71, 8.3, 20.64)

var _inst: Node
var _frames := 0


func _initialize() -> void:
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("[dist] FAIL: 载不动 %s" % SCENE)
		quit()
		return
	_inst = ps.instantiate()
	root.add_child(_inst)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	var half := ROOM_SIZE * 0.5
	print("[dist] 画室盒子：中心 %s / 尺寸 %s" % [str(ROOM_CENTER), str(ROOM_SIZE)])

	var rows: Array = []
	for n in _inst.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l == null or l.text.strip_edges() == "":
			continue
		rows.append({
			"text": String(l.text).replace("\n", " ⏎ "),
			"pos": l.global_position,
			"d": _box_distance(l.global_position, ROOM_CENTER, half),
		})
	rows.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))

	print("[dist] 有字的 Label3D 共 %d 个" % rows.size())
	print("[dist] ---- 离画室盒子最近的 15 个 ----")
	for i in mini(rows.size(), 15):
		var it: Dictionary = rows[i]
		print("[dist]  %7.1f m  %-30s @ %s" % [
			float(it["d"]), String(it["text"]), str(it["pos"])])

	print("[dist] ---- 半径内会「穿进房间」的招牌数 ----")
	for k in [6.0, 8.0, 12.0, 20.0, 40.0]:
		var c := 0
		for it in rows:
			if float(it["d"]) <= k:
				c += 1
		print("[dist]  %5.0f m 内：%d 个" % [k, c])

	_inst.queue_free()
	quit()
	return true


func _box_distance(p: Vector3, center: Vector3, half: Vector3) -> float:
	var d := Vector3(
		maxf(absf(p.x - center.x) - half.x, 0.0),
		maxf(absf(p.y - center.y) - half.y, 0.0),
		maxf(absf(p.z - center.z) - half.z, 0.0))
	return d.length()
