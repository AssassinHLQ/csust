class_name Parkour
extends Node3D
## 跑酷路线总控（v8：**12 段 / 99 站 / 84 跳 + 9 处机关 / 571 m**）。
##
## v4 只在第 2 段之后插了 **第 3 段「同花顺 K 线区」**（12 根红绿蜡烛，K1…K12，
## 由 `tools/make_flush_section.py` 生成）；原第 3~6 段整体西移 ~81 m、站号 +12，
## 段数 6 → 7。几何与余量见 README §1.16 和 `_probe_parkour.gd`。
##
## ── 这一份干五件事 ──
##   1. 报出路线顺序（`route`）与**分段**（`segments`）—— 自检、探针、文档都拿它当真相；
##   2. 摔下去送回**最近踩过的落脚点**（`checkpoint`）；段起点只是视觉地标；
##   3. 段内计时 + 最好成绩（存 `user://`），终点停表；
##   4. 岛上的「回平台」传送台；
##   5. 进度落盘（`parkour_run.cfg`），但**启动默认不恢复** —— 重进游戏回初始位置。
##
## ── 为什么复活点是「最近踩过的落脚点」而不是「本段起点」──
## v1 是「回最近落脚点」，v2 曾改成「回本段起点」，用户玩过之后反馈**太难**
## （最长一段 45 m，摔一次重跑整段）。现在改回最近踩过的站；段起点保留 4 m 休息台
## + 5 m 信号桅杆当地标。这正是 Minecraft 跑酷地图的常见做法（检查点稀疏但复活不罚）。
##
## ── 什么时候**解除**武装 ──
## 站在主平台上、且脚下不是路线上的落脚点 → 视为「离开跑酷去干别的了」：
## **只停表、保留检查点**（用户要的「进度别丢」），下一次从跑道重新开始计时。
##
## ── 判据为什么用「网格的世界 AABB」而不是碰撞形状 ──
## 路线第 0 站（`Launch`）是**画在平台地面上的跑道标记，故意没有碰撞**
## （2.5 cm 的坎就足以把 CharacterBody3D 挡在门外，见 README §1.13）。
## 拿碰撞形状当判据会把这一站漏掉，所以统一读 `Mesh` 的世界包围盒。

## 低于这个高度就判定「摔出路线」，送回最近踩过的落脚点。
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
## 进度存档：最近踩过的站号（+ 一份最好成绩）。
##
## ⚠️ 用户 2026-10-17 反馈「退出游戏重进还在之前存档位置，要改成回初始位置」：
##    这里**仍然落盘**（方便调试/以后做「继续游戏」按钮），但启动时**不再恢复检查点**，
##    也不再把人传送到存档站。重进游戏 = 从跑道口的初始出生点开始。
##    `parkour_run.cfg` 里旧的 checkpoint 不会自动删除，只是被忽略。
const RUN_PATH := "user://parkour_run.cfg"
## 启动时要不要恢复上次的跑酷检查点。**默认 false**（用户要求重进回初始位置）。
## 想做「继续游戏」时把它改成 true 即可，落盘的数据一直都在。
@export var resume_on_start := false

## 按顺序排的落脚点节点路径（相对本节点）。**顺序就是路线顺序**。
@export var route: Array = []
## **段起点**的站号（升序）。只是视觉地标；复活点用 `checkpoint`（最近踩过的站）。
@export var segments: Array = [0]
## 段名（自检、探针的段表用），长度应与 `segments` 一致
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
## 摔了，被送回最近踩过的第 index 站
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
## 读档续跑：**只有 `resume_on_start = true` 时**才会在启动后把人送回存档站。
## 默认 false ⇒ 重进游戏从初始位置开始（用户 2026-10-17 的要求）。
var _resume_pending := false


func _ready() -> void:
	_build_route()
	_load_best()
	_load_run()
	_spawn_roof_gpu()
	_spawn_bank_sign()
	_spawn_settlement()
	_ensure_roof_solid()


## 最后平台的掩体屋顶上放一块 RTX 5090（用户 2026-10-20：「房子上面放一个 5090……
## 5090 也是加入资产的，全新正版现价 59999」）。
##
## **运行时生成**、不写进场景：屋顶位置跟着掩体走，写死绝对坐标以后一改房子就漂。
func _spawn_roof_gpu() -> void:
	var shed := get_node_or_null("Island/Props/Shed")
	if shed == null or shed.get_node_or_null("RTX5090") != null:
		return
	var gpu := Rtx5090.new()
	gpu.name = "RTX5090"
	# 屋顶**东侧**（招牌挪到西边以后，2026-10-20 用户画的框：「放这里」）
	gpu.position = Vector3(1.1, 2.5, 0.2)
	shed.add_child(gpu)


## 屋顶的 **BANK 招牌**（2026-10-20 用户：「在这个房顶上面放一个 BANK 的牌子，
## 我已经做好模型放桌面了，你来缩放一下适配大小，这样子一个简单的银行就做好了」）。
##
## 站在屋顶**西侧**、正面朝**第 12 段下降链的落点**（岛东缘那一带）——
## 玩家从跑酷链走过来第一眼就看见它；东侧留给 5090。
##
## ⚠️ 2026-10-20 晚第二轮：用户在原截图上画了个红框标「放这里」——
##    位置从 `(1.35, 2.5, 0.15)` 挪到 **`(-0.9, 2.5, 0.1)`**（屋顶左半边），
##    5090 跟着挪到东侧 `(1.1, 2.5, 0.2)`，两件东西在屋顶上一左一右、互不遮挡。
func _spawn_bank_sign() -> void:
	var shed := get_node_or_null("Island/Props/Shed") as Node3D
	if shed == null or shed.get_node_or_null("BankSign") != null:
		return
	var sign := BankSign.new()
	sign.name = "BankSign"
	sign.position = Vector3(-0.9, 2.5, 0.1)     # 屋顶顶面
	shed.add_child(sign)
	sign.face_towards(Vector3(-583.5, sign.global_position.y, -9.5))


## 房顶必须**能站人**（2026-10-20 用户：「房顶怎么没有碰撞箱，跳上去掉下来了」）。
##
##   · `RoofSolid`：4.4 × 0.2 × 3.4 的碰撞盒，和 `Roof` 网格完全重合（顶面 y = 2.5）。
##
## ⚠️ 2026-10-21 用户：「这五个方块要删掉」—— 截图里那五个白盒子是
##    **西侧三级台阶（`RoofSteps` 的 3 个 Mesh）** + **掩体旁边那两只木箱（`Crates` 的 2 个 Mesh）**，
##    五个都已经从 `parkour.tscn` 里删了，所以这里也不再生成台阶（`RoofSolid` 留着）。
##    代价写在 README §1.16.4f：屋顶 2.5 m、跳跃 1.26 m，**没有台阶就上不去**，
##    而 5090 要求「站在屋顶正上方」才能捡 —— 需要另找一条上去的路（待用户定方案）。
func _ensure_roof_solid() -> void:
	var shed := get_node_or_null("Island/Props/Shed") as Node3D
	if shed == null:
		return
	if shed.get_node_or_null("RoofSolid") != null:
		return
	var body := StaticBody3D.new()
	body.name = "RoofSolid"
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4.4, 0.2, 3.4)
	cs.shape = bx
	cs.position = Vector3(0.0, 2.4, 0.0)
	body.add_child(cs)
	shed.add_child(body)
	print("[Parkour] 房顶补上碰撞盒 RoofSolid（台阶已按用户要求删除）")


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
##    所以改回「回最近踩过的落脚点」。检查点仍然只在段交界推进（段号也只在段交界前进），
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


## 读进度存档。
##
## ⚠️ 用户要求「重进游戏回到初始位置」，所以默认**不恢复 checkpoint**：
##    只把文件里的最好成绩读回来；`checkpoint` 留在 −1（段号回到第 1 段），
##    人从 `game.tscn` 的初始出生点开始，不会被传送到上次的塔/机关上。
##    需要旧行为时把 `resume_on_start` 打开（落盘数据一直都在）。
##    站号照旧校验一遍（免得改了路线之后旧存档把人送到空里）。
func _load_run() -> void:
	var cf := ConfigFile.new()
	if cf.load(RUN_PATH) != OK:
		return
	var idx := int(cf.get_value("parkour", "checkpoint", -1))
	if _best <= 0.0:
		_best = maxf(0.0, float(cf.get_value("parkour", "best", 0.0)))
	if not resume_on_start:
		var shown := "无" if idx < 0 else "第 %d 站 %s" % [
			idx + 1, label_at(clampi(idx, 0, node_count() - 1))]
		print("[Parkour] 读档：忽略上次检查点（%s）—— 重进游戏从初始位置开始" % shown)
		return
	if idx >= 0 and idx < node_count():
		checkpoint = idx
		_resume_pending = checkpoint > 0
	print("[Parkour] 读档：最近踩过第 %d 站 %s（最好 %s，续跑已开启）"
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

	# 读档续跑（**仅在 `resume_on_start = true` 时**；默认关闭，重进回初始位置）
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

	# 起跑：上过跑道（checkpoint ≥ 0）之后**离开第 0 站**就开始计时。
	#
	# ⚠️ 判据必须是 `here > 0`，不能是 `here != 0`：`here = −1` 表示「脚下不是任何一站」，
	#    玩家站在平台上时就是 −1 —— 那样会变成
	#    「起表 → 下一帧『回到主平台』停表 → 再起表」**每帧来回抖**，
	#    日志一秒刷几百行「回到主平台：停表、保留进度」（2026-10-20 自检里撞见的）。
	if checkpoint >= 0 and not timer_running and not finished and here > 0:
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
	if here < 0 and _standing_on_platform(p) and (timer_running or finished):
		if finished:
			print("[Parkour] 通关后回到主平台：进度清空，下次从跑道重来")
			reset_run()
		else:
			print("[Parkour] 回到主平台：停表、**保留进度**（最近踩过第 %d 站 %s）"
				% [checkpoint + 1, label_at(checkpoint)])
			_disarm()


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
## ⚠️ 只看 **xz**：一个人掉到 −59 m 时 y 已经说明不了「他是从哪儿掉下去的」，
##    但 xz 能 —— 在平台范围内掉下去交给 game.gd（它送出生点），出了平台就是跑酷的路线。
func _on_platform(p: Vector3) -> bool:
	return absf(p.x) <= 20.0 and absf(p.z) <= 20.0


## 站在平台**地面上**（收工判定用；和上面那条分开，免得下坠途中就把表停了）
func _standing_on_platform(p: Vector3) -> bool:
	return p.y > -0.5 and p.y < 3.0 and _on_platform(p)


## 收工但**保留进度**：只停表、不清检查点（玩家回平台拿东西不该丢进度）
func _disarm() -> void:
	timer_running = false
	finished = false
	_elapsed = 0.0


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


## 小屋里的结算台（2026-10-20）：站在屋里就自动把资产+保证金结算进银行卡并还债。
func _spawn_settlement() -> void:
	var shed := get_node_or_null("Island/Props/Shed")
	if shed == null or shed.get_node_or_null("Settlement") != null:
		return
	var sp := SettlementPad.new()
	sp.name = "Settlement"
	sp.position = Vector3(0.0, 0.0, 0.4)
	shed.add_child(sp)


## ── 陷阱：牢笼 + 倭瓜优香（2026-10-20）──
##
## 用户：「5090 两次 F 确认后，信号塔上方会突然滑下来牢笼让我们回不去，然后出现
## 神秘 boss 倭瓜优香，boss 出场提示是：爱丽丝还我十万美刀!!!」
##
## 牢笼罩住 `ReturnPad`（回初始平台的传送台）—— 它本来就是唯一的退路，罩住就回不去。
## 信号塔现在也挪到了同一个位置（`Island/Props/Tower`），牢笼就是从塔顶滑下来的。
var _trap_done := false
var _cage: Node3D
var _avenger: Boss


func trap_sequence() -> void:
	if _trap_done:
		return
	_trap_done = true
	var pad := get_node_or_null("Island/Props/ReturnPad") as Node3D
	if pad == null:
		push_warning("[Parkour] 找不到 ReturnPad，牢笼跳过")
		return
	_cage = _build_cage(pad)
	var tw := create_tween()
	tw.tween_property(_cage, "global_position",
		pad.global_position + Vector3(0.0, 0.02, 0.0), 0.45) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		Sfx.play("ui_open", 4.0)
		_spawn_avenger(pad))
	Sfx.play("ui_close", 2.0)
	print("[Parkour] 牢笼从信号塔顶滑下，罩住传送台")


func _build_cage(pad: Node3D) -> Node3D:
	var cage := Node3D.new()
	cage.name = "TrapCage"
	get_parent().add_child(cage)           # 挂到 game 下：牢笼不随 Parkour 的局部变换
	cage.global_position = pad.global_position + Vector3(0.0, 7.6, 0.0)  # 塔顶平台下沿
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.20, 0.21, 0.24)
	steel.metallic = 0.8
	steel.roughness = 0.4
	var half := 1.5
	var h := 2.6
	var bar := 0.07
	# 2026-10-20 用户：「牢笼密集一点」—— 间距从 0.6 m 收到 **0.3 m**
	# （每面 11 根、顶盖 22 根，合计 66 根；之前是每面 5 根、顶 10 根）
	var offs: Array[float] = []
	for k in range(-5, 6):
		offs.append(float(k) * 0.3)
	for side in 4:
		for t in offs:
			var pos := Vector3(t, h * 0.5, half)
			match side:
				1: pos = Vector3(t, h * 0.5, -half)
				2: pos = Vector3(half, h * 0.5, t)
				3: pos = Vector3(-half, h * 0.5, t)
			_add_cage_bar(cage, pos, Vector3(bar, h, bar), steel)
	# 顶：横竖两组，像笼子盖
	for t in offs:
		_add_cage_bar(cage, Vector3(t, h, 0.0), Vector3(bar, bar, 2.0 * half), steel)
		_add_cage_bar(cage, Vector3(0.0, h, t), Vector3(2.0 * half, bar, bar), steel)
	# 碰撞：四面薄墙（不封顶，掉下来时玩家还在里面也无所谓 —— 反正出不去）
	var body := StaticBody3D.new()
	body.name = "Col"
	cage.add_child(body)
	for side in 4:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(2.0 * half + bar, h, 0.16) if side < 2 			else Vector3(0.16, h, 2.0 * half + bar)
		cs.shape = bx
		cs.position = Vector3(0.0, h * 0.5, half) if side == 0 			else Vector3(0.0, h * 0.5, -half) if side == 1 			else Vector3(half, h * 0.5, 0.0) if side == 2 			else Vector3(-half, h * 0.5, 0.0)
		body.add_child(cs)
	return cage


func _add_cage_bar(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _spawn_avenger(pad: Node3D) -> void:
	var ps := load("res://scenes/bosses_standby.tscn") as PackedScene
	if ps == null:
		push_warning("[Parkour] 没有 bosses_standby.tscn，倭瓜优香来不了")
		return
	var holder := ps.instantiate()
	var boss := holder.get_node_or_null("BossSquash") as Boss
	if boss == null:
		holder.queue_free()
		return
	boss.owner = null
	holder.remove_child(boss)
	get_parent().add_child(boss)
	boss.global_position = pad.global_position + Vector3(3.5, 0.0, 2.0)
	boss.rotation.y = PI
	# 用户 2026-10-20：「打败倭瓜优香后牢笼解除，倭瓜优香不能复活」
	boss.respawn_on_death = false
	_avenger = boss
	if not boss.died.is_connected(_on_avenger_died):
		boss.died.connect(_on_avenger_died)
	var game := get_parent()
	if game != null and game.has_method("_on_gate_boss"):
		game.call("_on_gate_boss", boss)
	holder.queue_free()
	# 用户：「真正拾取 5090 后视角强制锁定倭瓜优香一秒钟」
	var player := get_tree().get_first_node_in_group("player") as Player
	if player != null:
		player.look_at_node(boss, 1.0)
	var fut := get_tree().get_first_node_in_group("futures")
	if fut != null and fut.has_method("boss_line"):
		fut.call("boss_line", "爱丽丝还我十万美刀！！！")
	print("[Parkour] 倭瓜优香登场：爱丽丝还我十万美刀！！！")


## 倭瓜优香倒下：牢笼升回去消失（用户：「打败倭瓜优香后牢笼解除」），它本人不复活
## （`respawn_on_death = false`，见 `boss.gd::_die()`）。
func _on_avenger_died(_by_damage: float) -> void:
	if _cage != null and is_instance_valid(_cage):
		var cage := _cage
		_cage = null
		var tw := create_tween()
		tw.tween_property(cage, "global_position",
			cage.global_position + Vector3(0.0, 9.0, 0.0), 0.5) 			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_callback(cage.queue_free)
		Sfx.play("ui_open", 4.0)
	print("[Parkour] 倭瓜优香倒下 → 牢笼解除")
