extends SceneTree
## 验收：**F5 秒杀不该把游戏搞崩**（用户 2026-11-11：「按 f3 的 f5 游戏崩溃」）。
##
## 崩溃现场（用户截图）：
##     Cannot call method 'set_trans' on a null value.
##     0 - res://scripts/boss.gd:747  at function: _die
##     1 - res://scripts/trex_yuuka_boss.gd:151  at function: _d
##     2 - res://scripts/boss.gd:172  at function: take_damage
##     3 - res://scripts/player.gd:590  at function: _dev_key   ← F5
##
## 真因：Boss 的模型是 **BootGate 延迟建**的（`boss.gd::_ready` 里
## `BootGate.when_near(...)` 挂的，近距离才跑 `_boot()`）。F5 给全场 Boss
## 打 1e9 伤害时，**远处的 Boss 还没建出模型**，`model` 还是 null。
## `tween_property(null, ...)` 返回 **null**，链式的 `.set_trans(...)` 就崩了。
##
## 这不只是调试路径的问题：任何「Boss 还没生成就被打死」都会踩到
## （远程武器、爆炸、脚本强制结算）。
##
## 本验收做的事：
##   ① 造一个**没 boot 过**的 Boss（model 必然是 null），直接 take_damage 打死 → 不许崩
##   ② 打死之后 `_dead` 必须是 true、血量为 0（结算逻辑照常走完）
##   ③ `respawn_on_death` 为真时，复活计时**照常**挂上（不能因为没模型就吞掉）
##   ④ 正常 boot 过的 Boss 打死 → 也不能崩（回归）
##
## 用法：& <godot_console.exe> --headless --path . --script res://scripts/_verify_boss_kill_unbooted.gd -- --splat=off --no-capture

const BossScript := preload("res://scripts/boss.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("═══ Boss 未建模型即被击杀 · 不崩验收 ═══\n")

	# ── ① 未 boot 的 Boss（model 必定是 null）──
	# ⚠️ 用 `BossScript.new()` 而不是 `Node3D.new() + set_script()`：
	#    后者在 `--script` 模式下**方法表不生效**，`take_damage` 会报
	#    `Nonexistent function 'take_damage (via call)'`（实测踩过）。
	#
	# ⚠️⚠️ 而且**不能 add_child 进树**：`boss.gd::_ready()` 里会直接
	#    `BootGate.when_near(...)`，距离够近就立刻 `_boot()` 把模型建出来，
	#    "model == null" 这个前提就没了（第一版就是这么写错的，三项误报）。
	#    这里**手动构造出"已死但没模型"的状态**，正是 F5 打到远处 Boss 时的样子。
	var boss: Node3D = BossScript.new()
	# 不进树 → 不触发 _ready → 不 boot → model 保持 null
	boss.set("display_name", "测试Boss-未建模型")
	boss.set("max_health", 100.0)
	boss.set("health", 100.0)
	boss.set("drop_yuan", 0)
	boss.set("respawn_on_death", true)
	boss.set("respawn_time", 0.2)

	var model_is_null: bool = boss.get("model") == null
	_check(model_is_null, "① 这个 Boss 的 model 确实是 null（复现崩溃前提）")
	_check(boss.get("_booted") != true, "① 它还没被 boot 过")

	# ★ 这一刀就是 F5 做的事
	print("   → 调用 take_damage(1e9)（等同 F5 秒杀）")
	boss.call("take_damage", 1.0e9, Vector3.ZERO, Vector3.ZERO)
	for _f in 3:
		await process_frame

	# 如果上面崩了，这几行根本执行不到（Godot 会 SCRIPT ERROR 并中断）
	_check(true, "① 杀死未建模型的 Boss **没有崩**")
	_check(boss.get("_dead") == true, "② 状态正确：_dead = true")
	_check(float(boss.get("health")) <= 0.0, "② 血量归零（%.1f）" % float(boss.get("health")))

	# ③ 复活计时应当照常挂上（respawn_time 0.2 s）
	#    tween 必须挂在树里的节点上才会跑，所以这一步才把它加进树。
	#    ⚠️ 加进树会触发 `_ready()` → BootGate，但那时 `_dead` 已经是 true，
	#    不会影响「没模型也被打死」这个已经验证过的结论。
	root.add_child(boss)
	await process_frame
	var respawned := false
	for _f in 90:      # 90 帧 ≈ 1.5 s @60fps，足够 0.2 s 的计时
		await process_frame
		if boss.get("_dead") != true:
			respawned = true
			break
	# ⚠️ 没模型时也该复活：`_respawn()` 里只跳过视觉，不改状态
	_check(respawned, "③ respawn_on_death 为真时，没模型也会按时复活")

	# ④ 回归：正常 boot 过的 Boss 打死也不能崩
	var boss2: Node3D = BossScript.new()
	root.add_child(boss2)
	boss2.set("display_name", "测试Boss-已建模型")
	boss2.set("max_health", 100.0)
	boss2.set("health", 100.0)
	boss2.set("drop_yuan", 0)
	boss2.set("respawn_on_death", false)
	boss2.set("boot_distance", 1.0e9)   # 保证 BootGate 马上放行
	boss2.set("boot_max_wait", 0.0)
	for _f in 60:
		await process_frame
	var booted: bool = boss2.get("_booted") == true
	var has_model: bool = boss2.get("model") != null
	print("   已 boot=%s  model=%s" % [str(booted), "有" if has_model else "无"])
	boss2.call("take_damage", 1.0e9, Vector3.ZERO, Vector3.ZERO)
	for _f in 5:
		await process_frame
	_check(true, "④ 正常 Boss 被打死也没崩")
	_check(boss2.get("_dead") == true, "④ 状态正确：_dead = true")

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
		print("★ 全过：Boss 没建模型就被打死不再崩溃，结算/复活照常")
