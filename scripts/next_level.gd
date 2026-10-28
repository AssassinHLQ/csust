extends Node3D
## 第二个场景（构成主义大厅）的关卡逻辑。
##
## 用户 2026-10-27：「完善第二个场景，做关卡，这次使用构成主义」。
## 建筑本体在 `scenes/constructivist_hall_baked.tscn`（`constructivist_hall.gd` 烘的），
## 本脚本只管玩法：
##   1. 从场景门进来时落在门前；直接跑这个场景则用 SpawnPoint
##   2. 收集场上 3 个 `Target`，击破全部 → 高台终点解锁（圆盘变亮、Area 开始监测）
##   3. 玩家踩上终点圆盘 → 「关卡完成」提示
##
## 靶子的 `respawn_time` 在场景里设成 9999 s —— 关卡里不许复活，不然「击破全部」
## 永远完不成。

const SceneFlow := preload("res://scripts/scene_flow.gd")

@onready var _player: Node3D = $Player
@onready var _hud: CanvasLayer = $HUD
@onready var _score: Label3D = $Scoreboard
@onready var _goal: Area3D = $Goal
@onready var _pad: MeshInstance3D = $Goal/Pad
@onready var _goal_light: OmniLight3D = $Goal/Light
@onready var _message: Label = $LevelUI/Message
@onready var _fall: Area3D = $FallReset
@onready var _campus: Node3D = get_node_or_null("Campus")
@onready var _door: Node3D = $ExitDoor

var _targets: Array = []
var _left := 0
var _total := 0
var _complete := false
var _door_open := false
## 校园泼溅只在「出了大厅、且朝着校园」时才打开：Compute 后端 615 万点每帧
## 固定成本约 500 ms，藏起来大厅里能 57 fps（实测 2.5 → 56.8）。
var _campus_shown := false
var _msg_tween: Tween
var _pad_off: Material
var _pad_on: Material


func _ready() -> void:
	var entry := SceneFlow.consume_entry()
	var gate := SceneFlow.find_gate(self, String(entry.get("gate", "")))
	var point: Vector3 = ($SpawnPoint as Node3D).global_position
	if gate != null:
		point = gate.call("arrival_point")
	_player.global_position = point
	_player.set("velocity", Vector3.ZERO)
	_hud.bind(_player, _player.get_node("Weapon"))

	for c in get_children():
		if c is Target:
			_targets.append(c)
	_total = _targets.size()
	_left = _total
	for t in _targets:
		if not t.died.is_connected(_on_target_died):
			t.died.connect(_on_target_died)

	_pad_off = _pad.get_surface_override_material(0)
	_pad_on = _make_pad_on(_pad_off)
	if not _goal.body_entered.is_connected(_on_goal_body):
		_goal.body_entered.connect(_on_goal_body)
	if not _fall.body_entered.is_connected(_on_fall):
		_fall.body_entered.connect(_on_fall)
	# 场上的泼溅（长沙理工校园）挂到 HUD 的状态行：解码进度/就绪都看得见
	var splats: Array = []
	for c in get_children():
		if c.has_method("force_start") and c.has_method("is_ready"):
			splats.append(c)
	if not splats.is_empty() and _hud.has_method("bind_splats"):
		_hud.bind_splats(splats)
	_set_goal_open(false)
	_update_scoreboard()
	_show_message("击破 %d 个机关 —— 东门会下沉，可以出去看校园" % _total, 5.0)
	print("[ConstructivistLevel] 关卡就绪：靶子 %d 个，玩家落点 %s"
		% [_total, str(point.snappedf(0.01))])
	SceneFlow.report_memory("构成主义关卡就绪")


func _make_pad_on(base: Material) -> Material:
	var m: StandardMaterial3D = (base as StandardMaterial3D).duplicate() \
		if base is StandardMaterial3D else StandardMaterial3D.new()
	m.albedo_color = Color(0.90, 0.16, 0.12)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.25, 0.16)
	m.emission_energy_multiplier = 2.6
	return m


func _on_target_died(_by: float) -> void:
	if _complete:
		return
	_left = maxi(_left - 1, 0)
	_update_scoreboard()
	if _left <= 0:
		_set_goal_open(true)
		_open_exit_door()
		_show_message("机关全部击破 —— 东门下沉，可以出去看校园", 6.0)
		Sfx.play("ui_open", -2.0)
		print("[ConstructivistLevel] 机关清空，终点解锁 + 东门开启")


func _set_goal_open(on: bool) -> void:
	# 这个函数可能在 `died` 信号的物理刷新里被调，直接改 monitoring 会被引擎拒绝
	_goal.set_deferred("monitoring", on)
	_goal_light.light_energy = 2.6 if on else 0.6
	_pad.set_surface_override_material(0, _pad_on if on else _pad_off)


func _on_goal_body(body: Node3D) -> void:
	if _complete or _left > 0:
		return
	if body == null or not body.is_in_group("player"):
		return
	_complete = true
	_goal.set_deferred("monitoring", false)
	_goal_light.light_energy = 4.5
	_show_message("关卡完成 · 构成主义大厅", 8.0)
	Sfx.play("ui_open")
	print("[ConstructivistLevel] 关卡完成（靶子 %d/%d）" % [_total - _left, _total])


## 掉出广场（校园泼溅没有碰撞，掉下去就是无底洞）→ 送回大厅出生点。
func _on_fall(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_player.global_position = ($SpawnPoint as Node3D).global_position
	_player.set("velocity", Vector3.ZERO)
	_show_message("掉出广场 —— 已送回大厅", 2.5)
	print("[ConstructivistLevel] 玩家掉出广场，已送回出生点")


## 东门下沉（动画 1.8 s），把碰撞一起沉到地板下面。
func _open_exit_door() -> void:
	if _door_open or _door == null:
		return
	_door_open = true
	var tw := create_tween()
	tw.tween_property(_door, "position:y", -3.3, 1.8) 		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	print("[ConstructivistLevel] 东门下沉")


func _process(_delta: float) -> void:
	_update_campus_visibility()


## 校园泼溅的可见性闸门：
##   · 还没加载完 → 不动（保持隐藏）
##   · 玩家还在大厅里 → **藏起来**（墙本来就挡着，没必要为它付每帧 500 ms）
##   · 出了大厅 → 一律显示
##
## ⚠️ 以前还有一条「朝着校园那半边才显示」的朝向判断，结果是玩家在广场上
##    一转身校园整片消失、只剩近乎全黑的背景色，看起来就像「突然没光照了」
##    （用户 2026-10-28 报）。朝向判断已删：宁可多付渲染成本，也不能让场景
##    在玩家转视角时凭空消失。
func _update_campus_visibility() -> void:
	if _campus == null or _player == null:
		return
	if not _campus.has_method("is_ready") or not bool(_campus.call("is_ready")):
		return
	var node := _campus.get("splat_node") as Node3D
	if node == null:
		return
	if not _campus_shown:
		node.visible = false
	var pos := _player.global_position
	var want := absf(pos.x) > 15.0 or absf(pos.z) > 10.0
	if want != _campus_shown or node.visible != want:
		_campus_shown = want
		node.visible = want
		print("[ConstructivistLevel] 校园泼溅 %s" % ("显示" if want else "隐藏（大厅里）"))


func _update_scoreboard() -> void:
	_score.text = "机关 %d / %d" % [_left, _total]


func _show_message(text: String, seconds: float) -> void:
	if _msg_tween != null and _msg_tween.is_valid():
		_msg_tween.kill()
	_message.text = text
	_message.visible = true
	_message.modulate = Color(1, 1, 1, 1)
	if seconds > 0.0:
		_msg_tween = create_tween()
		_msg_tween.tween_interval(seconds)
		_msg_tween.tween_property(_message, "modulate:a", 0.0, 0.8)
		_msg_tween.tween_callback(_hide_message)


func _hide_message() -> void:
	_message.visible = false