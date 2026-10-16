class_name ParkourBounce
extends Area3D
## 弹跳板：**踩上去就弹**（被动式，不用按键、不新增输入）。
##
## ── 为什么是「直接改 velocity.y」而不是加冲量 ──
## 玩家是 `CharacterBody3D`，没有刚体质量；`player.gd` 每帧只拿 `velocity` 做积分。
## 所以「弹」就是直接写它的竖直速度 —— 在 `body_entered` 里做，等价于「踩上去」。
##
## ⚠️ **高度是 `v² / (2 × GRAVITY)`，而玩家的重力是 20（不是 9.8）**：
##      需求里写的「11.5 级」只能给到 11.5²/40 = **3.31 m**，够不着 4.5 m 的高台。
##      要 +4.5 m 得 `v = √(2 × 20 × 4.5) = 13.42` —— 这里取 **13.5**（峰值 4.56 m），
##      目标高台放在 **+4.40 m**，留 16 cm 余量。
##    （`peak_height()` 直接拿 `Player.GRAVITY` 算，别把 20 抄第二遍。）
##
## ⚠️ 只允许「正在下落或站着」时弹：`velocity.y > 1` 时不弹，
##    否则落回来的一瞬间会被连弹、速度越叠越高。

signal bounced(power: float)

@export var launch_speed := 13.5
## 两次弹跳之间的冷却（秒），防同一帧里反复触发
@export var cooldown := 0.2
## 进区时竖直速度的上限：只有「站着 / 正在下落」的人会被弹。
## ⚠️ 少了这一条，从**侧面**蹭进区域（比如横跳擦边）也会被弹飞，玩家会觉得莫名其妙。
@export var max_entry_speed := 0.2

var hits := 0
var _ready_at := 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var p := body as Player
	if p == null:
		return
	if Time.get_ticks_msec() < _ready_at or p.velocity.y > max_entry_speed:
		return
	_ready_at = Time.get_ticks_msec() + int(cooldown * 1000.0)
	p.velocity.y = launch_speed
	hits += 1
	bounced.emit(launch_speed)
	Sfx.play("ui_toggle")
	print("[Parkour] 弹跳板 %s：把 %s 弹到 %.2f m（第 %d 次）"
		% [name, p.name, peak_height(), hits])


## 这块板能把人弹多高（v²/2g，用玩家自己的重力）
func peak_height() -> float:
	return launch_speed * launch_speed / (2.0 * Player.GRAVITY)
