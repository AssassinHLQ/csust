extends SceneTree
## 校验招牌门控（2026-11-07 起是**两档**）：
##   ① 所有 Label3D 都是 `no_depth_test = false`；
##      近档（`SignPost` / `ReadyZone` / `Island` 下的）`visibility_range_end = 6`，
##      其余（跑道 `Route` 下的一切）**不限距离**（`visibility_range_end = 0`）
##   ② 区域门控的几何判据正确：画室盒子中心判「内」、跑酷起点判「外」
##   ③ 找不到玩家时默认「隐藏」（避免开局闪字）
##
## 用法：_tools/run_probe.sh res://scripts/_verify_label_gate.gd

const SCENE := "res://scenes/parkour.tscn"
const WANT_END := 6.0
const NEAR_ROOTS := ["SignPost", "ReadyZone", "Island"]
const ROOM_CENTER := Vector3(-0.5, 1.5, 3.54)
const ROOM_HALF := Vector3(5.36, 4.15, 10.32)
const ROOM_EXIT_MARGIN := 1.5

var _inst: Node
var _frames := 0


func _initialize() -> void:
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("[gate] FAIL: 载不动 %s" % SCENE)
		quit()
		return
	_inst = ps.instantiate()
	root.add_child(_inst)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	var total := 0
	var near_count := 0
	var bad_range: Array = []
	var visible_now := 0
	for n in _inst.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l == null or l.text.strip_edges() == "":
			continue
		total += 1
		var want_near := _is_near(n)
		if want_near:
			near_count += 1
		var want_end := WANT_END if want_near else 0.0
		if l.no_depth_test or not is_equal_approx(l.visibility_range_end, want_end):
			bad_range.append("%s (depth=%s end=%.1f want=%.1f)"
				% [String(_inst.get_path_to(n)), str(l.no_depth_test),
					l.visibility_range_end, want_end])
		if l.visible:
			visible_now += 1

	var ok := true
	print("[gate] ① 有字招牌 %d 个（近档 %d / 远档 %d），距离/深度不合格 %d 个"
		% [total, near_count, total - near_count, bad_range.size()])
	for i in mini(bad_range.size(), 8):
		print("     x " + String(bad_range[i]))
	if bad_range.size() > 0 or total == 0 or near_count == 0:
		ok = false

	# ③ 没有玩家时应默认隐藏
	print("[gate] ③ 当前可见 %d 个（无玩家 → 应为 0）" % visible_now)
	if visible_now != 0:
		ok = false

	# ② 几何判据
	var probes := {
		"画室中心（应=内/隐藏）": ROOM_CENTER,
		"画室门口西墙 (-5.9,1.5,3.5)（应≈内）": Vector3(-5.9, 1.5, 3.5),
		"跑酷起点招牌 (-11.5,1.1,6.2)（应=外/显示）": Vector3(-11.5, 1.1, 6.2),
		"准备区 (-13.0,0,4.0)（应=外/显示）": Vector3(-13.0, 0.0, 4.0),
	}
	print("[gate] ② 区域门控判据（阈值 %.1f m）" % ROOM_EXIT_MARGIN)
	for k in probes.keys():
		var d := _box_dist(probes[k])
		var outside := d > ROOM_EXIT_MARGIN
		print("     %-42s d=%5.2f → %s" % [k, d, "外(显示)" if outside else "内(隐藏)"])
	# 画室中心必须是「内」，跑酷起点必须是「外」
	if _box_dist(ROOM_CENTER) > 0.001:
		ok = false
		print("     !! 画室中心被判成「外」，盒子常量不对")
	if _box_dist(Vector3(-11.5, 1.1, 6.2)) <= ROOM_EXIT_MARGIN:
		ok = false
		print("     !! 跑酷起点被判成「内」，门控会一直隐藏")

	print("[gate] 结果: %s" % ("PASS" if ok else "FAIL"))
	_inst.queue_free()
	quit()
	return true


## 与 `parkour.gd::_label_near_zone()` 同一判据：挂在这几棵子树下的算近档。
func _is_near(n: Node) -> bool:
	for p in NEAR_ROOTS:
		var r: Node = _inst.get_node_or_null(NodePath(p))
		if r == null:
			continue
		if r == n or r.is_ancestor_of(n):
			return true
	return false


func _box_dist(p: Vector3) -> float:
	var d := Vector3(
		maxf(absf(p.x - ROOM_CENTER.x) - ROOM_HALF.x, 0.0),
		maxf(absf(p.y - ROOM_CENTER.y) - ROOM_HALF.y, 0.0),
		maxf(absf(p.z - ROOM_CENTER.z) - ROOM_HALF.z, 0.0))
	return d.length()
