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
## 待机动画名候选。芹香是 `Normal_Idle`；后面几个是给别的模型留的退路。
const IDLE_CLIPS := ["Normal_Idle", "Cafe_Idle", "Stand_Idle", "Idle"]
## 手骨名候选（`side` = "l" / "r"）。`Bip001` 那套是 Blue Archive 的骨架命名。
const HAND_BONES := {
	"l": ["Bip001 L Hand", "hand.l"],
	"r": ["Bip001 R Hand", "hand.r"],
}
## 抬高到能露出柜台（米）。
##
## ⚠️ 为什么是「抬高」而不是「缩放」：实测**改 `scale` 几乎不改变她的世界高度**
##    （1.113× 时 `Bip001 Head` 世界 y=0.84，1.55× 时反而是 0.75）——
##    这套 rig 的骨头处在压缩空间里，蒙皮网格最终落在哪由骨骼矩阵决定，
##    节点 scale 只把这套矩阵整体缩了一点，位置基本不动。
##    结果就是不管怎么缩，她站在台面 1.05 m 的柜台后面只剩天灵盖（实拍三次）。
##    所以直接抬起来：脚下等于踩了一个看不见的垫脚箱（玩家看不到柜台后面）。
const MODEL_SCALE := 1.55
const CLERK_LIFT := 0.45

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


func _play_idle() -> void:
	for n in model.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		var list := ap.get_animation_list()
		for want in IDLE_CLIPS:
			if list.has(want):
				ap.play(want)
				ap.speed_scale = 1.0
				_idle = ap
				return


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
