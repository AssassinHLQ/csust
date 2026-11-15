extends Node3D
## 「校园封锁 + 最终 BOSS 登场」——第二关的终局演出。
##
## 用户 2026-11-13 原话：
##   「看到我给学校建的围墙了吗，在打败三只霸王龙之后，围墙会上升锁住我们，
##     此时围墙变成半透明红色并且有上下红色密集线条封锁，天空盒变成末日风格的，
##     然后最终 boss 优香-恐怖登场！此时背景音乐是 …/Encroached Sky.mp3」
##
## 所以本文件按顺序做四件事：
##   ① 围墙从地里升起（同一圈 footprint，见下）
##   ② 墙变半透明红 + 上下两圈密集红色扫描线（`shaders/arena_barrier.gdshader`）
##   ③ 天空盒换成程序化生成的末日全景（`assets/sky/sky_doom.jpg`）＋雾/环境光/辉光转血色
##   ④ 生成最终 BOSS「优香-恐怖」，并放 Boss 主题（`assets/music/doom_theme.ogg`）
##
## ── 墙建在哪儿：不写死，量 `CampusCollision` ──
## 用户说的「我给学校建的围墙」是 `scenes/campus_collision_walls_final.scn`
## 那份烘焙网格（`next_level.tscn` 里的 `CampusCollision` 节点）。
## 实测（`_probe_campuswall.gd`）它的包围盒是 **573.17 × 53.68 × 483.39**，
## y 从 −0.87 到 52.81，和 `CampusFloor` 的 x/z footprint 完全一致
## （x ±287.8、z −558.4 ~ −75）。
## 所以墙直接长在这个矩形上 —— 校园以后改大小，这里自动跟着变。
##
## ── 为什么升起的是"新墙"而不是把那面墙抬起来 ──
## `CampusCollision` 是**整座校园**的碰撞网格（18 万个三角面，含楼、路、台阶），
## 抬它等于把整座学校抬起来。所以另建一圈同 footprint 的能量墙，
## 平时整个埋在地面以下（顶面在地面下 1 m），触发时才升上来。
##
## ── 顺序上的一处讲究 ──
## 墙先升、后出 BOSS：这样"锁住"这件事发生在 BOSS 出现之前，
## 玩家的注意力顺序是「门被关上」→「天上变了」→「它来了」，
## 而不是三件事糊在同一帧。

## BOSS 生成后发出去，给 `next_level.gd` 重绑 HUD 血条用。
signal boss_spawned(boss: Node3D)
## 优香-恐怖倒下、封锁解除后发出去（`next_level.gd` 接这个弹"已击破"）。
signal finished

const BARRIER_SHADER := preload("res://shaders/arena_barrier.gdshader")
const BOSS_SCRIPT := preload("res://scripts/yuuka_horror_boss.gd")
const SKY_PATH := "res://assets/sky/sky_doom.jpg"
## `scripts/music.gd` 里这一首的逻辑名（Encroached Sky）
const TRACK := "finalboss"

## 墙的视觉参数。60 m 高 —— 校园里的楼最高到 y≈53（`CampusCollision` 实测），
## 所以站在校园里看，这圈墙是真的"出不去"，不是一道齐腰的栏杆。
const WALL_HEIGHT := 60.0
const WALL_THICK := 2.0
## 上升用时（秒）。太快像贴图弹出，太慢没有压迫感。
const RISE_SEC := 3.4
## 每面墙之间的起升错开（秒），四边依次立起来
const RISE_STAGGER := 0.18
## 平时埋多深（墙顶沉到地面以下多少米）。留 1 m 保证任何地形起伏下都看不见。
const BURY := 1.0
## 上下两圈扫描线各自的高度（米）和离墙顶/墙底的距离
const BAND_H := 7.0
const BAND_INSET := 0.8
## BOSS 出现在玩家前方多远（米）
const SPAWN_DIST := 48.0
## 射线打不到地面时的兜底高度（校园地面实测就在 0 附近）
const GROUND_FALLBACK := 0.0
## 地面射线的**合理区间**。⚠️ 这个夹紧不是洁癖，是实测踩出来的：
##
## 校园里那块 `CampusFloor`（120 万 m³ 的大盒子）顶面在 **y = −100.91**，
## 它是给"掉出校园"接人的兜底板，**不是**可行走地面。
## 而 `CampusCollision`（用户建的围墙/地形碰撞网格）是**有洞的** ——
## 实测 `_probe_arena_bounds.gd`：校园中心 (0, −316.7)、(0, −80)、
## (−60, −150) 这些点射线都打不到校园网格，直接穿到 −100.91 那块板上。
##
## 第一版没有夹紧，后果很直接（`_probe_final_phase.gd` 日志）：
##   · 东墙 ground_y = −100.91 → 整面墙埋到地下 100 m，等于没建；
##   · 优香-恐怖生成在 y = −100.86 → 站在地底，玩家根本看不见它。
## 所以：只有落在 [GROUND_MIN, GROUND_MAX] 里的命中才算"地面"，
## 其余一律当"这里没有地面"，用兜底 0（校园可视面就在 0 附近）。
const GROUND_MIN := -20.0
const GROUND_MAX := 90.0

var _walls: Array[Node3D] = []
var _fill_mat: ShaderMaterial
var _band_mat_up: ShaderMaterial
var _band_mat_down: ShaderMaterial
var _started := false
var _released := false
var _boss: Node3D
## 封锁前的天空/雾/环境光/辉光/太阳快照，解除时按它还原
var _env_state := {}
var _env: WorldEnvironment
var _sun: DirectionalLight3D


func _ready() -> void:
	name = "ArenaLock"
	_fill_mat = _make_fill_mat()
	# 上下两圈"密集线"：72 条 → 130 条（用户要更密）
	_band_mat_up = _make_band_mat(130.0, 0.15, 0.55)
	_band_mat_down = _make_band_mat(130.0, 0.15, -0.55)


## 跑整个终局序列。`bounds` 只用到 x/z（y 由射线现打）。
func start(env: WorldEnvironment, sun: DirectionalLight3D,
		who: Node3D, bounds: AABB) -> void:
	if _started:
		return
	_started = true
	# The wall-rise gives model/texture IO several seconds before the first cast.
	# Keep the cache alive through this arena, including repeated pig summons.
	var warmup := preload("res://scripts/battle_asset_warmup.gd").new()
	warmup.name = "BattleAssetWarmup"
	get_tree().root.add_child(warmup)
	warmup.start(self)
	_env = env
	_sun = sun
	_snapshot_env()
	_build_walls(bounds)
	_apply_doom_sky(env, sun)
	Music.play(TRACK)
	_rise()
	await get_tree().create_timer(RISE_SEC + RISE_STAGGER * 4.0 + 0.25).timeout
	_spawn_boss(who, bounds)
	print("[ArenaLock] 封锁完成：墙 %d 面，BOSS = %s" % [
		_walls.size(), String(_boss.name) if _boss != null else "（失败）"])


# ────────────────────────── 墙 ──────────────────────────

func _build_walls(bounds: AABB) -> void:
	var x0 := bounds.position.x
	var x1 := bounds.position.x + bounds.size.x
	var z0 := bounds.position.z
	var z1 := bounds.position.z + bounds.size.z
	print("[ArenaLock] 墙 footprint：x %.1f ~ %.1f ｜ z %.1f ~ %.1f（%.0f × %.0f m）" % [
		x0, x1, z0, z1, x1 - x0, z1 - z0])
	# 四面：东/西是"沿 z 走的长墙"，北/南是"沿 x 走的长墙"
	_add_wall("S", true, z1, x0, x1)
	_add_wall("N", true, z0, x0, x1)
	_add_wall("W", false, x0, z0, z1)
	_add_wall("E", false, x1, z0, z1)


## `along_x = true` → 这面墙沿 x 方向延伸，`fixed` 是它的 z 坐标；反之亦然。
func _add_wall(tag: String, along_x: bool, fixed: float,
		span0: float, span1: float) -> void:
	var length := absf(span1 - span0)
	var mid := (span0 + span1) * 0.5
	var cx := mid if along_x else fixed
	var cz := fixed if along_x else mid
	var gy := _ground_y(cx, cz)
	var size := Vector3(length, WALL_HEIGHT, WALL_THICK) if along_x \
		else Vector3(WALL_THICK, WALL_HEIGHT, length)

	var holder := Node3D.new()
	holder.name = "Wall%s" % tag
	# 埋起来：盒子顶面落在 (地面 − BURY)
	holder.position = Vector3(cx, gy - WALL_HEIGHT * 0.5 - BURY, cz)
	holder.set_meta("stand_y", gy + WALL_HEIGHT * 0.5 - BURY)
	holder.set_meta("ground_y", gy)
	add_child(holder)

	# 碰撞：和场景里其它静态体一样走第 1 层
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	holder.add_child(body)

	# 墙本体（半透明红 + 稀疏参考线）
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	var bm := BoxMesh.new()
	bm.size = size
	fill.mesh = bm
	fill.material_override = _fill_mat
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(fill)

	# 上下两圈密集扫描线。⚠️ 放在墙厚中心（局部 z/x = 0）而不是贴在某一面：
	# 贴面的话，从另一侧看就是"墙里埋着一层线"；居中则两侧看到的距离一样。
	for spec in [["BandTop", 1.0, _band_mat_up], ["BandBot", -1.0, _band_mat_down]]:
		var sign_y := float(spec[1])
		var q := MeshInstance3D.new()
		q.name = String(spec[0])
		var qm := QuadMesh.new()
		qm.size = Vector2(length, BAND_H)
		q.mesh = qm
		q.material_override = spec[2]
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var y := sign_y * (WALL_HEIGHT * 0.5 - BAND_H * 0.5 - BAND_INSET)
		if along_x:
			q.position = Vector3(0, y, 0)
		else:
			q.position = Vector3(0, y, 0)
			q.rotation.y = PI * 0.5
		holder.add_child(q)

	_walls.append(holder)


func _make_fill_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BARRIER_SHADER
	# ⚠️ alpha 从 0.22 提到 0.34：探针第一版在**看不到校园**的角度取景
	# （渲染距离 100 m 之外的泼溅被剔了），墙后面是纯黑，
	# 0.22 的红叠在黑上几乎还是黑 —— 整面墙看起来"只有线条、没有墙"。
	# 0.34 在黑色背景上也看得出是一层红雾。
	m.set_shader_parameter("fill_color", Color(0.90, 0.06, 0.07, 0.34))
	m.set_shader_parameter("line_color", Color(1.0, 0.20, 0.13, 0.40))
	# 用户 2026-11-13「校园红线不够密集」：11 条 → 34 条，线也收细
	m.set_shader_parameter("line_count", 34.0)
	m.set_shader_parameter("line_width", 0.11)
	m.set_shader_parameter("scroll_speed", 0.10)
	m.set_shader_parameter("pulse_speed", 1.5)
	m.set_shader_parameter("pulse_depth", 0.18)
	m.set_shader_parameter("edge_glow", 1.3)
	m.set_shader_parameter("edge_width", 0.05)
	return m


## 上下两圈用的材质：线条密、线宽细、滚动方向相反（一圈向上扫、一圈向下扫）。
func _make_band_mat(count: float, width: float, scroll: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BARRIER_SHADER
	m.set_shader_parameter("fill_color", Color(0.90, 0.04, 0.05, 0.10))
	m.set_shader_parameter("line_color", Color(1.0, 0.14, 0.08, 0.92))
	m.set_shader_parameter("line_count", count)
	m.set_shader_parameter("line_width", width)
	m.set_shader_parameter("scroll_speed", scroll)
	m.set_shader_parameter("pulse_speed", 4.5)
	m.set_shader_parameter("pulse_depth", 0.30)
	m.set_shader_parameter("edge_glow", 0.0)
	m.set_shader_parameter("edge_width", 0.05)
	return m


func _rise() -> void:
	var i := 0
	for w in _walls:
		if w == null or not is_instance_valid(w):
			continue
		var target := float(w.get_meta("stand_y", 0.0))
		var tw := create_tween()
		tw.tween_interval(RISE_STAGGER * float(i))
		tw.tween_property(w, "position:y", target, RISE_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		i += 1
	Sfx.play("ui_open", -4.0)
	print("[ArenaLock] 墙开始上升（%d 面，%.1f s，错开 %.2f s）" % [
		_walls.size(), RISE_SEC, RISE_STAGGER])


# ────────────────────────── 天空 ──────────────────────────

## 把封锁前的天空/雾/环境光/辉光/太阳存一份，BOSS 死后照着还原。
func _snapshot_env() -> void:
	_env_state.clear()
	if _env == null or _env.environment == null:
		return
	var e := _env.environment
	_env_state = {
		"sky": e.sky,
		"bg": e.background_mode,
		"fog_color": e.fog_light_color,
		"fog_density": e.fog_density,
		"ambient_color": e.ambient_light_color,
		"ambient_energy": e.ambient_light_energy,
		"glow": e.glow_intensity,
	}
	if _sun != null:
		_env_state["sun_color"] = _sun.light_color
		_env_state["sun_energy"] = _sun.light_energy


func _apply_doom_sky(env: WorldEnvironment, sun: DirectionalLight3D) -> void:
	if env == null or env.environment == null:
		push_warning("[ArenaLock] 没有 WorldEnvironment，只能跳过换天")
		return
	var e := env.environment
	var tex := load(SKY_PATH) as Texture2D
	if tex == null:
		push_warning("[ArenaLock] 末日天空加载失败：%s" % SKY_PATH)
	else:
		var mat := PanoramaSkyMaterial.new()
		mat.panorama = tex
		mat.filter = true
		var sky := Sky.new()
		sky.sky_material = mat
		sky.process_mode = Sky.PROCESS_MODE_REALTIME
		sky.radiance_size = Sky.RADIANCE_SIZE_256
		e.sky = sky
		e.background_mode = Environment.BG_SKY
		# 和 `next_level.gd::_setup_sky()` 同一个坑：雾不能糊到天上
		e.fog_sky_affect = 0.0
		print("[ArenaLock] 天空换成末日全景（%d×%d）" % [tex.get_width(), tex.get_height()])

	# 雾 / 环境光 / 辉光 一起往血色推（2 s 渐变，别硬切）
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(e, "fog_light_color", Color(0.52, 0.10, 0.07), 2.0)
	tw.tween_property(e, "fog_density", 0.0024, 2.0)
	tw.tween_property(e, "ambient_light_color", Color(0.44, 0.13, 0.11), 2.0)
	tw.tween_property(e, "ambient_light_energy", 0.42, 2.0)
	# 场景默认 glow 只有 0.12（下一关）/0.25（主场景）—— 封锁罩和 BOSS 的红光
	# 全靠自发光，辉光不抬一点就"亮而不发光"。
	# ⚠️ 别抬太狠：试过 0.62，校园泼溅（烘焙亮度、本身就白）整片过曝成白楼
	#    （出图 `_final_phase/2_sky.png` 实测）。0.30 够罩子发光，又不动泼溅。
	tw.tween_property(e, "glow_intensity", 0.30, 2.0)
	if sun != null:
		tw.tween_property(sun, "light_color", Color(1.0, 0.42, 0.28), 2.0)
		tw.tween_property(sun, "light_energy", 0.80, 2.0)
	print("[ArenaLock] 雾/环境光/辉光 → 血色")


# ────────────────────────── BOSS ──────────────────────────

func _spawn_boss(who: Node3D, bounds: AABB) -> void:
	var cx := bounds.position.x + bounds.size.x * 0.5
	var cz := bounds.position.z + bounds.size.z * 0.5
	var dir := Vector3(0, 0, -1)
	if who != null and is_instance_valid(who):
		var p := who.global_position
		var d := Vector3(cx - p.x, 0.0, cz - p.z)
		dir = d.normalized() if d.length() > 1.0 else Vector3(0, 0, -1)
	var at := _pick_spawn(who, dir, bounds)

	var boss := BOSS_SCRIPT.new() as Node3D
	if boss == null:
		push_error("[ArenaLock] 最终 BOSS 建不出来")
		return
	boss.name = "YuukaHorror"
	add_child(boss)
	boss.global_position = at
	if who != null and is_instance_valid(who):
		var d2 := who.global_position - at
		# Boss 的脸朝 +Z（和其它 Boss 同一套约定）
		boss.rotation.y = atan2(d2.x, d2.z)
	_boss = boss
	_spawn_fx(at)
	if boss.has_signal("died"):
		boss.connect("died", _on_boss_died)
	boss_spawned.emit(boss)
	print("[ArenaLock] 优香-恐怖登场：%s（面向玩家，脚下地面 y=%.2f）"
		% [str(at.snappedf(0.01)), at.y])


## 挑一个"站得住、头顶开天"的落点。
##
## ⚠️ 上一版只沿"玩家→校园中心"一条直线放 48 m，实测会落在人家楼顶上
##    （出图 `_final_phase/6_boss.png`：优香-恐怖站在一栋平房房顶，
##    脚下一圈红环画在屋面上，看着像贴纸）。
## 判据三条：地面高度合理、和玩家**同层**（±3 m）、正上方 40 m 内没有碰撞
## （楼/树冠）。沿玩家周围一圈试，先试正前方，不行再往两边偏。
func _pick_spawn(who: Node3D, dir: Vector3, bounds: AABB) -> Vector3:
	var player_g: Variant = null
	if who != null and is_instance_valid(who):
		player_g = _ground_of(who.global_position.x, who.global_position.z)
	for ang in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0, 180.0]:
		for dist in [SPAWN_DIST, SPAWN_DIST * 0.72, SPAWN_DIST * 1.28]:
			var d := dir.rotated(Vector3.UP, deg_to_rad(float(ang)))
			var x := clampf((who.global_position.x if who != null else 0.0) + d.x * float(dist),
				bounds.position.x + 40.0, bounds.end.x - 40.0)
			var z := clampf((who.global_position.z if who != null else 0.0) + d.z * float(dist),
				bounds.position.z + 40.0, bounds.end.z - 40.0)
			var g: Variant = _ground_of(x, z)
			if g == null:
				continue
			if player_g != null and absf(float(g) - float(player_g)) > 3.0:
				continue
			if not _open_sky(x, float(g), z):
				continue
			print("[ArenaLock] BOSS 落点：偏 %.0f°、%.0f m 处（地面 y=%.2f）"
				% [float(ang), float(dist), float(g)])
			return Vector3(x, float(g) + 0.05, z)
	# 兜底：老方案（沿玩家→中心 48 m，不管楼顶）
	var fallback := Vector3(bounds.position.x + bounds.size.x * 0.5, 0.0,
		bounds.position.z + bounds.size.z * 0.5)
	if who != null and is_instance_valid(who):
		fallback = who.global_position + dir * SPAWN_DIST
	fallback.x = clampf(fallback.x, bounds.position.x + 40.0, bounds.end.x - 40.0)
	fallback.z = clampf(fallback.z, bounds.position.z + 40.0, bounds.end.z - 40.0)
	fallback.y = _ground_y(fallback.x, fallback.z) + 0.05
	push_warning("[ArenaLock] 找不到开阔落点，BOSS 用兜底位置 %s" % str(fallback))
	return fallback


## 正上方 40 m 内有没有东西（楼檐 / 树冠）。有 = 不是开阔地。
func _open_sky(x: float, y: float, z: float) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, y + 1.5, z), Vector3(x, y + 40.0, z))
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


## 和 `_ground_y()` 一样，但打不到 / 不合理时返回 null（让调用方去试下一个点）。
func _ground_of(x: float, z: float) -> Variant:
	var space := get_world_3d().direct_space_state
	if space == null:
		return null
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, 300.0, z), Vector3(x, -200.0, z))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var y := (hit["position"] as Vector3).y
	if y < GROUND_MIN or y > GROUND_MAX:
		return null
	return y


## 优香-恐怖倒下 → 封锁解除：墙沉回地里、天空/雾/环境光还原、音乐切回。
func _on_boss_died(_by: float) -> void:
	if _released:
		return
	_released = true
	print("[ArenaLock] 优香-恐怖倒下 → 解除封锁")
	_lower_walls()
	_restore_sky()
	finished.emit()


func _lower_walls() -> void:
	var i := 0
	for w in _walls:
		if w == null or not is_instance_valid(w):
			continue
		var buried := float(w.get_meta("ground_y", 0.0)) - WALL_HEIGHT * 0.5 - BURY
		var tw := create_tween()
		tw.tween_interval(0.12 * float(i))
		tw.tween_property(w, "position:y", buried, 2.6) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		i += 1
	Sfx.play("ui_close", -2.0)


func _restore_sky() -> void:
	if _env == null or _env.environment == null or _env_state.is_empty():
		return
	var e := _env.environment
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(e, "fog_light_color", _env_state["fog_color"], 2.6)
	tw.tween_property(e, "fog_density", float(_env_state["fog_density"]), 2.6)
	tw.tween_property(e, "ambient_light_color", _env_state["ambient_color"], 2.6)
	tw.tween_property(e, "ambient_light_energy", float(_env_state["ambient_energy"]), 2.6)
	tw.tween_property(e, "glow_intensity", float(_env_state["glow"]), 2.6)
	if _sun != null and _env_state.has("sun_color"):
		tw.tween_property(_sun, "light_color", _env_state["sun_color"], 2.6)
		tw.tween_property(_sun, "light_energy", float(_env_state["sun_energy"]), 2.6)
	# 天空本身也换回去（雾先淡出，2.6 s 后再换，避免硬切）
	await get_tree().create_timer(2.4).timeout
	if not is_inside_tree():
		return
	var sky: Sky = _env_state.get("sky")
	if sky != null:
		e.sky = sky
		e.background_mode = int(_env_state.get("bg", Environment.BG_SKY))
	Music.play("mondrian")
	print("[ArenaLock] 天空 / 雾 / 环境光 已还原")


## 登场特效：一道冲天红柱 + 一圈地面冲击环。
func _spawn_fx(at: Vector3) -> void:
	Sfx.play("ex_fire", -3.0)

	var pillar := MeshInstance3D.new()
	pillar.name = "SpawnPillar"
	var cm := CylinderMesh.new()
	cm.top_radius = 7.0
	cm.bottom_radius = 10.0
	cm.height = 120.0
	cm.radial_segments = 32
	cm.rings = 1
	pillar.mesh = cm
	pillar.material_override = _additive(Color(1.0, 0.24, 0.12, 0.45))
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar.position = at + Vector3(0.0, 60.0, 0.0)
	add_child(pillar)
	var tw1 := create_tween()
	tw1.set_parallel(true)
	tw1.tween_property(pillar, "scale", Vector3(1.9, 1.0, 1.9), 1.9)
	if pillar.material_override is StandardMaterial3D:
		tw1.tween_property(pillar.material_override, "albedo_color:a", 0.0, 1.9)
	tw1.chain().tween_callback(pillar.queue_free)

	var ring := MeshInstance3D.new()
	ring.name = "SpawnRing"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.86
	tm.outer_radius = 1.0
	tm.rings = 96
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = _additive(Color(1.0, 0.30, 0.15, 0.85))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = at + Vector3(0.0, 0.25, 0.0)
	add_child(ring)
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(ring, "scale", Vector3(46.0, 1.0, 46.0), 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if ring.material_override is StandardMaterial3D:
		tw2.tween_property(ring.material_override, "albedo_color:a", 0.0, 1.5)
	tw2.chain().tween_callback(ring.queue_free)

	var light := OmniLight3D.new()
	light.name = "SpawnLight"
	light.light_color = Color(1.0, 0.24, 0.14)
	light.light_energy = 14.0
	light.omni_range = 70.0
	light.position = at + Vector3(0.0, 8.0, 0.0)
	add_child(light)
	var tw3 := create_tween()
	tw3.tween_property(light, "light_energy", 0.0, 2.4)
	tw3.tween_callback(light.queue_free)


func _additive(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	return m


# ────────────────────────── 工具 ──────────────────────────

## 从 (x, 300, z) 向下打到 −200，返回第一个命中面的 y。
## 只有命中落在 [GROUND_MIN, GROUND_MAX] 才算地面 —— 见上面那两个常量的注释。
func _ground_y(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return GROUND_FALLBACK
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, 300.0, z), Vector3(x, -200.0, z))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return GROUND_FALLBACK
	var y := (hit["position"] as Vector3).y
	if y < GROUND_MIN or y > GROUND_MAX:
		return GROUND_FALLBACK
	return y


## 自检用：当前四面的 y 和"应该站的 y"。
func status() -> Dictionary:
	var rows: Array = []
	for w in _walls:
		if w == null or not is_instance_valid(w):
			continue
		rows.append({
			"name": String(w.name),
			"y": (w as Node3D).position.y,
			"stand_y": float(w.get_meta("stand_y", 0.0)),
			"ground_y": float(w.get_meta("ground_y", 0.0)),
		})
	return {
		"walls": rows,
		"boss": String(_boss.name) if _boss != null and is_instance_valid(_boss) else "",
		"boss_pos": (_boss as Node3D).global_position if _boss != null \
			and is_instance_valid(_boss) else Vector3.ZERO,
	}
