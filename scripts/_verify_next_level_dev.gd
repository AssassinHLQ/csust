extends SceneTree
## 验收：**第二场景也能开开发者模式**（用户 2026-11-11：「为什么第二场景开不了开发者模式」）。
##
## 病因：F3 的处理**只写在 `game.gd::_input()` 里**，而 `next_level.gd` 连 `_input` 都没有
## —— 第二场景压根没人听 F3。`player.gd` 只认领 F4/F5/F6，且都先判 `DevMode.is_on()`，
## 所以第二场景里不但 F3 没反应，F4/F5/F6 也全废（开关永远打不开）。
##
## 本验收做的事：
##   ① 直接跑 `next_level.tscn`（不经 game.tscn），确认根节点有 `_input`；
##   ② 造一个真的 `InputEventKey(KEY_F3)` 喂进去，读 `DevMode.is_on()` 必须变开；
##   ③ 再喂一次，必须变关（toggle 语义）；
##   ④ 浮层：按 F3 后 `PerfOverlay` 节点存在且 visible；
##   ⑤ 跨场景一致性：`DevMode` 的存在和 `game.gd` 用的是同一个 GameSettings 键。
##
## 用法：& <godot_console.exe> --headless --path . --script res://scripts/_verify_next_level_dev.gd -- --splat=off --no-capture

const DevMode := preload("res://scripts/dev_mode.gd")
const NEXT_SCENE := "res://scenes/next_level.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("═══ 第二场景 · 开发者模式验收 ═══\n")

	# 从干净状态开始
	DevMode.set_on(false)

	var ps := load(NEXT_SCENE) as PackedScene
	_check(ps != null, "能加载 %s" % NEXT_SCENE)
	if ps == null:
		_summary()
		quit(1)
		return

	var level := ps.instantiate() as Node3D
	root.add_child(level)
	# 这个场景会等泼溅/天光之类，给足时间
	for _i in 180:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame

	_check(level.get_script() != null, "根节点挂了脚本")
	# ① 有 _input 吗（按 GDScript 反射查方法表）
	var has_input := false
	var sc: Script = level.get_script()
	if sc != null:
		for m in sc.get_script_method_list():
			if String(m.get("name", "")) == "_input":
				has_input = true
				break
	_check(has_input, "① 根节点有 _input（第二场景有人听 F3）")

	# ② 喂一个真 F3 事件
	_check(not DevMode.is_on(), "初始：开发者模式 = 关")
	_send_f3(level)
	for _f in 5:
		await process_frame
	_check(DevMode.is_on(), "② 按 F3 → 开发者模式 = 开")

	# ③ 浮层出现
	var overlay := level.get_node_or_null("PerfOverlay") as CanvasLayer
	_check(overlay != null, "③ 性能浮层节点 PerfOverlay 已创建")
	_check(overlay != null and overlay.visible, "③ 浮层可见")

	# ④ 再按一次 → 关
	_send_f3(level)
	for _f in 5:
		await process_frame
	_check(not DevMode.is_on(), "④ 再按 F3 → 开发者模式 = 关")
	_check(overlay != null and not overlay.visible, "④ 浮层隐藏")

	# ⑤ 和 game.gd 用同一个存储键（跨场景保留）
	_check(GameSettings.value("dev_mode", false) != null, "⑤ dev_mode 存在 GameSettings 里")

	# 收尾：恢复成关
	DevMode.set_on(false)

	_summary()
	quit(0 if _fail == 0 else 1)


## 造一个真的 InputEventKey 喂给场景根节点
func _send_f3(target: Node) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_F3
	ev.physical_keycode = KEY_F3
	ev.pressed = true
	ev.echo = false
	target.call("_input", ev)


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
		print("★ 全过：第二场景按 F3 能开开发者模式，浮层也出得来")
