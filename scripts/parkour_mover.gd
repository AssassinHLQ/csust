class_name ParkourMover
extends AnimatableBody3D
## 移动平台：在 `point_a` ⇄ `point_b` 之间直线来回，把人载过缺口（被动式）。
##
## ── 为什么必须是 `AnimatableBody3D` + `sync_to_physics` ──
##   玩家走的是 `CharacterBody3D.move_and_slide()`，**只有 `AnimatableBody3D` 才会被
##   Godot 的移动平台机制认账**（`platform_on_leave` 默认 `ADD_VELOCITY`）：
##   玩家站着不动也会被平台带着走。用 `StaticBody3D` 自己推位置是推不动的。
##   `sync_to_physics = true`（在 .tscn 里设）保证平台的位移发生在物理帧里，
##   否则承载会抖。
##
## ⚠️ 两个端点都要落在 **0.05 m 网格**上（几何纪律），而且平台在端点要**压住两岸的边**
##    （重叠 0.3 m 左右）—— 只留一条缝的话，`CharacterBody3D` 不会迈那一步，会掉下去。
##
## ⚠️ 速度 1.2~2.0 m/s：太快站不稳，太慢没耐心。端点停 `wait_time` 秒，好让人上下。
##    （0.8 s 实测**不够**：人下船时平台已经开始往回走，走路 2.4 m/s 对 1.8 m/s 只净剩
##     0.6 m/s，600 ms 只挪 0.36 m —— 自检的「连续通关」就卡在 F2 那一站。改 1.2 s。）

signal arrived(end_name: String)

@export var point_a := Vector3.ZERO
@export var point_b := Vector3.ZERO
@export var speed := 1.8
## 到端点后停多久（秒）
@export var wait_time := 1.2

var trips := 0
var _t := 0.0
var _dir := 1.0
var _wait := 0.0
var _len := 0.0


func _ready() -> void:
	_len = point_a.distance_to(point_b)
	position = point_a


func _physics_process(delta: float) -> void:
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
		trips += 1
		arrived.emit("B")
	elif _t <= 0.0:
		_t = 0.0
		_dir = 1.0
		_wait = wait_time
		arrived.emit("A")
	position = point_a.lerp(point_b, _t)


func progress() -> float:
	return _t


## 单程多远（米）
func travel() -> float:
	return _len


## 停靠在端点了吗
func docked() -> bool:
	return _t <= 0.001 or _t >= 0.999


## 自检用：把平台按到某个进度（省得每次都等它跑过来）。
## `hold` > 0 时在端点多停这么久，方便自检从容登船。
func force_progress(t: float, hold := 0.0) -> void:
	_t = clampf(t, 0.0, 1.0)
	_wait = hold
	position = point_a.lerp(point_b, _t)
