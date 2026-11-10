extends SceneTree
## 自检：机甲飞行特效细化（噪声焰面 + 喷口激波环）。
##
## 用户 2026-11-10：「继续细化飞行特效」（此前：「机甲特效不好看,不够细致」）。
##
## 这一轮加了两样东西，本探针逐一核实**它们真的建出来了**：
##   ① 焰面噪声贴图（`_flame_noise_tex`）：非空、尺寸 128、**不是纯色**
##      （纯色 = 噪点做废了，出图还是塑料片）
##   ② 每个推进器各挂 2 个激波环（`rings`），且材质是加色混合
##   ③ 驱动的核心：跑几帧后环的 scale/透明度在变（不是死的）
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_verify_carrier_fx.gd

const GAME := "res://scenes/game.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _run() -> void:
	print("========== 机甲飞行特效细化自检 ==========")
	# ① 噪声贴图：静态生成器（`_flame_noise_tex_or_make` 不是 static，
	#    本来应该加 static —— 它用的是 static 变量 `_flame_noise_tex`。
	#    先按现状调：拿一份实例来叫它（`carrier_form.gd` 是 Node3D 子类，
	#    `new()` 出来的实例在 headless 下不 _ready，只调这一个纯函数是安全的）。
	var CarrierForm := load("res://scripts/carrier_form.gd") as GDScript
	_check(CarrierForm != null, "carrier_form.gd 能加载")
	if CarrierForm == null:
		_finish()
		return
	var tmp := CarrierForm.new()
	if tmp == null:
		_check(false, "实例化 carrier_form")
		_finish()
		return
	var tex: ImageTexture = tmp.call("_flame_noise_tex_or_make")
	_check(tex != null, "生成出噪声贴图")
	if tex == null:
		tmp.free()
		_finish()
		return
	var img := tex.get_image()
	if img == null:
		_check(false, "噪声贴图能取到 Image")
		tmp.free()
		_finish()
		return
	print("  噪声贴图尺寸 = %s" % str(img.get_size()))
	_check(img.get_width() == 128 and img.get_height() == 128,
		"尺寸 128×128（实际 %s）" % str(img.get_size()))

	# ② 不是纯色：抽样统计 min/max 差距
	var lo := 2.0
	var hi := -1.0
	var sum := 0.0
	var n := 0
	for y in range(0, 128, 7):
		for x in range(0, 128, 7):
			var c := img.get_pixel(x, y)
			lo = minf(lo, c.r)
			hi = maxf(hi, c.r)
			sum += c.r
			n += 1
	var avg := sum / maxf(float(n), 1.0)
	print("  噪声亮度：min=%.2f max=%.2f 平均=%.2f" % [lo, hi, avg])
	_check(hi - lo > 0.25,
		"噪声有明显起伏（max-min = %.2f > 0.25）—— 不是纯色" % (hi - lo))
	_check(avg > 0.25 and avg < 0.95,
		"平均亮度在合理区间 %.2f（不至于全黑或全白）" % avg)

	# ③ 材质确实用了这张贴图
	var mat: StandardMaterial3D = tmp.call("_make_flame_mat",
		Color(0.85, 0.96, 1.0, 0.95))
	tmp.free()
	_check(mat != null, "造出火焰材质")
	if mat != null:
		_check(mat.albedo_texture == tex, "火焰材质挂上了噪声贴图")
		_check(absf(mat.uv1_scale.y - 3.0) < 0.01,
			"UV 在 Y 方向拉伸 3 倍（实际 %.1f）—— 竖向火舌" % mat.uv1_scale.y)
		_check(mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "仍是加色混合")

	# ④ 进关卡：看推进器上真的挂了两个环
	var ps := load(GAME) as PackedScene
	var level := ps.instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 15:
		await process_frame

	var player := level.get_node_or_null("Player")
	if player == null:
		print("  （没有 Player，跳过场景内检查）")
		_finish()
		return
	var carrier := player.get_node_or_null("Arisu/CarrierForm")
	if carrier == null:
		print("  （没有 CarrierForm，跳过场景内检查）")
		_finish()
		return

	# ⚠️ 推进器 FX **只在变形时才建**（`carrier_form.gd::_build()` 里调
	#    `_build_boost_fx()`，而 `_build()` 由 `set_form(true)` 触发）。
	#    所以必须先真的变形一次，否则 `_boost_fx` 永远是空的
	#    —— 本探针第一版就是这样，9 项全 PASS 但**根本没检查到环**。
	print("  触发变形（建推进器 FX）…")
	# ⚠️ 必须先解锁：`set_form(true)` 开头就查 `MechState.carrier_unlocked()`，
	#    没解锁直接 return false（本探针第一版就是这么空的）。
	#    这是**探针专用**的绕过 —— 正式玩法里要玩家自己去第二场景找凯伊改装。
	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	if MechStateScript != null:
		MechStateScript.call("set_carrier_for_test", true)
	var ok_form: bool = bool(carrier.call("set_form", true))
	_check(ok_form, "变形到机甲形态成功")
	for _i in 25:
		await process_frame

	var fx_list: Array = carrier.get("_boost_fx")
	print("  推进器 FX 节点数 = %d" % fx_list.size())
	if fx_list.is_empty():
		print("  ⚠️ 没有推进器 FX（模型没加载？）—— 环的检查跳过")
		_finish()
		return

	var all_two_rings := true
	var all_add := true
	for fx in fx_list:
		var rings: Array = fx.get("rings", [])
		if rings.size() != 2:
			all_two_rings = false
		for r in rings:
			var mi := r as MeshInstance3D
			if mi != null and mi.material_override is StandardMaterial3D:
				if (mi.material_override as StandardMaterial3D).blend_mode \
						!= BaseMaterial3D.BLEND_MODE_ADD:
					all_add = false
	_check(all_two_rings, "每个推进器都挂了 2 个激波环")

	# ⑤ 装饰特效层（2026-11-10 新增五样）
	# ⚠️ 路径：`ExtraFx` 挂在 **_carrier（载具模型节点）** 下，不是 CarrierForm 下
	#    —— 见 `carrier_form.gd::_build_extra_fx()` 里的 `_carrier.add_child(_fx_extra)`。
	#    本探针第一版查的是 carrier 自己，所以拿到 null。
	var extra := carrier.get("_fx_extra") as Node3D
	_check(extra != null, "装饰特效层 _fx_extra 已创建")
	if extra != null:
		_check(bool(extra.call("is_built")), "ExtraFx 完成 build()")
		# ── 2026-11-10 用户明确要求删掉三样 ──
		# 「机甲特效圆环不要,飞行特效向后的线条也不要,
		#   飞行特效角色身前射出的光也不要」
		# 所以断言**反过来**：这三样必须是 0，留着才是 bug。
		for pair in [["_ribbons", "等离子光带（身前射出的光）"],
				["_rings", "能量环（机甲特效圆环）"],
				["_speed_lines", "速度气流线（向后的线条）"]]:
			var arr0: Array = extra.get(pair[0])
			print("  %s = %d 个（应为 0）" % [pair[1], arr0.size()])
			_check(arr0.size() == 0, "%s **已移除**（%d 个）" % [pair[1], arr0.size()])
		# 加力白焰也删了（2026-11-10 补删：0.055×2.4 m 的白棍子，和用户要删的是同一类东西）
		var burners: Array = extra.get("_burners")
		print("  加力白焰 = %d 个（应为 0）" % burners.size())
		_check(burners.size() == 0, "加力白焰 **已移除**（%d 个）" % burners.size())
		# 只留翼尖光点
		var tips: Array = extra.get("_tips")
		print("  翼尖光点 = %d 个" % tips.size())
		_check(tips.size() > 0, "翼尖光点 建出来了（%d 个）" % tips.size())

	# ⑥ 环在动：快进几帧看 scale 是否变化
	var sample := (fx_list[0]["rings"] as Array)[0] as MeshInstance3D
	var s0 := sample.scale
	for _i in 20:
		await process_frame
	var s1 := sample.scale
	print("  环 scale：%s → %s" % [str(s0.snappedf(0.01)), str(s1.snappedf(0.01))])
	_check(not s0.is_equal_approx(s1), "环的尺寸每帧在变（不是死的）")

	_finish()


func _finish() -> void:
	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 飞行特效细化生效" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)
