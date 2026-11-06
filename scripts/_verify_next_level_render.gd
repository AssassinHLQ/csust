extends SceneTree
## 校验「校园场景（next_level）也吃画面设置」。
##
## 背景：2026-11-06 用户 —— 「next_level.gd（校园场景）完全不碰任何画面设置 是为什么,
## 需要同步画面设置」。修法是抽出 `scripts/render_env.gd::RenderEnv.apply()`，
## 两个场景各留一层薄壳。本探针**不直接调 `_apply_render()`**，而是走
## `GameSettings.set_value()` 的广播 —— 那样才证明「设置界面里改一下，校园真的动」
## 这条链路（listen 注册 + 薄壳 + 落地）整条是通的。
##
## 用法：
##   _tools/run_probe.sh res://scripts/_verify_next_level_render.gd -- --no-ggs-campus
## ⚠️ 必须带 `--no-ggs-campus`：否则会去加载校园那份 1.4 GB 的 GGS 数据。
## ⚠️ `user://` 要可写（本会话跑探针时若报写入失败，先把 `$env:APPDATA` 指到工作区）。

const LEVEL_SCENE := "res://scenes/next_level.tscn"
## ⚠️ `--script` 模式下 `class_name` 全局标识符**不保证可见**（和 game_settings.gd 那段
## 说明是同一个坑），所以这里一律 preload，别写裸的 `RenderEnv.xxx`。
const RenderEnvScript := preload("res://scripts/render_env.gd")

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fail += 1


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var level := (load(LEVEL_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _i in 90:
		await process_frame

	print("── ⓪ 场景里到底有没有那层薄壳 ──")
	_check(level.has_method("_apply_render"), "next_level.gd 有 _apply_render()")
	_check(level.has_method("_on_setting_changed"), "next_level.gd 有 _on_setting_changed()")
	_check(level.has_method("_fit_render_scale"), "next_level.gd 有 _fit_render_scale()")

	var vp := level.get_viewport()
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_check(we != null and we.environment != null, "场景里有 WorldEnvironment + Environment")
	var cams := level.find_children("*", "Camera3D", true, false)
	_check(not cams.is_empty(), "场景里找到 %d 台 Camera3D" % cams.size())
	var lights := level.find_children("*", "Light3D", true, false)
	_check(not lights.is_empty(), "场景里找到 %d 盏 Light3D" % lights.size())

	print("── ① 3D 渲染缩放 ──")
	GameSettings.set_value("resolution_scale", 0.75)
	await process_frame
	await process_frame
	var auto_scale := float(level.get("_auto_scale"))
	var want := clampf(auto_scale * 0.75, 0.25, 1.0)
	print("     自动上限 %.3f → 期望 %.3f，实得 %.3f"
		% [auto_scale, want, vp.scaling_3d_scale])
	_check(is_equal_approx(vp.scaling_3d_scale, want), "scaling_3d_scale 跟着设置走")

	print("── ② 帧率上限 / 垂直同步 ──")
	# ⚠️ `fps_limit` 的步长是 10，所以设 144 会被对齐成 140 —— 这里就按 140 验，
	#    免得把「对齐步长」误判成「没生效」。
	GameSettings.set_value("fps_limit", 144.0)
	await process_frame
	print("     Engine.max_fps = %d（设 144，步长 10 → 期望 140）" % Engine.max_fps)
	_check(Engine.max_fps == 140, "max_fps 跟着设置走")

	print("── ③ 抗锯齿 ──")
	GameSettings.set_value("aa_mode", 3.0)
	await process_frame
	print("     msaa_3d = %d（期望 %d = MSAA_4X）" % [vp.msaa_3d, Viewport.MSAA_4X])
	_check(vp.msaa_3d == Viewport.MSAA_4X, "MSAA 4× 生效")
	GameSettings.set_value("aa_mode", 5.0)
	await process_frame
	print("     use_taa = %s，msaa_3d = %d" % [str(vp.use_taa), vp.msaa_3d])
	_check(vp.use_taa and vp.msaa_3d == Viewport.MSAA_DISABLED, "TAA 生效且 MSAA 被关掉")

	print("── ④ 阴影质量（关 → 全部不投影；回高档 → 恢复场景原本状态）──")
	var authored := {}
	for n in lights:
		authored[n.get_instance_id()] = (n as Light3D).shadow_enabled
	GameSettings.set_value("shadow_quality", 0.0)
	await process_frame
	var any_on := false
	for n in lights:
		if (n as Light3D).shadow_enabled:
			any_on = true
	print("     关阴影后还有 %s 盏开着" % ("一些" if any_on else "0"))
	_check(not any_on, "阴影质量=关 → 全部不投影")
	GameSettings.set_value("shadow_quality", 3.0)
	await process_frame
	var mismatch := 0
	for n in lights:
		var l := n as Light3D
		if l.shadow_enabled != bool(authored[l.get_instance_id()]):
			mismatch += 1
	print("     回到「高」后和场景原本状态不一致的灯：%d 盏" % mismatch)
	_check(mismatch == 0, "阴影质量=高 → 恢复场景原本的投影状态")

	print("── ⑤ 后处理 + 雾 ──")
	var env := we.environment
	GameSettings.set_value("ssao", false)
	GameSettings.set_value("glow", false)
	GameSettings.set_value("ssr", true)
	GameSettings.set_value("fog", false)
	await process_frame
	print("     SSAO=%s 辉光=%s SSR=%s 雾=%s"
		% [str(env.ssao_enabled), str(env.glow_enabled), str(env.ssr_enabled), str(env.fog_enabled)])
	_check(not env.ssao_enabled and not env.glow_enabled and env.ssr_enabled and not env.fog_enabled,
		"Environment 四个开关跟着设置走")

	print("── ⑥ 渲染距离 → 摄像机远裁剪面 ──")
	GameSettings.set_value("render_distance", 200.0)
	await process_frame
	var fars: Array = []
	for c in cams:
		fars.append((c as Camera3D).far)
	print("     摄像机 far = %s（期望全部 200）" % str(fars))
	_check(fars.all(func(f): return is_equal_approx(float(f), 200.0)), "所有 Camera3D.far == 200")

	print("── ⑦ 全局 LOD 阈值 ──")
	GameSettings.set_value("lod_threshold_px", 2.0)
	await process_frame
	print("     根视口 mesh_lod_threshold = %.2f（期望 2.00）" % root.mesh_lod_threshold)
	_check(is_equal_approx(root.mesh_lod_threshold, 2.0), "mesh_lod_threshold 跟着设置走")

	print("── ⑧ 换场景不清掉别人的原始状态（主场景那套独立于这里）──")
	# `_shadow_authored` 换根节点就该清空：拿主场景的 id 去污染校园的灯是错的。
	var before := int(RenderEnvScript._active_root_id)
	_check(before == int(level.get_instance_id()), "RenderEnv 记住的是当前校园场景的根节点")
	print("     记住的根节点 id 与场景一致：%s" % str(before == int(level.get_instance_id())))

	# 收尾：全部还原默认，别把探针的值留在用户存档里
	GameSettings.reset_all()
	await process_frame
	await process_frame
	print("── 收尾：已 reset_all()，scaling=%.3f far=%s lod=%.2f fps=%d"
		% [vp.scaling_3d_scale, str((cams[0] as Camera3D).far), root.mesh_lod_threshold, Engine.max_fps])

	print("")
	print("结果：%s（失败 %d 项）" % ["PASS" if _fail == 0 else "FAIL", _fail])
	quit(0 if _fail == 0 else 1)
