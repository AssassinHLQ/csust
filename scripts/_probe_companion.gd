extends SceneTree
## 探针：三只同伴（未花 / 优香 / 诺亚）的 GLB 导入结果。
## 除了尺寸和动画名，重点回答一个几何问题：**模型自己朝哪边**。
##
## 朝向判定靠骨骼而不是猜：人形骨架的「脚趾骨」相对「脚踝骨」一定指向身体正前方，
## 所以 (Toe − Foot) 在 XZ 上的方向就是模型的本体前方。
## Arisu 的 GLB 实测是 −Z（player.tscn 里那个 180° 的旋转就是把它掰成 +Z 的）。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_companion.gd

const MODELS := {
	"未花 Mika": "res://models/companions/Mika.glb",
	"优香 Yuuka": "res://models/companions/Yuuka.glb",
	"诺亚 Noa": "res://models/companions/Noa.glb",
	"小桃 Momoi": "res://models/companions/Momoi.glb",
	"小绿 Midori": "res://models/companions/Midori.glb",
	"柚子 Yuzu": "res://models/companions/Yuzu.glb",
	"凯伊 Kei": "res://models/companions/Kei.glb",
	"（对照）Arisu": "res://models/Arisu_ext.glb",
}

## 跟随要用的三个动作
const WANTED := ["Normal_Idle", "Cafe_Idle", "Cafe_Walk", "Move_Ing", "Move_Jump"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for label in MODELS.keys():
		await _report(label, MODELS[label])
	quit(0)


func _report(label: String, path: String) -> void:
	print("\n============================================================")
	print("【%s】%s" % [label, path])
	if not ResourceLoader.exists(path):
		print("  ❌ 读不到（先跑一次 --import）")
		return
	var packed: PackedScene = load(path)
	var node: Node = packed.instantiate()
	root.add_child(node)
	await process_frame
	await process_frame

	var meshes := _all(node, "MeshInstance3D")
	print("  网格 %d 个" % meshes.size())

	# GLB 根节点自己带不带旋转？—— 这一层最容易被忽略：
	# companion.gd 只动 Rig，根节点如果自带 180°，那「Rig 不动」并不等于「脸朝 +Z」。
	var n3 := node as Node3D
	if n3 != null:
		print("  根节点 rotation = %s   basis.z(前) = %s" % [
			str(n3.rotation_degrees.snappedf(0.01)),
			str(n3.global_transform.basis.z.snappedf(0.01))])

	var skels := _all(node, "Skeleton3D")
	var best: Skeleton3D = null
	for s in skels:
		var sk := s as Skeleton3D
		if best == null or sk.get_bone_count() > best.get_bone_count():
			best = sk
	if best == null:
		print("  ❌ 没有 Skeleton3D")
	else:
		print("  Skeleton3D %d 个，主骨架「%s」%d 骨" % [
			skels.size(), best.name, best.get_bone_count()])
		_report_bone_names(best)
		_report_facing(best)
		_report_eye_facing(best)
		_report_bone_height(best)

	var aps := _all(node, "AnimationPlayer")
	for a in aps:
		var ap := a as AnimationPlayer
		var list := ap.get_animation_list()
		print("  AnimationPlayer「%s」%d 个动作" % [ap.name, list.size()])
		for w in WANTED:
			if ap.has_animation(w):
				print("      ✓ %-14s 时长 %.3f s  循环=%s" % [
					w, ap.get_animation(w).length,
					ap.get_animation(w).loop_mode != Animation.LOOP_NONE])
			else:
				print("      ✗ %-14s 缺失" % w)

	var aabb := _visual_aabb(node)
	print("  视觉包围盒 size = %s（y %.3f … %.3f）" % [
		str(aabb.size.snappedf(0.001)), aabb.position.y,
		aabb.position.y + aabb.size.y])
	print("  身高 %.3f m → 若要统一到 1.62 m，scale ≈ %.4f" % [
		aabb.size.y, 1.62 / maxf(aabb.size.y, 0.0001)])

	node.queue_free()
	await process_frame


## 没有 Toe 骨时的兜底判据：**两眼中点 − 头骨**。
##
## 为什么需要：小桃 / 小绿 的骨架里没有 Toe 骨（只有 Foot），Toe−Foot 判不了。
## 眼骨判据的缺点是「眼骨在头局部带横向偏移」，绝对值可能差几十度；
## 但这里只要**方向落在哪个半轴**（+Z / −Z），够用。
func _report_eye_facing(skel: Skeleton3D) -> void:
	var eyes: Array[int] = []
	var head := -1
	for i in skel.get_bone_count():
		var low := skel.get_bone_name(i).to_lower()
		if low.contains("eye"):
			eyes.append(i)
		if head < 0 and low.contains("head"):
			head = i
	if eyes.size() < 2 or head < 0:
		print("      眼骨判据：eye 骨 %d 个 / head %s，判不了" % [
			eyes.size(), "有" if head >= 0 else "无"])
		return
	var xf2 := skel.global_transform
	var mid := Vector3.ZERO
	for e in eyes:
		mid += xf2 * skel.get_bone_global_pose(e).origin
	mid /= float(eyes.size())
	var d := mid - (xf2 * skel.get_bone_global_pose(head).origin)
	d.y = 0.0
	if d.length() < 0.0001:
		print("      眼骨判据：两眼中点与头骨重合，判不了")
		return
	var n := d.normalized()
	print("      眼骨判据：两眼中点 − 头骨 = %s → 脸朝 %.1f° 的 XZ 方向（含横向偏移，只看半轴）" % [
		str(d.snappedf(0.001)), rad_to_deg(atan2(n.x, n.z))])
	if n.z < -0.3:
		print("      ⇒ 脸朝 **−Z**（与 Arisu 同一套导出，Rig 补 180°）")
	elif n.z > 0.3:
		print("      ⇒ 脸朝 **+Z**（不需要补 180°）")
	else:
		print("      ⇒ 脸朝 ±X：横向偏移太大，判不准，需要渲图定夺")


func _report_bone_names(skel: Skeleton3D) -> void:
	var hits: Array[String] = []
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i)
		var low := n.to_lower()
		if low.contains("toe") or low.contains("foot") or low.contains("head") \
				or low.contains("neck"):
			hits.append("%d:%s" % [i, n])
	print("      关键骨（前 14）：%s" % ", ".join(hits.slice(0, 14)))


## (Toe − Foot) 的 XZ 方向 = 模型本体前方。
##
## ⚠️ 必须把骨骼点乘上 `skel.global_transform` 才是**模型空间**的方向。
##    这批 GLB 的 Skeleton3D 节点自带 180°，只算骨骼空间会得到**反的符号**
##    —— 2026-10-14 就是这么把「本体朝 +Z」判成「本体朝 −Z」的，
##    害得 companion.gd 给 Rig 多补了 180°，七只同伴全在倒着走。
func _report_facing(skel: Skeleton3D) -> void:
	var toes: Array[int] = []
	var feet: Array[int] = []
	for i in skel.get_bone_count():
		var low := skel.get_bone_name(i).to_lower()
		if low.contains("toe"):
			toes.append(i)
		elif low.contains("foot") or low.contains("ankle"):
			feet.append(i)
	if toes.is_empty() or feet.is_empty():
		print("      朝向：骨名里没有 Toe/Foot，判不了（看下面的眼骨判据）")
		return
	var xf := skel.global_transform
	var to_p: Vector3 = xf * skel.get_bone_global_pose(toes[0]).origin
	var fr_p: Vector3 = xf * skel.get_bone_global_pose(feet[0]).origin
	var d := to_p - fr_p
	d.y = 0.0
	if d.length() < 0.0001:
		print("      朝向：Toe 与 Foot 重合，判不了")
		return
	d = d.normalized()
	var ang := rad_to_deg(atan2(d.x, d.z))
	print("      「%s」−「%s」= %s → 本体前方 ≈ %.1f° 处的 XZ 方向 %s（模型空间）" % [
		skel.get_bone_name(toes[0]), skel.get_bone_name(feet[0]),
		str((to_p - fr_p).snappedf(0.001)), ang, str(d.snappedf(0.001))])
	if d.z < -0.5:
		print("      ⇒ 本体朝 **−Z**（Rig 要补 180° 才是「节点 +Z = 脸」）")
	elif d.z > 0.5:
		print("      ⇒ 本体朝 **+Z**（Rig 不要动，「节点 +Z = 脸」直接成立）")
	else:
		print("      ⇒ 本体朝 ±X，属于侧向，需要额外偏航")


## 身高别用网格包围盒量：蒙皮网格的 AABB 是绑定姿态的，还会把武器/挂件算进去
## （实测 Arisu y 从 −0.564 起、诺亚只有 1.125 m，都是被这么污染的）。
## 用 Head 骨 − Foot 骨 最干净，顺便给出脚底相对模型原点的偏移。
func _report_bone_height(skel: Skeleton3D) -> void:
	var head := -1
	var foot := -1
	for i in skel.get_bone_count():
		var low := skel.get_bone_name(i).to_lower()
		if head < 0 and low.contains("head"):
			head = i
		if foot < 0 and (low.contains("toe") or low.contains("foot")):
			foot = i
	if head < 0 or foot < 0:
		print("      骨骼高度：找不到 Head 或 Foot 骨，跳过")
		return
	var hy := skel.get_bone_global_pose(head).origin.y
	var fy := skel.get_bone_global_pose(foot).origin.y
	print("      骨骼高度：Head y = %.3f，Foot y = %.3f → 身高 ≈ %.3f m；脚底原点偏移 %.3f m" % [
		hy, fy, hy - fy, fy])


func _all(node: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		if n.is_class(cls):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _visual_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in _all(node, "VisualInstance3D"):
		var vi := m as VisualInstance3D
		var box := vi.get_aabb()
		if box.size.length() <= 0.0001:
			continue
		var b := vi.global_transform * box
		out = b if first else out.merge(b)
		first = false
	return out
