extends SceneTree
## 量「第一次变机甲」到底卡在哪一步。
##
## 用户 2026-11-11：「机甲爱丽丝为什么第一次变身总是卡顿」。
## `carrier_form.gd::_build()` 里一串重活全在主线程同步做：
##   载具 GLB 的 `load()` / 借 18 条战斗动作（`AnimExtra.merge_glb_multi`）/
##   4 组特效构建（推进器 + 炮口 + 装饰层 + 光晕贴图）。
## 本探针把它们**分段计时**，再跑第二次做对照（第一次冷、第二次热）。
##
##   & <godot> --headless --path . --script res://scripts/_diag_carrier_build_cost.gd

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CARRIER_GLB := "res://models/Arisu_Battle_Carrier.glb"
const BORROW_GLB := "res://models/Arisu_Battle.glb"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("========== 第一次变身耗时分解 ==========")
	MechState.set_carrier_for_test(true)
	if not OS.get_cmdline_user_args().has("--prewarm"):
		# 冷启动：不预先 load，直接让 set_form 走完整条路（真实玩家路径）
		print("[cost] 冷启动模式（不预热；加 --prewarm 可对照热启动）")
		await _measure_cold()
		quit(0)
		return
	print("[cost] 预热对照模式")

	# ---- ① 冷启动：GLB 首次 load（含磁盘 + 反序列化 + LOD/材质处理）----
	var t := Time.get_ticks_msec()
	var a := load(CARRIER_GLB)
	var t_load_carrier := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	var b := load(BORROW_GLB)
	var t_load_borrow := Time.get_ticks_msec() - t
	print("① load 载具 GLB      %6d ms" % t_load_carrier)
	print("① load 借动作 GLB    %6d ms" % t_load_borrow)

	# ---- ② 实例化 + 骨架/动画器查找 ----
	var stage := Node3D.new()
	root.add_child(stage)
	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame
	var cf = player.get_node_or_null("Arisu/CarrierForm")
	if cf == null:
		push_error("[cost] 没有 CarrierForm")
		quit(1)
		return

	t = Time.get_ticks_msec()
	var ok1: bool = cf.call("set_form", true)
	var t_first := Time.get_ticks_msec() - t
	print("② 第一次 set_form(true)  %6d ms   ok=%s" % [t_first, str(ok1)])

	t = Time.get_ticks_msec()
	var ok2: bool = cf.call("set_form", false)
	var t_off := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	ok2 = cf.call("set_form", true)
	var t_second := Time.get_ticks_msec() - t
	print("③ set_form(false)        %6d ms" % t_off)
	print("③ 第二次 set_form(true)  %6d ms   （热：模型已建好，不走 _build）" % t_second)

	# ---- ④ 单独量 merge_glb_multi（借动作）这一步 ----
	var AnimExtra := load("res://scripts/anim_extra.gd")
	var ap = cf.get("_ap")
	var skel = cf.get("_skel")
	if AnimExtra != null and ap != null and skel != null:
		var clips := ["Move_Ing", "Normal_Idle", "Normal_Attack_Ing", "Normal_Reload",
			"Normal_Attack_Start", "Normal_Attack_End", "Normal_Attack_Delay",
			"Vital_Death", "Vital_Dying_Ing", "Vital_Panic", "Vital_Retreat",
			"Exs01", "Exs02_01", "Exs01_Cutin_01", "Exs01_Cutin_02",
			"Exs02_Cutin_01", "Exs02_Cutin_02", "Exs02_02"]
		t = Time.get_ticks_msec()
		var rep = AnimExtra.merge_glb_multi(ap, BORROW_GLB, {}, skel, clips)
		var t_borrow := Time.get_ticks_msec() - t
		print("④ 借 18 条动作（merge）  %6d ms" % t_borrow)

	print("")
	print("========== 结论 ==========")
	print("第一次变身总计 ≈ %d ms；其中 load 载具 %d ms + load 借动作 %d ms" % [
		t_first, t_load_carrier, t_load_borrow])
	print("第二次变身 %d ms（对照：应该几乎为 0）" % t_second)
	quit(0)


## 冷启动：完全不预热，只量 set_form(true) 自己 —— 这才是玩家第一次变身的体验。
func _measure_cold() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame
	var cf = player.get_node_or_null("Arisu/CarrierForm")
	if cf == null:
		push_error("[cost] 没有 CarrierForm")
		return
	# 模拟真实玩家：进场景后有几秒才会按 G —— 让预热协程跑完
	var waited := 0
	while waited < 180 and (not bool(cf.get("_prewarm_done")) or cf.get("_carrier") == null):
		await process_frame
		waited += 1
	print("[cost] 预热跑完 = %s（等了 %d 帧）" % [str(cf.get("_prewarm_done")), waited])
	print("[cost] 载具已预建 = %s" % str(cf.get("_carrier") != null))
	print("[cost] ResourceLoader.has_cached(载具) = %s" % str(ResourceLoader.has_cached(CARRIER_GLB)))
	var t := Time.get_ticks_msec()
	var ok: bool = cf.call("set_form", true)
	var first := Time.get_ticks_msec() - t
	print("★ 冷启动 第一次 set_form(true) = %d ms   ok=%s" % [first, str(ok)])
	t = Time.get_ticks_msec()
	cf.call("set_form", false)
	cf.call("set_form", true)
	print("  之后再次变身 = %d ms" % (Time.get_ticks_msec() - t))
	print("")
	print("⇒ 一帧 16.7 ms 的话，第一次变身相当于卡住约 %d 帧" % int(first / 16.7))
