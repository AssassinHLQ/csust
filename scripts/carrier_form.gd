extends Node3D
## 阿比·埃舒（**载具形态**）：按 G 在「爱丽丝本体」和「载具」之间变形。
##
## 用户 2026-11-05：在第二场景**花钱找凯伊改装**之后要能真的用上。
##
## ── 为什么不做成「换皮肤」──
## `Arisu_Battle_Carrier.glb` 只有 **Idle / Walk 两条动作**（过场精简版），
## 拿它替掉玩家模型的话，`AnimDriver` 要的 `Normal_Idle` / `Normal_Attack_Ing` /
## `Move_Ing` 一条都没有 —— 所以这里**不接 AnimDriver**，自己按移动速度
## 在 Idle / Walk 之间交叉淡化，够用且不会报错。
##
## ── 优雅降级 ──
## 模型是本地素材（`models/*.glb` 已被 gitignore，不进仓库）：文件不在时
## 按 G 只打一条 warning，**不崩、也不影响本体**。
##
## ⚠️ 朝向：载具模型的脸朝哪一侧本喵没在窗口里看过，所以留 `facing_yaw_deg`
##    这个导出参数（默认 0）。要是看到它是倒着走的，把它改成 180 就行。

const MechState := preload("res://scripts/mech_state.gd")

const CARRIER_GLB := "res://models/Arisu_Battle_Carrier.glb"
## 交叉淡化时长（秒）
const FADE := 0.18
## 超过这个水平速度就播 Walk
const WALK_SPEED := 0.6

@export var toggle_key: Key = KEY_G
## 载具模型相对本体的额外偏航（度）。看到倒着走就改 180。
@export var facing_yaw_deg := 0.0
## 载具模型整体缩放（先用 1.0，看着不对再调）
@export var carrier_scale := 1.0

var _player: CharacterBody3D
var _model: Node3D
var _carrier: Node3D
var _ap: AnimationPlayer
var _on := false
var _cur_anim := ""


func _ready() -> void:
	_player = get_parent().get_parent() as CharacterBody3D   # Arisu → Player
	_model = get_node_or_null("../Model")
	set_process(false)


## 变形能不能用（解锁了 + 模型在）
func available() -> bool:
	return MechState.carrier_unlocked() and ResourceLoader.exists(CARRIER_GLB)


func is_on() -> bool:
	return _on


## 切到 / 切回。返回切换后是不是载具形态。
func set_form(on: bool) -> bool:
	if on == _on:
		return _on
	if on:
		if not MechState.carrier_unlocked():
			push_warning("[Carrier] 还没解锁（先在第二场景找凯伊改装）")
			return false
		if _carrier == null and not _build():
			return false
	_on = on
	if _model != null:
		_model.visible = not on
	if _carrier != null:
		_carrier.visible = on
	set_process(on)
	if on:
		_play("Idle", true)
	print("[Carrier] 变形 → %s" % ("阿比·埃舒（载具）" if on else "爱丽丝本体"))
	return _on


func toggle() -> bool:
	return set_form(not _on)


## 建载具实例：模型 + 脚底对齐 + 找 AnimationPlayer
func _build() -> bool:
	if not ResourceLoader.exists(CARRIER_GLB):
		push_warning("[Carrier] 没有载具模型：%s（本地素材，不随仓库分发）" % CARRIER_GLB)
		return false
	var ps := load(CARRIER_GLB) as PackedScene
	if ps == null:
		push_error("[Carrier] %s 不是有效的场景" % CARRIER_GLB)
		return false
	_carrier = ps.instantiate() as Node3D
	_carrier.visible = false
	add_child(_carrier)
	_align_feet()
	_carrier.rotation.y = deg_to_rad(facing_yaw_deg)
	_ap = _find_anim_player(_carrier)
	if _ap == null:
		# 没有 AnimationPlayer 也能用（只是站着不动），但要说一声
		push_warning("[Carrier] 载具模型里没找到 AnimationPlayer，只能静态显示")
	else:
		print("[Carrier] 载具就位：%s｜动作 %s" % [
			CARRIER_GLB.get_file(), str(_ap.get_animation_list())])
	return true


## 把模型脚底挪到节点原点（本体胶囊站在 y=0 上，模型也得对齐）
func _align_feet() -> void:
	var lo := INF
	var found := false
	for m in _meshes(_carrier):
		var aabb: AABB = (m as MeshInstance3D).get_aabb()
		# 用 8 个角在**局部**空间里取最低点（父链只有平移/旋转，够用）
		for i in 8:
			var p: Vector3 = m.transform * aabb.get_endpoint(i)
			lo = minf(lo, p.y)
			found = true
	if found:
		_carrier.position.y -= lo
	_carrier.scale = Vector3.ONE * carrier_scale


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer and not node.get_animation_list().is_empty():
		return node
	for c in node.get_children():
		var got := _find_anim_player(c)
		if got != null:
			return got
	return null


func _process(_delta: float) -> void:
	if _ap == null or _player == null:
		return
	var v := _player.velocity
	var speed := Vector2(v.x, v.z).length()
	_play("Walk" if speed > WALK_SPEED else "Idle", false)
	# 走快一点就把动画放快一点，免得脚底打滑
	if _cur_anim == "Walk":
		_ap.speed_scale = clampf(speed / 2.6, 0.6, 1.8)


func _play(name_: String, force: bool) -> void:
	if _ap == null or (not force and _cur_anim == name_):
		return
	if not _ap.has_animation(name_):
		return
	_cur_anim = name_
	_ap.speed_scale = 1.0
	_ap.play(name_, FADE)


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode != toggle_key:
		return
	# 对话/菜单暂停世界时不响应
	if get_tree().paused:
		return
	if toggle():
		get_viewport().set_input_as_handled()
