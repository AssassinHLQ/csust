class_name Rtx5090
extends Node3D
## 屋顶上的 **RTX 5090**（2026-10-20 用户：「房子上面放一个 5090……5090 也是加入
## 资产的，全新正版现价 59999」）。
##
## 模型：`models/rtx5090/RTX5090simplified.obj`（用户从爱给网下的 OBJ，945 KB 简化版）。
## 摆位：由 `parkour.gd::_spawn_roof_gpu()` 挂到 `Island/Props/Shed`（最后平台的掩体）
## 屋顶上，局部 y = 2.4（屋顶顶面）。
##
## 手感：
##   · **必须站在屋顶、卡的正上方**才收得到（水平 1.5 m 内、脚落在屋顶高度附近，
##     而且 `is_on_floor()` 为真）—— 用户 2026-10-20：「为什么站这里都能捡到 5090，
##     必须站房顶 5090 正上方才行」。所以从屋檐下面、从空中掠过都收不到；
##   · 收走后 `assets_yuan += 59999`，走 `ParkourFutures.add_asset()`，和内存条同一本账；
##   · 屋顶底下那个金色呼吸圈已经删掉（同一天用户：「黄色圆圈去掉」）。
##
## ⚠️ 模型轴不确定（OBJ 可能是 Y-up / Z-up），所以 `_build()` 里**按包围盒的最长轴**
##    自动转成「长边沿 X、平放」，再按最长边缩到 `LONG_SIDE`。
const MODEL := "res://models/rtx5090/RTX5090simplified.obj"
## 全新正版现价（用户 2026-10-20 给的数）
const PRICE := 59999
const DISPLAY_NAME := "RTX 5090 24G"
## 摆放长度（m）。真卡 30~35 cm，但玩家在空中抓拍时「太小了」——
## 用户 2026-10-20：「5090 也太小了，加大 3 倍」→ 0.34 × 3 = 1.02 m。
const LONG_SIDE := 1.02
## 收走判定：水平 / 竖直窗口都收得很紧，保证「只有站屋顶正上方」才够得着
const PICK_RADIUS := 1.5
const PICK_DY_MIN := -0.25    # 比屋顶低 25 cm 以上（= 站在屋檐下）就收不到
const PICK_DY_MAX := 1.20

var _holder: Node3D
var _taken := false
var _prompting := false
var _confirming := false
var _t := 0.0


func _ready() -> void:
	add_to_group("rtx5090")
	_build()


func _build() -> void:
	var mesh := load(MODEL) as Mesh
	if mesh == null:
		# ⚠️ 这个 OBJ 的许可只到「学习交流」，`.gitignore` 排除了整个目录 ——
		#    克隆者没有它时不能把游戏搞崩：用一张程序化占位卡，功能（收走 + 59999）照旧。
		push_warning("[Rtx5090] 没有 %s（不随仓库分发）→ 用程序化占位卡" % MODEL)
		_build_placeholder()
		return
	var box := mesh.get_aabb()
	# 哪个轴最长，就把哪个轴转到 X 上（OBJ 常见 Y-up / Z-up 两种）
	var rot := Vector3.ZERO
	if box.size.y >= box.size.x and box.size.y >= box.size.z:
		rot = Vector3(0.0, 0.0, deg_to_rad(-90.0))
	elif box.size.z >= box.size.x and box.size.z >= box.size.y:
		rot = Vector3(0.0, deg_to_rad(90.0), 0.0)
	_holder = Node3D.new()
	_holder.rotation = rot
	add_child(_holder)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	_holder.add_child(mi)

	# 旋转后的局部包围盒 → 统一缩放到「长边 LONG_SIDE」，并把底面对齐到 y = 0
	var after := Transform3D(Basis.from_euler(_holder.rotation), Vector3.ZERO) * box
	var s := LONG_SIDE / maxf(maxf(after.size.x, after.size.y), maxf(after.size.z, 0.001))
	_holder.scale = Vector3(s, s, s)
	_holder.position = Vector3(-after.get_center().x * s, -after.position.y * s,
		-after.get_center().z * s)

	rotate_y(0.6)            # 稍微斜放，别正对一条棱
	print("[Rtx5090] 屋顶 5090 就位：模型原始尺寸 %s → 缩放 %.2f（长边 %.2f m）"
		% [str(box.size.snappedf(0.01)), s, LONG_SIDE])


## 没有 OBJ 时的占位卡：一块黑 PCB + 银灰罩子 + 两个风扇圈（尺寸和真卡对齐）。
func _build_placeholder() -> void:
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.06, 0.06, 0.07)
	black.metallic = 0.2
	black.roughness = 0.6
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.62, 0.64, 0.68)
	silver.metallic = 0.8
	silver.roughness = 0.35
	var pcb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.34, 0.012, 0.13)
	pcb.mesh = bm
	pcb.material_override = black
	pcb.position.y = 0.006
	add_child(pcb)
	var shroud := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.32, 0.03, 0.12)
	shroud.mesh = sm
	shroud.material_override = silver
	shroud.position.y = 0.03
	add_child(shroud)
	for sx in [-0.075, 0.075]:
		var fan := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.05
		cyl.height = 0.008
		cyl.radial_segments = 20
		fan.mesh = cyl
		fan.material_override = black
		fan.position = Vector3(sx, 0.046, 0.0)
		add_child(fan)
	# 和真模型一样放大 3 倍（0.34 → 1.02 m）
	scale = Vector3.ONE * (LONG_SIDE / 0.34)
	print("[Rtx5090] 占位卡就位（%.2f m 长，两个风扇）" % LONG_SIDE)


func _physics_process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var fut := _futures()
	var d := player.global_position - global_position
	var flat := Vector2(d.x, d.z).length()
	# ⚠️ 三件事同时成立才算「站在屋顶正上方」：
	#   ① 水平 1.5 m 内（人就在卡的上方）
	#   ② 脚的高度 = 屋顶高度（±0.25 m）—— 站在屋檐下时 d.y ≈ −2.5，够不着
	#   ③ 真的踩在东西上（`is_on_floor()`）—— 从空中掠过、跳起来那一下都不算
	var body := player as CharacterBody3D
	var standing := body != null and body.is_on_floor()
	var near: bool = flat <= PICK_RADIUS \
		and d.y >= PICK_DY_MIN and d.y <= PICK_DY_MAX and standing
	if near and not _confirming:
		if fut != null:
			fut.ask_prompt(self, "按 F 拾取 RTX 5090（¥59,999）")
		_prompting = true
	elif not near and _prompting:
		_prompting = false
		_confirming = false
		if fut != null:
			fut.clear_prompt(self)


## 第一次 F：弹「真的要拾取吗？」；第二次 F：确认收走 → 触发牢笼 + 倭瓜优香。
## 走开（离开范围）会把确认状态取消。
func _input(event: InputEvent) -> void:
	if _taken or not _prompting:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_F:
		return
	var fut := _futures()
	if fut == null or fut.prompt_owner() != self:
		return
	if not _confirming:
		_confirming = true
		fut.ask_prompt(self, "真的要拾取吗？再按 F 确认（走开取消）")
		Sfx.play("ui_toggle", 0.0)
	else:
		_take()
	get_viewport().set_input_as_handled()


func _futures() -> ParkourFutures:
	return get_tree().get_first_node_in_group("futures") as ParkourFutures


func _take() -> void:
	_taken = true
	_confirming = false
	_prompting = false
	if _futures() != null:
		_futures().clear_prompt(self)
	if _futures() != null:
		_futures().call("add_asset", DISPLAY_NAME, PRICE)
	else:
		push_warning("[Rtx5090] 场上没有 Futures，59999 没进资产账")
	Sfx.play("ui_toggle", 6.0)
	print("[Rtx5090] 收走屋顶的 RTX 5090 → 资产 +¥%d" % PRICE)
	# 触发陷阱：牢笼从信号塔顶滑下来 + 倭瓜优香出场（在 Parkour 那边实现）
	var n: Node = get_parent()
	while n != null and not (n is Parkour):
		n = n.get_parent()
	if n != null and n.has_method("trap_sequence"):
		n.call("trap_sequence")
	visible = false
	queue_free()


## 自检用
func price() -> int:
	return PRICE


func taken() -> bool:
	return _taken
