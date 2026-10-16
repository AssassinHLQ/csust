class_name AnimDriver
extends Node
## 动画驱动：直接用 AnimationPlayer 播动作，自己做状态切换与混合。
##
## 为什么不用 AnimationTree：
##   实测（Godot 4.7.1 + 这份 glTF 导入的骨架）AnimationTree 整体不驱动骨骼——
##   AnimationNodeBlendSpace1D、AnimationNodeBlend2、AnimationNodeBlendTree、
##   StateMachine 全都逐帧截图 0 像素差异；而同一个 AnimationPlayer 直接 play()
##   完全正常。为了不让玩法卡死，这里绕开 AnimationTree，用 AnimationPlayer 自己做。
##
## 状态：
##   LOCOMOTION  按速度在 Normal_Idle / Move_Ing 之间切
##   FIRE        播一次 Normal_Attack_Ing，播完回 LOCOMOTION
##   RELOAD      播一次 Normal_Reload，播完回 LOCOMOTION
##
## ⚠️ **为什么只有两条循环动画，没有 `Cafe_Walk`** —— 这一条是踩过一次才想明白的，
##    改动前务必看 `CYCLE_SPEED` 上面那段注释（用户报「为什么小桃小绿行走动作是拿
##    游戏机的，还有好多角色行走也没有拿枪了」就是它）。
##
## 标注速度：每个循环动画在某个移动速度下脚步最贴合，用它算播放速率，
## 避免「脚下打滑」。

enum State { LOCOMOTION, FIRE, RELOAD }

## 循环动画的标称速度（米/秒）——按这个速度播时脚步与位移最匹配
##
## ⚠️⚠️ **这里只有 Idle 和 Move_Ing 两条，是故意的 —— `Cafe_Walk` 一律不用。**
##
## ── 起因（用户报）──
## 「为什么小桃小绿行走动作是拿游戏机的，还有好多角色行走也没有拿枪了」
##
## ── 量出来的真相（`scripts/_probe_companion_anim.gd`）──
## Blue Archive 的 `Cafe_*` 是**咖啡厅模式**的动画，那一套里角色**不拿武器**：
## 素材是靠**把武器骨的 scale 缩到 ≈0** 来藏枪的。实测 8 个模型**全都如此** ——
## `Cafe_Walk` 里的武器骨 scale.x 最小是
##     爱丽丝 0.038 / 未花 0.020 / 优香 0.143 + 0.107 / 诺亚 0.001 /
##     小桃 0.000 / 小绿 0.000 / 柚子 0.020 / 凯伊 0.001
## 而同一根骨在 `Move_Ing`（战斗移动）里是 **1.0**（拿枪）。
## 所以「走路不拿枪」**不是挑错了 clip，是素材本身如此**；小桃/小绿在咖啡厅姿势里
## 手里那个「游戏机」就是她们的招牌道具。
##
## ── 试过并否掉的修法 ──
## 把 `Cafe_Walk` 复制一份、把「Move_Ing 里显示、Cafe_Walk 里藏起来」的骨 scale
## 改回 1.0（保住漫步步态 + 补回武器）：枪确实回来了，但**是挂在身侧的**，
## 两只手还在胸前捧着游戏机（那件道具**不在武器骨下**，改 scale 抠不掉它）——
## 比原来更怪。四种候选的对照图见 `scripts/_probe_armed_walk_shot.gd`
## （输出在 `_arisu_captures/_armedwalk/`）。
##
## ── 结论 ──
## 整个游戏（主角 + 七名同伴）**一律用战斗动画**，走 / 跑只靠 `speed_scale` 区分。
## 这也正是 BA 自己的做法：`Cafe_*` 只在咖啡厅界面出现，战斗里只有 `Move_Ing`。
## 代价是「走路时用的是跑步的**姿势**、放慢到 0.46 倍」——步幅仍然吻合
## （见下面 `speed_scale` 那段），只是上身前倾是跑步那一下。
const CYCLE_SPEED := {
	"Normal_Idle": 0.0,
	"Move_Ing": 5.2,
}
## 低于这个速度就播待机（原来是「低于 WALK_THRESHOLD 播 Cafe_Walk」）
const IDLE_SPEED := 0.15
## 播放速率的上下限。
##
## ⚠️ 下限从 0.35 放到 **0.25**：蹲行（1.3 m/s）现在也走 `Move_Ing`（标称 5.2），
##    1.3 / 5.2 = 0.25。卡在 0.35 会让脚比地面快 40%（打滑），
##    而「步幅吻合」比「步频好看」重要 —— 播放速率是**按实际位移补脚步**的。
const SPEED_SCALE_MIN := 0.25
const SPEED_SCALE_MAX := 2.0
const FADE := 0.18               # 交叉淡入时间

## 一次性动作的播放倍速。
## Normal_Attack_Ing 原长 2.67 s，而枪的连发间隔是 0.075 s——
## 原速播的话一次射击动作要 2.67 秒才收招，手感「卡卡的」。
## 加速到 2.5 倍后约 1.07 s 收招，跟打空一梭 2.25 s 的节奏对得上。
const FIRE_SPEED := 2.5
const RELOAD_SPEED := 1.9

var state := State.LOCOMOTION
var player: AnimationPlayer
var skeleton: Skeleton3D

var _speed := 0.0
var _aiming := false
var _auto_return := false


func _ready() -> void:
	player = get_node_or_null(animation_player_path) as AnimationPlayer
	skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	# 两个 NodePath 都留空时，先在**自己所在的模型子树**里找，再退回整棵树。
	# 同伴（companion.gd 运行时 new 出来的 AnimDriver）走的就是这条路：
	# 三只 GLB 的内部节点名互不相同，写死路径没法共用。
	if player == null or skeleton == null:
		var scope: Node = get_parent()
		if player == null:
			player = _find_first(scope, "AnimationPlayer") as AnimationPlayer
			if player == null and get_tree():
				player = _find_first(get_tree().root, "AnimationPlayer") as AnimationPlayer
		if skeleton == null:
			skeleton = _find_first(scope, "Skeleton3D") as Skeleton3D
	if player == null:
		push_error("[AnimDriver] 找不到 AnimationPlayer")
		return

	_configure_library()
	if player.has_animation("Normal_Idle"):
		player.play("Normal_Idle", -1.0, 1.0)
	player.animation_finished.connect(_on_finished)


func _configure_library() -> void:
	# 只给**用到的**两条循环动画设循环；`Cafe_Walk` 也在模型里，但本工程不播它
	# （理由见 CYCLE_SPEED 上面那段），所以不用管它。
	for n in ["Normal_Idle", "Move_Ing"]:
		if player.has_animation(n):
			player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in ["Normal_Attack_Ing", "Normal_Reload"]:
		if player.has_animation(n):
			player.get_animation(n).loop_mode = Animation.LOOP_NONE


# --- 接口 ---

func set_locomotion(speed: float, _on_floor: bool, _vertical_speed: float) -> void:
	_speed = speed
	if player == null or state != State.LOCOMOTION:
		return
	_update_locomotion()


func set_aiming(on: bool) -> void:
	_aiming = on


func is_aiming() -> bool:
	return _aiming


func request_fire() -> void:
	_play_once("Normal_Attack_Ing", State.FIRE)


func request_reload() -> void:
	_play_once("Normal_Reload", State.RELOAD)


func current_state_name() -> String:
	match state:
		State.FIRE:
			return "Fire"
		State.RELOAD:
			return "Reload"
		_:
			return "Locomotion"


func current_clip() -> String:
	return player.current_animation if player else ""


func blend_amount() -> float:
	return clampf(_speed / CYCLE_SPEED["Move_Ing"], 0.0, 1.0)


func fire_clip_length() -> float:
	if player and player.has_animation("Normal_Attack_Ing"):
		return player.get_animation("Normal_Attack_Ing").length
	return 0.5


func reload_clip_length() -> float:
	if player and player.has_animation("Normal_Reload"):
		return player.get_animation("Normal_Reload").length
	return 1.5


# --- 内部 ---

func _update_locomotion() -> void:
	# 走 / 跑 / 蹲 / 开镜 **都用 Move_Ing**（战斗动画：两只手在枪上），
	# 只靠 `speed_scale` 区分快慢。理由见 CYCLE_SPEED 上面那段（`Cafe_Walk` 不拿枪）。
	var want := "Normal_Idle" if _speed <= IDLE_SPEED else "Move_Ing"

	if player.current_animation != want:
		player.play(want, FADE, 1.0)

	# 播放速率按实际速度 / 该动画的标称速度算 —— 这一条是**防脚底打滑**的：
	# `Move_Ing` 的标称是 5.2 m/s，走 2.4 m/s 就播 0.46 倍，
	# 一个循环仍然是 3.47 m 的步幅（2.4 × 0.667 / 0.46 = 3.48），和地面严丝合缝。
	var nominal: float = CYCLE_SPEED.get(want, 0.0)
	if nominal > 0.01:
		player.speed_scale = clampf(_speed / nominal, SPEED_SCALE_MIN, SPEED_SCALE_MAX)
	else:
		player.speed_scale = 1.0


func _play_once(anim: String, new_state: State) -> void:
	if player == null or not player.has_animation(anim):
		return
	# 一次性动作播到一半就不打断，避免动作被腰斩
	if state != State.LOCOMOTION:
		return
	state = new_state
	_auto_return = true
	player.speed_scale = RELOAD_SPEED if new_state == State.RELOAD else FIRE_SPEED
	player.play(anim, 0.08, 1.0)


func _on_finished(anim_name: StringName) -> void:
	if not _auto_return:
		return
	if state == State.FIRE and anim_name == "Normal_Attack_Ing":
		_return_to_locomotion()
	elif state == State.RELOAD and anim_name == "Normal_Reload":
		_return_to_locomotion()


func _return_to_locomotion() -> void:
	state = State.LOCOMOTION
	_auto_return = false
	_update_locomotion()


func _find_first(n: Node, cls: String) -> Node:
	if n == null:
		return null
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find_first(c, cls)
		if r:
			return r
	return null


@export var skeleton_path: NodePath
@export var animation_player_path: NodePath
