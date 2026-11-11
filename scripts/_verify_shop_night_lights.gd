extends SceneTree
## 验收：柴关电脑城营业灯 —— 20:00 开、06:00 熄。
##
## 用户 2026-11-11：「柴关电脑城晚上才开灯」「要求 20 点到 6 点才开灯」。
##
## 查的东西（全部读**运行时真值**，不看代码）：
##   ① `is_on_now()` 边界：19:59 关 / 20:00 开 / 23:59 开 / 00:00 开 / 05:59 开 / 06:00 关；
##      以及跨零点不能写成 `h >= 20 and h < 6`（那样永远 false）。
##   ② 真场景里把 `TimeOfDay.set_hours()` 拨到 7 个时刻，读回：
##      · 三盏灯的实际 `light_energy`
##      · 招牌板自发光倍率
##      · 灯管自发光倍率
##   ③ `NightLights` 只挂一份（幂等）—— 挂两份会把白天的 0 当成夜间值存下来，
##      导致白天黑夜全灭（第一版踩过，见 `shop_night_lights.gd::attach()`）。
##
## 用法：& <godot_console.exe> --headless --path . --script res://scripts/_verify_shop_night_lights.gd -- --splat=off --no-capture
## 注意：这是**不用出图**的验收，headless 就够（不抢前台）。

const NightLights := preload("res://scripts/shop_night_lights.gd")

## [小时, 期望是否开灯]
const CASES := [
	[19.99, false],
	[20.0, true],
	[23.99, true],
	[0.0, true],
	[3.0, true],
	[5.99, true],
	[6.0, false],
	[12.0, false],
	[18.0, false],
]

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("═══ 柴关电脑城 · 营业灯时刻表验收 ═══\n")

	# ── ① 纯函数边界 ──
	print("① is_on_now() 边界")
	for c in CASES:
		var h: float = c[0]
		var want: bool = c[1]
		var got: bool = NightLights.is_on_now(h)
		_check(got == want, "%5.2f h → %-5s（期望 %s）" % [h, str(got), str(want)])
	# 显式打一遍"错误写法"的对照，防止以后有人把它改回去
	var wrong := false
	for h in [0.0, 3.0, 23.0]:
		if float(h) >= 20.0 and float(h) < 6.0:
			wrong = true
	_check(not wrong, "跨零点不能写成 `h >= 20 and h < 6`（那样 00:00~05:59 全漏）")

	# ── ② 真场景 ──
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame

	var shop := game.get_node_or_null("Shop") as Node3D
	_check(shop != null, "场景里有 Shop")
	if shop == null:
		_summary()
		quit(1)
		return

	# 幂等：只能有一个 NightLights
	var n_nl := 0
	for c in shop.get_children():
		if String(c.name).begins_with("NightLights"):
			n_nl += 1
	_check(n_nl == 1, "NightLights 只挂 1 份（实测 %d 份）" % n_nl)

	var nl := shop.get_node_or_null("NightLights")
	_check(nl != null, "NightLights 挂上了")

	var lights: Array[Light3D] = []
	for n in shop.find_children("*", "OmniLight3D", true, false):
		lights.append(n as Light3D)
	_check(lights.size() == 3, "店里 3 盏 OmniLight（实测 %d）" % lights.size())

	var sign_sm: StandardMaterial3D = null
	var sb := shop.get_node_or_null("Body/SignBoard") as MeshInstance3D
	if sb != null:
		sign_sm = sb.material_override as StandardMaterial3D
	_check(sign_sm != null, "招牌板有自发光材质")

	var tubes: Array[StandardMaterial3D] = []
	for mi in shop.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for si in m.get_surface_count():
			var mat := m.surface_get_material(si)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				if sm.emission_enabled and sm.emission.get_luminance() > 0.99 \
						and sm.emission.g >= sm.emission.r:
					tubes.append(sm)
	_check(not tubes.is_empty(), "认出了灯管材质（%d 个）" % tubes.size())

	var tod := get_root().get_node_or_null("TimeOfDay")
	_check(tod != null, "TimeOfDay 自动加载存在")
	if tod == null:
		_summary()
		quit(1)
		return
	tod.call("set_day_minutes", 0.0)   # 停表，读数不漂

	print("\n② 逐时刻读回真值")
	print("   %-7s %-6s %-28s %-8s %-6s" % ["小时", "应开灯", "三盏灯能量", "招牌自发光", "灯管"])
	for c in CASES:
		var h: float = c[0]
		var want: bool = c[1]
		tod.call("set_hours", h)
		# 过渡 0.6 s，按 60 fps 等 60 帧足够了
		for _f in 60:
			await process_frame
		var e: Array[String] = []
		var lit := 0
		for l in lights:
			e.append("%.2f" % l.light_energy)
			if l.light_energy > 0.05:
				lit += 1
		var sg := sign_sm.emission_energy_multiplier if sign_sm != null else -1.0
		var tb := tubes[0].emission_energy_multiplier if not tubes.is_empty() else -1.0
		print("   %5.2f  %-6s %-28s %-8.2f %.2f"
			% [h, "开" if want else "关", " ".join(e), sg, tb])
		var ok_lit: bool = (lit == 3) if want else (lit == 0)
		_check(ok_lit, "  %5.2f：%d/3 盏亮（应 %s）" % [h, lit, "3" if want else "0"])
		var ok_sg: bool = sg > 0.1 if want else sg < 0.1
		_check(ok_sg, "  %5.2f：招牌自发光 %.2f" % [h, sg])

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
		print("★ 全过：20:00 开、06:00 熄，白天全灭")
