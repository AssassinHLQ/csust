class_name Ryzen9950x3d
extends Node3D

const BankCard := preload("res://scripts/bank_card.gd")
## 609 画室桌子上的 **AMD Ryzen 9 9950X3D**（2026-11 用户：
## 「在 609 上面放十颗，按市场价算，这是隐藏的福利」）。
##
## 价格：京东行情（2026-10）盒装自营 ¥4,819、第三方散片 ¥4,089~4,569，
## 取 **¥4,599/颗**（用户 2026-11：「就不翻倍了」）。屋顶一共 **149 颗**，
## 合计 ¥685,251 —— 速通路线，一趟刚好够买 67 万的整机。
##
## 模型：`models/cpu_9950x3d/ryzen_9950x3d.glb`。用户给的源文件是 SolidWorks
## `.SLDPRT`（Godot / Blender 都不认），所以按同目录参考图重建了低模：
## 蓝色基板 + 银色 IHS + 四排金手指 + IHS 丝印。参考素材来自爱给网，
## 仅供学习参考、不商用（见 CREDITS / credits.gd）。
##
## 手感：**站在地上 + 靠近**就亮「按 F 拾取」；一按就收，不用二次确认。
## 2026-11 用户：模型放大 3 倍（36 cm）、拾取范围加大、收进**银行卡**（速通路线）。

const MODEL := "res://models/cpu_9950x3d/ryzen_9950x3d.glb"
const PRICE := 4599
const DISPLAY_NAME := "AMD Ryzen 9 9950X3D"
const PICK_RADIUS := 3.2
const PICK_DY_MAX := 2.0
## 模型放大倍数（用户：「大一点，大三倍，不然很难捡到」）
const MODEL_SCALE := 3.0

var _built := false
var _taken := false
var _prompting := false
var _model: Node3D


func _ready() -> void:
	add_to_group("ryzen9950x3d")
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var ps := load(MODEL) as PackedScene
	if ps != null:
		_model = ps.instantiate() as Node3D
		_model.scale = Vector3.ONE * MODEL_SCALE
		add_child(_model)
	else:
		push_warning("[9950X3D] 没有 %s → 用程序化占位 CPU" % MODEL)
		_build_placeholder()
	_add_glow()


## 桌子上的「宝藏」提示：CPU 底下垫一圈很细的金色光环（不挡视线）。
func _add_glow() -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.062
	tm.outer_radius = 0.0645
	tm.rings = 24
	tm.ring_segments = 8
	ring.mesh = tm
	var g := StandardMaterial3D.new()
	g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	g.albedo_color = Color(1.0, 0.80, 0.32, 0.55)
	g.emission_enabled = true
	g.emission = Color(1.0, 0.74, 0.22)
	g.emission_energy_multiplier = 0.6
	ring.material_override = g
	ring.scale = Vector3.ONE * MODEL_SCALE
	ring.position.y = 0.001
	add_child(ring)


func _build_placeholder() -> void:
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.05, 0.17, 0.44)
	blue.roughness = 0.45
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.66, 0.68, 0.71)
	silver.metallic = 0.9
	silver.roughness = 0.3
	var pcb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.004, 0.12)
	pcb.mesh = bm
	pcb.material_override = blue
	pcb.position.y = 0.002
	add_child(pcb)
	var ihs := MeshInstance3D.new()
	var bm2 := BoxMesh.new()
	bm2.size = Vector3(0.09, 0.004, 0.09)
	ihs.mesh = bm2
	ihs.material_override = silver
	ihs.position.y = 0.006
	add_child(ihs)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _taken:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var fut := _futures()
	var d := player.global_position - global_position
	var flat := Vector2(d.x, d.z).length()
	var body := player as CharacterBody3D
	var standing := body != null and body.is_on_floor()
	var near := standing and flat <= PICK_RADIUS and absf(d.y) <= PICK_DY_MAX
	if near and not _prompting:
		_prompting = true
		if fut != null:
			fut.ask_prompt(self, "按 F 拾取 Ryzen 9 9950X3D（¥4,599 → 银行卡）")
	elif not near and _prompting:
		_prompting = false
		if fut != null:
			fut.clear_prompt(self)


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or _taken or not _prompting:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_F:
		return
	var fut := _futures()
	if fut == null or fut.prompt_owner() != self:
		return
	_take()
	get_viewport().set_input_as_handled()


func _futures() -> ParkourFutures:
	return get_tree().get_first_node_in_group("futures") as ParkourFutures


func _take() -> void:
	_taken = true
	_prompting = false
	var fut := _futures()
	if fut != null:
		fut.clear_prompt(self)
		fut.add_bank(PRICE, DISPLAY_NAME)
	else:
		BankCard.add(PRICE)
		push_warning("[9950X3D] 场上没有 Futures，¥%d 直接进银行卡" % PRICE)
	Sfx.play("ui_toggle", 4.0)
	print("[9950X3D] 收走一颗 Ryzen 9 9950X3D → 银行卡 +¥%d" % PRICE)
	queue_free()


## 自检用
func price() -> int:
	return PRICE


func taken() -> bool:
	return _taken
