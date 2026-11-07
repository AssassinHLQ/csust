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

## 倭瓜优香登场台词。用户 2026-10-21：「从『爱丽丝还我十万美刀.』变成
## 『敢动我 5090?!』换行『爱丽丝还我十万美刀!!!』」—— 先炸显卡,再讨债。
## `\n` 是硬换行（`BossLine` 那个 Label 的 autowrap 关着,换行只认这里）。
const BOSS_LINE := "敢动我5090？！\n爱丽丝还我十万美刀！！！"

## 倭瓜优香倒下掉进银行卡的钱（元）。用户 2026-11：「掉落 10w」→ 后改「20w」
## （67 万的整机门槛，10 万太少，凑不够）
const AVENGER_DROP := 200000
## 通关后立在跑道口的传送门，踩上去直接送到岛上的结算屋
const PORTAL_DEST := "Island/Props/Shed"
## 传送门送到的地方：屋里那台结算台会自动把资产 + 保证金转进这张卡
const BankCard := preload("res://scripts/bank_card.gd")
## 可骑乘火箭的控制器。用 `preload` 而不是全局类名 —— 探针在 `--script` 下
## 解析不到 `class_name`（`RenderEnv` 那次栽过），这样最稳。
const RocketRideScript := preload("res://scripts/rocket_ride.gd")

## 跑道口那一头**唯一的停机位**（相对 `Launch`，往 +Z 挪 4.5 m ——
## 离开跑道 z 2.5~5.5，又还在主平台上）。
##
## ⚠️ 2026-11-07 起这个点**同时**是：传送门所在处 / 去程起飞点 / **回程落点**。
##    原来回程落点被我自己推开了 4 m（旧 `HOME_LAND_OFFSET`），理由是「免得两枚
##    火箭叠在同一个格子里」—— 用户反馈「火箭落地不是传送门那一块，是因为有东西
##    挡住吧」：**挡住它的就是另一枚火箭**，地上并没有任何实体（射线量过，见
##    `scripts/_probe_rocket_land.gd`）。现在改成两枚火箭**互换位置**（见
##    `_start_ride()` 里的空载摆渡），这一个停机位就够用了。
const PORTAL_OFFSET := Vector3(0.0, 0.0, 4.5)
## 岛上那一头**唯一的停机位**（相对 `Island/Props/ReturnPad`，往 −Z 挪 5 m）。
##
## 位置是被三件东西夹出来的（全部实测，见 `_probe_rocket_land.gd` 与
## `_arisu_captures/_rocket_spots/`）：
##   · 传送台台面 3×3（z −6~−3）—— 不能压上去；
##   · 信号塔平台 4×4、y 18（x −597~−593、z −6.5~−2.5）—— 42 m 的箭体是根
##     半径 1.5 m 的柱子，z 必须退到 −8 以外才不相交（−4 m 时只剩 0.5 m，
##     俯视图里看着像穿塔，所以多让 1 m）；
##   · 结算屋屋顶（x −596.2~−591.8、z −15.2~−11.8、y 10.3）—— z 不能超过 −11。
## 折中到 z = −9.5：离塔 1.5 m、离屋顶 0.8 m、离传送台 5 m。
const ISLAND_SPOT_OFFSET := Vector3(0.0, 0.0, -5.0)
## 空载摆渡的巡航高度（米）。比载人那趟（`RocketRide.lift_altitude` = 45 m）
## 高一倍多，两枚对飞时不会在半空中撞在一起。
const FERRY_ALTITUDE := 95.0

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


## ── 招牌可见距离（2026-11-07 改）──────────────────────────────────────────────
##
## 历史：2026-11-06 用户说「把这些穿墙大字去掉，只有站在最附近才可以显示」，
## 于是**全部** Label3D 被压到 6 m 内可见 —— 结果整条跑道上「第 N 段」「+15.00%」
## 这些牌子全得踩上去才看得见，跑起来就不知道前面是哪儿、下一块跳多少。
##
## 2026-11-07 用户重新划界：「只要开始平台上面的字，在六米内才显示就可以了，
## 跑酷那一长段不要这样子」。所以现在拆成两档：
##
##   · **近档 6 m**  —— 只给「站台上/零散装饰」用：`SignPost`（跑酷 · 12 段 → /
##                     第 1 段 · 起点）、`ReadyZone`（跑酷准备区）、`Island`（终点岛
##                     那块「坐火箭 · 去结算屋」与传送台）。
##                     ⚠️ 注意 `Route/P1` **不算**站台 —— 它是跑道第一块砖，
##                     「第 1 段 · 起点」那两根信号桅杆是挂在 `Route/Beacon_K1` 上的。
##   · **远档**     —— 跑道上剩下的全部（`Route` 下所有 `Pct` / `Sign` / 规则牌），
##                     以及任何不在上面两个清单里的节点：不限距离 = 引擎默认。
##
## 为什么还要留着距离门控这件事：画室 609 的泼溅走 Compositor 画，**不写引擎深度
## 缓冲**，所以实体墙挡得住招牌、泼溅墙挡不住。`_gate_world_labels()` 会把
## `no_depth_test` 统一关掉（靠真深度测试挡住实体墙），近档再用距离兜住泼溅墙。
##
## 想改可见范围只动这两个常量；想把某个节点整体挪到某一档，改 `_label_near_zone()`。
const LABEL_NEAR_END := 6.0
const LABEL_NEAR_MARGIN := 2.0

## 走近档（6 m）的根节点路径（相对本场景）。空字符串 = 整棵子树都按近档处理。
## 命中第一条就停 —— 所以顺序 = 优先级，`Route` 永远不进这个表。
const LABEL_NEAR_ROOTS := ["SignPost", "ReadyZone", "Island"]

## 画室 609 的房间盒子（实测值，来自游戏日志）：
##   `[Game] 609 门内外切换：… 房间矩形 (10.71, 8.3, 20.64)，中心 (-0.5, 1.5, 3.54)`
##
## 为什么要它：`_probe_label_distance.gd` 量出来，跑酷起点那几个招牌离画室盒子只有
## **5.6 / 7.1 / 9.1 m**（`跑酷 · 12 段 →`、`第 1 段 · 起点`、`跑酷准备区`、
## `同伴在此待命`、`稳定基金…`），而跑酷整体包围盒的东缘 x=-6.0、
## 画室西墙 x=-5.86 —— **两者只隔 0.1 m**。所以光靠距离门控永远挡不住：
## 玩家站在房间里，那几个牌子就在「最附近」。
## 加上这条区域门控后，**人在画室里 → 全部招牌隐藏**，出了门才启用。
const ROOM_CENTER := Vector3(-0.5, 1.5, 3.54)
const ROOM_HALF := Vector3(5.36, 4.15, 10.32)
## 出了房间再多走一点才启用（避免站在门口时字突然糊一脸）
const ROOM_EXIT_MARGIN := 1.5

## 所有受门控的招牌（`_gate_world_labels()` 收集，`_update_label_visibility()` 开关）
var _label_nodes: Array[Label3D] = []
var _labels_on := true


func _ready() -> void:
	_build_route()
	if not run_finished.is_connected(_on_run_finished):
		run_finished.connect(_on_run_finished)
	_load_best()
	_load_run()
	_spawn_roof_gpu()
	_spawn_bank_sign()
	_spawn_settlement()
	_ensure_roof_solid()
	_spawn_ride_rockets()
	# 立即扫一遍（覆盖 .tscn 里摆好的招牌），再延迟扫一遍 —— 子场景
	# `parkour_futures.gd` 会在运行时动态生成「第 N 段」规则牌，第一遍扫不到。
	_gate_world_labels()
	_gate_world_labels.call_deferred()


## 把本场景里所有世界空间文字（Label3D / Sprite3D）统一成「正常深度测试」，
## **再按位置分档**决定要不要压近距离（见上面 `LABEL_NEAR_ROOTS` 那段注释）。
##
## 为什么放在 `_ready()` 末尾一次性扫：`parkour.tscn` 里有 64 个招牌，
## 逐个改 `.tscn` 容易漏、以后新加也会忘；扫一遍子树是唯一不漏的做法。
## 唯一的例外是运行期才生成的牌子（`parkour_futures.gd` / `ram_market.gd`），
## 它们在 `_ready()` 之后才 add_child —— 那几个自己写好了数值。
func _gate_world_labels() -> void:
	_label_nodes.clear()
	var n := 0
	var near := 0
	for node in find_children("*", "Label3D", true, false):
		var lab := node as Label3D
		if lab == null:
			continue
		lab.no_depth_test = false
		if _label_near_zone(lab):
			lab.visibility_range_end = LABEL_NEAR_END
			lab.visibility_range_end_margin = LABEL_NEAR_MARGIN
			near += 1
		else:
			# 远档：不限距离 = 引擎默认值（0），显式写出来，免得 .tscn 里留着的旧值
			# 把人骗了
			lab.visibility_range_end = 0.0
		# 立刻对齐当前开关状态：`_update_label_visibility()` 有「状态没变就早退」
		# 的优化，新收集进来的牌子不会被它扫到（踩过一次：4 个动态牌一直亮着）。
		lab.visible = _labels_on
		_label_nodes.append(lab)
		n += 1
	for node in find_children("*", "Sprite3D", true, false):
		var spr := node as Sprite3D
		if spr == null:
			continue
		spr.no_depth_test = false
		if _label_near_zone(spr):
			spr.visibility_range_end = LABEL_NEAR_END
			spr.visibility_range_end_margin = LABEL_NEAR_MARGIN
		else:
			spr.visibility_range_end = 0.0
		n += 1
	print("[Parkour] 世界招牌 %d 个：%d 个近档（%.0f m 内显示），其余不限距离；人在画室内全部隐藏"
		% [n, near, LABEL_NEAR_END])
	_update_label_visibility()


## 这个节点属不属于「近档」（6 m 内才显示）—— 只看它挂在哪棵子树下。
## `LABEL_NEAR_ROOTS` 里是相对本场景的路径；取不到就按远档处理（宁可看得见）。
func _label_near_zone(node: Node) -> bool:
	for root_path in LABEL_NEAR_ROOTS:
		var root := get_node_or_null(NodePath(root_path))
		if root == null:
			continue
		if root == node or root.is_ancestor_of(node):
			return true
	return false


## 玩家在画室 609 盒子里 → 招牌全关；出了房间（再多 1.5 m）→ 全开。
## 每帧只做一次 AABB 判断，只有状态翻转时才真的去写 `visible`。
func _update_label_visibility() -> void:
	if _label_nodes.is_empty():
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		# `_ready()` 阶段玩家还没进场景。玩家本来就出生在画室里，
		# 所以「先隐藏」才是安全默认 —— 否则开局会闪一下大字。
		if _labels_on:
			_labels_on = false
			for lab in _label_nodes:
				if is_instance_valid(lab):
					lab.visible = false
		return
	var p := _player.global_position
	var d := Vector3(
		maxf(absf(p.x - ROOM_CENTER.x) - ROOM_HALF.x, 0.0),
		maxf(absf(p.y - ROOM_CENTER.y) - ROOM_HALF.y, 0.0),
		maxf(absf(p.z - ROOM_CENTER.z) - ROOM_HALF.z, 0.0))
	var want := d.length() > ROOM_EXIT_MARGIN
	if want == _labels_on:
		return
	_labels_on = want
	for lab in _label_nodes:
		if is_instance_valid(lab):
			lab.visible = want


## 最后平台的掩体屋顶上放一块 RTX 5090（用户 2026-10-20：「房子上面放一个 5090……
## 5090 也是加入资产的，全新正版现价 59999」）。
##
## **运行时生成**、不写进场景：屋顶位置跟着掩体走，写死绝对坐标以后一改房子就漂。
func _spawn_roof_gpu() -> void:
	var shed := get_node_or_null("Island/Props/Shed")
	if shed == null:
		return
	# 旧场景里烘过一张，先清掉再按四张重新摆
	for c in shed.get_children():
		if String(c.name).begins_with("RTX5090"):
			c.queue_free()
	# 2026-11 用户：「跑酷终点的 5090 换成四张，整齐摆放」——
	# 东半边 2×2 摆开（西边留给 BANK 招牌），每张仍按 ¥59,999 进资产账。
	var spots := [
		Vector3(0.55, 2.5, -0.55), Vector3(1.45, 2.5, -0.55),
		Vector3(0.55, 2.5, 0.75), Vector3(1.45, 2.5, 0.75),
	]
	for i in spots.size():
		var gpu := Rtx5090.new()
		gpu.name = "RTX5090_%d" % (i + 1)
		gpu.position = spots[i]
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


## 摔下去该回哪一站 —— **每一段一个存档点（= 本段起点）**。
##
## 演进过程（别再来回改）：
##   v1/v3 回「最近踩过的落脚点」→ 用户 2026-11 报「每个格子都是存档点，太多」；
##   v4   改成「整关只有一个」→ 用户当天又报「这个难死了，为什么不是每隔一段一个」；
##   现在 = **段起点**：12 段就有 12 个复活点，摔了只重跑当前这一段。
func respawn_station() -> int:
	if checkpoint < 0:
		return 0
	var seg := segment_of(checkpoint)
	if seg + 1 < segments.size() and checkpoint >= segment_start(seg + 1) - 1:
		# 已经踩到本段最后一站（比如 C1 = 第 1 段终点）→ 存档推进到下一段起点，
		# 而不是把玩家打回本段开头。段终点那根「第 N 段·终点」的柱子就是存档点。
		return segment_start(seg + 1)
	return segment_start(seg)


## 站在第 i 站的台面上时，人应该被放在哪儿（台面正中、抬高 5 cm 免得嵌进去）
## 摔落 / 被打死回哪儿：上过岛就回岛上记的那个点，否则回本段起点。
func respawn_position() -> Vector3:
	if _island_cp != Vector3.INF:
		return _island_cp
	return respawn_point(respawn_station())


## 「已存档：结束平台」
func _notify_island_save() -> void:
	var fut := get_tree().get_first_node_in_group("futures")
	if fut != null and fut.has_method("boss_line"):
		fut.call("boss_line", "已存档：结束平台")
	print("[Parkour] 已存档：结束平台 %s" % str(_island_cp.snappedf(0.1)))


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
	# 回到主平台重开一轮：岛上的存档作废，否则下一次摔落还会被送回终点。
	_island_cp = Vector3.INF


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
	_portal_cooldown = maxf(0.0, _portal_cooldown - _delta)
	# 招牌开关放在 `enabled` 判断**之前**：即使跑酷没启用，画室里也不该飘着大字
	_update_label_visibility()
	if not enabled:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			return
		# 复活点由场景（game.gd）统一设成「本场景唯一的存档点」，跑酷不再自己改。
		if not _player.died.is_connected(_on_player_died):
			_player.died.connect(_on_player_died)
	var p := _player.global_position
	# 只有**脚踏实地站在大平台台面**上才算岛上存档：存档坐标写死成平台上的安全点，
	# 不再记玩家踩上去的那一点（那可能是平台边缘 / 半空，y 压到 7.75 会生成在板子底下）。
	if _island_cp == Vector3.INF and _player.is_on_floor() \
			and absf(p.x - ISLAND_CENTER.x) < ISLAND_INNER \
			and absf(p.z - ISLAND_CENTER.z) < ISLAND_INNER \
			and p.y > ISLAND_TOP_Y - 0.4 and p.y < ISLAND_TOP_Y + 1.5:
		_island_cp = ISLAND_SPAWN
		_notify_island_save()
	var here := _station_at(p)

	# 读档续跑（**仅在 `resume_on_start = true` 时**；默认关闭，重进回初始位置）
	if _resume_pending and checkpoint > 0 and _on_platform(p):
		_resume_pending = false
		_player.global_position = respawn_point(checkpoint)
		_player.velocity = Vector3.ZERO
		print("[Parkour] 读档续跑：送回第 %d 站 %s" % [checkpoint + 1, label_at(checkpoint)])
		return

	var save_at := respawn_station()
	if save_at > _saved_station:
		_saved_station = save_at
		_notify_save(save_at)

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
	# 每段一个存档点：摔了就回**本段起点**，进度退到段首（不是清零整关）
	var back := respawn_station()
	var pos := respawn_position()
	if _island_cp == Vector3.INF:
		checkpoint = back
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.set_respawn_point(pos)
	rescued.emit(back, label_at(back))
	Sfx.play("ui_open")
	print("[Parkour] 第 %d 次摔落 → %s" % [rescues,
		"回结束平台" if _island_cp != Vector3.INF
		else "回第 %d 段起点（第 %d 站 %s）" % [segment_of(back) + 1, back + 1, label_at(back)]])


## 被 boss 打死：和摔落一样，进度清零；传送和回血由玩家自己在 0.6 s 后完成。
## 存档推进时弹一句（踩到「第 N 段·终点」那根柱子就算存过档）
func _notify_save(station: int) -> void:
	var text := "已存档：第 %d 段起点" % (segment_of(station) + 1)
	var fut := get_tree().get_first_node_in_group("futures")
	if fut != null and fut.has_method("boss_line"):
		fut.call("boss_line", text)
	print("[Parkour] %s（第 %d 站 %s）" % [text, station + 1, label_at(station)])


func _on_player_died() -> void:
	# 和摔落同一条规则：回本段起点。玩家 0.6 s 后才传送，先把复活点改掉。
	var back := respawn_station()
	var pos := respawn_position()
	if _island_cp == Vector3.INF:
		checkpoint = back
	_player.set_respawn_point(pos)
	print("[Parkour] 玩家倒下 → %s" % [
		"回结束平台" if _island_cp != Vector3.INF
		else "回第 %d 段起点（第 %d 站 %s）" % [segment_of(back) + 1, back + 1, label_at(back)]])


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
	if _riding:
		# 正飞着呢：落地动画途中又踩一下触发盒，不许重复起飞
		return
	var rocket := _ensure_return_rocket()
	if rocket == null:
		# 兜底：火箭造不出来就退回原来的瞬移（没有回头路 = 死局，见上面那段注释）
		_player.global_position = return_target
		_player.velocity = Vector3.ZERO
		reset_run()
		Sfx.play("ui_toggle")
		print("[Parkour] 传送台（火箭不可用，退回瞬移）→ 主平台 %s" % str(return_target))
		return
	# ⚠️ 这里**不要**写 `_return_rocket = rocket`：换过一次边之后，站在岛上的
	#    可能正是 `_finish_rocket` 那一枚，赋值会让两个变量指向同一个节点，
	#    `_other_rocket()` 就永远返回 null、空载摆渡失效。位置一律用 `_rocket_at()` 查。
	Sfx.play("ui_toggle")
	print("[Parkour] 传送台 → 坐火箭回跑道口（人出舱 %s）" % str(return_target))
	_start_ride(rocket, _home_spot(), return_target, _player, "回程", true)


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
## 通关后立的传送门（见 _spawn_finish_portal）
var _finish_portal: Node3D
## 两枚火箭：**开场就各就各位**，一直站在两头。
##
## ⚠️ 2026-11-07 改：原来只有 `_finish_rocket` 是常驻的，回程那枚是**懒生成**
##    （第一次踩岛上传送台才造出来，省得没走到岛上的人白扛 116k 面）。
##    用户反馈「火箭是我站在传送台才出现的，不是一直在那儿等着的」——
##    一站上去凭空冒出一枚 42 m 的火箭确实很怪，所以现在两枚都在 `_ready()` 里造好。
##    代价是多一份 GLB 实例（`ResourceLoader` 会缓存 PackedScene 和网格，
##    第二枚只多付一份节点/材质，不重复解码文件）。
##
## 名字保持 `_finish_` / `_return_` 是为了少动代码，但**别再按名字认位置**：
## 两枚每次飞完都会互换（见 `_start_ride()`），谁在哪头要用 `_rocket_at()` 现查。
var _finish_rocket: Node3D
var _return_rocket: Node3D
## 正在飞。防止降落动画途中又踩一次触发盒，重复起飞
var _riding := false
## 这次骑乘结束后要不要 `reset_run()`（回程要清检查点/计时，去程不要）
var _ride_reset_after := false
## 上一次提示过的存档站（只在往前推进时弹一次，别每帧刷）
var _saved_station := 0
## 结束平台（岛）的存档：用户 2026-11「结束平台也要算一个存档，不然别人复活到了
## 柱子上就无伤倭瓜优香了」——第一次落到岛上就记下，之后摔落/被打死回岛上，
## 而不是回第 12 段的柱子顶上。
##
## 存档点**写死**在大平台台面上（用户 2026-11「存档点错了……应该存档在这个大平台才对」）：
## 记玩家落点会把边缘/半空的坐标存下来，复活直接生成到板子底下摔死。
## 平台：`Island` 中心 (-590.95, 7.4, -9.5)，16×16 m 板厚 1.2 → 台面 y = 8.0。
## 安全点选在平台东侧空地：避开结算屋（x ≈ -594）、信号塔腿（x ≈ -595）和倭瓜出生点（-591, -2.5）。
const ISLAND_CENTER := Vector3(-590.95, 7.4, -9.5)
const ISLAND_TOP_Y := 8.0
const ISLAND_SPAWN := Vector3(-587.5, 8.08, -8.5)
## 台面内圈半边长：栏杆在 ±7.4，退进来一点（7.0）免得贴着边生成。
const ISLAND_INNER := 7.0
var _island_cp := Vector3.INF
var _portal_cooldown := 0.0
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
		fut.call("boss_line", BOSS_LINE)
	print("[Parkour] 倭瓜优香登场：%s" % BOSS_LINE.replace("\n", " / "))


## 倭瓜优香倒下：牢笼升回去消失（用户：「打败倭瓜优香后牢笼解除」），它本人不复活
## （`respawn_on_death = false`，见 `boss.gd::_die()`）。
## ── 通关后的「直达终点」传送门（2026-11 用户要求）──
##
## 用户：「通关跑酷后，在跑酷开始的地方可以设置传送门直接抵达结束处，方便玩家将资产
## 转化银行卡里面」。所以 `run_finished` 一响，就在跑道口旁边立一座发光的门；
## 踩上去直接送到岛上的结算屋 —— 屋里那台 SettlementPad 会自动把资产 + 保证金
## 转进银行卡，省得再跑一遍全程。
func _on_run_finished(_seconds: float, _best: float) -> void:
	_spawn_finish_portal()


func _spawn_finish_portal() -> void:
	if is_instance_valid(_finish_portal):
		return
	var launch := get_node_or_null("Launch") as Node3D
	var shed := get_node_or_null(PORTAL_DEST) as Node3D
	if launch == null or shed == null:
		push_warning("[Parkour] 传送门缺 Launch 或 %s，跳过" % PORTAL_DEST)
		return

	var door := Node3D.new()
	door.name = "FinishPortal"
	add_child(door)
	# 跑道口往 +Z 挪 4.5 m：离开跑道（z 2.5~5.5），又还在主平台上
	door.global_position = launch.global_position + PORTAL_OFFSET

	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.05, 0.05, 0.06)
	frame.roughness = 0.45
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(0.42, 0.80, 1.0, 0.5)
	glow.emission_enabled = true
	glow.emission = Color(0.42, 0.80, 1.0)
	glow.emission_energy_multiplier = 1.4

	for x in [-1.05, 1.05]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 2.7, 0.22)
		post.mesh = bm
		post.material_override = frame
		post.position = Vector3(x, 1.35, 0.0)
		door.add_child(post)
	var lintel := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(2.24, 0.16, 0.22)
	lintel.mesh = lm
	lintel.material_override = frame
	lintel.position = Vector3(0.0, 2.74, 0.0)
	door.add_child(lintel)

	var panel := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.96, 2.4)
	panel.mesh = qm
	panel.material_override = glow
	panel.position = Vector3(0.0, 1.34, 0.0)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	door.add_child(panel)

	var label := Label3D.new()
	label.text = "坐火箭 · 去结算屋"
	label.font_size = 64
	label.pixel_size = 0.008
	label.modulate = Color(0.75, 0.92, 1.0, 1.0)
	label.outline_modulate = Color(0.05, 0.05, 0.08, 1.0)
	label.outline_size = 18
	# 往 +X 让开 2.4 m：火箭直径 1.51 m 正好卡在门框正中，招牌压在箭体上会糊成一团
	# （出图 `_arisu_captures/_rocket/4_engines.png` 里能看到）。
	label.position = Vector3(2.4, 3.05, 0.0)
	door.add_child(label)

	var area := Area3D.new()
	area.name = "Trigger"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 2.6, 0.9)
	cs.shape = bs
	cs.position = Vector3(0.0, 1.3, 0.0)
	area.add_child(cs)
	area.body_entered.connect(_on_finish_portal_body)
	door.add_child(area)

	_finish_portal = door
	# 火箭和门立在同一格：用户 2026-11-06「SpaceX 火箭加入跑酷尽头那个传送门」。
	# 火箭本身在 `_ready()` 里就造好了（两头各一枚常驻），这里只兜底补造。
	if _rocket_at(_home_spot()) == null:
		var r := _spawn_ride_rocket(door.global_position)
		if r != null:
			_finish_rocket = r
	print("[Parkour] 通关：传送门立在跑道口 %s（目标 %s），火箭就位：%s" % [
		str(door.global_position.snappedf(0.1)), PORTAL_DEST,
		"有" if _rocket_at(_home_spot()) != null else "无"])


func _on_finish_portal_body(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if _portal_cooldown > 0.0 or _riding:
		return
	var shed := get_node_or_null(PORTAL_DEST) as Node3D
	if shed == null:
		return
	# 站在跑道口那一头的是哪一枚就用哪一枚（换边之后可能已经是对面那枚）
	var rocket := _rocket_at(_home_spot())
	if rocket == null:
		rocket = _spawn_ride_rocket(_home_spot())
		if rocket == null:
			# 兜底：火箭造不出来就退回原来的瞬移，别把人困在门口
			_portal_cooldown = 2.0
			body.global_position = shed.global_position + Vector3(0.0, 0.1, 0.6)
			if body is CharacterBody3D:
				(body as CharacterBody3D).velocity = Vector3.ZERO
			Sfx.play("ui_open", -2.0)
			print("[Parkour] 传送门（火箭不可用，退回瞬移）→ 结算屋")
			return
	print("[Parkour] 传送门 → 坐火箭去结算屋（火箭 %s）" % str(rocket.global_position.snappedf(0.1)))
	_portal_cooldown = 2.0
	_start_ride(rocket, _island_spot(),
		shed.global_position + Vector3(0.0, 0.1, 0.6), body, "去程", false)


## ── 两头各一个停机位 ─────────────────────────────────────────────────
## 跑道口：传送门脚下（去程起飞 / **回程落地**）
func _home_spot() -> Vector3:
	var launch := get_node_or_null("Launch") as Node3D
	if launch == null:
		return Vector3.ZERO
	return launch.global_position + PORTAL_OFFSET


## 岛上：传送台外侧 4 m（回程起飞 / 去程落地）
func _island_spot() -> Vector3:
	var pad := get_node_or_null("Island/Props/ReturnPad") as Node3D
	if pad == null:
		return Vector3.ZERO
	return pad.global_position + ISLAND_SPOT_OFFSET


## 除 `r` 之外的另一枚火箭（空载摆渡要用）
func _other_rocket(r: Node3D) -> Node3D:
	if r == _finish_rocket:
		return _return_rocket
	if r == _return_rocket:
		return _finish_rocket
	return null


## 谁站在 `spot` 附近。**别按 `_finish_` / `_return_` 的名字认位置** ——
## 两枚每飞一趟就互换一次（见 `_start_ride()`），名字早就对不上号了。
func _rocket_at(spot: Vector3, tol := 3.0) -> Node3D:
	for r in [_finish_rocket, _return_rocket]:
		var n := r as Node3D
		if n != null and is_instance_valid(n) and n.global_position.distance_to(spot) <= tol:
			return n
	return null


## 造两枚火箭，开场就停在两头。
##
## 用户 2026-11-07：「火箭是我站在传送台才出现的，不是一直在那儿等着的」——
## 所以不再是「踩到才懒生成」，`_ready()` 里两枚都造好，走不走得到岛上都在那儿站着。
func _spawn_ride_rockets() -> void:
	if not is_instance_valid(_finish_rocket):
		_finish_rocket = _spawn_ride_rocket(_home_spot())
	if not is_instance_valid(_return_rocket):
		_return_rocket = _spawn_ride_rocket(_island_spot())
	if _finish_rocket == null or _return_rocket == null:
		print("[Parkour] !! 火箭没造全（跑道口 %s / 岛上 %s）→ 缺的那头会退回瞬移" % [
			"有" if _finish_rocket != null else "无",
			"有" if _return_rocket != null else "无"])
		return
	print("[Parkour] 火箭就位：跑道口 %s / 岛上 %s（各高 %.0f m，%s）" % [
		str(_finish_rocket.global_position.snappedf(0.1)),
		str(_return_rocket.global_position.snappedf(0.1)),
		float(_finish_rocket.call("height")),
		"占位" if bool(_finish_rocket.call("is_placeholder")) else "Falcon9"])


## 岛上那枚。造不出来返回 null（调用方退回瞬移）。
##
## ⚠️ 用户 2026-11-07：「第一次传送回来怎么不是 SpaceX」——
##    如果这里返回 null，`_on_return_pad_entered` 会**静默退回瞬移**（压根没有火箭），
##    看起来就像「回程不是 SpaceX」。所以每条失败路径都必须留下带原因的日志。
func _ensure_return_rocket() -> Node3D:
	var here := _rocket_at(_island_spot())
	if here != null:
		return here
	# 不在停机位（理论上不该发生）：再造一枚补上
	var pad := get_node_or_null("Island/Props/ReturnPad") as Node3D
	if pad == null:
		push_warning("[Parkour] 回程火箭造不出来：找不到 Island/Props/ReturnPad")
		print("[Parkour] !! 回程火箭失败：Island/Props/ReturnPad 不存在 → 将退回瞬移")
		return null
	var r := _spawn_ride_rocket(_island_spot())
	if r == null:
		print("[Parkour] !! 回程火箭失败：_spawn_ride_rocket 返回 null → 将退回瞬移")
	else:
		_return_rocket = r
		print("[Parkour] 回程火箭补造：%s（缩放 %.2f，高 %.1f m）" % [
			str(r.global_position.snappedf(0.1)),
			float(r.get("rocket_scale")), float(r.call("height"))])
	return r


## 造一枚火箭停在 `at`：当载具兼地标
func _spawn_ride_rocket(at: Vector3) -> Node3D:
	var r := RocketRideScript.new()
	r.name = "RideRocket"
	add_child(r)
	r.call("park_at", at)
	return r


## 起飞。`land` 是火箭落点，`exit_point` 是**人**的最终落点（两者可以不同）。
##
## ── 关键：另一枚同时空载起飞，两枚互换位置 ──
## 用户 2026-11-07 的三条连起来是同一件事：火箭要**一直在**两头等着、
## 而且落地要落在传送门脚下。但一个停机位同一时刻只能站一枚 ——
## 玩家坐 A 飞向那头时，那头站着 B，A 落地就会和 B 叠在一起（旧代码的解法是把
## 回程落点推开 4 m，用户看到的就是「落地不是传送门那一块」）。
##
## 现在让 B 在 A 起飞的同时**飞向 A 刚离开的那个点补位**：
## 玩家落地时那头正好空出来，两头永远「走一枚、来一枚」，全程没有瞬移
## （瞬移会被看见凭空消失/出现）。B 走的是 95 m 高度，A 走 45 m，空中不会撞。
func _start_ride(rocket: Node3D, land: Vector3, exit_point: Vector3,
		body: Node3D, tag: String, reset_after: bool) -> void:
	if _riding or rocket == null:
		return
	_riding = true
	_ride_reset_after = reset_after
	if rocket.has_signal("ride_finished") and not rocket.is_connected("ride_finished", _on_ride_finished):
		rocket.connect("ride_finished", _on_ride_finished)
	# 另一枚空载去补位（目标 = 这枚刚离开的停机位）
	var other := _other_rocket(rocket)
	if other != null and is_instance_valid(other):
		if other.has_method("depart_to"):
			other.call("depart_to", rocket.global_position, FERRY_ALTITUDE)
	print("[Parkour] %s：坐火箭 %s → %s（人出舱 %s）" % [
		tag, str(rocket.global_position.snappedf(0.1)),
		str(land.snappedf(0.1)), str(exit_point.snappedf(0.1))])
	rocket.call("begin", rocket.global_position, land, exit_point, body)


func _on_ride_finished() -> void:
	_riding = false
	if _ride_reset_after:
		_ride_reset_after = false
		reset_run()
	print("[Parkour] 火箭落地，人已就位（跑道口 %s / 岛上 %s）" % [
		"有" if _rocket_at(_home_spot()) != null else "空",
		"有" if _rocket_at(_island_spot()) != null else "空"])


func _on_avenger_died(_by_damage: float) -> void:
	if _cage != null and is_instance_valid(_cage):
		var cage := _cage
		_cage = null
		var tw := create_tween()
		tw.tween_property(cage, "global_position",
			cage.global_position + Vector3(0.0, 9.0, 0.0), 0.5) 			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_callback(cage.queue_free)
		Sfx.play("ui_open", 4.0)
	var fut := get_tree().get_first_node_in_group("futures")
	if fut != null and fut.has_method("add_loot"):
		fut.call("add_loot", AVENGER_DROP, "倭瓜优香掉落")
	else:
		BankCard.add(AVENGER_DROP)
	if fut != null and fut.has_method("boss_line"):
		fut.call("boss_line", "倭瓜优香掉落 ¥%d → 本轮资产（结算后进银行卡）" % AVENGER_DROP)
	print("[Parkour] 倭瓜优香倒下 → 牢笼解除；掉落 %s（本轮资产，结算后进银行卡）" % [
		BankCard.format_yuan(AVENGER_DROP)])
