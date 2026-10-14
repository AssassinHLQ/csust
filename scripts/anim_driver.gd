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
##   LOCOMOTION  按速度在 Normal_Idle / Cafe_Walk / Move_Ing 之间切
##   FIRE        播一次 Normal_Attack_Ing，播完回 LOCOMOTION
##   RELOAD      播一次 Normal_Reload，播完回 LOCOMOTION
##
## 标注速度：每个循环动画在某个移动速度下脚步最贴合，用它算播放速率，
## 避免「脚下打滑」。

enum State { LOCOMOTION, FIRE, RELOAD }

## 循环动画的标称速度（米/秒）——按这个速度播时脚步与位移最匹配
const CYCLE_SPEED := {
	"Normal_Idle": 0.0,
	"Cafe_Walk": 1.6,
	"Move_Ing": 5.2,
}
const WALK_THRESHOLD := 2.4      # 低于这个速度用 Cafe_Walk，高于用 Move_Ing
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
	if player == null:
		player = _find_first(get_tree().root, "AnimationPlayer") as AnimationPlayer
	if player == null:
		push_error("[AnimDriver] 找不到 AnimationPlayer")
		return
	skeleton = get_node_or_null(skeleton_path) as Skeleton3D

	_configure_library()
	if player.has_animation("Normal_Idle"):
		player.play("Normal_Idle", -1.0, 1.0)
	player.animation_finished.connect(_on_finished)


func _configure_library() -> void:
	for n in ["Normal_Idle", "Cafe_Walk", "Move_Ing"]:
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
	var want := "Normal_Idle"
	if _speed >= WALK_THRESHOLD:
		want = "Move_Ing"
	elif _speed > 0.15:
		want = "Cafe_Walk"

	if player.current_animation != want:
		player.play(want, FADE, 1.0)

	# 播放速率按实际速度 / 该动画的标称速度算
	var nominal: float = CYCLE_SPEED.get(want, 0.0)
	if nominal > 0.01:
		player.speed_scale = clampf(_speed / nominal, 0.35, 2.0)
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
