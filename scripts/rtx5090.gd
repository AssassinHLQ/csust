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
##   · 站在房子旁边（水平 2.0 m、竖直 −3.2~0.5 m）就自动收走 —— 屋顶 3 m 高，人上不去，
##     所以判定是「贴着屋檐走一圈就能拿」，不是要跳上屋顶；
##   · 收走后 `assets_yuan += 59999`，走 `ParkourFutures.add_asset()`，和内存条同一本账；
##   · 底下有个金色呼吸圈，远远能看见「这儿有件大货」。
##
## ⚠️ 模型轴不确定（OBJ 可能是 Y-up / Z-up），所以 `_build()` 里**按包围盒的最长轴**
##    自动转成「长边沿 X、平放」，再按最长边缩到 0.34 m（真卡 30~35 cm）。
const MODEL := "res://models/rtx5090/RTX5090simplified.obj"
## 全新正版现价（用户 2026-10-20 给的数）
const PRICE := 59999
const DISPLAY_NAME := "RTX 5090 24G"
## 收走判定
const PICK_RADIUS := 2.0
const PICK_DY_MIN := -3.2     # 人站在房檐下（比屋顶低 2.5 m）也能收
const PICK_DY_MAX := 0.5

var _holder: Node3D
var _taken := false
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

	# 旋转后的局部包围盒 → 统一缩放到「长边 0.34 m」，并把底面对齐到 y = 0
	var after := Transform3D(Basis.from_euler(_holder.rotation), Vector3.ZERO) * box
	var s := 0.34 / maxf(maxf(after.size.x, after.size.y), maxf(after.size.z, 0.001))
	_holder.scale = Vector3(s, s, s)
	_holder.position = Vector3(-after.get_center().x * s, -after.position.y * s,
		-after.get_center().z * s)

	# 金色呼吸圈（和地上内存条同款材质做法）
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.28
	cyl.bottom_radius = 0.28
	cyl.height = 0.02
	cyl.radial_segments = 28
	ring.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.84, 0.36, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.76, 0.25)
	mat.emission_energy_multiplier = 2.0
	ring.material_override = mat
	ring.position = Vector3(0.0, 0.02, 0.0)
	add_child(ring)
	rotate_y(0.6)            # 稍微斜放，别正对一条棱
	print("[Rtx5090] 屋顶 5090 就位：模型原始尺寸 %s → 缩放 %.2f（长边 0.34 m）"
		% [str(box.size.snappedf(0.01)), s])


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
	print("[Rtx5090] 占位卡就位（0.34 × 0.05 m，两个风扇）")


func _physics_process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var d := player.global_position - global_position
	if Vector2(d.x, d.z).length() > PICK_RADIUS:
		return
	if d.y < PICK_DY_MIN or d.y > PICK_DY_MAX:
		return
	_take()


func _take() -> void:
	_taken = true
	var fut := get_tree().get_first_node_in_group("futures")
	if fut != null and fut.has_method("add_asset"):
		fut.call("add_asset", DISPLAY_NAME, PRICE)
	else:
		push_warning("[Rtx5090] 场上没有 Futures，59999 没进资产账")
	Sfx.play("ui_toggle", 6.0)
	print("[Rtx5090] 收走屋顶的 RTX 5090 → 资产 +¥%d" % PRICE)
	visible = false
	queue_free()


## 自检用
func price() -> int:
	return PRICE


func taken() -> bool:
	return _taken
