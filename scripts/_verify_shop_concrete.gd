extends SceneTree
## 验收：柴关电脑城白墙 → 混凝土质感。
##
## 用户 2026-11-11：「店里白墙改混凝土的质感，现在是不是反射高了」。
##
## 查的东西（读运行时真值）：
##   ① 墙材质 `PLASTIK_W`、地台 `Rectangle009__0` 的 albedo / roughness / metallic / 贴图
##   ② 反照率必须落在混凝土的物理区间（0.30~0.50），粗糙度 ≥0.80
##      —— 这是「反射高」的根因（旧值 albedo 0.95 / rough 0.55）
##   ③ 三张贴图都真的挂上了（albedo / roughness / normal），且 normal 是 enabled
##   ④ 白天过曝比例显著下降
##
## 用法：& <godot_console.exe> --headless --path . --script res://scripts/_verify_shop_concrete.gd -- --splat=off --no-capture

const WALL_MAT := "PLASTIK_W"
const FLOOR_MAT := "Rectangle009__0"

## ⚠️⚠️ 2026-11-11 用户第四句定稿：「不行，还是换回全白吧」，
## 并在选项里明确选了 **纯白 + 保持哑光 + 不加贴图**。
## 所以这套门槛整个反过来了：
##   · 反照率区间从"混凝土 [0.55,0.78]" → **白墙 [0.80, 0.88]**
##   · **要求没有贴图**（albedo / roughness / normal 三样都必须为空/关闭）
##   · 粗糙度下限仍然 **0.90**（哑光 —— 这是白墙不再过曝的唯一保障）
##
## 为什么反照率封顶在 0.88 而不是 1.0：实测（`_probe_shop_pure_white.gd`，12:00）
##     albedo 0.85 → 过曝 12.72%   ← 采用
##     albedo 0.90 → 过曝 38.79%   ← **陡变点**，只差 0.05 就崩
##     albedo 0.95 → 过曝 56.64%   ← 最初那个"瞎死我了"
## 所以 0.90 以上一律判失败，防止以后有人"顺手调白一点"把问题调回来。
const ALBEDO_MIN := 0.80
const ALBEDO_MAX := 0.88
const ROUGH_MIN := 0.90
## 中性度：白墙不能偏色。R 与 B 的差超过这个就当"染色了"。
const NEUTRAL_MAX_DRIFT := 0.05
## UV 密度下限（用户 2026-11-11「太粗糙了…近看特别糊」）。
## 墙网格模型单位 x 跨 168.38 = 实际 8.0 m，所以 uv1_scale = N 时
## 一个贴图周期铺 8/N 米。uv3 → 2.67 m/周期，一坨斑点 4 m 大，近看必糊。
## uv16 → 0.5 m/周期，单纹素 ~5 mm，近看才是水泥颗粒。
const UV_SCALE_MIN := 12.0
## 法线上限：0.85 近看一片肉麻凸起，实测 0.40 合适
const NORMAL_MAX := 0.60

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("═══ 柴关电脑城 · 混凝土墙材质验收 ═══\n")

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame

	var shop := game.get_node_or_null("Shop") as Node3D
	_check(shop != null, "场景里有 Shop")
	if shop == null:
		_summary()
		quit(1)
		return

	# 收集运行时 override 的材质（`_fix_glb_materials()` 复制出来的那份）
	var got := {}
	for mi in shop.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var ov := (mi as MeshInstance3D).get_surface_override_material(s) as StandardMaterial3D
			if ov == null:
				continue
			var src := m.surface_get_material(s) as StandardMaterial3D
			if src == null:
				continue
			var nm := src.resource_name
			if not got.has(nm):
				got[nm] = ov

	for nm in [WALL_MAT, FLOOR_MAT]:
		_check(got.has(nm), "找到材质 %s" % nm)
		if not got.has(nm):
			continue
		var mat: StandardMaterial3D = got[nm]
		# 用感知亮度当反照率代表值
		var lum := 0.2126 * mat.albedo_color.r + 0.7152 * mat.albedo_color.g \
			+ 0.0722 * mat.albedo_color.b
		print("   %s：albedo=%s（亮度 %.2f）rough=%.2f metallic=%.2f"
			% [nm, str(mat.albedo_color), lum, mat.roughness, mat.metallic])
		_check(lum >= ALBEDO_MIN and lum <= ALBEDO_MAX,
			"  %s 反照率 %.2f 落在白墙区间 [%.2f, %.2f]" % [nm, lum, ALBEDO_MIN, ALBEDO_MAX])
		# 中性度：白墙不能偏色
		var drift := absf(mat.albedo_color.r - mat.albedo_color.b)
		_check(drift <= NEUTRAL_MAX_DRIFT,
			"  %s 色相中性（|R−B| = %.3f ≤ %.2f）" % [nm, drift, NEUTRAL_MAX_DRIFT])
		# ⚠️ 加 0.001 容差：float32 里 0.9 存成 0.8999999…，
		#    直接写 `0.90 >= 0.90` 会判假（第一次跑就栽在这）。
		_check(mat.roughness >= ROUGH_MIN - 0.001,
			"  %s 粗糙度 %.2f ≥ %.2f（哑光，不会过曝）" % [nm, mat.roughness, ROUGH_MIN])
		_check(mat.metallic <= 0.01, "  %s metallic ≈ 0（不是镜面反射高）" % nm)
		# 纯白：**要求没有任何纹理**（用户明确选了"不加贴图"）
		_check(mat.albedo_texture == null, "  %s 没有 albedo 贴图（纯白平涂）" % nm)
		_check(mat.roughness_texture == null, "  %s 没有 roughness 贴图" % nm)
		_check(not mat.normal_enabled and mat.normal_texture == null,
			"  %s 没有法线贴图（没有颗粒感）" % nm)
		_check(not mat.emission_enabled, "  %s 关掉了自发光（不再是烘焙光）" % nm)

	# 贴图文件虽然不用了，但要还在（以后想再接回去，别让资源被误删）
	for p in ["res://assets/tex/concrete_albedo.png",
			"res://assets/tex/concrete_rough.png",
			"res://assets/tex/concrete_normal.png"]:
		_check(ResourceLoader.exists(p), "贴图资源保留（备用）：%s" % p)

	# 灯带仍然自发光（别把灯管也关了）
	if got.has("light"):
		var lm: StandardMaterial3D = got["light"]
		_check(lm.emission_enabled and lm.emission_energy_multiplier > 0.5,
			"灯带 light 仍然自发光（%.2f）" % lm.emission_energy_multiplier)

	# 玻璃仍然是透明
	if got.has("01_-_Default"):
		var gm: StandardMaterial3D = got["01_-_Default"]
		_check(gm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED,
			"玻璃仍然半透明（transparency=%d, alpha=%.2f）"
				% [gm.transparency, gm.albedo_color.a])

	_summary()
	quit(0 if _fail == 0 else 1)


func _check(ok: bool, msg: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % msg)
	else:
		_fail += 1
		print("  ✗ %s" % msg)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])
	if _fail == 0:
		print("★ 全过：白墙是**纯白哑光无贴图**（albedo 0.85 / rough 0.90）")
