class_name ShopNightLights
extends Node
## 柴关电脑城的**营业灯**：20:00 开、06:00 熄。
##
## 用户 2026-11-11：「柴关电脑城晚上才开灯」「要求 20 点到 6 点才开灯」。
##
## ── 为什么不在 `shop.gd::_build_lights()` 里判断一次 ──
## 那个函数只在**建店**（`build()`）时跑一次。灯一旦定死，白天再走回来还是亮的。
## 所以这里挂一个每帧的节点，跟着 `TimeOfDay.hours` 走。
##
## ── 关灯时关的是什么 ──
##   ① `ShopLightW` / `ShopLightE`：店里两盏主灯（`shop_baked.tscn`，2.2 / range 25.15）；
##   ② `SignLight`：门头招牌灯（1.1 / range 6.0）；
##   ③ 招牌板 `Body/SignBoard` 的**自发光**（那圈蓝色灯箱）——
##      夜里整块牌子应该像灯箱一样发亮，白天不该。
##   ④ **灯管**（日光灯管）的那个材质：它在 `Shell` 里由 `shop.gd::_fix_glb_materials()`
##      把 GLB 里**所有** `StandardMaterial3D.emission_enabled` 都打开（见那里的注释），
##      所以运行时按"e > 0.99 且 g/b ≥ r"认出它 —— GLB 灯带是 (1, 0.98, 0.94)，
##      店里其它自发光都带明显色相（招牌蓝 (0.45,0.78,1)、展柜 (0.55,0.85,1)、
##      屏幕 (0.35,0.72,0.95)），只有灯带是近白的。
##      ⚠️ 只认**灯管**，不认墙：GLB 里墙的材质本来也就是白的，
##        但 `_fix_glb_materials()` 已经把墙的自发光**关掉**了，所以它们不会进来。
##
## ── 为什么用 0 而不是 `visible = false` / `light_enabled` ──
## 关掉 `Light3D` 节点会让 Godot 重排灯光列表；能量置 0 是纯 uniform 更新，
## 每帧全量刷一遍也不值一提（只有几盏）。而且从 0 回升不会出现"闪一下"。

## 开灯时段（小时，左闭右开）。20:00 → 次日 06:00，跨零点，所以判断要分两段。
const ON_HOUR_FROM := 20
const ON_HOUR_TO := 6

## 灯能量的**白天值**。不开灯 ≠ 完全无光：白天店里还得能看清东西，
## 环境光（`ambient_light_source = 3` 走天空）已经给了基本照度，
## 这里留一点暖光当"漫射"，不然柜台底下会死黑。
## 想改成"白天彻底不亮"就把这两个改成 0.0。
##
## ⚠️ 实测（`_probe_shop_light_budget.gd`，机位都出过图）：
##    · 12:00 白天**过曝 50.89%**，21:00 夜里只有 2.05% —— 白天是真的炸。
##    · 把三盏灯全关（12:00）画面**一点没变**（还是 50.89%）⇒ 白天的过曝**不是灯**。
##      根因是 `ambient_light_source = 3`（走天空）+ 店里的白墙白地台 + 屋顶玻璃；
##      `time_of_day.gd::KEY_AMBIENT` 在太阳高时给 0.73~0.75。
##    · 21:00 关灯 191.4 → 170.9 ⇒ 夜里灯确实在起作用（差 20 点）。
##    ⇒ 所以这个控制器负责的是"夜里点灯"，白天的过曝是**另一件事**
##      （`game.tscn` 的 Env_arena / 店里的白材质），这里管不到，也不该假装管到了。
const DAY_INDOOR_ENERGY := 0.0
const DAY_SIGN_ENERGY := 0.0
## 自发光（招牌灯箱 + 灯管）白天的倍率
const DAY_EMISSION_MULT := 0.0

## 过渡时长（秒）。0 = 瞬间开关。
## 20:00 到点"啪"一下全亮其实挺有感觉的，但如果是慢慢天黑，瞬间跳变会显得断。
## 给 0.6 s 的软过渡，两头都不难看。
const FADE_TIME := 0.6

var _lights: Array[Light3D] = []
var _night_energy: Array[float] = []
var _emissions: Array[StandardMaterial3D] = []
var _emission_night: Array[float] = []
var _collected := false
var _k := 0.0                 # 0 = 白天，1 = 夜里
var _applied_key := -1        # -1 = 还没应用过；否则是 `round(_k*100)`


## 挂到商店根节点上。商店可能在 `game.tscn` 之前就建好，所以等一帧再摸子节点。
##
## ⚠️ 这里**不用** `ShopNightLights.new()` —— `class_name` 是靠全局类名表解析的，
##    `--script` 探针模式下那张表还没建好，会编译报 `Identifier not found: ShopNightLights`。
##    走 `new()` 拿脚本自己，永远可用。
##
## ⚠️⚠️ **幂等**：`shop.gd` 有两条建店路径（`_wire_baked()` / `build()`），
##    探针重烘时可能两条都走一遍，实测 `attach()` 被调了**两次**。
##    第二个实例会把第一个**已经改好的**（白天=0）能量当成"夜间值"存下来，
##    于是 `DAWN=0` 变成"夜间值 0" → 白天黑夜全灭。
##    所以：已经有 `NightLights` 就直接返回它，绝不再挂第二个。
static func attach(shop: Node) -> Node:
	var existing := shop.get_node_or_null("NightLights")
	if existing != null:
		return existing
	var n: Node = new()
	n.name = "NightLights"
	shop.add_child(n)
	return n


func _ready() -> void:
	# 灯光/材质要等烘焙节点都在树上
	await get_tree().process_frame
	_collect()
	# ⚠️ `_collect()` 里 `process_mode` 默认是 INHERIT，而商店在**暂停**的探针里
	#    也会被建出来 —— 那时 `_process` 不跑，灯就永远停在"夜间值"不关。
	#    这里显式设成 ALWAYS，昼夜控制不该被暂停菜单挡住。
	process_mode = Node.PROCESS_MODE_ALWAYS


func _collect() -> void:
	var host := get_parent()
	if host == null:
		return
	for n in host.find_children("*", "OmniLight3D", true, false) + \
			host.find_children("*", "SpotLight3D", true, false) + \
			host.find_children("*", "DirectionalLight3D", true, false):
		var l := n as Light3D
		if l == null:
			continue
		_lights.append(l)
		_night_energy.append(l.light_energy)

	# 招牌板的自发光（材质是 tscn 里的 sub_resource，是**共享**的，改一处就够）
	var sign_board := host.get_node_or_null("Body/SignBoard") as MeshInstance3D
	if sign_board != null:
		var sm := sign_board.material_override as StandardMaterial3D
		if sm != null and sm.emission_enabled:
			_emissions.append(sm)
			_emission_night.append(sm.emission_energy_multiplier)

	# 屋壳里的灯管：近白自发光
	for mi in host.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for si in m.get_surface_count():
			var mat := m.surface_get_material(si)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				if sm.emission_enabled and not _emissions.has(sm) \
						and sm.emission.get_luminance() > 0.99 \
						and sm.emission.g >= sm.emission.r:
					_emissions.append(sm)
					_emission_night.append(sm.emission_energy_multiplier)

	print("[ShopNightLights] 接管 %d 盏灯（%s）、%d 个自发光材质"
		% [_lights.size(), _names(_lights), _emissions.size()])
	_collected = true
	# ⚠️ 收完**先按当前时刻**定 `_k`，再刷一次 ——
	#    不这么做的话 `_k` 还是初值 0（白天），而 `_applied_key` 又被记成 0，
	#    于是"到点了却不亮"，直到比例下一次变化才补上。
	_k = 1.0 if is_on_now(_tod_hours()) else 0.0
	_applied_key = int(round(_k * 100.0))
	_apply()


func _names(arr: Array[Light3D]) -> String:
	var out: Array[String] = []
	for l in arr:
		out.append(String(l.name))
	return "/".join(out)


## 现在是不是开灯时段。跨零点，所以不能写成 `h >= 20 and h < 6`（永远 false）。
static func is_on_now(hours: float) -> bool:
	var h := fposmod(hours, 24.0)
	if ON_HOUR_FROM > ON_HOUR_TO:
		return h >= float(ON_HOUR_FROM) or h < float(ON_HOUR_TO)
	return h >= float(ON_HOUR_FROM) and h < float(ON_HOUR_TO)


func _process(delta: float) -> void:
	if not _collected:
		return
	if _lights.is_empty() and _emissions.is_empty():
		return

	var target := 1.0 if is_on_now(_tod_hours()) else 0.0
	if FADE_TIME <= 0.0001:
		_k = target
	else:
		_k = move_toward(_k, target, delta / FADE_TIME)
	# 只有比例变了才重刷（白天站着不动时不会每帧写一堆 uniform）
	var key := int(round(_k * 100.0))
	if key == _applied_key:
		return
	_applied_key = key
	_apply()


func _apply() -> void:
	for i in _lights.size():
		var l := _lights[i]
		var night := _night_energy[i]
		var day := night
		match String(l.name):
			"SignLight":
				day = DAY_SIGN_ENERGY
			_:
				day = DAY_INDOOR_ENERGY
		l.light_energy = lerpf(day, night, _k)
	for i in _emissions.size():
		var m := _emissions[i]
		m.emission_energy_multiplier = lerpf(
			DAY_EMISSION_MULT, _emission_night[i], _k)


## 从自动加载的 `TimeOfDay` 读当前小时。读不到就当作**白天**（安全侧：
## 宁可不开灯，也不要白天一直亮着 —— 那正是用户抱怨的东西）。
func _tod_hours() -> float:
	var n := get_node_or_null("/root/TimeOfDay")
	if n != null and "hours" in n:
		return float(n.get("hours"))
	return 12.0
