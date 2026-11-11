extends SceneTree
## 验：**跨场景记忆**（2026-11-11）。
##
## 用户：「切换场景会重置 9950X3D」+「火箭飞回来怎么飞不回去了」。
## 定的口径：「记住，当且仅当重开游戏。全量重置除了高斯泼溅缓存以外的」。
##
## 所以这里验三件事：
##   ① 捡走一颗之后，**重新实例化**一份 `room609_cpus.tscn`（等价于换场景回来），
##      那一颗必须不在；没捡的必须都在。
##   ② `wipe()`（等价于重开游戏）之后，整批 149 颗全部回来。
##   ③ 跑酷通关过的记忆跨实例有效：新实例化一份 `parkour.tscn`，
##      跑道口那枚火箭 / 传送门应当**直接就在**。
##
## 用 `RunMemory` 而不是真的走两次 `change_scene_to_file()`：那样要跑整个关卡
## 十几分钟，而且真正要证明的只是「state 活在 static 里、且 `_ready()` 会去读它」。
##
## 用法：
##   bash _tools/run_probe.sh res://scripts/_verify_run_memory.gd -- --splat=off

const RunMemory := preload("res://scripts/run_memory.gd")
const CPUS_SCENE := "res://scenes/room609_cpus.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


## 数一份 `room609_cpus` 实例里**还活着**的 CPU（`queue_free()` 过的会在下一帧消失，
## 所以每次数之前都等两帧）
func _alive(root_node: Node) -> Array:
	var out: Array = []
	for c in root_node.get_children():
		if c.has_method("price") and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _fresh() -> Node3D:
	var n := (load(CPUS_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(n)
	return n


func _run() -> void:
	print("========== 跨场景记忆（RunMemory）==========")
	RunMemory.wipe()

	# ── ① 捡一颗 → 换场景回来还在不在 ──
	print("\n── ① 捡走一颗，再「换场景回来」──")
	var a := _fresh()
	for _i in 4:
		await process_frame
	var al := _alive(a)
	print("  第一次进 609：%d 颗" % al.size())
	_check(al.size() == 149, "第一次进 609 是满的 149 颗（实际 %d）" % al.size())
	if al.is_empty():
		quit(1)
		return

	var victim := al[0] as Node3D
	var key := RunMemory.cpu_key(victim)
	print("  收走 %s（key = %s）" % [victim.name, key])
	# 直接调 `_take()`：它才是「登记 + 发钱 + queue_free」那条完整路径。
	# （真按 F 也要走这里，只是中间多一层提示/输入判定，和本自检无关。）
	victim.call("_take")
	for _i in 4:
		await process_frame
	_check(RunMemory.cpu_taken(key), "RunMemory 记下了这一颗")

	# 换场景 = 旧场景整棵释放 + 新的一份实例化
	a.queue_free()
	for _i in 4:
		await process_frame
	var b := _fresh()
	for _i in 4:
		await process_frame
	var bl := _alive(b)
	print("  换场景回来：%d 颗（期望 148）" % bl.size())
	_check(bl.size() == 148, "换场景之后**少一颗**（实际 %d）" % bl.size())
	var still := 0
	for c in bl:
		if RunMemory.cpu_key(c as Node3D) == key:
			still += 1
	_check(still == 0, "被收走的那颗**没有再出现**（同坐标 %d 颗）" % still)

	# 再捡一颗，同样要跨场景生效
	var victim2 := bl[0] as Node3D
	var key2 := RunMemory.cpu_key(victim2)
	victim2.call("_take")
	for _i in 4:
		await process_frame
	b.queue_free()
	for _i in 4:
		await process_frame
	var c := _fresh()
	for _i in 4:
		await process_frame
	print("  连捡两颗后再换场景：%d 颗（期望 147）" % _alive(c).size())
	_check(_alive(c).size() == 147, "连捡两颗后是 147 颗（实际 %d）" % _alive(c).size())
	c.queue_free()
	for _i in 4:
		await process_frame

	# ── ② 重开游戏 = wipe() → 全部回来 ──
	print("\n── ② 重开游戏（wipe）──")
	RunMemory.wipe()
	var d := _fresh()
	for _i in 4:
		await process_frame
	print("  wipe 之后：%d 颗（期望 149）" % _alive(d).size())
	_check(_alive(d).size() == 149, "重开游戏后整批**全部回来**（实际 %d）" % _alive(d).size())
	_check(not RunMemory.cpu_taken(key) and not RunMemory.cpu_taken(key2),
		"两颗的登记都被清掉了")
	d.queue_free()
	for _i in 4:
		await process_frame

	# ── ③ 通关记忆跨场景：航道口那枚火箭 + 传送门 ──
	print("\n── ③ 「通关过」跨场景 ──")
	RunMemory.wipe()
	_check(not RunMemory.parkour_done(), "刚开始「没通关过」")
	RunMemory.set_parkour_done(true)
	_check(RunMemory.parkour_done(), "记成通关过了")

	var pk := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(pk)
	for _i in 12:
		await process_frame
	print("  新实例化的跑酷场景：_home_rocket_revealed = %s，FinishPortal 在 %s" % [
		str(pk.get("_home_rocket_revealed")),
		"有" if pk.get("_finish_portal") != null else "无"])
	# ⚠️ 跑酷场景实例化在根上时，`Launch` 这些锚点是它自己的子节点，正常。
	_check(bool(pk.get("_home_rocket_revealed")),
		"换场景回来跑道口那枚火箭**直接就是亮的**")
	_check(pk.get("_finish_portal") != null, "传送门**直接就在**（不用再跑一遍）")

	var fut := pk.get_node_or_null("Futures")
	print("  Futures 在%s（上箭提示靠它显示）" % ("，有" if fut != null else "无"))
	if fut != null:
		var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Node3D
		player.add_to_group("player")
		root.add_child(player)
		# 先把玩家弄远，免得刚 add 就站进门里（下面解释为什么）
		player.global_position = Vector3(0.0, 5.0, 0.0)
		pk.set("_player", player)
		for _i in 4:
			await process_frame

		var home: Vector3 = pk.call("_home_spot")
		# ⚠️ 不要把人放在 `home` 正上方：那一格就是 `FinishPortal` 的门框里，
		#    `body_entered` 会**立刻**把这一趟发走（实测日志：「传送门 → 坐火箭去结算屋」
		#    直接打出来了，然后 `_riding = true`，F 提示当然挂不上）。
		#    要验的是「回程落地之后门不会再响」那一半 —— 人就在门**旁边**，
		#    这才是玩家真实的处境（回程落点 `return_target` 离 home 约 4.9 m）。
		player.global_position = home + Vector3(3.0, 1.0, 0.0)
		for _i in 6:
			await process_frame
		var owner: Variant = fut.call("prompt_owner")
		print("  站到火箭旁边 %s（离停机位 %.1f m）：提示 owner = %s" % [
			str(player.global_position.snappedf(0.1)),
			player.global_position.distance_to(home), str(owner)])
		_check(owner == pk, "站在火箭脚下会挂出「按 F 上箭」提示")

		# 按下 F：应当真的起飞（`_riding` 变 true）
		var ev := InputEventKey.new()
		ev.keycode = KEY_F
		ev.physical_keycode = KEY_F
		ev.pressed = true
		Input.parse_input_event(ev)
		for _i in 8:
			await process_frame
		print("  按 F 之后：_riding = %s" % str(pk.get("_riding")))
		_check(bool(pk.get("_riding")), "按 F 真的上了火箭（`_riding` = true）")

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 跨场景记忆正常" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)
