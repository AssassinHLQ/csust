class_name ParkourDrift
extends AnimatableBody3D
## 「会动的方块」：升降台（上下）/ 平移台（左右）/ 布朗运动块。
##
## ── 为什么必须是 `AnimatableBody3D` + `sync_to_physics` ──
## 和 `parkour_mover.gd` 同一个理由：玩家走的是 `CharacterBody3D.move_and_slide()`，
## 只有 `AnimatableBody3D` 才会被 Godot 的移动平台机制认账（站着不动也被带走）。
## 用 `StaticBody3D` 自己推位置是推不动的。
##
## ── 三种运动 ──
##   LIFT     : `point_a` ⇄ `point_b` 直线往返（竖直用：台面高度差 = 抬升量）
##   SLIDE    : 同上，但两端在 z 上拉开（左右用：横跨 z 方向的缺口）
##   BROWNIAN : 在以出生点为中心、半径 `roam` 的盒子里**随机游走**，每 `retarget` 秒换目标
##
## 端点都停 `wait_time` 秒 —— 和移动平台踩过的坑一样：不停留就没法上下船。

enum Mode { LIFT, SLIDE, BROWNIAN }

@export var mode := Mode.LIFT
@export var point_a := Vector3.ZERO
@export var point_b := Vector3.ZERO
@export var speed := 1.8
## 到端点后停多久（秒）：上下船窗口
@export var wait_time := 1.5
## 布朗运动的活动半径（米）与换目标间隔（秒）
@export var roam := 2.4
@export var retarget := 1.1
@export var seed_value := 2067

var _t := 0.0
var _dir := 1.0
var _wait := 0.0
var _len := 0.0
var _rng := RandomNumberGenerator.new()
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _next_pick := 0.0


func _ready() -> void:
	sync_to_physics = true
	_rng.seed = seed_value
	if mode == Mode.BROWNIAN:
		_home = global_position
		_target = _pick()
	else:
		_len = point_a.distance_to(point_b)
		global_position = point_a


func _physics_process(delta: float) -> void:
	if mode == Mode.BROWNIAN:
		_brownian(delta)
		return
	if _len <= 0.001:
		return
	if _wait > 0.0:
		_wait -= delta
		return
	_t += _dir * speed * delta / _len
	if _t >= 1.0:
		_t = 1.0
		_dir = -1.0
		_wait = wait_time
	elif _t <= 0.0:
		_t = 0.0
		_dir = 1.0
		_wait = wait_time
	global_position = point_a.lerp(point_b, _t)


func _brownian(delta: float) -> void:
	_next_pick -= delta
	var to := _target - global_position
	if _next_pick <= 0.0 or to.length() < 0.15:
		_target = _pick()
		_next_pick = retarget
		return
	global_position += to.normalized() * minf(speed * delta, to.length())


## 在 home 附近随机挑一个点（xz 为主，y 小幅起伏）
func _pick() -> Vector3:
	var ang := _rng.randf() * TAU
	var r := _rng.randf_range(0.6, roam)
	return _home + Vector3(cos(ang) * r, _rng.randf_range(-0.5, 0.5), sin(ang) * r)


func progress() -> float:
	return _t


func docked() -> bool:
	return _t <= 0.001 or _t >= 0.999


## 自检用：按进度摆到某个位置（`hold` > 0 时在端点多停一会儿，方便从容上下）
func force_progress(t: float, hold := 0.0) -> void:
	_t = clampf(t, 0.0, 1.0)
	_wait = hold
	global_position = point_a.lerp(point_b, _t)
