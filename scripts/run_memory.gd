extends RefCounted
## 「这一个游戏进程里已经发生过的事」——**跨场景记得，重开游戏清空**。
##
## 用户 2026-11-11：
##   「记住，当且仅当重开游戏。全量重置除了高斯泼溅缓存以外的，这是小体量游戏」。
##
## 所以这里是**纯内存**的 static：不落盘、不写 `user://`。
##   · 换场景（`change_scene_to_file()` 会把旧场景整棵释放）之后仍然记得；
##   · 关掉游戏再开 → 一律空白（和 `BankCard` 每次启动清零同一个口径）；
##   · **高斯泼溅缓存不归这里管**：它是 `_cache/` 里的磁盘缓存，跨启动必须留着
##     （那是加载速度，不是"进度"）。
##
## 为什么另开一个脚本而不是塞进某个已有节点：和 `BankCard` / `SceneFlow` / `DevMode`
## 一样走「preload + 全静态」，不动 `project.godot` 的 autoload —— 而且换场景时
## **任何挂在节点上的状态都会跟着节点一起没**，只有 static 活得过那一刀。
##
## 目前记三样：
##   · `cpus`        —— 609 屋顶已经收走的 9950X3D，按**量化世界坐标**认（见 `cpu_key()`）
##   · `parkour_done`—— 跑酷是否通关过（决定跑道口那枚火箭 / 传送门在不在）
##   · `carrier`     —— 机甲能量条：攒了几条 + 进度 + 已启用那几条的剩余秒数
##
## ⚠️ 为什么不按"第几颗"记：序号会随「在编辑器里删一颗 / 加一颗」整体错位，
##    于是玩家会莫名少掉几颗**没捡过的**。坐标只认"这一颗"；在编辑器里挪过的位置
##    会被当成新的一颗（那正是想要的：挪过 = 重新可捡）。

static var _cpus := {}
static var _parkour_done := false
## 机甲能量条状态。用户 2026-11-11：「为什么跨场景就清空了r的技能充能?」
## 原来这些都是 `carrier_form.gd` 的**实例变量**，换场景（旧场景整棵释放）
## 就跟着没了 —— 和 9950X3D 是同一个根因，所以走同一个地方。
static var _carrier_bars := 0
static var _carrier_fly_m := 0.0
## 已启用那几条的剩余秒数（每条独立计时，见 `carrier_form.gd::use_energy_bar`）
static var _carrier_timers: Array[float] = []


## ── 机甲能量条 ────────────────────────────────────────────────────────

static func carrier_snapshot() -> Dictionary:
	return {
		"bars": _carrier_bars,
		"fly_m": _carrier_fly_m,
		"timers": _carrier_timers.duplicate(),
	}


## 只在**真正有变化**时写：`carrier_form.gd` 每帧都会调，别每帧拷数组。
static func set_carrier(bars: int, fly_m: float, timers: Array) -> void:
	_carrier_bars = bars
	_carrier_fly_m = fly_m
	_carrier_timers.clear()
	for t in timers:
		_carrier_timers.append(float(t))


## 一颗 CPU 的稳定身份：世界坐标量化到 1 cm。
## ⚠️ 只能在**已经进树**之后调（`_ready()` 里就行）—— 那时 `global_position` 才算得出来。
static func cpu_key(node: Node3D) -> String:
	var p := node.global_position
	return "%.2f_%.2f_%.2f" % [p.x, p.y, p.z]


static func cpu_taken(key: String) -> bool:
	return _cpus.has(key)


static func mark_cpu(key: String) -> void:
	_cpus[key] = true


## 本次运行一共收走几颗（HUD / 自检用）
static func cpu_count() -> int:
	return _cpus.size()


static func parkour_done() -> bool:
	return _parkour_done


static func set_parkour_done(v: bool) -> void:
	_parkour_done = v


## 自检用：把记忆清空（等价于「重开游戏」）。
## ⚠️ 这是**唯一**的清空入口 —— 游戏里没有任何地方会调它。
static func wipe() -> void:
	_cpus.clear()
	_parkour_done = false
	_carrier_bars = 0
	_carrier_fly_m = 0.0
	_carrier_timers.clear()
