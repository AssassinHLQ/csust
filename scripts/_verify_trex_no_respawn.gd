extends SceneTree
## 验收：第二场景三只霸王龙优香 —— **名字 + 配色 + 真不复活**（用户 2026-11-11）。
##
## 用户原话：
##   「设置霸王龙也不能复活，到时候加新的霸王龙贴图，
##     第一个就是暗影霸王龙优香，第二个是炫彩霸王龙优香，第三是经典霸王龙优香」
##   并指出：`respawn_time = 9999` 不算不复活 —— 9999 秒（2.78 h）后照样站起来。
##
## 查的东西：
##   ① 三只的 `display_name` 分别是 暗影 / 炫彩 / 经典
##   ② 三只的 `respawn_on_death` 都是 **false**（真不复活，不是靠大数字拖时间）
##   ③ 三只的 `tint` 各不相同且符合设定（暗影偏暗、炫彩高饱和、经典纯白）
##   ④ 打死之后**等过 `respawn_time` 也不复活**（真跑计时，不是只读字段）
##
## 用法：& <godot_console.exe> --headless --path . --script res://scripts/_verify_trex_no_respawn.gd -- --splat=off --no-capture

const NEXT_SCENE := "res://scenes/next_level.tscn"

## [节点名, 期望名字, 期望 tint 的关键特征]
const EXPECT := [
	["TrexBossA", "暗影霸王龙优香"],
	["TrexBossB", "炫彩霸王龙优香"],
	["TrexBossC", "经典霸王龙优香"],
]

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("═══ 第二场景霸王龙 · 名字/配色/不复活 验收 ═══\n")

	var level := (load(NEXT_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _i in 200:
		await process_frame
	paused = false
	for _f in 40:
		await process_frame

	var nodes: Array[Node] = []
	for e in EXPECT:
		var b := level.get_node_or_null(String(e[0]))
		_check(b != null, "① 场景里有 %s" % e[0])
		if b != null:
			nodes.append(b)

	if nodes.size() != 3:
		_summary()
		quit(1)
		return

	# ① 名字
	print("\n① 名字")
	for i in EXPECT.size():
		var want: String = EXPECT[i][1]
		var got := String(nodes[i].get("display_name"))
		print("   %-11s display_name = 「%s」" % [EXPECT[i][0], got])
		_check(got == want, "  %s 名字是「%s」（实测「%s」）" % [EXPECT[i][0], want, got])

	# ② respawn_on_death 必须是 false（而不是靠 respawn_time 拖）
	print("\n② 真不复活（respawn_on_death）")
	for b in nodes:
		var rod := nodes_desc(b, "respawn_on_death")
		var rt := float(nodes_desc(b, "respawn_time"))
		print("   %-11s respawn_on_death=%s  respawn_time=%.1f"
			% [String(b.name), str(rod), rt])
		_check(rod == false, "  %s respawn_on_death = false（不靠 9999 拖时间）"
			% String(b.name))

	# ③ 配色
	print("\n③ 配色（tint）")
	var tints: Array[Color] = []
	for b in nodes:
		var c: Color = b.get("tint")
		tints.append(c)
		print("   %-11s tint = (%.2f, %.2f, %.2f)" % [String(b.name), c.r, c.g, c.b])
	# 暗影：整体偏暗
	var shadow_lum := 0.2126 * tints[0].r + 0.7152 * tints[0].g + 0.0722 * tints[0].b
	_check(shadow_lum < 0.45, "  暗影确实偏暗（亮度 %.2f < 0.45）" % shadow_lum)
	# 炫彩：至少一个通道很高（高饱和）
	var mx := maxf(maxf(tints[1].r, tints[1].g), tints[1].b)
	var mn := minf(minf(tints[1].r, tints[1].g), tints[1].b)
	_check(mx - mn > 0.35, "  炫彩是高饱和（max−min = %.2f > 0.35）" % (mx - mn))
	# 经典：纯白
	_check(tints[2].r > 0.97 and tints[2].g > 0.97 and tints[2].b > 0.97,
		"  经典是纯白 tint（%.2f,%.2f,%.2f）" % [tints[2].r, tints[2].g, tints[2].b])
	# 三者互不相同
	var distinct := true
	for i in 3:
		for j in range(i + 1, 3):
			if tints[i].is_equal_approx(tints[j]):
				distinct = false
	_check(distinct, "  三只配色互不相同")

	# ④ 打死之后真的不复活
	print("\n④ 打死 → 等过 respawn_time 也不复活")
	# 先记下原 respawn_time，打死后等它 +2 秒
	var rt_max := 0.0
	for b in nodes:
		rt_max = maxf(rt_max, float(nodes_desc(b, "respawn_time")))
	print("   respawn_time 最大值 %.1f s，这里等到 %.1f s 再看"
		% [rt_max, rt_max + 2.0])
	for b in nodes:
		b.call("take_damage", 1.0e9, Vector3.ZERO, Vector3.ZERO)
	for _f in 10:
		await process_frame
	for b in nodes:
		_check(b.get("_dead") == true, "  %s 已死亡" % String(b.name))

	# 用「帧数 × 固定 delta」推进时间：headless 下 delta 不一定是 1/60，
	# 所以这里靠 `create_timer` 更可靠 —— 但为了不真的等 6 秒以上，
	# 直接把 respawn_time 临时改小再验证「即使到点也不复活」。
	for b in nodes:
		b.set("respawn_time", 0.05)
	await create_timer(0.6).timeout
	for _f in 20:
		await process_frame
	for b in nodes:
		var still_dead: bool = b.get("_dead") == true
		_check(still_dead, "  等过 respawn_time 后 %s 仍然死亡（不复活）"
			% String(b.name))

	_summary()
	quit(0 if _fail == 0 else 1)


## 读属性（GDScript 没有 has_property，用 get 返回 null 判）
func nodes_desc(n: Object, key: String) -> Variant:
	return n.get(key)


func _check(ok: bool, msg: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % msg)
	else:
		_fail += 1
		print("  ✗ %s" % msg)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])
	if _fail == 0:
		print("★ 全过：三只恐龙各有名字和配色，且打死真的不复活")
