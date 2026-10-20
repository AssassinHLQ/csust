extends SceneTree
## 量一下倭瓜优香（`models/boss_squash/倭瓜优香.obj`）的包围盒，按 `height = 3.0` 归一化
## 之后正面到底有多宽 —— 用来定普通攻击的预警圈半径（不能比它自己身体还小，
## 也不能一贯就到 3 m 外）。
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "res://models/boss_squash/倭瓜优香.obj"
	var res = load(path)
	if res == null:
		print("PROBE 加载失败：", path)
		quit(1)
		return
	var box := AABB()
	var first := true
	if res is Mesh:
		box = (res as Mesh).get_aabb()
		first = false
	var h := 3.0
	var size := box.size
	var k := h / maxf(size.y, 0.0001)
	print("PROBE 原始 AABB size = (%.3f, %.3f, %.3f)  pos = (%.3f, %.3f, %.3f)" % [
		size.x, size.y, size.z, box.position.x, box.position.y, box.position.z])
	print("PROBE 归一化到 height=3.0 的缩放 k = %.4f" % k)
	print("PROBE 缩放后 高 %.3f m / 宽(x) %.3f m / 深(z) %.3f m / 半宽 %.3f m" % [
		size.y * k, size.x * k, size.z * k, maxf(size.x, size.z) * k * 0.5])
	quit(0)
