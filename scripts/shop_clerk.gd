class_name ShopClerk
extends Node3D
## 天使24 的店员：**黑见芹香（Serika）**，校服版。
##
## ── 素材来源（署名，务必保留）──
##   模型：Blue Archive 模型包里的 `Serika.glb`（校服/默认版，4.0 MB）
##        原作 © NEXON Games / Yostar；**第三方素材，只在本地学习用**，
##        `/models/npc/**` 在 `.gitignore` 里，不随仓库分发。
##   放置：`models/npc/serika/serika.glb`（本喵 2026-10-22 从
##        `C:\Users\WY157\Downloads\BlueArchiveModels-main` 拷进来的）
##
## ── 为什么从小空换成芹香（2026-10-22 用户）──
##   「小空出差，芹香亲作为热血打工仔自愿工作很合理」
##   「不了不了，小空和我们角色模型画风不同，因为我们这个是卡通大头小人，
##     不是那种精致剧情立绘改的模型」
##   → 主题是**画风统一**：小空（338 骨 MMD 风）和爱丽丝/同伴那批卡通小人
##     差得太多，所以直接换掉，不做「可切换」。
##
## ── 和她的小设定 ──
##   待机动画用她自己带的 `Normal_Idle`（40 条动画里挑的），不再是程序化晃。
##   ⚠️ 小空那版的「转不动手臂」问题在这里不存在 —— 芹香是标准
##   `Bip001` 骨架 + 带 Idle，不需要摆姿势。
##
## ── 尺寸 ──
##   实测包围盒 0.67 × 1.39 × 0.50 m，**底在 y = −0.27**（原点在脚上方），
##   所以 `_ground()` 会把模型整体抬高 0.27 m 让脚踩到地板。
##   比爱丽丝（1.47 m）矮一点点，正好是芹香矮个子的设定，不缩放。
##   手骨高 0.45 + 0.27 = 0.72 m，柜台台面 1.04 m —— 手藏在柜台后面 ✓
const MODEL := "res://models/npc/serika/serika.glb"
## 待机动画名候选。
##
## ⚠️ 顺序是有意的：**`Cafe_Idle` 排第一**。
##   用户 2026-10-22：「芹香怎么拿着枪，有没有不拿枪的版本」——
##   `Normal_Idle` 是战斗待机，她双手抱着那把步枪（实拍 `_clerk/clerk.png` 里看得见枪）。
##   而 `Cafe_*` 这套「咖啡厅模式」的素材本身**把武器骨的 scale 缩到 ≈0**（和
##   `anim_driver.gd` 里写的爱丽丝/小桃那批完全一样），播 `Cafe_Idle` 枪就没了 ——
##   正好是店员该有的样子，而且不用改模型、不用抠网格。
const IDLE_CLIPS := ["Cafe_Idle", "Normal_Idle", "Stand_Idle", "Idle"]
## 手骨名候选（`side` = "l" / "r"）。`Bip001` 那套是 Blue Archive 的骨架命名。
const HAND_BONES := {
	"l": ["Bip001 L Hand", "hand.l"],
	"r": ["Bip001 R Hand", "hand.r"],
}
## 尺寸与抬脚（米）。
##
## ⚠️ 2026-10-22 晚修正：这两个数原来是 `1.55` / `0.45`，实测**她变成 2.20 m 高**
##    （`_probe_three.gd`：世界 AABB 底 0.029、顶 2.226）—— 站在 1.04 m 的柜台后面
##    比爱丽丝（1.47 m）高出一大截，用户一眼看出「芹香站这么高」。
##    上一版以为「改 scale 几乎不改变世界高度」，是被**绑定姿态 AABB** 骗了；
##    实际渲染高度就是 `1.39 × scale`（`1.39` 是她自己的包围盒高度）。
##    现在按设定身高给：芹香 152 cm → `1.52 / 1.39 = 1.09`；
##    抬脚 = 模型原点那个 −0.27 的偏移 × 缩放 = 0.294（脚正好踩在 y = 0）
##    **再加 0.22 m 的「看不见的垫脚箱」**：柜台台面 1.04 m，脚踩在地上时
##    实拍（`_knob/clerk_xm.png`）只剩一个脑袋露在台面上，像个小孩扒柜台。
##    柜台柜体本身 0.86 m 高，加这 0.22 从任何角度都看不到脚 ——
##    头顶变成 1.74 m，露到胸口，是正常店员的观感。
const MODEL_SCALE := 1.09
const CLERK_LIFT := 0.514

## 整只模型左右轻晃的幅度（没有 Idle 动画时的退路；芹香有动画，默认不晃）
@export var idle_sway := false
@export var sway_deg := 1.1
@export var sway_hz := 0.16

var model: Node3D
var skeleton: Skeleton3D
var bone_count := 0
## 量出来的：两只手骨的世界高度（自检/探针用来对照台面高度）
var hand_y := {}
## 缩放/抬高（探针用）
var ground_lift := 0.0
var fit_scale := 1.0

var _t := 0.0
var _idle: AnimationPlayer
var _idle_name := ""


func _ready() -> void:
	if not ResourceLoader.exists(MODEL):
		push_warning("[Clerk] 没有芹香的模型：%s（本地素材，不随仓库分发）" % MODEL)
		return
	var ps := load(MODEL) as PackedScene
	if ps == null:
		push_error("[Clerk] %s 不是有效的场景" % MODEL)
		return
	model = ps.instantiate() as Node3D
	add_child(model)
	_fit(model)
	skeleton = _best_skeleton(model)
	if skeleton != null:
		bone_count = skeleton.get_bone_count()
		for side in ["l", "r"]:
			var idx := _hand_bone(side)
			if idx >= 0:
				hand_y[side] = (skeleton.global_transform
					* skeleton.get_bone_global_pose(idx).origin).y
	# 光环抛光（和玩家/同伴那 8 顶一样的处理：受光 + 自发光 0.8 + 不投阴影）
	HaloFix.polish(model)
	_play_idle()
	print("[Clerk] 芹香就位：%s（骨架 %d 骨，缩放 %.2f×，抬脚 %.2f m，手骨高度 L=%.2f R=%.2f m，动画 %s）" % [
		MODEL.get_file(), bone_count, fit_scale, ground_lift,
		float(hand_y.get("l", -1.0)), float(hand_y.get("r", -1.0)),
		String(_idle.current_animation) if _idle != null else "无（保持静止姿势）"])


## 定高：按 `MODEL_SCALE` 等比缩放，脚底就落在模型原点（y = 0）。
## 为什么不用包围盒算，见 `MODEL_SCALE` 上面那段（绑定 AABB 会骗人）。
func _fit(root: Node3D) -> void:
	fit_scale = MODEL_SCALE
	root.scale = Vector3.ONE * fit_scale
	ground_lift = CLERK_LIFT
	root.position.y = ground_lift


## 播待机动画，并且**让它真的循环**。
##
## ⚠️ 用户 2026-10-22：「为什么芹香站这么高**也不动**」。
##   实测（`_probe_three.gd`）：`Cafe_Idle` 播了，`is_playing() == true`，
##   长度 1.667 s、140 条轨道、89 条有 >1 个关键帧 —— 但 `loop_mode` 是
##   **0（LOOP_NONE）**，`current_animation_position` 停在 1.659 s：
##   她播完第一遍就定格在最后一帧，看起来就是一根不动的桩。
##   glb 里带来的动画默认不循环，`.play()` 也不会替你打开。
func _play_idle() -> void:
	for n in model.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		var list := ap.get_animation_list()
		for want in IDLE_CLIPS:
			if not list.has(want):
				continue
			var anim := ap.get_animation(want)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR
			ap.play(want)
			ap.speed_scale = 1.0
			# 万一这条动画是只读资源（改不动 loop_mode），播完再自己续上
			if not ap.animation_finished.is_connected(_replay_idle):
				ap.animation_finished.connect(_replay_idle)
			_idle = ap
			_idle_name = want
			return


func _replay_idle(anim_name: StringName) -> void:
	if _idle == null or anim_name != _idle_name:
		return
	_idle.play(anim_name)


func _process(delta: float) -> void:
	if _idle != null or not idle_sway or model == null:
		return
	_t += delta
	model.rotation.y = deg_to_rad(sway_deg) * sin(_t * TAU * sway_hz)


func _hand_bone(side: String) -> int:
	for want in HAND_BONES.get(side, []):
		var i := _find_bone(want)
		if i >= 0:
			return i
	return -1


func _find_bone(want: String) -> int:
	if skeleton == null:
		return -1
	return skeleton.find_bone(want)


func _best_skeleton(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for s in _skeletons(node):
		if best == null or s.get_bone_count() > best.get_bone_count():
			best = s
	return best


func _skeletons(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node is Skeleton3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_skeletons(c))
	return out
