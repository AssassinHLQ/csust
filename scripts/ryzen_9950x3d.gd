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
## 149 颗散在 609 屋顶上：单颗 12,386 面，合计 184 万面。从部室（约 50 m 外）看过去
## 每帧都要过一遍顶点 —— 实测站在部室东侧那个角，帧率 220 → 127（图元 30 万 → 214 万）。
## 但拾取半径只有 3.2 m，更远的 CPU 只有几个像素，画了纯属白烧。
## 22 m 外整颗不提交（引擎侧剔除，不是每帧脚本判断）；小物件也不投影。
##
## ── 距离分档（2026-11-04 用户：「走出 10 m 回退到 3000 网格面版本」）──
##   0 ~ 10 m  ：高模 12,386 面（`ryzen_9950x3d.glb`）
##   10 ~ 22 m ：低模 3,001 面（`ryzen_9950x3d_lod.glb`，`tools/decimate_cpu.py` 减出来的）
##   22 m 以外 ：整颗不提交
## 用 `visibility_range_begin/end` 做，是**引擎侧**切换，不进每帧脚本。
##
## ⚠️ 为什么不用 Godot 的自动 LOD：`lod_bias` 从 1 扫到 64，图元数一直是
##    459,287 ~ 460,051（实测，`_probe_cpu_distance.gd`）—— 引擎根本没切低模。
##    所以这里用**两份网格 + 可见距离**自己分档。
const MODEL_LOD := "res://models/cpu_9950x3d/ryzen_9950x3d_lod.glb"
## 用户 2026-11-04：「10m 缩到 5m」——5 m 外就换 3,001 面的低模。
const LOD_DISTANCE := 5.0
const VIEW_DISTANCE := 22.0
## 两档之间留一点重叠，避免正好站在 10 m 上时两边都不画
const LOD_OVERLAP := 0.5

var _built := false
var _taken := false
var _prompting := false
var _model: Node3D
var _model_lod: Node3D


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
		_build_lod()
	else:
		push_warning("[9950X3D] 没有 %s → 用程序化占位 CPU" % MODEL)
		_build_placeholder()
	_add_glow()
	_apply_view_range()


## 10 m 外换这个低模（3,001 面，`tools/decimate_cpu.py` 减出来的）。
## 缺文件就只是没有低模 —— 高模会一直画到 `VIEW_DISTANCE`，功能不受影响。
func _build_lod() -> void:
	var ps := load(MODEL_LOD) as PackedScene
	if ps == null:
		push_warning("[9950X3D] 没有低模 %s → 10 m 外仍用高模" % MODEL_LOD)
		return
	_model_lod = ps.instantiate() as Node3D
	_model_lod.name = "LodModel"
	_model_lod.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model_lod)


## 分档：高模 0~10 m、低模 10~22 m、22 m 外整颗不提交。
## 放在 `_build()` 末尾，占位模型和光环一视同仁。
##
## ⚠️ **自动 LOD 对这批模型无效**（2026-11-04 实测，`_probe_cpu_distance.gd`）：
##    `ryzen_9950x3d.glb.import` 里确实有 `meshes/generate_lods=true`，
##    但把 `lod_bias` 从 1 扫到 4 / 16 / 64，图元数一直是 459,287 ~ 460,051（全是噪声）。
##    所以这里不用引擎自动 LOD，改成**两份网格 + 可见距离**自己分档。
func _apply_view_range() -> void:
	# 高模：0 ~ LOD_DISTANCE
	if _model != null:
		_set_range(_model, 0.0, LOD_DISTANCE, 0.0,
			LOD_OVERLAP)
	# 低模：LOD_DISTANCE ~ VIEW_DISTANCE（起点往前压 LOD_OVERLAP，避免 10 m 处闪空）
	if _model_lod != null:
		_set_range(_model_lod, LOD_DISTANCE - LOD_OVERLAP, VIEW_DISTANCE, 0.0, 0.0)
	else:
		# 没有低模 → 高模直接撑到 VIEW_DISTANCE
		if _model != null:
			_set_range(_model, 0.0, VIEW_DISTANCE, 0.0, 0.0)
	# 光环：跟着整颗的可见距离
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if _under(mi, _model) or _under(mi, _model_lod):
			continue
		mi.visibility_range_end = VIEW_DISTANCE
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _set_range(root: Node3D, begin: float, end: float,
		begin_margin: float, end_margin: float) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.visibility_range_begin = begin
		mi.visibility_range_begin_margin = begin_margin
		mi.visibility_range_end = end
		mi.visibility_range_end_margin = end_margin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _under(n: Node, root: Node3D) -> bool:
	if root == null:
		return false
	var p := n.get_parent()
	while p != null:
		if p == root:
			return true
		p = p.get_parent()
	return false


## 桌子上的「宝藏」提示：CPU 底下垫一圈很细的金色光环（不挡视线）。
##
## ⚠️ 2026-11-04 实测（`_probe_cpu_cost.gd`，机位在 CPU 质心外 18 m）：
##      全开        图元 828,562   draw call 798
##      去掉光环    图元 775,186   draw call 659
##    → **光环一项就占 53,376 图元 / 139 次 draw call**，
##      而整批 CPU（网格 + 光环）总共才多 470,513 图元 / 142 次 draw call。
##      也就是说 **draw call 的涨幅 98% 来自光环**（149 个独立的细圆环）。
##    用户 2026-11-04：「光环去除看看」→ 默认关掉。
##    想开回来把 `GLOW_ENABLED` 改成 true 即可（其余代码不用动）。
const GLOW_ENABLED := false


func _add_glow() -> void:
	if not GLOW_ENABLED:
		return
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
	var d0 := player.global_position - global_position
	var body := player as CharacterBody3D
	var standing := body != null and body.is_on_floor()
	# 远的一律不参与（149 颗时省掉大部分扫描）
	if not standing or Vector2(d0.x, d0.z).length() > PICK_RADIUS + 1.0 \
			or absf(d0.y) > PICK_DY_MAX + 1.0:
		if _prompting:
			_prompting = false
			if fut != null:
				fut.clear_prompt(self)
		return
	# 只让**离玩家最近的那一颗**占用提示：149 颗挤在一起时，
	# 之前的「先到先得」会让远处那颗抢着 owner，按 F 捡到的不是脚下这颗。
	var near := _nearest(player) == self
	if near:
		if fut == null:
			return
		var owner := fut.prompt_owner()
		if owner == null or owner == self:
			_prompting = true
			fut.ask_prompt(self, "按 F 拾取 Ryzen 9 9950X3D（¥4,599 → 银行卡）")
		else:
			_prompting = false
	elif _prompting:
		_prompting = false
		if fut != null:
			fut.clear_prompt(self)


## 玩家拾取范围内、离得最近的一颗（都够不着时返回 null）
func _nearest(player: Node3D) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for c in get_tree().get_nodes_in_group("ryzen9950x3d"):
		if c == null or not is_instance_valid(c) or bool(c.get("_taken")):
			continue
		var n := c as Node3D
		var d := player.global_position - n.global_position
		if Vector2(d.x, d.z).length() > PICK_RADIUS or absf(d.y) > PICK_DY_MAX:
			continue
		var score := d.length_squared()
		if score < best_d:
			best_d = score
			best = n
	return best


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
