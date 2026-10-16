class_name ParkourUpdraft
extends Area3D
## 上升气流：**走进来就被往上托**，把人从低处送到 +5 m 的高台（被动式）。
##
## ── 数值怎么来的 ──
##   `player.gd` 离地时每帧自己扣 `GRAVITY = 20 m/s²`；这里给 **30 m/s²** 的向上加速度，
##   净上升 10 m/s²，封顶 **8 m/s**（不封顶会一进气流就窜到天上，落点全靠玄学）。
##   上升 5.4 m 的用时约 1 s。
##
## ── 「要蹬一下才出得来」是怎么实现的 ──
##   气流柱的顶层**比出口台面高一截**，人被托过台面之后气流的力就没了，
##   靠**空中操控**（`ACCEL_AIR = 9`）横移过去落在台面上 —— 所以站着不动是出不来的，
##   必须一直按住方向键。这也是自检里那条「按住 W 之后真的站上了出口台」的由来。

signal lifted(player: Node3D)

@export var accel := 30.0
@export var max_rise_speed := 8.0

var lifted_count := 0
## 自检用：气流里被托过的人里，达到过的最高点（世界 y）
var highest_seen := -INF
var _was_inside := false


func _physics_process(delta: float) -> void:
	var inside := false
	for b in get_overlapping_bodies():
		var p := b as Player
		if p == null:
			continue
		inside = true
		p.velocity.y = minf(p.velocity.y + accel * delta, max_rise_speed)
		highest_seen = maxf(highest_seen, p.global_position.y)
		if not _was_inside:
			lifted_count += 1
			lifted.emit(p)
			print("[Parkour] 上升气流 %s：托起 %s（第 %d 次）" % [name, p.name, lifted_count])
	_was_inside = inside
