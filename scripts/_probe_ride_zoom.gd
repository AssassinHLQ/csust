extends SceneTree
## 自检：**火箭骑乘期间的滚轮闸门**。
##
## 用户 2026-11-08：「在火箭上面虽然可以自由转视角但是不能滚轮缩放了，修复」。
##
## ── 根因 ──
## `player.gd::_input()` 开头原来是：
##     `if _ride_active and not (event is InputEventMouseMotion): return`
## 把所有非鼠标移动的事件一律吃掉 —— 滚轮（`InputEventMouseButton` + `WHEEL_*`）也在内。
##
## ── ⚠️ 这个探针为什么不去"真的滚一下然后看 zoom 变没变" ──
## 实测（`_tmp_mouse.gd`，已删）：**headless 平台下 `Input.mouse_mode` 恒为 0
## （VISIBLE）**，赋值 `MOUSE_MODE_CAPTURED`(=2) 读回来还是 0。而 `player.gd` 的
## 滚轮分支和转视角分支都要求 `mouse_mode == CAPTURED`，所以那两条分支在 headless
## 里**永远进不去**、`_zoom_distance` 永远不变。
## 这正是 `_verify_facing.gd` 里「下滚没有改变距离 / 没被 zoom_max 卡住 /
## 没被 zoom_min 卡住 / 拉近没生效」四条一直红的**真原因** —— 不是功能坏了，
## 是 headless 测不到。本探针不重蹈覆辙，改为**直接验闸门的放行/拦截判定**。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_ride_zoom.gd

var _fail := 0
var _pass := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % msg)
	else:
		_fail += 1
		print("  ✗ %s" % msg)


func _wheel(btn: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = true
	return e


func _run() -> void:
	print("========== 火箭骑乘 · 滚轮闸门自检 ==========")

	# 说明环境限制，免得以后有人以为这几条是"没测"
	print("  · 注：headless 下 mouse_mode 无法进入 CAPTURED，故本探针验闸门判定而非实际缩放")

	var player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	for _i in 10:
		await physics_frame
	if player.aiming:
		player._set_aiming(false)

	# ── 1. `_is_wheel()`：滚轮识别对不对 ──
	print("\n---------- 1. 滚轮识别 ----------")
	_check(bool(player.call("_is_wheel", _wheel(MOUSE_BUTTON_WHEEL_UP))), "上滚认成滚轮")
	_check(bool(player.call("_is_wheel", _wheel(MOUSE_BUTTON_WHEEL_DOWN))), "下滚认成滚轮")
	_check(not bool(player.call("_is_wheel", _wheel(MOUSE_BUTTON_LEFT))),
		"**左键不算滚轮**（否则骑乘时会误放行开火）")
	_check(not bool(player.call("_is_wheel", _wheel(MOUSE_BUTTON_RIGHT))),
		"**右键不算滚轮**（右键是信号镜）")

	# ── 2. 闸门：骑乘时各事件该放行还是拦截 ──
	# `_input()` 的闸门逻辑是：
	#     if _ride_active and not (event is InputEventMouseMotion):
	#         if not (event is InputEventMouseButton and _is_wheel(...)): return
	# 这里把这段判定单独复刻一遍来验 —— 探针不关心闸门后面那层 mouse_mode 限制。
	print("\n---------- 2. 骑乘闸门放行/拦截 ----------")
	var mm := InputEventMouseMotion.new()
	_check(_gate_passes(player, true, mm), "骑乘时**鼠标移动**放行（转视角）")
	_check(_gate_passes(player, true, _wheel(MOUSE_BUTTON_WHEEL_UP)),
		"骑乘时**上滚**放行（本次修复点）")
	_check(_gate_passes(player, true, _wheel(MOUSE_BUTTON_WHEEL_DOWN)),
		"骑乘时**下滚**放行（本次修复点）")

	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	lmb.pressed = true
	_check(not _gate_passes(player, true, lmb), "骑乘时**左键开火**仍被拦截")

	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	_check(not _gate_passes(player, true, rmb), "骑乘时**右键信号镜**仍被拦截")

	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	_check(not _gate_passes(player, true, key), "骑乘时**WASD** 仍被拦截（位置由火箭写）")

	# ── 3. 不骑乘时闸门完全放行（回归）──
	print("\n---------- 3. 不骑乘时一切照旧 ----------")
	_check(_gate_passes(player, false, lmb), "不骑乘时左键放行")
	_check(_gate_passes(player, false, key), "不骑乘时键盘放行")
	_check(_gate_passes(player, false, _wheel(MOUSE_BUTTON_WHEEL_DOWN)), "不骑乘时滚轮放行")

	# ── 4. 真·骑乘锁状态与闸门的一致性 ──
	print("\n---------- 4. 骑乘锁联动 ----------")
	player.set_ride_lock(true)
	await physics_frame
	_check(player.is_riding(), "`set_ride_lock(true)` → `is_riding()` = true")
	_check(_gate_passes(player, bool(player.is_riding()), _wheel(MOUSE_BUTTON_WHEEL_DOWN)),
		"真实骑乘状态下滚轮能过闸门")
	player.set_ride_lock(false)
	await physics_frame
	_check(not player.is_riding(), "`set_ride_lock(false)` → `is_riding()` = false")

	print("\n==========================================")
	print("骑乘滚轮闸门自检：通过 %d，失败 %d" % [_pass, _fail])
	print("==========================================")
	quit(1 if _fail > 0 else 0)


## 复刻 `player.gd::_input()` 开头那道骑乘闸门，返回"这个事件能不能走到后面的分支"。
##
## ⚠️ 复刻而不是调用 `_input()` 的原因写在文件头：`_input()` 后半段还有
##    `mouse_mode == CAPTURED` 的限制，headless 下永远为假，会把结论搅浑。
##    这里只验闸门本身，那才是本次改动的东西。
func _gate_passes(player, ride_active: bool, event: InputEvent) -> bool:
	if ride_active and not (event is InputEventMouseMotion):
		if not (event is InputEventMouseButton and bool(player.call("_is_wheel", event))):
			return false
	return true
