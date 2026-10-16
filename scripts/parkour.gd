class_name Parkour
extends Node3D
## 跑酷路线总控：「记忆平台 → 信号塔岛」这条线的**顺序**与**摔落惩罚**。
##
## ── 这一份只干两件事 ──
##   1. 报出路线顺序（`route` 里按顺序排的落脚点）—— 自检、探针、文档都拿它当真相；
##   2. 摔下去时把人送回**最近踩过的那个落脚点**，而不是送回出生点。
##
## ── 为什么第 2 条是必需的，不是「贴心」 ──
## 路线一共 10 跳。`game.gd` 的兜底只有一条：掉到 y < −60 就送回出生点。
## 那意味着**每摔一次都要从出生点重新跑 70 m**（穿过画室、绕过两位 Boss、
## 再从平台西边跳一遍前 5 跳）—— 跑酷地图没有检查点根本没法玩。
## 所以这里把兜底线抬到 `FALL_Y`（路线上最低的落脚点在 y = +0.40，
## 所以 −12 只可能意味着「真的掉出路线了」），并记住最后一个踩过的落脚点。
##
## ── 什么时候**解除**武装 ──
## 站在主平台上、且脚下不是路线上的落脚点 → 视为「离开跑酷去干别的了」，
## 清空检查点。否则一个只是在平台边上失足的路人会被凭空塞到跑酷中段。
##
## ── 判据为什么用「网格的世界 AABB」而不是碰撞形状 ──
## 路线第 0 站（`Launch`）是**画在平台地面上的跑道标记，故意没有碰撞**
## （2.5 cm 的坎就足以把 CharacterBody3D 挡在门外，见 README §1.13）。
## 拿碰撞形状当判据会把这一站漏掉，所以统一读 `Mesh` 的世界包围盒。

## 低于这个高度就判定「摔出路线」，送回最近踩过的落脚点。
## 比 `game.gd` 的 FALL_LIMIT（−60）高得多 —— 就是要**抢在它前面**出手，
## 否则人要看着天空下坠 2.5 s 才被送回出生点。
const FALL_Y := -12.0

## 脚底离台面多近算「站在这一站上」
const ON_TOP := 0.40
## 水平方向的外扩。实测：胶囊半径 0.30，**站到板外 +0.20 m 还能被边缘托住**
## （+0.25 m 就滑下去，见 `_verify_parkour.gd` 第 2 节量出来的那张表）——
## 所以站位判定要跟着放宽，不然「挂在边上」会被误判成没踩到。
const EDGE_MARGIN := 0.30

## 按顺序排的落脚点节点路径（相对本节点）。**顺序就是路线顺序**。
@export var route: Array = []
## 关掉就完全不干预（自检里想单独测 game.gd 的兜底时会用）
@export var enabled := true
## 岛上那台「回平台」传送台把人送到哪儿（主平台西侧、跑道口旁边的一块空地）
@export var return_target := Vector3(-10.5, 0.05, 6.5)

## 前进到新的一站（只在往后推进时发，退回旧站不发）
signal checkpoint_reached(index: int, label: String)
## 摔了，被送回第 index 站
signal rescued(index: int, label: String)

## 当前检查点（−1 = 没上路线）
var checkpoint := -1
var rescues := 0

## 每一站的世界包围盒 + 台面高度 + 名字
var _boxes: Array[AABB] = []
var _tops: PackedFloat32Array = []
var _labels: PackedStringArray = []
var _player: Player


func _ready() -> void:
	_build_route()


## 把 `route` 里的节点路径解析成世界包围盒。自检可以直接调它核对。
func _build_route() -> void:
	_boxes.clear()
	_tops.clear()
	_labels.clear()
	for entry in route:
		var np := NodePath(String(entry))
		var node := get_node_or_null(np)
		if node == null:
			push_warning("[Parkour] 路线里有一站找不到：%s" % String(entry))
			_boxes.append(AABB())
			_tops.append(0.0)
			_labels.append(String(entry))
			continue
		var box := _world_aabb(node)
		_boxes.append(box)
		_tops.append(box.position.y + box.size.y)
		_labels.append(String(node.name))


func node_count() -> int:
	return _boxes.size()


func label_at(i: int) -> String:
	return _labels[i] if i >= 0 and i < _labels.size() else ""


func top_at(i: int) -> float:
	return _tops[i] if i >= 0 and i < _tops.size() else 0.0


func box_at(i: int) -> AABB:
	return _boxes[i] if i >= 0 and i < _boxes.size() else AABB()


## 站在第 i 站的台面上时，人应该被放在哪儿（台面正中、抬高 5 cm 免得嵌进去）
func respawn_point(i: int) -> Vector3:
	var b := box_at(i)
	return Vector3(b.position.x + b.size.x * 0.5, top_at(i) + 0.05,
		b.position.z + b.size.z * 0.5)


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			return
	var p := _player.global_position
	var here := _station_at(p)
	if here > checkpoint:
		checkpoint = here
		checkpoint_reached.emit(here, label_at(here))
		print("[Parkour] 检查点 %d/%d：%s（y = %.2f）"
			% [here + 1, node_count(), label_at(here), p.y])
	if checkpoint >= 0 and p.y < FALL_Y:
		_rescue()
		return
	# 回到主平台（且脚下不是路线上的落脚点）→ 收工，检查点清空
	if checkpoint >= 0 and here < 0 and p.y > -0.5 \
			and absf(p.x) <= 20.0 and absf(p.z) <= 20.0:
		print("[Parkour] 回到主平台，检查点清空（上一站 %s）" % label_at(checkpoint))
		checkpoint = -1


## 脚下是第几站（不在任何一站上 → −1）。有重叠时取**靠后**的那一站。
##
## 下界给到 −0.25 而不是「台面以下一点点」：实测**挂在板边上**时人比台面低
## 7.6 cm（胶囊底部球搁在棱上，见 `_verify_parkour.gd` 第 2 节），
## 卡太紧会把「挂在边缘」误判成「没踩到」，然后在人还挂着的时候判定摔落。
func _station_at(p: Vector3) -> int:
	var best := -1
	for i in _boxes.size():
		var b: AABB = _boxes[i]
		if b.size.x <= 0.0:
			continue
		var top := _tops[i]
		if p.y < top - 0.25 or p.y > top + ON_TOP:
			continue
		if p.x < b.position.x - EDGE_MARGIN or p.x > b.position.x + b.size.x + EDGE_MARGIN:
			continue
		if p.z < b.position.z - EDGE_MARGIN or p.z > b.position.z + b.size.z + EDGE_MARGIN:
			continue
		best = maxi(best, i)
	return best


func _rescue() -> void:
	rescues += 1
	_player.global_position = respawn_point(checkpoint)
	_player.velocity = Vector3.ZERO
	rescued.emit(checkpoint, label_at(checkpoint))
	Sfx.play("ui_open")
	print("[Parkour] 第 %d 次摔落 → 送回第 %d 站 %s"
		% [rescues, checkpoint + 1, label_at(checkpoint)])


## 岛上的传送台：踏上去回主平台。
##
## ⚠️ 没有它就是个死局：整条路线是**上坡**的（0 → +4.70），回头跳不上去；
##    而检查点又会把摔下去的人送回岛上 —— 玩家到了终点就再也回不来了。
func _on_return_pad_entered(body: Node3D) -> void:
	if not enabled:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null or body != _player:
		return
	_player.global_position = return_target
	_player.velocity = Vector3.ZERO
	checkpoint = -1
	Sfx.play("ui_toggle")
	print("[Parkour] 传送台 → 送回主平台 %s，检查点清空" % str(return_target))


## 一个节点的世界包围盒：节点**自己**是网格就用它（跑道标记没有碰撞，只有网格），
## 否则找 `Mesh` 子节点，再否则用碰撞形状，最后退回节点位置（一个点）。
func _world_aabb(node: Node) -> AABB:
	var self_mesh := node as MeshInstance3D
	if self_mesh != null and self_mesh.mesh != null:
		return self_mesh.global_transform * self_mesh.get_aabb()
	var mesh := node.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		return mesh.global_transform * mesh.get_aabb()
	var col := node.get_node_or_null("Col") as CollisionShape3D
	if col != null and col.shape is BoxShape3D:
		var s := (col.shape as BoxShape3D).size
		return col.global_transform * AABB(-s * 0.5, s)
	if node is Node3D:
		return AABB((node as Node3D).global_position, Vector3.ZERO)
	return AABB()


# --- 设计期的解析核对（探针与自检共用同一份实现）-------------------------------

## 一跳能不能过：**纯解析弹道**，不跑物理。
##
## 起跳点取「上一块板台面上、离目标板最近的那个点」—— 那就是玩家会踩到的地方；
## 落地时刻解 `½gt² − v·t + Δy = 0` 的大根，乘以跑速就是这一跳的水平射程。
##
## 返回：
##     required   float      起跳点到目标板**最近边缘**的水平距离（必须 ≤ reach）
##     rise       float      台面高差
##     time/reach float      滞空时间 / 射程
##     landing    Vector3    解析弹道落点（落在目标板台面那一层）
##     inside     bool       落点是否落在目标板 footprint 内（落不进去 = 跳过头）
##     edge_dist  float      落点到板边界的距离（正 = 在板内，负 = 冲出去了）
##     reachable  bool       判别式 ≥ 0（Δy 太高就直接无解）
##
## ⚠️ 「reach − required」就是**落进板里的深度**。这一列的上下界都要管：
##    太小说明余量不够（跳不到），太大说明会**跳过板**（板太短/射程太远）。
static func hop_analysis(from_box: AABB, to_box: AABB,
		jump_v: float, gravity: float, run_speed: float) -> Dictionary:
	var from_top := from_box.position.y + from_box.size.y
	var to_top := to_box.position.y + to_box.size.y
	var tc := to_box.position + to_box.size * 0.5
	# 起跳点：上一块板的台面上、水平方向离目标板中心最近的点
	var takeoff := Vector3(
		clampf(tc.x, from_box.position.x, from_box.position.x + from_box.size.x), from_top,
		clampf(tc.z, from_box.position.z, from_box.position.z + from_box.size.z))
	# 目标板上离起跳点最近的点 →「必须跨过去的那条边」
	var near := Vector3(
		clampf(takeoff.x, to_box.position.x, to_box.position.x + to_box.size.x), to_top,
		clampf(takeoff.z, to_box.position.z, to_box.position.z + to_box.size.z))
	var to_near := Vector2(near.x - takeoff.x, near.z - takeoff.z)
	var required := to_near.length()
	var rise := to_top - from_top
	var disc := jump_v * jump_v - 2.0 * gravity * rise
	var out := {
		"takeoff": takeoff, "near": near, "required": required, "rise": rise,
		"time": 0.0, "reach": 0.0, "landing": takeoff, "inside": false,
		"edge_dist": -INF, "reachable": disc >= 0.0,
	}
	if disc < 0.0 or run_speed <= 0.0:
		return out
	var t := (jump_v + sqrt(disc)) / gravity
	var reach := run_speed * t
	# 水平前进方向（required = 0 时退化成「朝目标板中心」）
	var dir := to_near / required if required > 0.001 \
		else Vector2(tc.x - takeoff.x, tc.z - takeoff.z).normalized()
	var landing := Vector3(takeoff.x + dir.x * reach, to_top, takeoff.z + dir.y * reach)
	out["time"] = t
	out["reach"] = reach
	out["landing"] = landing
	out["inside"] = landing.x >= to_box.position.x and landing.x <= to_box.position.x + to_box.size.x \
		and landing.z >= to_box.position.z and landing.z <= to_box.position.z + to_box.size.z
	out["edge_dist"] = minf(
		minf(landing.x - to_box.position.x, to_box.position.x + to_box.size.x - landing.x),
		minf(landing.z - to_box.position.z, to_box.position.z + to_box.size.z - landing.z))
	return out
