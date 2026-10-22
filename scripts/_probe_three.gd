extends SceneTree
## 探针：一次量三件事（用户 2026-10-22）
##   ① 门把手离门板/门框多远（是不是飘在空气里）
##   ② 芹香：世界包围盒底在哪（站太高？）、待机动画到底播没播
##   ③ 准星：设备像素下真的居中吗（四条臂是否对称）
##   godot --path . --script res://scripts/_probe_three.gd
func _initialize() -> void:
	_run.call_deferred()


func _world_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var all: Array = []
	if node is MeshInstance3D:
		all.append(node)
	all.append_array(node.find_children("*", "MeshInstance3D", true, false))
	for n in all:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var a := mi.global_transform * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _run() -> void:
	var sz := Vector2i(int(OS.get_environment("PROBE_W")), int(OS.get_environment("PROBE_H")))
	if sz.x < 320:
		sz = Vector2i(1600, 900)
	root.size = sz
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false

	# ── ① 门把手 ────────────────────────────────────────────────
	var proxy := game.get_node_or_null("RoomProxy") as Node3D
	print("── ① 门把手 ──")
	if proxy != null:
		var knob := proxy.get_node_or_null("DoorKnob") as Node3D
		var panel := proxy.get_node_or_null("DoorPanel") as MeshInstance3D
		if knob != null and panel != null:
			var ka := _world_aabb(knob)
			var pa := _world_aabb(panel)
			print("  把手中心 %s  半径 %.3f" % [
				str(ka.get_center().snappedf(0.001)), ka.size.y * 0.5])
			print("  门板 AABB  pos=%s size=%s" % [
				str(pa.position.snappedf(0.001)), str(pa.size.snappedf(0.001))])
			# 门板最外表面（x+ 面）到把手中心的距离
			var face := pa.position.x + pa.size.x
			print("  门板外表面 x=%.3f  把手中心 x=%.3f  → 悬空 %.3f m" % [
				face, ka.get_center().x, ka.get_center().x - face])
			print("  把手是否落在门板薄片厚度内：%s" % str(
				absf(ka.get_center().x - face) <= ka.size.y * 0.5 + 0.001))
		else:
			print("  没有 DoorKnob 或 DoorPanel")

	# ── ② 芹香 ─────────────────────────────────────────────────
	print("── ② 芹香 ──")
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk != null:
		var a := _world_aabb(clerk)
		print("  世界 AABB pos=%s size=%s → 脚底 y=%.3f、头顶 y=%.3f（地面 y=0）" % [
			str(a.position.snappedf(0.001)), str(a.size.snappedf(0.001)),
			a.position.y, a.position.y + a.size.y])
		print("  MODEL_SCALE=%.2f  CLERK_LIFT=%.2f  ground_lift=%.2f" % [
			float(clerk.get("MODEL_SCALE")), float(clerk.get("CLERK_LIFT")),
			float(clerk.get("ground_lift"))])
		var ap := clerk.get("_idle") as AnimationPlayer
		if ap == null:
			print("  ❌ 没有拿到 AnimationPlayer（动画没播）")
			for n in clerk.find_children("*", "AnimationPlayer", true, false):
				print("     找到 AnimationPlayer：%s，动画 %d 条" % [
					(n as AnimationPlayer).name, (n as AnimationPlayer).get_animation_list().size()])
		else:
			var an := ap.current_animation
			var anim := ap.get_animation(an)
			print("  当前动画「%s」：playing=%s length=%.3f s loop=%s tracks=%d 位置=%.3f s" % [
				an, str(ap.is_playing()), anim.length if anim else -1.0,
				str(anim.loop_mode) if anim else "?",
				anim.get_track_count() if anim else -1, ap.current_animation_position])
			if anim != null:
				var moving := 0
				for i in anim.get_track_count():
					if anim.track_get_key_count(i) > 1:
						moving += 1
				print("     有 >1 个关键帧的轨道：%d / %d（0 就是一条静止姿势）" % [
					moving, anim.get_track_count()])
		var list := []
		for n in clerk.find_children("*", "AnimationPlayer", true, false):
			list = (n as AnimationPlayer).get_animation_list()
			break
		print("  可用动画（前 12 条）：%s" % str(list.slice(0, 12)))
	else:
		print("  没有 ClerkSerika")

	# ── ③ 准星 ─────────────────────────────────────────────────
	print("── ③ 准星 ──")
	var hud := game.get_node_or_null("HUD")
	if hud != null:
		var ch := hud.get("crosshair") as Control
		var vp := root
		var xf := vp.get_final_transform()
		var canvas := vp.get_visible_rect().size
		var s: float = hud.call("crosshair_scale")
		print("  画布逻辑 %s  设备缩放 %.4f  设备尺寸 %s" % [
			str(canvas), s, str(xf * canvas)])
		var centre_dev := xf * (canvas * 0.5)
		print("  画布中心（设备px，未取整）%s" % str(centre_dev.snappedf(0.01)))
		for nm in ["Dot", "T", "B", "L", "R"]:
			var c := ch.get_node_or_null(nm) as Control
			if c == null:
				continue
			var r := c.get_global_rect()
			var d0 := xf * r.position
			var d1 := xf * (r.position + r.size)
			print("   %-3s 设备px [%.1f, %.1f] ~ [%.1f, %.1f]  宽 %.1f 高 %.1f  中心 %s" % [
				nm, d0.x, d0.y, d1.x, d1.y, d1.x - d0.x, d1.y - d0.y,
				str(((d0 + d1) * 0.5).snappedf(0.01))])
		var th := ch.get_node_or_null("T") as Control
		var bb := ch.get_node_or_null("B") as Control
		var ll := ch.get_node_or_null("L") as Control
		var rr := ch.get_node_or_null("R") as Control
		if th and bb and ll and rr:
			var top := xf * th.get_global_rect().position
			var bot := xf * bb.get_global_rect().position
			var lef := xf * ll.get_global_rect().position
			var rig := xf * rr.get_global_rect().position
			print("  上下臂 x 起点差 %.2f px（应为 0）；左右臂 y 起点差 %.2f px（应为 0）" % [
				top.x - bot.x, lef.y - rig.y])
			print("  竖直臂相对画布中心 x 偏差 %.2f px；水平臂 y 偏差 %.2f px" % [
				top.x - centre_dev.x, lef.y - centre_dev.y])
	quit(0)
