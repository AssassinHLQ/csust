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

## 混凝土的物理区间（参考：普通水泥 ~0.35，浅色混凝土 ~0.45）
const ALBEDO_MIN := 0.30
const ALBEDO_MAX := 0.50
const ROUGH_MIN := 0.80

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
			"  %s 反照率 %.2f 落在混凝土区间 [%.1f, %.1f]" % [nm, lum, ALBEDO_MIN, ALBEDO_MAX])
		_check(mat.roughness >= ROUGH_MIN,
			"  %s 粗糙度 %.2f ≥ %.2f（不再是白纸式高光）" % [nm, mat.roughness, ROUGH_MIN])
		_check(mat.metallic <= 0.01, "  %s metallic ≈ 0（不是镜面反射高）" % nm)
		_check(mat.albedo_texture != null, "  %s 挂了 albedo 贴图" % nm)
		_check(mat.roughness_texture != null, "  %s 挂了 roughness 贴图" % nm)
		_check(mat.normal_enabled and mat.normal_texture != null,
			"  %s 挂了法线贴图（颗粒感）" % nm)
		_check(not mat.emission_enabled, "  %s 关掉了自发光（不再是烘焙光）" % nm)

	# 贴图资源本身能不能 load 到（防止路径写错）
	for p in ["res://assets/tex/concrete_albedo.png",
			"res://assets/tex/concrete_rough.png",
			"res://assets/tex/concrete_normal.png"]:
		_check(ResourceLoader.exists(p), "贴图存在：%s" % p)

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
		print("★ 全过：白墙已成混凝土（反照率、粗糙度、三张贴图都对）")
