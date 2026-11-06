extends SceneTree
## 校验「全局 LOD 阈值」设置项：
##   ① 在 DEFAULTS / RANGES / LABELS / RENDER_KEYS 里都登记了（界面才会出现滑块）
##   ② set_value 会夹范围 + 对齐步长
##   ③ apply_lod_threshold() 真的改了根视口的 mesh_lod_threshold
##   ④ 落盘后能读回来
##
## 用法：_tools/run_probe.sh res://scripts/_verify_lod_setting.gd

const GameSettings := preload("res://scripts/game_settings.gd")
const KEY := "lod_threshold_px"


func _initialize() -> void:
	var ok := true

	# ① 登记齐全
	for what in [["DEFAULTS", GameSettings.DEFAULTS.has(KEY)],
			["RANGES", GameSettings.RANGES.has(KEY)],
			["LABELS", GameSettings.LABELS.has(KEY)],
			["RENDER_KEYS", KEY in GameSettings.RENDER_KEYS]]:
		var has_it := bool(what[1])
		print("[lodset] %-12s %s" % [String(what[0]), "OK" if has_it else "缺失"])
		if not has_it:
			ok = false
	print("[lodset] 标签 = 「%s」" % GameSettings.label(KEY))
	print("[lodset] 范围 = %s" % str(GameSettings.spec(KEY)))
	print("[lodset] 默认 = %s" % str(GameSettings.DEFAULTS[KEY]))

	# ② 夹范围 / 步长
	GameSettings.set_value(KEY, 999.0)
	print("[lodset] 设 999 → %s（应被夹到 8.0）" % str(GameSettings.value(KEY)))
	if not is_equal_approx(float(GameSettings.value(KEY)), 8.0):
		ok = false
	GameSettings.set_value(KEY, -5.0)
	print("[lodset] 设 -5  → %s（应被夹到 0.1）" % str(GameSettings.value(KEY)))
	if not is_equal_approx(float(GameSettings.value(KEY)), 0.1):
		ok = false

	# ③ 应用是否真的写进视口
	GameSettings.set_value(KEY, 2.5)
	var applied := GameSettings.apply_lod_threshold()
	print("[lodset] 设 2.5 → 应用值 %s，根视口回读 %s" % [str(applied), str(root.mesh_lod_threshold)])
	if not is_equal_approx(root.mesh_lod_threshold, 2.5) or not is_equal_approx(applied, 2.5):
		ok = false

	# ④ 落盘 + 读回（GameSettings 是静态类，这里直接看文件）
	GameSettings.set_value(KEY, 3.0)
	var cfg := ConfigFile.new()
	var err := cfg.load(GameSettings.PATH)
	print("[lodset] 落盘 err=%d，盘上值 = %s" % [err, str(cfg.get_value(GameSettings.SECTION, KEY, null))])
	if err != OK or not is_equal_approx(float(cfg.get_value(GameSettings.SECTION, KEY, 0.0)), 3.0):
		ok = false

	# 还原默认，别把探针的值留在用户存档里
	GameSettings.set_value(KEY, 1.0)
	GameSettings.apply_lod_threshold()
	print("[lodset] 已还原默认 1.0，根视口回读 %s" % str(root.mesh_lod_threshold))

	print("[lodset] 结果: %s" % ("PASS" if ok else "FAIL"))
	quit()
