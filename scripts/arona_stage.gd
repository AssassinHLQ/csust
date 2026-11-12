class_name AronaStage
extends Node3D
## 电脑屏幕里的**阿洛娜**（3D 模型 + 自己的相机/灯光，独立世界）。
##
## 用户 2026-11-12：「然后打 arona 可以出现电脑里面的阿洛娜，找 arona 的 live2d 看看能不能找到」。
##
## ── Live2D 找不到，只能走 3D ──
## 磁盘上（`C:\Users\WY157\Downloads` 全盘搜）**一个 Live2D 文件都没有**：
## `.moc3` / `.model3.json` / `.mtn` / `.can3` 全为空。搜到的是爱给网那个
## **3D 模型**：`碧蓝档案 阿罗娜 3d模型\source\[BlueArchive] - Arona.blend`（带 6 张贴图）。
## 所以用 Blender 后台模式把它转成 GLB：
##   blender --background --factory-startup --python _log/arona_export.py
## 产物 `models/arona/arona.glb`（1.14 MB，205 根骨骼的绑定模型，无动画）。
##
## ── 为什么要「独立世界」 ──
## 这段 3D 是塞在电脑屏幕那个 `SubViewport` 里的。`SubViewport` 默认**共用父场景的
## World3D** —— 那会把整个校园/小屋一起渲染进屏幕里。所以
## `hut_computer.gd` 里给那个 viewport 设了 `own_world_3d = true`，
## 再把这个舞台挂进去，屏幕里就只剩阿洛娜。
##
## ── 没有动画怎么办 ──
## 模型没有姿态动画（Blender 里那些 shape key 只有 Halo 有，而且是数值名）。
## 所以这里自己加一点点「活着」的感觉：轻微上下浮动 + 左右微摆 + 光环呼吸发光。
## 幅度都很小 —— 目的是「不是一张静止的贴图」，不是跳舞。

const GLB := "res://models/arona/arona.glb"

## 相机看哪儿：模型高度的这个比例处（0 = 脚底，1 = 头顶）。
## 0.90 ≈ 头部偏上，画面里是「头 + 肩」。
const LOOK_AT_RATIO := 0.90
## 画面里要塞进多高的模型（米）。越小 = 脸越大越近。
## ⚠️ 第一版是 0.62，结果脸大得顶满屏幕、下半张脸被对话框盖掉。
##    1.05 大约是「头 + 肩 + 一点胸口」。
const FRAME_HEIGHT := 1.05
## 把阿洛娜推到画面**右侧**（经典桌面助手布局：右边站人、左边放气泡）。
## 单位是相机视野里的世界单位，符号靠实测确定（见 `_build()` 里的注释）。
const SUBJECT_SHIFT_X := 0.15
## 竖向偏移：正值把模型往画面下方推。负值往上去 —— 往下跑会把胸口切出画面。
const SUBJECT_SHIFT_Y := -0.05
## 浮动 / 摆动的幅度与频率
const BOB_AMP := 0.010
const BOB_SPEED := 1.1
const SWAY_AMP := 0.9          # 度
const SWAY_SPEED := 0.55

var model: Node3D
var cam: Camera3D

var _t := 0.0
var _base_y := 0.0
var _halo_mats: Array[BaseMaterial3D] = []
var _halo_base_energy: Array[float] = []


func _ready() -> void:
	visible = false
	set_process(false)
	_build()


func _build() -> void:
	if not ResourceLoader.exists(GLB):
		push_warning("[Arona] 缺 %s —— 用 _log/arona_export.py 重新导出" % GLB)
		print("[Arona] !! 缺模型 %s" % GLB)
		return

	# ── 环境：给一点环境光，别让背光面死黑 ──
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.065, 0.085)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.80)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# ── 灯：主光 + 补光 + 一点冷色轮廓光（屏幕感）──
	_key_light(Vector3(1.4, 1.6, 2.2), Color(1.0, 0.96, 0.90), 2.1)
	_key_light(Vector3(-1.8, 0.6, 1.2), Color(0.72, 0.82, 1.0), 0.9)
	_key_light(Vector3(0.0, 1.2, -2.0), Color(0.55, 0.78, 1.0), 1.4)

	# ── 模型 ──
	model = (load(GLB) as PackedScene).instantiate() as Node3D
	add_child(model)

	# 用**网格包围盒**定位（骨架 rest pose 下 AABB 就够，不用算骨骼）
	var box := _mesh_aabb(model)
	var h := box.size.y
	var top := box.end.y
	if h < 0.001:
		h = 1.0
	var look_y := box.position.y + h * LOOK_AT_RATIO

	cam = Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.02
	cam.far = 100.0
	add_child(cam)
	# 相机放在脸正前方偏下一点，仰视一点点更精神
	var dist: float = (FRAME_HEIGHT * 0.5) / tan(deg_to_rad(cam.fov * 0.5))
	var target := Vector3(box.get_center().x, look_y, box.get_center().z)
	cam.position = target + Vector3(0.02, -0.04, dist)
	cam.look_at(target, Vector3.UP)
	# 横向/竖向偏移把阿洛娜推到画面右侧、偏上一点：
	# `h_offset` 正值让**画面向右移**（模型相对往左），所以这里要用负值才能把人推到右边。
	cam.h_offset = -SUBJECT_SHIFT_X
	cam.v_offset = SUBJECT_SHIFT_Y
	cam.make_current()

	# 让模型「站」在画面里：整体基准高度记下来，浮动从这里加减
	_base_y = model.position.y

	# ── 光环：收集材质，做呼吸发光 ──
	_collect_halo(model)

	print("[Arona] 模型就位：%s，尺寸 (%.2f, %.2f, %.2f) m，相机距离 %.2f m，光环材质 %d 个"
		% [GLB, box.size.x, box.size.y, box.size.z, dist, _halo_mats.size()])


func _key_light(pos: Vector3, col: Color, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = 8.0
	l.shadow_enabled = false
	add_child(l)


func _mesh_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		var b: AABB = m.transform * m.mesh.get_aabb()
		# 逐层往上乘到本舞台的坐标
		var n: Node = m
		while n != null and n != self:
			if n is Node3D:
				b = (n as Node3D).transform * b
			n = n.get_parent()
		out = b if first else out.merge(b)
		first = false
	return out


## 光环网格的材质名字里带 halo（`Aris_Original_Halo_001` 那个命名习惯一样）
##
## ⚠️ 原模型的 `Arona_Halo.png` 是一张**彩虹渐变**（大概是给发光/bloom 用的通道图），
##    直接当 albedo 贴图渲出来就是一圈细细的彩虹线 —— 不像阿洛娜那个蓝白光环。
##    所以这里**不用它的底色**：albedo 压成白色、改用自发光染成蓝白，让它像个光源。
func _collect_halo(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null:
			continue
		if not String(m.name).to_lower().contains("halo"):
			continue
		for s in m.mesh.get_surface_count() if m.mesh != null else 0:
			var mat := m.get_active_material(s)
			if mat is BaseMaterial3D:
				var b := mat as BaseMaterial3D
				b.albedo_color = Color(1, 1, 1)
				b.albedo_texture = null
				b.emission_enabled = true
				b.emission = Color(0.62, 0.84, 1.0)
				b.emission_energy_multiplier = 2.4
				_halo_mats.append(b)
				_halo_base_energy.append(2.4)


func set_active(on: bool) -> void:
	visible = on
	set_process(on)
	if on:
		_t = 0.0
	if cam != null and on:
		cam.make_current()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if model != null:
		# 上下浮动（呼吸）+ 极小幅左右摆
		model.position.y = _base_y + sin(_t * BOB_SPEED) * BOB_AMP
		model.rotation.y = deg_to_rad(sin(_t * SWAY_SPEED) * SWAY_AMP)
	# 光环呼吸
	for i in _halo_mats.size():
		var e: float = _halo_base_energy[i]
		_halo_mats[i].emission_energy_multiplier = e * (0.82 + 0.18 * sin(_t * 1.7 + float(i)))
