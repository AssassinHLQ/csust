extends Node3D
## 「临时服务器据点」小屋的 BGM（用户 2026-11-12）。
##
## 素材：「碧蓝档案OST Vol.1（320K）」P44「Daily Routine 247（阿罗娜／彩奈）」。
## 用户原话：「这个临时服务器据点用这个音乐，去掉结尾没声音时候就可以循环了」。
##
## ── 做法 ──
## 和商店／部室／电竞房一样：屋里放一个 `Area3D`，玩家进来就开 BGM、出去就停
## （2026-11-11 起全程**不淡化**，用户：「不要淡入淡出了，所有的」）。
## 尺寸**运行时按小屋自己的墙量**，不写死 —— 小屋是 CSG 拼的，改尺寸不用同步改这里。
##
## ── 触发区为什么是「往内缩」而不是「往外扩」──
## 用户 2026-11-12：「为什么占到边上也播放？缩小圈子，要进门才行」。
## 之前是外扩 1.2 m（想在门口留点余量），结果触发区比房子还大 ——
## 站在墙外、甚至只踩在门槛上就响了。现在改成内缩 `MUSIC_INSET`，
## 实测边界（胶囊体口径，见 `_verify_music` 的第 8 段）：
##
##     小屋世界 x 10.7~17.3（门在 −X 侧），内壁 x≈10.9
##     触发区世界 x 11.70~16.30、y 0~2.20、z −17.30~−13.70
##     ⇒ 音乐在 **x ≈ 11.40** 才开始响，也就是走进屋里约 0.5 m；
##        站在门槛（10.7）或墙外都不响；
##        y ≈ 2.55（脚底 1.50）以上停止 —— 站屋顶不会响
##
## ── 音频本身怎么处理的（在 `assets/music/README.md` 里也有记录）──
## 原曲 117.3537 s，但**头尾都有数字静音**（mp3 编码器留的）：
##   头部静音 0.1338 s、尾部静音 1.3691 s。
## 只切尾部的话，每次循环会多出 120 ms 空白（能听出来像「喘一口气」），
## 所以头尾都切掉 → 新长度 **115.8507 s**，末尾再补 8 ms 淡出收到干净零。
## 循环接缝跳变 0.0011，只有曲子内部相邻样点平均跳变（0.0239）的 **×0.045**。
##
## 判据与 `scripts/shop.gd::_build_music_zone()` 同一套，理由见那里。

## 曲目表见 `scripts/music.gd`（逻辑名 `hut`）
const MUSIC_TRACK := "hut"
## 触发区比屋内空间**往内缩**多少米（每边）。
##
## ⚠️ 这个数字被用户投诉过两轮，别再随手改大改小：
##
##   ① 2026-11-12「为什么占到边上也播放？缩小圈子，要进门才行」
##      当时是**往外扩 1.2 m**（想在门口留余量）→ 区比房子还大，站墙外就响。
##   ② 于是四周内缩 0.8 m → 2026-11-13 用户报「站在桌前音乐就停了」：
##      桌子在小屋局部 (−0.6, **−2.2**)，离 −Z 内壁只有 0.4 m，被内缩排除掉了。
##   ③ 又改成「门侧缩 1.1 m、其余缩 0.25 m」→ 用户再报
##      「站在门口里面还是没有音乐」：屋子总共才 6.2 m 宽，1.1 m 等于要求往里走将近一米。
##
## ⇒ 最终取 **0.2 m**（≈ 墙厚级别，等于「屋内就是触发区」）。
##   配合胶囊半径 0.30 的判定，实际效果是：
##     · 站门口内侧 → 响（胶囊一进屋就碰到区）
##     · 站屋外贴墙 → 静（胶囊够不到，区边在内壁内侧 0.2 m）
##     · 桌前贴墙（局部 z=−2.2，区 z 到 −2.4）→ 响
const MUSIC_INSET := 0.2
## 触发区高度（米，从地板起）。小屋墙面到 2.5 m 左右，取 **1.9** —— 故意**比屋顶低一截**：
## 站屋顶时胶囊中心 ≈ 3.65、底部 ≈ 2.60，高于区顶 1.9，不会误触发。
## 而站在屋里（胶囊中心 ≈ 1.05）完整落在 0~1.9 内。
## ⚠️ 不要用 CSG `Walls` 盒的 5.7 m：那个盒子比可见的墙高得多，用它连屋顶都算屋里。
const MUSIC_HEIGHT := 1.9
## 触发区节点名（自检按名字找）
const ZONE_NODE := "MusicZone"

## 屋里空间的水平范围（本节点空间），运行时量一次
var _inner := AABB()
var _music_inside := 0
var _music_area: Area3D


func _ready() -> void:
	_build_music_zone()


## 量小屋的内部空间。
##
## 用 CSG 的 `Walls` 盒（外框）减掉墙厚，而不是去扫 `Hut` 的合并网格 ——
## CSG 合并后的网格没有「一面墙一个节点」的结构，拿不到可靠的内壁。
## 小屋的墙就是 `Hut/Walls` 那个 6.6 × 5.7 × 5.6 的盒子（墙厚可以从
## `Walls` 与 `Cavity` 的尺寸差算出来）。
func _measure_inner() -> AABB:
	var walls := get_node_or_null("Hut/Walls") as CSGBox3D
	var cavity := get_node_or_null("Hut/Cavity") as CSGBox3D
	if walls == null:
		return AABB()
	var w := walls.size
	var c := cavity.size if cavity != null else Vector3(w.x - 0.4, w.y, w.z - 0.4)
	# 墙厚 = (外框 − 内腔) / 2，逐轴算；y 轴通常是通的（地板到天花板）
	var half := Vector3(maxf((w.x - c.x) * 0.5, 0.1), 0.0,
		maxf((w.z - c.z) * 0.5, 0.1))
	var inner_size := Vector3(w.x - half.x * 2.0, w.y, w.z - half.z * 2.0)
	# `Walls` 在自己的 transform 里抬到了 y 中心，这里换成「从地面起」
	var base_y := walls.position.y - w.y * 0.5
	return AABB(Vector3(walls.position.x - inner_size.x * 0.5, base_y,
			walls.position.z - inner_size.z * 0.5),
		inner_size)


func _build_music_zone() -> void:
	if get_node_or_null(ZONE_NODE) != null:
		return
	_inner = _measure_inner()
	if _inner.size == Vector3.ZERO:
		push_warning("[HutMusic] 量不到小屋内部尺寸（Hut/Walls 不在？），BGM 触发区不建")
		return

	var area := Area3D.new()
	area.name = ZONE_NODE
	area.collision_layer = 0          # 自己不被撞
	area.collision_mask = 1           # 只感应世界层（玩家在第 1 层）
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()

	# ── 四面等距内缩（0.2 m，理由见 `MUSIC_INSET` 那段三次投诉记录）──
	var x0 := _inner.position.x + MUSIC_INSET
	var x1 := _inner.end.x - MUSIC_INSET
	var z0 := _inner.position.z + MUSIC_INSET
	var z1 := _inner.end.z - MUSIC_INSET
	if x1 - x0 < 0.5 or z1 - z0 < 0.5:
		push_warning("[HutMusic] 内缩之后触发区太小（%.2f × %.2f），不建"
			% [x1 - x0, z1 - z0])
		return
	box.size = Vector3(x1 - x0, MUSIC_HEIGHT, z1 - z0)
	cs.shape = box
	# 中心取「内缩后区间」的中心；y 从地板往上量 MUSIC_HEIGHT 的一半
	# （不跟着 CSG 那个 5.7 m 盒走）
	cs.position = Vector3((x0 + x1) * 0.5,
		_inner.position.y + MUSIC_HEIGHT * 0.5, (z0 + z1) * 0.5)
	area.add_child(cs)
	add_child(area)
	# ⚠️ 用「计数」而不是布尔：玩家被瞬移时可能先 entered B 再 exited A，
	#    布尔量会在同一帧里被后到的 exited 抹掉（理由详见 `shop.gd`）。
	area.body_entered.connect(_on_music_body.bind(1))
	area.body_exited.connect(_on_music_body.bind(-1))
	_music_area = area
	print("[HutMusic] BGM 触发区：%.2f × %.2f × %.2f m（屋内 %.2f × %.2f × %.2f，每边内缩 %.2f）曲目 `%s`"
		% [box.size.x, box.size.y, box.size.z,
			_inner.size.x, _inner.size.y, _inner.size.z, MUSIC_INSET, MUSIC_TRACK])
	# ⚠️ `cs.position` 是本节点（小屋）**局部**空间，换算成世界再打印，
	#    否则看到的是「x -2.5~2.5」这种让人误解的数字（本喵第一版就这么错）。
	var wc: Vector3 = global_transform * cs.position
	var ws: Vector3 = global_transform.basis * box.size
	print("[HutMusic]   触发区世界范围 x %.2f~%.2f，y %.2f~%.2f，z %.2f~%.2f"
		% [wc.x - absf(ws.x) * 0.5, wc.x + absf(ws.x) * 0.5,
			wc.y - absf(ws.y) * 0.5, wc.y + absf(ws.y) * 0.5,
			wc.z - absf(ws.z) * 0.5, wc.z + absf(ws.z) * 0.5])


func _on_music_body(body: Node3D, delta: int) -> void:
	if not body.is_in_group("player"):
		return
	_music_inside = maxi(_music_inside + delta, 0)
	if _music_inside > 0:
		Music.play(MUSIC_TRACK)
	elif Music.current() == MUSIC_TRACK:
		# 只在「放的正好是自己这首」时才停 —— 免得别的房间共用同一台播放器时
		# 走到门口把人家的 BGM 掐掉
		Music.stop()


## 小屋被释放 / 换场景时别把 BGM 留在空气里飘。
func _exit_tree() -> void:
	if _music_inside > 0 and Music.current() == MUSIC_TRACK:
		Music.stop()
