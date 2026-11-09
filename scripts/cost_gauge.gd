extends RefCounted
## COST（费用）量表 —— 蔚蓝档案那套「按时间攒费用、放 EX 技能时花掉」。
##
## 规则由用户 2026-11-09 当场指定（原话拆条）：
##   · 「上限10」        → `MAX_COST = 10`
##   · 「0」             → `START_COST = 0`（开局不给）
##   · 「固定1秒回一」    → `PER_SECOND = 1.0`
##   · 「只爱丽丝」       → 只有玩家的 EX 花它（同伴不放 EX，本类不管谁花，
##                        真正的花销由 EX 技能那边的会话调 `spend()`）
##
## ⚠️ **数值出处是「用户指定」，不是本喵从 wiki 查证的。**
##    查证那次 `bluearchive.wiki/wiki/Cost` 被 Cloudflare 403 挡住、Fandom 连不上，
##    本喵明确说过「不猜数字」。将来若要改成原作实测值：
##    **只改 `PER_SECOND` 这一行**，并同步改 `_verify_cost.gd` 里的期望值。
##
## ⚠️ 原作里 COST 回复是**全局被动**的，和场上几个学生无关 ——
##    「带 6 个人就涨得快」是误解。所以本类不接任何「人数」参数。
##
## 为什么不是 autoload：和 `BankCard` / `MechState` / `SceneFlow` / `GameSettings`
## 一样走「`preload` + 全静态」，不动 `project.godot`（用户不让改 autoload；
## 而且 `--script` 自检模式下 autoload 名不是编译期可见的）。
##
## 谁让它走时间：`hud.gd::_process()` 每帧调 `tick(delta)`。
##   · 静态类没有生命周期，不能自己 tick；
##   · 放 HUD 是因为**两个关卡都有 HUD**，一处接线两关都生效；
##   · ⚠️ 顺带一个正确行为：HUD 在暂停时也停（`process_mode` 默认继承），
##     所以对话/菜单暂停时 COST 不涨 —— 和原作一致。

## 上限（用户 2026-11-09：「上限10」）
const MAX_COST := 10
## 开局给多少（用户 2026-11-09：「0」）
const START_COST := 0.0
## 每秒回复多少（用户 2026-11-09：「固定1秒回一」）
const PER_SECOND := 1.0

## 当前费用。**是小数**：条是连续涨的，整数只是显示 ——
## 放完技能余下的小数照常留着（原作就是这样，不是「攒够整数才动」）。
static var cost := START_COST

## 有没有被 tick 过（自检 / 调试用：没 tick 就说明没人接线）
static var _ticked := false


## 攒费用。由 `hud.gd::_process()` 每帧调用。
## ⚠️ 封顶在 `MAX_COST`，**不做「溢出丢弃」的额外处理** —— 到顶就是到顶。
static func tick(delta: float) -> void:
	_ticked = true
	cost = minf(cost + PER_SECOND * delta, MAX_COST)


## 够不够放一个消耗 `n` 的技能。
## ⚠️ 容差是给浮点累加用的：`tick` 累加到 1.9999999 时也该算「有 2 点」。
static func can_afford(n: int) -> bool:
	return cost >= float(n) - 0.0001


## 花掉 `n` 点，够了才扣。返回是否真的扣成功。
## ⚠️ 小数**不丢**：扣完剩下的 0.x 照常留在 `cost` 里。
static func spend(n: int) -> bool:
	if n <= 0:
		return true
	if not can_afford(n):
		return false
	cost = maxf(cost - float(n), 0.0)
	return true


## 显示用的整数（向下取整）。HUD 只显示这个。
static func display() -> int:
	return int(floor(cost + 0.0001))


## 填充比例 0~1（画条用）
static func ratio() -> float:
	return clampf(cost / MAX_COST, 0.0, 1.0)


## 重置（新一局 / 自检）。默认回到 `START_COST`。
static func reset(v: float = START_COST) -> void:
	cost = clampf(v, 0.0, MAX_COST)


## 自检用：直接摆一个值
static func set_cost_for_test(v: float) -> void:
	reset(v)


## 自检用：有没有人真的在 tick 它
static func has_ticked() -> bool:
	return _ticked
