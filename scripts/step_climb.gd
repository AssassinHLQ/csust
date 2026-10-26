extends RefCounted
## `CharacterBody3D` 的**上台阶**辅助 —— Godot 自己没有这个能力。
##
## ⚠️ 故意**不写 `class_name`**：`class_name` 要等编辑器把脚本扫进
##    `.godot/global_script_class_cache.cfg` 才认得，而 `--headless --script` 跑探针时
##    不会做这一步（实测报 `Identifier "StepClimb" not declared in the current scope`）。
##    调用方一律用 `const StepClimb := preload("res://scripts/step_climb.gd")`。
##
## ── 为什么需要它（实测，不是推断）──
## `_probe_step_climb.gd` 在商店门前的干净空地上驱真玩家撞竖直台阶，六档全测：
##
##     台阶高    终点 y     判定
##     0.05     0.001      滑过去了（能过）
##     0.10     0.000      被挡住
##     0.15     0.000      被挡住
##     0.21     0.000      被挡住
##     0.30     0.000      被挡住
##     0.45     0.000      被挡住
##
## 门槛在 **0.05 ~ 0.10 m** 之间。`mesh_hut.tscn` 里那句「10 cm 的坎 cast_motion 的
## safe 从 1.000 掉到 0.387」是真的，这里用另一种方法（真按键 + 量 y）复现了。
##
## 原因不是「太高」，而是胶囊底部是半径 0.3 的**半球**：撞竖直面时接触点在球心下方，
## 法线朝下，`move_and_slide` 沿它滑移只会把人往下压，永远产生不了向上的分量。
## 倒角踢面也救不了 —— `_probe_stair_forms.gd` 量过 38°/40° 倒角，最多爬到 0.10 m。
##
## ── 做法：抬起 → 前探 → 落下，三步全问物理引擎 ──
## ① 头顶有东西 → 放弃（矮天花板下不能把人顶穿）；
## ② 抬到 `step_height` 后**前方一个「伸脚距离」内还有碰撞** → 那是墙，不是台阶，放弃。
##    这一条是关键判据：抬高之后台阶已经在我们脚下了，还能挡住我们的必然是墙；
## ③ 往前挪完再往下够，够到地面才算数，落到那个面上。
##
## ── 为什么前探要跨过一个胶囊半径（`reach`）──
## 第一版只用这一帧的前进量（2.4 m/s × 1/60 ≈ 0.04 m）去前探，结果**永远失败**：
## 人被挡在台阶前 0.70 m 处，抬起来往前挪 4 cm 仍然在台阶外面，落下去又落回地面。
## 实测六档全 ✘。必须往前跨出至少一个胶囊半径，才能让底面覆盖到台阶上表面。

## 默认上台阶高度（米）。要盖过 0.21 m 的踏步，同时明显小于桌面（0.80）、
## 柜台（1.04）这些「应该挡住人」的高度。
const DEFAULT_HEIGHT := 0.32
## 前探距离在胶囊半径之外再多给一点，落地时才有实的支撑面
const REACH_MARGIN := 0.06
## 落点比接触面略高一丝，避免和地面互相嵌进去（米）
const SKIN := 0.002


## 成功则把 `body` 挪到台阶上并返回 `true`。
## `want` 是这一帧本该走的水平位移（已乘 delta），只用它的**方向**。
static func try_step(body: CharacterBody3D, want: Vector3,
		step_height: float = DEFAULT_HEIGHT) -> bool:
	if not body.is_on_floor():
		return false
	var flat := Vector3(want.x, 0.0, want.z)
	if flat.length_squared() < 1e-8:
		return false
	var dir := flat.normalized()

	# ① 头顶有没有空间
	if body.test_move(body.global_transform, Vector3.UP * step_height):
		return false

	var raised := body.global_transform.translated(Vector3.UP * step_height)

	# ② 抬上去之后前方一个「伸脚距离」内还撞 → 是墙
	var reach := _capsule_radius(body) + REACH_MARGIN
	var probe := dir * reach
	if body.test_move(raised, probe):
		return false
	var ahead := raised.translated(probe)

	# ③ 往下够地面
	var col := KinematicCollision3D.new()
	if not body.test_move(ahead, Vector3.DOWN * step_height, col):
		return false
	var drop := col.get_travel().length()
	if drop <= 0.001 or drop > step_height:
		return false

	body.global_position = ahead.origin + Vector3.DOWN * maxf(drop - SKIN, 0.0)
	return true


## 胶囊半径（用来定前探距离）。取第一个 `CapsuleShape3D`，没有就按 0.3 兜底。
static func _capsule_radius(body: CharacterBody3D) -> float:
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null:
			continue
		var cap := cs.shape as CapsuleShape3D
		if cap != null:
			return cap.radius
	return 0.3


## 这一帧是不是被挡住了 —— 用「实际位移 vs 该走的位移」比。
## 走平地时不挡（比值 ≈ 1），斜着蹭墙也不判挡（比值仍有 0.7 以上），
## 只有正对着墙/台阶（比值 ≈ 0）才算，避免无谓的 `test_move` 开销。
static func blocked(actual: Vector3, intended: Vector3, ratio := 0.35) -> bool:
	var a := Vector2(actual.x, actual.z).length()
	var b := Vector2(intended.x, intended.z).length()
	if b < 1e-6:
		return false
	return a < b * ratio
