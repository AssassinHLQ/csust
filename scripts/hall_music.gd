extends Node3D
## next 关卡「蒙德里安门厅」的 BGM（用户 2026-11-12）。
##
## 素材：「碧蓝档案OST Vol.1（320K）」P5「Midsummer Cat」—— 和 `game.tscn` 里
## 那栋蒙德里安大楼是**同一首**，所以直接复用同一个 `mondrian_theme.ogg`，
## 曲目表里也是同一条 `mondrian`（见 `scripts/music.gd`）。
##
## 用户原话：「next 关卡的蒙德里安建筑是这个音乐，直接就可以循环」——
## 音频那边不用再处理（上一轮已经把「Midsummer Cat」的头尾静音切掉、
## 循环接缝做到 ×0.050 了），这里只管「进屋开、出门停」。
##
## ── 挂在哪 ──
## `scenes/mondrian_hall.tscn` 的根节点（`MondrianHall`）。那个场景的根节点
## 本来**没有脚本**（`scripts/mondrian_hall.gd` 是给程序化构建的另一份），
## 所以照小屋的套路新建这一个，专门管音乐。
##
## ── 范围怎么定 ──
## 这栋楼是三层（一层地板 y≈0.5、二层楼板 y≈4.8、三层楼板 y≈9.2），
## 三层楼板的水平范围还不一样（F1 x −11.75~5.75，F3 又偏到 −7.90~9.90）。
## 所以**运行时扫 `Interior` 里名字带 `F1_Floor`/`F2_`/`F3_` 的楼板盒**，
## 取它们并集当「玩家能走到的地方」，再内缩 `MUSIC_INSET`。
## 这样以后改楼层/改楼梯，音乐范围自动跟上，不会漂。
##
## ⚠️ 用户 2026-11-12 在小屋那边要求过「要进门才行，别站边上就响」，
##    所以这里同样是**往内缩**、不是外扩。

## 曲目名（`scripts/music.gd`）
const MUSIC_TRACK := "mondrian"
## 比楼板并集再**内缩**多少米（每边）
const MUSIC_INSET := 0.8
## 触发区顶部再往上留多少（米）。三层楼板顶 9.20，留 1.6 覆盖站上三楼的高度。
const MUSIC_TOP_PAD := 1.6
## 触发区节点名（自检按名字找）
const MUSIC_ZONE := "MusicZone"
## 算楼板并集时认的节点名前缀
const FLOOR_PREFIXES := ["F1_Floor", "F2_", "F3_"]

var _music_inside := 0


func _ready() -> void:
	_build_music_zone()


## 扫楼板盒，返回它们的世界并集 AABB；扫不到返回空 AABB。
func _floor_union() -> AABB:
	var inner := get_node_or_null("Interior") as Node3D
	if inner == null:
		return AABB()
	var out := AABB()
	var seen := false
	for prefix in FLOOR_PREFIXES:
		for child in inner.find_children(prefix + "*", "CollisionShape3D", true, false):
			var cs := child as CollisionShape3D
			if cs == null or not (cs.shape is BoxShape3D):
				continue
			var b := cs.shape as BoxShape3D
			var a: AABB = cs.global_transform * AABB(-b.size * 0.5, b.size)
			out = a if not seen else out.merge(a)
			seen = true
	return out


func _build_music_zone() -> void:
	if get_node_or_null(MUSIC_ZONE) != null:
		return
	var floors := _floor_union()
	if floors.size == Vector3.ZERO:
		push_warning("[HallMusic] 扫不到楼板盒（Interior/F1_F2_F3_*），BGM 触发区不建")
		return

	# 并集换成「本节点空间」再内缩
	var inv := global_transform.affine_inverse()
	var c_local: Vector3 = inv * floors.get_center()
	var size_x := floors.size.x - MUSIC_INSET * 2.0
	var size_z := floors.size.z - MUSIC_INSET * 2.0
	if size_x <= 0.5 or size_z <= 0.5:
		push_warning("[HallMusic] 楼板并集太小（%.2f × %.2f），BGM 触发区不建" % [size_x, size_z])
		return
	# 底部比最低楼板再低一点（一楼地板在 0.45，玩家脚底就在那），顶部到三楼 + 余量
	var y_bottom := floors.position.y - 0.20
	var y_top := floors.end.y + MUSIC_TOP_PAD
	var height := y_top - y_bottom
	var y_center_world := (y_bottom + y_top) * 0.5

	var area := Area3D.new()
	area.name = MUSIC_ZONE
	area.collision_layer = 0          # 自己不被撞
	area.collision_mask = 1           # 只感应世界层（玩家在第 1 层）
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size_x, height, size_z)
	cs.shape = box
	cs.position = Vector3(c_local.x, y_center_world, c_local.z)
	area.add_child(cs)
	add_child(area)
	# ⚠️ 用「计数」而不是布尔：玩家被瞬移时可能先 entered B 再 exited A，
	#    布尔量会在同一帧里被后到的 exited 抹掉（理由详见 `shop.gd`）。
	area.body_entered.connect(_on_music_body.bind(1))
	area.body_exited.connect(_on_music_body.bind(-1))
	print("[HallMusic] BGM 触发区：%.2f × %.2f × %.2f m，中心 (%.2f, %.2f, %.2f)（曲目 `%s`）"
		% [box.size.x, box.size.y, box.size.z,
			cs.position.x, cs.position.y, cs.position.z, MUSIC_TRACK])
	print("[HallMusic]   楼板并集 x %.2f~%.2f, y %.2f~%.2f, z %.2f~%.2f（每边内缩 %.1f）"
		% [floors.position.x, floors.end.x, floors.position.y, floors.end.y,
			floors.position.z, floors.end.z, MUSIC_INSET])


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


## 场景被释放 / 换关卡时别把 BGM 留在空气里飘。
func _exit_tree() -> void:
	if _music_inside > 0 and Music.current() == MUSIC_TRACK:
		Music.stop()
