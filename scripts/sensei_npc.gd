extends Node3D
## 「老师」NPC：站在学生身后，不参战、不说话，只是**会呼吸**。
##
## ── 素材现状 ──
## `models/npc/sensei.glb` 是**卡通版**（Rigify 骨架 338 根骨、0 条动作、0 张贴图）：
## 绿皮肤 / 黑头发 / 马克笔画的五官，颜色全烘在顶点色里，材质的
## `baseColorFactor` 反而是黑的。旧版 MMD 素材（313 根骨、贴图齐全）在
## `_sensei_out/sensei_tex.glb` 留着，换 `model_path` 就能回去。
##
## ── 四个坑，都在这里兜住了 ──
## 1. **55 个 Rigify 控制骨骼小方块**（`cs_*`）：没蒙皮、按 rest 位置摆着，
##    合起来 11.18 × 3.25 × 4.44 m，不摘掉会把整个场景糊白。
## 2. **网格几乎整块绑在 `head.x` 上**。实测顶点组权重：`head.x` 25675 +
##    `c_head.x` 25374，而 26630 个顶点里手臂各骨加起来不到 60。
##    也就是说**转手臂骨一格都不动** —— T-pose 是焊死在顶点里的，
##    只能像 `_bend_arms_mesh()` 那样直接掰顶点。（旧 MMD 素材的 `左腕/右腕`
##    是真吃权重的，所以两条路都留着，见 `_relax_arms()` 的自动判断。）
## 3. **只有 0.985 m 高**（学生小雪 1.39 m），直接放进来老师比学生矮一头。
##    `target_height` 按包围盒自动缩放，并把脚底对齐到 y=0。
## 4. **在昏暗房间里会黑成剪影**：颜色靠顶点色，材质本身是黑的，
##    一加光照就没了。`flat_shading` 把材质改成 unshaded，顶点色原样输出。
##
## 模型不随仓库分发（`.gitignore` 里有 `/models/npc/**`），
## 克隆者只看到一行 warning，游戏照常跑。

## 模型路径。换人不改场景，改这个导出值就行。
@export var model_path := "res://models/npc/sensei.glb"
## 朝向：两代素材在 Godot 里都**脸朝节点的 +Z**（实测 az=0° 从 +Z 侧拍到正脸），
## 所以要 180° 才和同伴一样朝 −Z。这一条是渲图 `_probe_glb_shot.gd` 看出来的。
@export var facing_yaw_deg := 180.0
## 目标身高（米）。0 = 不缩放，用模型自带尺寸。
## 学生小雪 1.39 m，老师略高一头 → 1.62 m。
@export var target_height := 1.62
## 额外缩放系数（在 `target_height` 之上再乘）
@export var model_scale := 1.0
## 手臂下垂角度（度）。素材是 **T-pose**，不放下来像个木偶。
@export var arm_down_deg := 58.0
@export var elbow_deg := 10.0
## 平面色（卡通）着色：把材质改成 **unshaded**，不吃场景光照。
## 这份素材是靠顶点色画出来的，材质本身几乎全黑（`baseColorFactor = (0,0,0,1)`），
## 放在画室这种昏暗场景里会黑成一团剪影（渲图实测）。
@export var flat_shading := true
## 呼吸幅度（度）与频率（次/秒）
@export var breath_deg := 1.5
@export var breath_hz := 0.2

## Rigify 控制骨骼的网格前缀（`cs_solid_bar`、`cs_circle_ik` …），载入即删。
const CONTROL_PREFIX := "cs_"
## 每侧手臂骨的别名，**取第一个命中的**，避免同一根手臂被转两次。
const ARM_ALIASES := [
	["左腕", "左腕.L", "arm.l", "upper_arm.L", "Bip001 L UpperArm"],
	["右腕", "右腕.R", "arm.r", "upper_arm.R", "Bip001 R UpperArm"],
]
const ELBOW_ALIASES := [
	["左ひじ", "左ひじ.L", "forearm.l", "lower_arm.L", "Bip001 L Forearm"],
	["右ひじ", "右ひじ.R", "forearm.r", "lower_arm.R", "Bip001 R Forearm"],
]
## 手臂骨加起来占全部权重低于这个比例 → 判定「骨架没绑上手臂」，改掰顶点。
const ARM_WEIGHT_MIN := 0.05

var _skel: Skeleton3D
var _chest := -1
var _head := -1
var _chest_rest := Quaternion.IDENTITY
var _head_rest := Quaternion.IDENTITY
## 手臂的「放下」姿势（骨索引 → 四元数）
var _arm_rest := {}
var _t := 0.0


func _ready() -> void:
	rotation.y = deg_to_rad(facing_yaw_deg)
	if not ResourceLoader.exists(model_path):
		push_warning("[Sensei] 找不到模型：%s（老师不出现，游戏继续）" % model_path)
		return
	var ps := load(model_path) as PackedScene
	if ps == null:
		push_warning("[Sensei] %s 不是 PackedScene" % model_path)
		return
	var inst := ps.instantiate() as Node3D
	if inst == null:
		push_warning("[Sensei] %s 实例化失败" % model_path)
		return
	var stripped := _strip_control_shapes(inst)
	add_child(inst)
	if stripped > 0:
		print("[Sensei] 摘掉 %d 个骨架控制方块（%s*）" % [stripped, CONTROL_PREFIX])
	if flat_shading:
		var flattened := _flatten(inst)
		if flattened > 0:
			print("[Sensei] %d 个材质改成 unshaded（卡通平面色）" % flattened)
	_fit(inst)
	_skel = _find_skel(inst)
	_relax_arms(inst)
	if _skel == null:
		push_warning("[Sensei] 模型里没有 Skeleton3D，只做静态摆放")
		return
	# 骨名两代不同：MMD 是日文（上半身 / 頭），Rigify 是 spine_02.x / head.x。
	# 找不到就算了，不该因此报错。
	_chest = _bone(_skel, ["上半身", "上半身2", "spine_02.x", "spine_01.x", "Bip001 Spine1"])
	_head = _bone(_skel, ["頭", "head.x", "head", "Bip001 Head"])
	if _chest >= 0:
		_chest_rest = _skel.get_bone_pose_rotation(_chest)
	if _head >= 0:
		_head_rest = _skel.get_bone_pose_rotation(_head)


# ────────────────────────────── 清理 ──────────────────────────────

## 删掉 `cs_*` 控制方块。它们是 Rigify 的控制骨骼形状（方块 / 圆圈 / 箭头），
## 没蒙皮、按 rest 位置摆着，纯属给动画师看的，游戏里必须清掉。
func _strip_control_shapes(inst: Node) -> int:
	var hits: Array[Node] = []
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.name.begins_with(CONTROL_PREFIX):
			hits.append(n)
		for c in n.get_children():
			stack.append(c)
	for n in hits:
		var mi := n as MeshInstance3D
		mi.visible = false
		mi.mesh = null
		mi.queue_free()
	return hits.size()


## 把角色材质改成 unshaded，保留顶点色。
## 用 `surface_override_material` 而不是改原材质 —— `mesh` 是 **glb 里共享的资源**，
## 直接改会把同一份材质的其它东西一起改掉。
func _flatten(inst: Node) -> int:
	var n := 0
	for mi in _all_meshes(inst):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat is StandardMaterial3D:
				var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mi.set_surface_override_material(s, m)
				n += 1
	return n


## 按包围盒把模型缩到 `target_height`，并把**脚底**对到 y=0、水平居中。
func _fit(inst: Node3D) -> void:
	var box := _local_aabb(inst)
	if box.size.y <= 0.0001:
		push_warning("[Sensei] 包围盒是空的，跳过身高对齐")
		return
	var s := model_scale
	if target_height > 0.0:
		s *= target_height / box.size.y
	inst.scale = Vector3.ONE * s
	var raw := box.size.y
	box = _local_aabb(inst)
	var c := box.get_center()
	inst.position.x -= c.x
	inst.position.z -= c.z
	inst.position.y -= box.position.y
	print("[Sensei] 原始身高 %.3f m → 缩放到 %.3f m（×%.3f），脚底 y=0" % [raw, box.size.y, s])


## 量 `inst` 的网格包围盒，坐标空间是**本节点**（已扣掉 facing 旋转）。
func _local_aabb(inst: Node3D) -> AABB:
	var to_self := global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for mi in _all_meshes(inst):
		if not mi.is_visible_in_tree():
			continue
		var b: AABB = to_self * mi.global_transform * mi.get_aabb()
		if b.size.length() > 0.0001:
			out = b if first else out.merge(b)
			first = false
	return out


# ────────────────────────────── 手臂 ──────────────────────────────

## 把 T-pose 的平举手臂放下来。**两条路，自动选**：
## * 手臂骨真吃权重 → 转骨（旧 MMD 素材走这条）；
## * 网格几乎全绑在躯干/头骨上 → 直接掰顶点（卡通版素材走这条）。
func _relax_arms(inst: Node) -> void:
	var ratio := _arm_weight_ratio(inst)
	if _skel != null and ratio >= ARM_WEIGHT_MIN:
		print("[Sensei] 手臂骨占权重 %.0f%% → 转骨放下" % (ratio * 100.0))
		_pose_arms_by_bone()
	else:
		print("[Sensei] 手臂骨只占权重 %.1f%%（骨架没绑上）→ 直接掰顶点" % (ratio * 100.0))
		_bend_arms_mesh(inst)


## 手臂上四根骨（左右上臂 + 左右前臂）占全部蒙皮权重的比例。
## ⚠️ `ARRAY_BONES` 里存的是 **skin 的 bind 索引**，不是 `Skeleton3D` 的骨索引；
##    不经过 `Skin.get_bind_bone()` 换算，权重会全算到别的骨头上（踩过）。
func _arm_weight_ratio(inst: Node) -> float:
	if _skel == null:
		return 0.0
	var want: Array[int] = []
	for list in [ARM_ALIASES, ELBOW_ALIASES]:
		for pair in list:
			var i := _bone(_skel, pair)
			if i >= 0:
				want.append(i)
	if want.is_empty():
		return 0.0
	var arm := 0.0
	var total := 0.0
	for mi in _all_meshes(inst):
		if not (mi.mesh is ArrayMesh):
			continue
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_BONES == 0:
				continue
			var arr := mi.mesh.surface_get_arrays(s)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			for k in bones.size():
				var bi := _bind_to_bone(mi, bones[k])
				if bi < 0:
					continue
				total += weights[k]
				if want.has(bi):
					arm += weights[k]
	return 0.0 if total <= 0.0 else arm / total


## skin 的 bind 索引 → Skeleton3D 骨索引
func _bind_to_bone(mi: MeshInstance3D, bind: int) -> int:
	if bind < 0:
		return -1
	if mi.skin != null and bind < mi.skin.get_bind_count():
		var b := mi.skin.get_bind_bone(bind)
		if b >= 0:
			return b
		var nm := mi.skin.get_bind_name(bind)
		if nm != "":
			return _skel.find_bone(nm)
	return bind


## ── 路 A：转骨 ──
## T-pose 里两臂分别指向骨架 **+X**（左）和 **−X**（右），要「往下」就是绕 Z 转：
## `(1,0,0)` 绕 +Z 转 −θ 得到 `(cosθ, −sinθ, 0)`（往下）；右臂 `(−1,0,0)` 反而要 +θ。
## 夹到骨局部空间用的是**父骨**的 global rest 基（同 `pose_fix.gd` 那条教训）。
func _pose_arms_by_bone() -> void:
	_arm_rest.clear()
	for i in ARM_ALIASES.size():
		var idx := _bone(_skel, ARM_ALIASES[i])
		if idx < 0:
			continue
		var sign_f := -1.0 if i == 0 else 1.0
		var q := _delta(idx, Vector3(0.0, 0.0, 1.0), arm_down_deg * sign_f)
		_arm_rest[idx] = q
		_skel.set_bone_pose_rotation(idx, q)
	for i in ELBOW_ALIASES.size():
		var idx := _bone(_skel, ELBOW_ALIASES[i])
		if idx < 0:
			continue
		var sign_f := -1.0 if i == 0 else 1.0
		_skel.set_bone_pose_rotation(idx,
			_delta(idx, Vector3(0.0, 0.0, 1.0), elbow_deg * sign_f))


## ── 路 B：直接掰顶点 ──
## 以肩膀为轴，把 |x| 超过肩宽的手臂顶点绕 **Z 轴**（glTF 的前后轴）往下压。
##
## ⚠️ 只用 `|x| > 肩宽` 当掩码会把**脑袋一起掰了** —— 这是大头娃娃，头比肩还宽，
##    第一版渲出来整个头被拉成扁椭圆（踩过）。所以还要加一条**高度带**：
##    只有贴着肩线（±0.05~0.14 身高）的顶点才算手臂，头和头发一律豁免。
##
## 靠肩的一段用 smoothstep 渐变，避免肩关节被撕开。
## 绕 Z 转 θ：(x, y) → (x cosθ − y sinθ, x sinθ + y cosθ)，
## +X 侧要往下就得 θ < 0，所以两边符号相反。
func _bend_arms_mesh(inst: Node) -> void:
	var bent := 0
	for mi in _all_meshes(inst):
		var m := mi.mesh
		if not (m is ArrayMesh):
			continue
		var box := mi.get_aabb()
		if box.size.x <= 0.0001:
			continue
		var half := box.size.x * 0.5
		var h := box.size.y
		var cx := box.get_center().x
		var shoulder_y := box.position.y + h * 0.575
		var shoulder_dx := half * 0.17
		var blend := maxf(half * 0.22, 0.0001)
		var y_in := h * 0.05
		var y_out := h * 0.14
		var out := ArrayMesh.new()
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in verts.size():
				var v: Vector3 = verts[i]
				var side := 1.0 if v.x >= cx else -1.0
				var shoulder_x := cx + side * shoulder_dx
				var reach := absf(v.x - shoulder_x)
				if reach <= 0.0 or absf(v.x) < absf(shoulder_x):
					continue
				var w := _smoothstep(0.0, blend, reach) * (1.0 - _smoothstep(
					y_in, y_out, absf(v.y - shoulder_y)))
				if w <= 0.0001:
					continue
				var ang := -side * deg_to_rad(arm_down_deg) * w
				var pivot := Vector3(shoulder_x, shoulder_y, 0.0)
				var rel := v - pivot
				verts[i] = pivot + Vector3(
					rel.x * cos(ang) - rel.y * sin(ang),
					rel.x * sin(ang) + rel.y * cos(ang),
					rel.z)
				if i < normals.size():
					var nn := normals[i]
					normals[i] = Vector3(
						nn.x * cos(ang) - nn.y * sin(ang),
						nn.x * sin(ang) + nn.y * cos(ang),
						nn.z)
				bent += 1
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = normals
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, m.surface_get_material(s))
		if out.get_surface_count() > 0:
			mi.mesh = out
	print("[Sensei] 掰了 %d 个手臂顶点（-%.0f°）" % [bent, arm_down_deg])


func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / maxf(edge1 - edge0, 0.000001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 骨架空间里绕 `axis` 转 `deg`，夹到这根骨的局部空间。
func _delta(idx: int, axis: Vector3, deg: float) -> Quaternion:
	var g := Basis.IDENTITY
	var parent := _skel.get_bone_parent(idx)
	if parent >= 0:
		g = _skel.get_bone_global_rest(parent).basis.orthonormalized()
	var gq := g.get_rotation_quaternion()
	return (gq.inverse() * Quaternion(axis, deg_to_rad(deg)) * gq).normalized()


# ────────────────────────────── 待机 ──────────────────────────────

## 呼吸：肋骨起伏（上半身小幅俯仰）+ 头随呼吸极轻地点一下。
## 相位刻意错开 25%，两个动作不会像机械一样同时到顶。
##
## ⚠️ 卡通版素材里网格几乎全绑在 `head.x` 上，转 `head.x` 会带着**整个身体**动，
##    所以它的幅度压到 0.3°，看起来只是「整个人在轻轻呼吸」。
func _process(delta: float) -> void:
	if _skel == null:
		return
	_t += delta
	var w := TAU * breath_hz * _t
	if _chest >= 0:
		_skel.set_bone_pose_rotation(_chest,
			_chest_rest * Quaternion(Vector3.RIGHT, deg_to_rad(breath_deg * sin(w))))
	if _head >= 0:
		_skel.set_bone_pose_rotation(_head,
			_head_rest * Quaternion(Vector3.RIGHT,
				deg_to_rad(breath_deg * 0.3 * sin(w * 0.75 + 0.9))))


# ────────────────────────────── 工具 ──────────────────────────────

## 骨名查找：先严格匹配，再退化成「只留字母数字、小写」比较。
## glTF 里 `arm.l` 这种带点的名字进 Godot 可能被清洗，严格匹配会漏。
func _bone(sk: Skeleton3D, names: Array) -> int:
	for n in names:
		var i := sk.find_bone(n)
		if i >= 0:
			return i
	for n in names:
		var want := _norm(n)
		for b in sk.get_bone_count():
			if _norm(sk.get_bone_name(b)) == want:
				return b
	return -1


func _norm(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch >= "\u3040" and ch <= "\u30ff":
			out += ch
	return out


func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D and (x as MeshInstance3D).mesh != null:
			out.append(x as MeshInstance3D)
		for c in x.get_children():
			stack.append(c)
	return out


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null
