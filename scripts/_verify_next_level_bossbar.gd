extends SceneTree
## 验收：**第二场景三只恐龙优香有没有血条**（用户 2026-11-11：「怎么没血条啊」）。
##
## 病因：血条建在 `hud.gd::bind_bosses()` 里，但**只有 `game.gd` 调过它**。
## `next_level.gd` 从来没调 → 第二场景的 `TrexBossA/B/C` 活着也没人建条。
##
## 本验收查：
##   ① 场上 `bosses` 组里有几只、是不是本场景的
##   ② `HUD` 下是否真的建出了 `BossBar0/1/2` 这些节点
##   ③ 条的 `visible` 与 `value/max_value` 是否跟着血量走
##   ④ 打掉一只血 → 对应条的 value 要降
##
## 用法：& <godot_console.exe> --headless --path . --script res://scripts/_verify_next_level_bossbar.gd -- --splat=off --no-capture

const NEXT_SCENE := "res://scenes/next_level.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("═══ 第二场景 · Boss 血条验收 ═══\n")

	var ps := load(NEXT_SCENE) as PackedScene
	_check(ps != null, "能加载 %s" % NEXT_SCENE)
	if ps == null:
		_summary()
		quit(1)
		return

	var level := ps.instantiate() as Node3D
	root.add_child(level)
	for _i in 200:
		await process_frame
	paused = false
	for _f in 40:
		await process_frame

	# ① bosses 组
	var mine: Array = []
	for node in get_nodes_in_group("bosses"):
		if level.is_ancestor_of(node):
			mine.append(node)
	print("   场上属于本场景的 Boss：%d 只（%s）"
		% [mine.size(), ", ".join(mine.map(func(b): return String(b.name)))])
	_check(mine.size() == 3, "① 三只恐龙优香都在 bosses 组里（实测 %d）" % mine.size())

	# ② HUD 下的 BossBar 节点
	var hud := level.get_node_or_null("HUD")
	_check(hud != null, "② 场景里有 HUD")
	if hud == null:
		_summary()
		quit(1)
		return
	var bars: Array = []
	for c in hud.get_children():
		if String(c.name).begins_with("BossBar"):
			bars.append(c)
	print("   HUD 下的 BossBar 节点：%d 个" % bars.size())
	_check(bars.size() == 3, "② 建出了 3 条血条（实测 %d）" % bars.size())

	# ③ 条的数量/可见性/血量比例
	var shown := 0
	for b in bars:
		var bar := b as ProgressBar
		if bar == null:
			continue
		if bar.visible:
			shown += 1
		print("     %-10s visible=%s  value=%.1f / max=%.1f"
			% [String(bar.name), str(bar.visible), bar.value, bar.max_value])
	_check(shown >= 1, "③ 至少有 1 条可见（实测 %d）" % shown)

	# ④ 打掉一只的血，对应条要跟着降
	if not mine.is_empty():
		var target: Node = mine[0]
		var before: float = -1.0
		for b in bars:
			var bar := b as ProgressBar
			if bar != null and bar.visible:
				before = bar.value
				break
		var hp0: float = float(target.get("health"))
		target.call("take_damage", hp0 * 0.5, Vector3.ZERO, Vector3.ZERO)
		for _f in 8:
			await process_frame
		var after: float = -1.0
		for b in bars:
			var bar := b as ProgressBar
			if bar != null and bar.visible:
				after = bar.value
				break
		print("   打掉半血：条 value %.1f → %.1f" % [before, after])
		_check(after < before, "④ 掉血后血条 value 下降（%.1f → %.1f）" % [before, after])

	_summary()
	quit(0 if _fail == 0 else 1)


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
		print("★ 全过：第二场景三只 Boss 都有血条，且跟着血量走")
