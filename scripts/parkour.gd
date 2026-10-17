class_name Parkour
extends Node3D
## 跑酷路线总控（v2：**4 段 / 33 站 / 30 跳 + 2 段独木桥 / 206 m**）。
##
## ── 这一份干四件事 ──
##   1. 报出路线顺序（`route`）与**分段**（`segments`）—— 自检、探针、文档都拿它当真相；
##   2. 摔下去送回**本段起点**（不是全程起点，也不是最近踩过的落脚点）；
##   3. 段内计时 + 最好成绩（存 `user://`），终点停表；
##   4. 岛上的「回平台」传送台。
##
## ── 为什么惩罚是「回本段起点」而不是「回最近落脚点」──
## v1 是「回最近踩过的落脚点」，对 10 跳的短图刚好；v2 有 30 跳，那样等于**没有惩罚**：
## 每一块板都能当检查点，摔一次只亏一跳，「难」就白设计了。
## 现在检查点只落在**段的交界**（4 段 = 3 个中途检查点 + 起点），摔一次要重跑整段
## （最长的一段 11 站 ≈ 45 m）。这正是 Minecraft 跑酷地图的常见做法。
##
## ── 什么时候**解除**武装 ──
## 站在主平台上、且脚下不是路线上的落脚点 → 视为「离开跑酷去干别的了」：
## 检查点清空、计时归零。否则一个只是在平台边上失足的路人会被凭空塞到跑酷中段。
##
## ── 判据为什么用「网格的世界 AABB」而不是碰撞形状 ──
## 路线第 0 站（`Launch`）是**画在平台地面上的跑道标记，故意没有碰撞**
## （2.5 cm 的坎就足以把 CharacterBody3D 挡在门外，见 README §1.13）。
## 拿碰撞形状当判据会把这一站漏掉，所以统一读 `Mesh` 的世界包围盒。

## 低于这个高度就判定「摔出路线」，送回本段起点。
## 比 `game.gd` 的 FALL_LIMIT（−60）高得多 —— 就是要**抢在它前面**出手，
## 否则人要看着天空下坠 2.5 s 才被送回平台出生点。v2 最低的落脚点是岛面 y = 0.00。
const FALL_Y := -12.0

## 脚底离台面多近算「站在这一站上」
const ON_TOP := 0.40
## 水平方向的外扩。实测：胶囊半径 0.30，**站到板外 +0.20 m 还能被边缘托住**
## （+0.25 m 就滑下去，见 `_verify_parkour.gd` 第 2 节量出来的那张表）。
const EDGE_MARGIN := 0.30

## 最好成绩存这儿（`user://`，跨启动保留）
const BEST_PATH := "user://parkour_best.cfg"
## **进度存档**：最近踩过的站号（+ 一份最好成绩）。
##
## 用户反馈「存档不了」—— 原来进度只活在内存里，一退出就没了。现在每推进一站就落盘，
## 启动时读回来，人一回到主平台就把他送回那一站接着跑（`_resume_pending`）。
const RUN_PATH := "user://parkour_run.cfg"

## 按顺序排的落脚点节点路径（相对本节点）。**顺序就是路线顺序**。
@export var route: Array = []
## **段起点**的站号（升序）。掉下去回这里；段与段之间才是检查点。
@export var segments: Array = [0]
## 段名（HUD 用），长度应与 `segments` 一致
@export var seg_names: Array = []
## **不是弹道跳**的站号（弹跳板抛射 / 上升气流托举 / 移动平台摆渡 / 传送门）。
## 探针与自检会**跳过这些跳的弹道核算**，改由各自的机关真物理自检负责。
@export var special_hops: Array = []
## **减速短跳**的站号（绕柱螺旋塔）：弦长比全速射程短得多，必须**站定起跳**、
## 靠空中操控过去 —— 核算要用 `air_hop_reach()` 而不是全速射程，自检也得换一套输入。
@export var short_hops: Array = []
## 关掉就完全不干预（自检里想单独测 game.gd 的兜底时会用）
@export var enabled := true
## 岛上那台「回平台」传送台把人送到哪儿（主平台西侧、跑道口旁边的一块空地）
@export var return_target := Vector3(-10.5, 0.05, 6.5)

## 前进到新的一站（只在往后推进时发，退回旧站不发）
signal checkpoint_reached(index: int, label: String)
## 摔了，被送回第 index 站（= 本段起点）
signal rescued(index: int, label: String)
## 离开起跳跑道、开始计时
signal run_started()
## 撞到终点：本次用时 + 历史最好
signal run_finished(seconds: float, best: float)

## 当前检查点（−1 = 没上路线）。**只是进度**，不是复活点 —— 复活点见 `respawn_station()`
var checkpoint := -1
var rescues := 0
## 计时中 / 已通关
var timer_running := false
var finished := false

var _elapsed := 0.0
var _started_at := 0
var _best := 0.0
## 每一站的世界包围盒 + 台面高度 + 名字
var _boxes: Array[AABB] = []
var _tops: PackedFloat32Array = []
var _labels: PackedStringArray = []
var _player: Player
var _hud_timer: Label
var _hud_seg: Label
var _hud_cache := ""
## 读档续跑：启动时若存档停在第 N 站（N>0），人一回到主平台就送他过去
var _resume_pending := false


func _ready() -> void:
	_build_route()
	_hud_timer = get_node_or_null("ParkourHUD/Timer") as Label
	_hud_seg = get_node_or_null("ParkourHUD/Seg") as Label
	_load_best()
	_load_run()
	_update_hud(true)


# --- 路线 ---------------------------------------------------------------------

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


## 第 i 站是不是「机关跳」（不按弹道算）
func is_special_hop(i: int) -> bool:
	return special_hops.has(i)


## 第 i 站是不是「减速短跳」（螺旋塔）
func is_short_hop(i: int) -> bool:
	return short_hops.has(i)


func segment_count() -> int:
	return maxi(segments.size(), 1)


func label_at(i: int) -> String:
	return _labels[i] if i >= 0 and i < _labels.size() else ""


func top_at(i: int) -> float:
	return _tops[i] if i >= 0 and i < _tops.size() else 0.0


func box_at(i: int) -> AABB:
	return _boxes[i] if i >= 0 and i < _boxes.size() else AABB()


func segment_name(seg: int) -> String:
	return String(seg_names[seg]) if seg >= 0 and seg < seg_names.size() else ""


## 第 i 站属于哪一段（−1 站的 → −1）
func segment_of(station: int) -> int:
	if station < 0 or segments.is_empty():
		return -1
	var seg := 0
	for k in segments.size():
		if station >= int(segments[k]):
			seg = k
	return seg


## 第 seg 段的**起点站号**
func segment_start(seg: int) -> int:
	if segments.is_empty():
		return 0
	return int(segments[clampi(seg, 0, segments.size() - 1)])


## 摔下去该回哪一站 —— **最近踩过的那一站**（= `checkpoint`）。
##
## ⚠️ 这里曾经是「回本段起点」，用户玩过之后反馈**太难**（摔一次要重跑整段，最长 45 m），
##    所以改回「回最近踩过的落脚点」。检查点仍然只在段交界推进（HUD 的 SEG 计数照旧），
##    但复活点就是你最后踩住的那一站。段起点（`segments`）继续当**视觉地标**：
##    那儿有 4 m 休息台 + 5 m 信号桅杆，只是不再当复活点。
func respawn_station() -> int:
	return maxi(checkpoint, 0)


## 站在第 i 站的台面上时，人应该被放在哪儿（台面正中、抬高 5 cm 免得嵌进去）
func respawn_point(i: int) -> Vector3:
	var b := box_at(i)
	return Vector3(b.position.x + b.size.x * 0.5, top_at(i) + 0.05,
		b.position.z + b.size.z * 0.5)


# --- 计时 / 最好成绩 ------------------------------------------------------------

func elapsed_seconds() -> float:
	if timer_running:
		return (Time.get_ticks_msec() - _started_at) / 1000.0
	return _elapsed


func best_seconds() -> float:
	return _best


func is_finished() -> bool:
	return finished


## 开始/重置一次跑动（自检也用；玩家在跑道上站住时也会自动走这条路）
func reset_run() -> void:
	timer_running = false
	finished = false
	_elapsed = 0.0
	_started_at = Time.get_ticks_msec()
	checkpoint = -1
	_update_hud(true)


func _start_timer() -> void:
	timer_running = true
	finished = false
	_elapsed = 0.0
	_started_at = Time.get_ticks_msec()
	run_started.emit()
	print("[Parkour] 起跑：计时开始")


func _stop_timer() -> void:
	if not timer_running:
		return
	_elapsed = (Time.get_ticks_msec() - _started_at) / 1000.0
	timer_running = false
	finished = true
	var is_best := _best <= 0.0 or _elapsed < _best
	if is_best:
		_best = _elapsed
		_save_best()
	run_finished.emit(_elapsed, _best)
	print("[Parkour] 通关：%.2f s%s" % [_elapsed, "（新纪录）" if is_best else
		"（最好 %.2f s）" % _best])


## 读进度存档。站号照旧校验一遍（免得改了路线之后旧存档把人送到空里）
func _load_run() -> void:
	var cf := ConfigFile.new()
	if cf.load(RUN_PATH) != OK:
		return
	var idx := int(cf.get_value("parkour", "checkpoint", -1))
	if idx >= 0 and idx < node_count():
		checkpoint = idx
		_resume_pending = checkpoint > 0
	if _best <= 0.0:
		_best = maxf(0.0, float(cf.get_value("parkour", "best", 0.0)))
	print("[Parkour] 读档：最近踩过第 %d 站 %s（最好 %s）"
		% [checkpoint + 1, label_at(checkpoint), "—" if _best <= 0.0 else "%.2f s" % _best])


## 落盘：进一站就写一次（用户要的「能存档」）
func _save_run() -> void:
	var cf := ConfigFile.new()
	cf.set_value("parkour", "checkpoint", checkpoint)
	cf.set_value("parkour", "best", _best)
	cf.save(RUN_PATH)


func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load(BEST_PATH) == OK:
		_best = maxf(0.0, float(cf.get_value("parkour", "best", 0.0)))


func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("parkour", "best", _best)
	cf.save(BEST_PATH)


func _update_hud(force := false) -> void:
	if _hud_timer == null:
		return
	var seg := segment_of(checkpoint)
	var head := "TIME %05.2f    BEST %s" % [_elapsed if not timer_running else elapsed_seconds(),
		"--.--" if _best <= 0.0 else "%05.2f" % _best]
	var state := "CLEAR!" if finished else ("RUN" if timer_running else "--")
	var sub := "SEG %d/%d  %s   %s" % [seg + 1 if seg >= 0 else 1, segment_count(),
		segment_name(maxi(seg, 0)), state]
	var key := head + "|" + sub
	if force or key != _hud_cache:
		_hud_cache = key
		_hud_timer.text = head
		_hud_seg.text = sub


# --- 每帧 ---------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			return
	var p := _player.global_position
	var here := _station_at(p)

	# 读档续跑（用户要的「从最近踩过的那一站继续，而不是从第 0 站重来」）
	if _resume_pending and checkpoint > 0 and _on_platform(p):
		_resume_pending = false
		_player.global_position = respawn_point(checkpoint)
		_player.velocity = Vector3.ZERO
		print("[Parkour] 读档续跑：送回第 %d 站 %s" % [checkpoint + 1, label_at(checkpoint)])
		return

	if here > checkpoint:
		checkpoint = here
		checkpoint_reached.emit(here, label_at(here))
		_save_run()          # 进一站就落盘（存档）
		if timer_running and here == node_count() - 1:
			_stop_timer()
		print("[Parkour] 第 %d/%d 站：%s（第 %d 段，y = %.2f）"
			% [here + 1, node_count(), label_at(here), segment_of(here) + 1, p.y])

	# 起跑：上过跑道（checkpoint ≥ 0）之后**离开第 0 站**就开始计时
	if checkpoint >= 0 and not timer_running and not finished and here != 0:
		_start_timer()

	# 摔下去就救 —— **不再要求 `checkpoint >= 0`**：还没踩到第一站的人从跑道或第一跳掉下去，
	# 旧写法会漏掉他，于是他一掉到 −60 就被 game.gd 的全局保险送回**初始出生点**
	# （用户报的「总是被拉回初始出生点」就是这个）。现在只要「不在主平台上」就归跑酷管。
	if p.y < FALL_Y and not _on_platform(p):
		_rescue()
		return

	# 回到主平台（且脚下不是路线上的落脚点）→ **只停表，不清检查点**：
	# 用户回平台拿个东西、或者只是摔回来，进度不该丢（「存档不了」的另一半）。
	# 只有**通关之后**再回平台才把进度清空（下一次从跑道重新开始）。
	if here < 0 and _on_platform(p) and (timer_running or finished):
		if finished:
			print("[Parkour] 通关后回到主平台：进度清空，下次从跑道重来")
			reset_run()
		else:
			print("[Parkour] 回到主平台：停表、**保留进度**（最近踩过第 %d 站 %s）"
				% [checkpoint + 1, label_at(checkpoint)])
			_disarm()


func _process(_delta: float) -> void:
	if enabled:
		_update_hud()


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


## 人是不是站在主平台上。跑酷自己的兜底（`FALL_Y`）和 game.gd 的全局保险（−60 m）
## 靠这一条分工：在平台上摔下去归 game.gd 送回出生点，出了平台就归跑酷救回落脚点。
func _on_platform(p: Vector3) -> bool:
	return p.y > -0.5 and p.y < 3.0 and absf(p.x) <= 20.0 and absf(p.z) <= 20.0


## 收工但**保留进度**：只停表、不清检查点（玩家回平台拿东西不该丢进度）
func _disarm() -> void:
	timer_running = false
	finished = false
	_elapsed = 0.0
	_update_hud(true)


## 第 i 站那台「回平台」传送台 —— 见 `_on_return_pad_entered`（岛上是唯一的回头路）
func _rescue() -> void:
	rescues += 1
	var back := respawn_station()
	_player.global_position = respawn_point(back)
	_player.velocity = Vector3.ZERO
	rescued.emit(back, label_at(back))
	Sfx.play("ui_open")
	print("[Parkour] 第 %d 次摔落 → 回**最近踩过的落脚点**第 %d 站 %s（第 %d 段）"
		% [rescues, back + 1, label_at(back), segment_of(back) + 1])


## 岛上的传送台：踏上去回主平台。
##
## ⚠️ 没有它就是个死局：检查点会把摔下去的人送回**本段起点**（第 4 段起点在
##    下降链之前、200 m 外），而终点岛四周是真的真空，走不回去。
func _on_return_pad_entered(body: Node3D) -> void:
	if not enabled:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null or body != _player:
		return
	_player.global_position = return_target
	_player.velocity = Vector3.ZERO
	reset_run()
	Sfx.play("ui_toggle")
	print("[Parkour] 传送台 → 送回主平台 %s，检查点/计时清空" % str(return_target))


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
## ⚠️ 真正的余量要拿**实测**射程算：`reach × 1.054`（v1 二分法量的系数）。
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


## **减速短跳**（绕柱螺旋塔那种）能走多远：站定起跳 + 空中一直按住方向键。
##
## 空中 `ACCEL_AIR` 推着走、上限 `SPEED_RUN`：先匀加速再匀速，滞空时间与
## `hop_analysis()` 同源。**为什么需要这一份**：螺旋塔一步的水平弦长只有 3.68 m，
## 而 +0.80 的全速射程是 3.87 m —— 全速起跳会直接飞过那块 2.0 m 的板，
## 玩家必须**减速**起跳（起跳前把速度收下来），落点才落在板上。
static func air_hop_reach(rise: float) -> float:
	var disc := Player.JUMP_VELOCITY * Player.JUMP_VELOCITY - 2.0 * Player.GRAVITY * rise
	if disc < 0.0:
		return -1.0
	var t := (Player.JUMP_VELOCITY + sqrt(disc)) / Player.GRAVITY
	var t_acc := Player.SPEED_RUN / Player.ACCEL_AIR
	if t <= t_acc:
		return 0.5 * Player.ACCEL_AIR * t * t
	return 0.5 * Player.ACCEL_AIR * t_acc * t_acc + Player.SPEED_RUN * (t - t_acc)
