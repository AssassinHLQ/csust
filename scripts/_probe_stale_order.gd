extends SceneTree
## 探针：验证「快速回头时高斯要过一秒才浮现完整」的成因 —— 排序延迟 + 陈旧排序表。
##
## 机理（源码位置）：
##   raster_sorter.gd            16 位计数排序，278 万点实测 **812 ms**（_probe_sort_cost.gd）
##   raster_sort_job.gd          双缓冲：排序在工作线程跑，主线程继续用**上一张**排序表
##   raster_render_backend.gd    _drive_entry 里 `not entry.job.is_running()` 挡住重踢，
##                               所以飞行中的 812 ms 内不会再排；落地才 _upload_order
##   ⇒ 快速转身后，画面拿「转身前那个朝向」的排序表去混合：深度顺序整体反了，
##     远端几何最后画、盖住近端 —— 看起来就是「后面的还没加载」。812 ms 后新表
##     落地，画面才「浮现完整」。
##
## ⚠️ 判据不能用「相邻帧是否变化」：陈旧表期间画面本来就是**冻结**的，
##    「不变」恰好是最不可靠的信号。本探针改为盯**排序表内容摘要**本身。
##
## 产出：
##   a_sorted    转身前、排序表已落地且不再变的图（基准）
##   b_stale     转身后第 1 帧 —— 用户看到的那张「没加载」的图
##   b_landed    排序表落地后的图（正确）
##   b_unsorted  同一机位、强制 use_order=false（资源顺序）—— 建议的兜底方案
##
## 用法：
##   godot --path . --script res://scripts/_probe_stale_order.gd
## 输出：…/_arisu_captures/_stale_order/*.png

const SplatSceneScript := preload("res://scripts/splat_scene.gd")
const Sorter := preload("res://addons/gdgs/runtime/render/raster/raster_sorter.gd")
const DataTextures := preload("res://addons/gdgs/runtime/render/raster/raster_data_textures.gd")

const OUT_DIR := "_stale_order"
const W := 960
const H := 540
const POLL_MAX_MS := 6000

var _mat: ShaderMaterial = null
var _order_tex: ImageTexture = null
var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(W, H)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	# 与 scenes/game.tscn 的 Room609 参数完全一致 —— 探针必须复现线上那间房。
	var scene: Node3D = SplatSceneScript.new()
	scene.name = "Room609"
	scene.set("sog_path", "res://splatdata/room609.sogdata")
	scene.set("display_name", "画室609")
	scene.set("venue", "room")
	scene.set("world_scale", 4.25)
	scene.set("yaw_degrees", 248.6)
	scene.set("auto_place", false)
	scene.set("use_anchor", true)
	scene.set("anchor_source", Vector3(0.022, -0.333, -0.121))
	scene.set("anchor_world", Vector3(0, 0.03, 4.25))
	scene.set("crop_enabled", true)
	scene.set("crop_margin", 0.5)
	scene.set("crop_max_scale", 0.5)
	scene.set("build_box_collision", false)
	scene.set("cache_mode", "auto")
	scene.set("auto_start", false)
	root.add_child(scene)

	var t0 := Time.get_ticks_msec()
	scene.call("load_now")
	if not scene.call("is_ready"):
		push_error("[stale] 泼溅没建立起来")
		quit(1)
		return
	print("[stale] %d 点，解码+建节点 %.1f s" % [
		int(scene.get("point_count")), (Time.get_ticks_msec() - t0) / 1000.0])

	var node: Node3D = scene.get("splat_node")
	# 后端是在节点进树之后**延迟**挂 MultiMeshInstance3D 的，所以要等几帧再找。
	var mmi: MultiMeshInstance3D = null
	for _try in range(30):
		await _frames(1)
		for ch in node.get_children(true):
			if ch is MultiMeshInstance3D:
				mmi = ch
				break
		if mmi != null:
			break
	if mmi == null:
		push_error("[stale] 找不到光栅后端的 MultiMeshInstance3D")
		quit(1)
		return
	_mat = mmi.material_override
	_order_tex = _mat.get_shader_parameter("order_data")
	var t_attach := Time.get_ticks_msec()
	print("[stale] 实例数 %d（每实例 128 高斯）；驱动节点 %s" % [
		mmi.multimesh.instance_count,
		"在" if root.get_node_or_null("_GdgsRasterDriver") != null else "**不在**"])

	# --- 相机：站在**真实出生点**的眼位（房间正中偏下会被桌椅和地板糊住）---
	# 出生点就是 anchor_world，地板在 y = 0.03，所以眼位再抬 1.7 m。
	var box: AABB = scene.call("content_world_aabb")
	var eye := Vector3(0.0, 0.03 + 1.7, 4.25)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 20000.0
	root.add_child(cam)
	cam.global_position = eye
	cam.look_at(eye + Vector3(0.0, 0.0, 1.0), Vector3.UP)   # 姿态 A：朝 +Z
	cam.make_current()
	print("[stale] 房间世界盒 pos %s size %s；相机 %s（房内，朝 +Z）" % [
		str(box.position.snappedf(0.1)), str(box.size.snappedf(0.1)), str(eye.snappedf(0.1))])

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out)

	# --- 0. 真实帧率（不回读，避免把测量开销算进去）---
	var tf := Time.get_ticks_msec()
	await _frames(60)
	var fps := 60000.0 / maxf(float(Time.get_ticks_msec() - tf), 1.0)
	print("[stale] 空转 60 帧 = %d ms ⇒ 约 %.1f fps（%dx%d，不回读）" % [
		Time.get_ticks_msec() - tf, fps, W, H])

	# --- 1. 等姿态 A 的排序表**真的**落地：use_order 转 true 且摘要连续两次不变 ---
	print("[stale] 等姿态 A 排序表落地（盯 use_order + 表摘要，不看画面变化）…")
	var hash_a := ""
	var prev_hash := "?"
	var stable := 0
	var t_first := -1
	while Time.get_ticks_msec() - t_attach < POLL_MAX_MS:
		await _frames(6)
		var h := _order_hash()
		var uo := bool(_mat.get_shader_parameter("use_order"))
		if uo and t_first < 0:
			t_first = Time.get_ticks_msec() - t_attach
			print("[stale]   +%d ms：use_order 已转 true（首次排序表落地）" % t_first)
		if h == prev_hash:
			stable += 1
			if uo and stable >= 2:
				break
		else:
			stable = 0
			prev_hash = h
		hash_a = h
		print("[stale]   +%d ms：use_order=%s 表摘要 %s" % [
			Time.get_ticks_msec() - t_attach, str(uo), h])
	hash_a = _order_hash()
	print("[stale] 姿态 A 就绪：表摘要 %s，use_order=%s" % [
		hash_a, str(_mat.get_shader_parameter("use_order"))])

	var img_a := await _snapshot()
	img_a.save_png(_out.path_join("a_sorted.png"))
	var small_a := _small(img_a)

	# --- 2. 转身 180°，**只轮询排序表**，绝对不回读画面 ---
	#
	# ⚠️ 这一步不能抓图：root.get_texture().get_image() 在 960×540 上要 ~190 ms，
	#    会把主线程整个卡住，而主线程的 _drive_entry 才是 poll()+上传排序表的地方。
	#    一抓图，量到的就不是「排序多久」，而是「我自己的回读多久」。
	#    排序表的 get_image() 只有 347 KB（表项是组不是点），几乎不要钱。
	cam.look_at(eye + Vector3(0.0, 0.0, -1.0), Vector3.UP)   # 姿态 B：朝 -Z
	var t_turn := Time.get_ticks_msec()
	var land_ms := -1
	var hash_b1 := hash_a
	while Time.get_ticks_msec() - t_turn < POLL_MAX_MS:
		await process_frame
		var h := _order_hash()
		if h != hash_a:
			land_ms = Time.get_ticks_msec() - t_turn
			hash_b1 = h
			break
	print("[stale] ★ 新排序表落地：转身后 %d ms（表摘要 %s → %s）" % [
		land_ms, hash_a, hash_b1])

	# --- 3. 落地后才抓图（这回卡顿无所谓，画面已经是对的）---
	var img_landed := await _snapshot()
	img_landed.save_png(_out.path_join("b_landed.png"))
	var small_landed := _small(img_landed)

	var tex_driver: Texture2D = _mat.get_shader_parameter("order_data")
	var width_driver: int = int(_mat.get_shader_parameter("order_width"))
	var group_driver: int = int(_mat.get_shader_parameter("order_group"))
	print("[stale] 后端实际用的组宽 %d，排序表 %dx%d（表项 %d）" % [
		group_driver, width_driver, int(_order_tex.get_image().get_height()),
		width_driver * int(_order_tex.get_image().get_height())])

	# --- 4. 兜底方案：**同一机位**强制 use_order = false（资源顺序）---
	_mat.set_shader_parameter("use_order", false)
	await _frames(4)
	var img_unsorted := await _snapshot()
	img_unsorted.save_png(_out.path_join("b_unsorted.png"))
	var small_unsorted := _small(img_unsorted)
	_mat.set_shader_parameter("use_order", true)

	# --- 5. 质检：自己算一份**逐高斯精确排序**，和组顺序的图对比 ---
	#
	# 这是整个改动唯一的近似：组内按源顺序连排。要证明它看不出来，就得拿
	# 精确排序的图当参照物 —— 所以这里在主线程硬算一次 278 万点的逐高斯排序
	# （约 750 ms，只在探针里付这个代价），替换材质的排序表再拍一张。
	var exact_ok := false
	var img_exact: Image = null
	if _exact_order_texture(node, cam) != null:
		await _frames(3)
		img_exact = await _snapshot()
		img_exact.save_png(_out.path_join("b_exact.png"))
		exact_ok = true
	# 还原后端自己的排序表和组宽
	_mat.set_shader_parameter("order_data", tex_driver)
	_mat.set_shader_parameter("order_width", width_driver)
	_mat.set_shader_parameter("order_group", group_driver)
	_mat.set_shader_parameter("use_order", true)
	await _frames(3)

	# --- 6. 转身回去，抓一张「残余陈旧帧」看还有多糊 ---
	cam.look_at(eye + Vector3(0.0, 0.0, 1.0), Vector3.UP)
	var t_back := Time.get_ticks_msec()
	var img_stale := await _snapshot()
	img_stale.save_png(_out.path_join("a_stale.png"))
	var small_stale := _small(img_stale)
	var back_ms := -1
	while Time.get_ticks_msec() - t_back < POLL_MAX_MS:
		await process_frame
		if _order_hash() == hash_a:
			back_ms = Time.get_ticks_msec() - t_back
			break
	var img_back := await _snapshot()
	img_back.save_png(_out.path_join("a_landed.png"))
	print("[stale] （转回来：%d ms 回到姿态 A 的排序表；转回来那张图与 a_sorted 差 %.4f）" % [
		back_ms, _diff(_small(img_back), small_a)])

	# --- 7. 结论 ---
	print("")
	print("[stale] ── 平均差（0 = 一模一样）──")
	print("[stale] 残余陈旧帧 a_stale  vs 同机位正确图 a_sorted   %.4f" % [
		_diff(small_stale, small_a)])
	print("[stale] 资源顺序 b_unsorted vs 同机位正确图 b_landed   %.4f" % [
		_diff(small_unsorted, small_landed)])
	if exact_ok:
		print("[stale] ★ 组顺序 b_landed   vs 逐高斯精确 b_exact      %.4f  ← 本改动唯一的近似误差" % [
			_diff(small_landed, _small(img_exact))])
	print("[stale] 输出目录 %s" % _out)
	quit(0)


## 用逐高斯精确排序替换材质的排序表（组宽 1），返回用到的纹理（失败返回 null）。
## 只是为了拿一张「精确排序」的参照图，不参与后端任何逻辑。
func _exact_order_texture(splat: Node3D, cam: Camera3D) -> Texture2D:
	if splat == null or cam == null:
		return null
	var gaussian: Resource = splat.get("gaussian")
	if gaussian == null:
		return null
	var xyz: PackedVector3Array = gaussian.get("xyz")
	if xyz.is_empty():
		return null
	var world_forward := -cam.global_transform.basis.z
	var dir_local := splat.global_transform.basis.transposed() * world_forward
	var t0 := Time.get_ticks_msec()
	var order := PackedFloat32Array()
	Sorter.sort_into(xyz, dir_local, order, xyz.size())
	print("[stale] 精确排序 %d 点耗时 %d ms" % [xyz.size(), Time.get_ticks_msec() - t0])
	var dims: Vector2i = DataTextures.order_dimensions(xyz.size())
	var bytes := order.to_byte_array()
	bytes.resize(dims.x * dims.y * 4)
	var img := Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RF, bytes)
	var tex := ImageTexture.create_from_image(img)
	_mat.set_shader_parameter("order_data", tex)
	_mat.set_shader_parameter("order_width", dims.x)
	_mat.set_shader_parameter("order_group", 1)
	_mat.set_shader_parameter("use_order", true)
	return tex


func _snapshot() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


## 排序表字节摘要。用它判断「后端有没有把新排序结果推上 GPU」。
## 一次 = 11.5 MB 回读 + MD5，所以只在轮询点调用。
## （PackedByteArray 在 4.7 里没有 hash()，所以走 HashingContext。）
func _order_hash() -> String:
	if _order_tex == null:
		return "-"
	var img := _order_tex.get_image()
	if img == null:
		return "-"
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(img.get_data())
	return ctx.finish().hex_encode().substr(0, 12)


func _small(img: Image) -> Image:
	var s := Image.new()
	s.copy_from(img)
	s.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	return s


## 两张小图的平均绝对差（0~1）。
func _diff(a: Image, b: Image) -> float:
	if a == null or b == null:
		return 1.0
	var sum := 0.0
	for y in 90:
		for x in 160:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return sum / float(160 * 90) / 3.0


func _frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
