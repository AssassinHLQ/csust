extends Node3D
## GGS 校园：GGS 渲染到纹理，全屏 quad 把「校园 + 同款全景天空」画在场景背景上；
## 大厅/玩家/广场按深度画在前面。没有 Compositor，所以保持 70+ fps。
##
## 2026-10-30 起**默认启用**（打包后也是这套），要回退 GDGS Compute：
##   -- --ggs-campus=off   或   -- --no-ggs-campus
## 1.4 GB 的 packed bin 现在放在项目里（res://campus_ggs.bin），导出才会带上；
## 项目里没有时退回开发机上的老绝对路径。

const BIN := "res://campus_ggs.bin"
const BIN_DEV := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/campus_ggs.bin"
const PlyFileScript := preload("res://addons/ggs_campus/ply_file.gd")
const Rasterizer := preload("res://addons/ggs_campus/gaussian_splatting_rasterizer.gd")

var rasterizer
var cam: Camera3D
var player: Node3D
var quad: MeshInstance3D
var tex := Texture2DRD.new()
var _quad_mat: ShaderMaterial = null
var _fine_ready := -1.0
var panorama: Texture2D
var _ready_done := false
var _gdgs_sc: Node
var _overlay: CanvasLayer
var _overlay_label: Label
var _total := 0
var _active := false
## 玩家在室内时把 GGS 光栅器停掉并释放 GPU 资源；出门再重建。
## AABB 从场景里的 Campus SplatScene 读取（next_level.tscn 已量好）。
var hide_inside_aabb := AABB()
var _released := false
var _inside_clock := 0.0
var _outside_clock := 0.0
## 被 scene_flow 的「黑屏预载」认出来的接口（和 GDGS 的 SplatScene 同一套）：
## 有 preload_on_gate + force_start() + is_ready()，切场景时就会先把校园点云
## 加载完再淡入，而不是进场后卡几秒。实测 610 万点首次上传要 ~5 s。
var preload_on_gate := true
## 起不来的情况（headless / 没 bin / 没相机）置 true，免得预载白等 20 s
var _gave_up := false
var _want_size := Vector2i.ZERO
## 泼溅光栅化纹理的最大宽度（可用 `--ggs-max-w=1600` 改）
var max_render_w := 1920.0
var _bin_path := BIN

## ── 10×10 分块窗口（2026-11-04）──
##
## 全量 1406 MB / 615 万点一次上传太重。分块之后只上传**离玩家最近的 9 块**（3×3），
## 其余根本不进显存（97 块里只碰 9 块 ≈ 9%）。
##
## 光栅器只吃**一个** `bin_path`，所以窗口换的时候把 9 块**拼成一个临时 bin**
## （双缓冲 `user://campus_window_a.bin` / `_b.bin`，后台线程写）再喂它 ——
## 不用改光栅器内部。
## 代价是每次跨格要重写+重传约 100~280 MB。原来这一步在主线程同步做，
## 实测最坏一帧 322~1258 ms；2026-11-05 改成后台线程 + 双缓冲，主线程不阻塞。
## 换来常驻显存从 2.9 GiB 降到约 0.3 GiB。
##
## 清单 `chunks.json` 由离线脚本生成（块名 → 世界中心 / bin 路径 / 字节数），
## 所以这里不需要知道 10×10 的网格参数，按「玩家所在格的 ±1 邻域」选窗口即可。
## ⚠️ 2026-11-05：默认指向 `campus_chunks10w`（**世界坐标**那套）。
## 老的 `campus_chunks10` 是第②步从 SOG 导的，尺度只有全量的 1/3、原点也不对
## （点数/字节数完全相同，所以一直没被发现），细层渲染出来是个「迷你校园」——
## 这才是 3×3 窗口看起来像浮空地皮的真正原因。重新切法：
##   python _tools/split_ggs_bin.py campus_ggs.bin splatdata/campus_chunks10w 10 10
## 回退对照：`--ggs-chunks=res://splatdata/campus_chunks10/chunks.json`
var chunks_json := "res://splatdata/campus_chunks10w/chunks.json"
const CHUNKS_JSON_OLD := "res://splatdata/campus_chunks10/chunks.json"
const WINDOW_SIDE := 3
## 实际使用的窗口边长，`--ggs-window=N` 可以临时改（量「多大才够看」用）。
## 3×3 ≈ 60×50 m，校园本体 ≈ 200×150 m —— 见 `_probe_campus_window_shot.gd` 的对照图。
var window_side := WINDOW_SIDE
## 双缓冲：换窗口时在**后台线程**把新窗口写进另一个文件，当前这份继续渲染。
## 单文件做不到 —— 写的时候会把正在读的那份覆盖掉，画面会闪一下破烂数据。
const WINDOW_BIN_A := "user://campus_window_a.bin"
const WINDOW_BIN_B := "user://campus_window_b.bin"
## 多久重新评估一次窗口（秒）。每帧排 97 个块没必要。
const WINDOW_POLL := 0.5

var _chunk_list: Array = []
var _window_names := PackedStringArray()
var _window_timer := 0.0
var _use_chunks := false
## 当前窗口的中心格（滞回用：见 `_pick_window()`）
var _center_name := ""
## 滞回余量（米）：新中心格要比现用中心近这么多才换窗口。
## 格子约 20×17 m，4 m 的余量 = 跨过中线 2 m 才换，站在交界处左右晃不会翻。
var hyst_m := 4.0
## `--ggs-bin=<path>`：探针直接指定一个 bin（关掉分块）。常驻方案对比用。
var _bin_override := ""

## ── 后台拼 bin（2026-11-05）──
##
## 原来 `_maybe_switch_window()` 在**主线程**同步拷 100~280 MB，实测最坏一帧
## 322~1258 ms（用户感受就是「好卡」）。现在改成：
##   · 主线程只把「块 → 路径/字节数」解析成 job 列表（微秒级）；
##   · `Thread` 在后台把 job 拷进**另一个** slot 文件，当前窗口照常渲染；
##   · 写完了下一次 poll 才切 `_bin_path` 并重建细层 —— 主线程一次都不阻塞。
var _write_thread: Thread = null
var _write_mutex := Mutex.new()
var _write_done := false
var _write_failed := false
var _write_bytes := 0
var _write_path := WINDOW_BIN_A
var _pending_window := PackedStringArray()
var _window_slot := 0

## ── 粗层常驻 + 细层叠加（2026-11-05）──
##
## 分块窗口只有 60×50 m，窗外一片黑（验收见 MEMORY §13）。改成两层：
##   · **粗层**：全校园按每 4 点留 1 抽稀（154 万点 / 352 MB），**一直常驻**，
##     负责远景与天空以下的所有东西 —— 换窗口时它不动，所以画面永远不会空；
##   · **细层**：3×3 分块窗口（43~118 万点），换窗口只重传这一层。
## 两层各一个光栅器、各一张纹理，最后由 `main_sky.gdshader` 按优先级合成：
##     天空 → 粗层 → 细层（细层 alpha 高的地方盖掉粗层）
## 粗层 bin 由 `_tools/decimate_ggs_bin.py` 生成，不进仓库（`*.bin` 已 gitignore）。
const COARSE_BIN := "res://campus_ggs_q4.bin"
const COARSE_BIN_DEV := "C:/Users/WY157/Desktop/GODOT/_arisu_learn/_log/campus_q4.bin"

var coarse_tex := Texture2DRD.new()
var coarse_rasterizer
var _coarse_path := ""
var _coarse_done := false
var _coarse_total := 0
## `--ggs-no-coarse`：关掉粗层做对照（量它到底值不值那份显存/帧率）
var _coarse_off := false
## 静止帧复用（见 `gaussian_splatting_rasterizer.gd` 顶部）：相机没动的那一帧
## 整条 compute 链直接不跑。`--ggs-idle-skip=off` 可关掉做对照。
var _idle_skip := true

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--ggs-campus=off" or a == "--no-ggs-campus":
			_gave_up = true
			set_process(false)
			return
		if a.begins_with("--ggs-max-w="):
			max_render_w = maxf(640.0, float(a.substr(12)))
		if a.begins_with("--ggs-window="):
			window_side = clampi(int(a.substr(13)), 1, 10)
		# 探针用：把滞回关掉（0）验证「原来会反复翻」
		if a.begins_with("--ggs-hyst="):
			hyst_m = maxf(0.0, float(a.substr(11)))
		# 探针用：直接吃某个 bin，绕开分块（量「降采样全量」这类方案）
		if a.begins_with("--ggs-bin="):
			_bin_override = a.substr(10)
		# 粗层 bin（空串 = 关掉粗层，退回单层分块）
		if a.begins_with("--ggs-coarse="):
			_coarse_path = a.substr(13)
		if a == "--ggs-no-coarse":
			_coarse_off = true
		# 换一套分块清单（回退对照老那套 / 换回旧的 mini 尺度）
		if a.begins_with("--ggs-chunks="):
			chunks_json = a.substr(13)
		# 关掉「静止帧复用」做对照（量它到底省了多少）
		if a == "--ggs-idle-skip=off" or a == "--no-ggs-idle-skip":
			_idle_skip = false
	# headless（探针/自检）没有渲染设备，GGS 跑不起来，也别去读 1.4 GB 的 bin
	if DisplayServer.get_name() == "headless":
		_gave_up = true
		set_process(false)
		return
	# 粗层：只有在分块模式下才有意义（单层全量本身就是「粗层」了）。
	# `--ggs-coarse=` 显式给了空串就关掉，方便对照。
	if _bin_override != "":
		_use_chunks = false
		_bin_path = _bin_override
		print("[campus_ggs] 指定 bin：%s" % _bin_path)
	else:
		_use_chunks = _load_manifest()
	if _use_chunks:
		print("[campus_ggs] 分块模式：%d 块，窗口 %d×%d" % [
			_chunk_list.size(), window_side, window_side])
		if _coarse_path == "" and not _coarse_off:
			if FileAccess.file_exists(COARSE_BIN):
				_coarse_path = COARSE_BIN
			elif FileAccess.file_exists(COARSE_BIN_DEV):
				_coarse_path = COARSE_BIN_DEV
		if _coarse_path != "" and FileAccess.file_exists(_coarse_path):
			var cf := FileAccess.open(_coarse_path, FileAccess.READ)
			if cf != null:
				_coarse_total = int(cf.get_length() / 240)
				cf.close()
			print("[campus_ggs] 粗层常驻：%s（%d 点 / %.0f MB）" % [
				_coarse_path, _coarse_total, float(_coarse_total) * 240.0 / 1048576.0])
		else:
			_coarse_path = ""
			push_warning("[campus_ggs] 没有粗层 bin，退回单层分块（窗外会空）")
	elif _bin_override == "":
		if not FileAccess.file_exists(BIN) and FileAccess.file_exists(BIN_DEV):
			_bin_path = BIN_DEV
			push_warning("[campus_ggs] 项目里没有 campus_ggs.bin，退回开发机路径")
		# 两处都没有就别硬撑：不碰 GDGS，让老泼溅照常工作（否则校园会整片消失）
		if not FileAccess.file_exists(_bin_path):
			push_error("[campus_ggs] 找不到 %s，回退 GDGS 泼溅" % _bin_path)
			_gave_up = true
			set_process(false)
			return
	var level := get_parent()
	_gdgs_sc = get_node_or_null("/root/SplatCompositor")
	if _gdgs_sc != null:
		_gdgs_sc.set_process(false)
	var campus := level.get_node_or_null("Campus")
	if campus != null:
		var ha = campus.get("hide_inside_aabb")
		if ha is AABB:
			hide_inside_aabb = ha
		campus.set("auto_start", false)
		campus.set_process(false)
		# auto_start 是在子节点 _ready 里判的，这里已经晚了：那条「等 8 s 再解码」
		# 的协程已经在跑。直接释放 GDGS 那份校园，省 16 s 解码 + 一块显存，
		# 也避免两套渲染器同时用 RenderingDevice 打架（实测掉到 23 fps）。
		campus.queue_free()
	player = level.get_node_or_null("Player") as Node3D
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null and we.environment.sky != null:
		var mat = we.environment.sky.sky_material
		if mat != null and mat is PanoramaSkyMaterial:
			panorama = (mat as PanoramaSkyMaterial).panorama
	if panorama == null:
		panorama = load("res://assets/sky/sky_pink.jpg")
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)
	_overlay_label = Label.new()
	_overlay_label.text = "校园渲染器加载中..."
	_overlay_label.add_theme_font_size_override("font_size", 30)
	_overlay_label.position = Vector2(80, 80)
	_overlay.add_child(_overlay_label)
	set_process(true)

func _exit_tree() -> void:
	_join_window_write()
	# ⚠️ 退出时 `queue_free()` 要等到这一帧末尾才真正释放，而 `_release_campus()`
	#    会立刻把纹理 RID 还掉 —— 中间那一瞬 quad 还活着、材质还指着已释放的纹理，
	#    渲染管线重建 uniform set 时就会报
	#    `Texture (binding: N, index 0) is not a valid texture`。
	#    所以退出路径**显式、同步**地把 quad 连同材质参数一起拆掉：
	#    先把材质里的纹理参数置空（`Texture2DRD` 此时 RID 还有效，只是解绑），
	#    再 `free()` 掉 quad，最后才让 `_release_campus()` 去还纹理。
	if quad != null:
		if _quad_mat != null:
			_quad_mat.set_shader_parameter("render_texture", null)
			_quad_mat.set_shader_parameter("coarse_texture", null)
		remove_child(quad)
		quad.free()
		quad = null
		_quad_mat = null
	_release_campus()
	if _gdgs_sc != null and is_instance_valid(_gdgs_sc):
		_gdgs_sc.set_process(true)


## 退出 / 释放时把后台写线程收干净，否则换场景会漏一个线程。
func _join_window_write() -> void:
	if _write_thread == null:
		return
	_write_thread.wait_to_finish()
	_write_thread = null
	_write_mutex.lock()
	_write_done = false
	_write_mutex.unlock()
	_pending_window = PackedStringArray()

func _make_bundle() -> bool:
	cam = get_viewport().get_camera_3d()
	if cam == null:
		return false
	if tex == null:
		tex = Texture2DRD.new()
		# `_release_campus()` 会把 tex 丢掉，重建之后必须让 quad 的材质重新指过来，
		# 否则 quad 还握着旧的 Texture2DRD（那张的 RID 已经被光栅器还掉了）。
		if _quad_mat != null:
			_quad_mat.set_shader_parameter("render_texture", tex)
	# 不要 Compositor：GGS 走全屏 quad，Compositor 会把光栅器拖到个位数帧率。
	if cam.compositor != null:
		cam.compositor = null
	var f := FileAccess.open(_bin_path, FileAccess.READ)
	if f == null:
		push_error("[campus_ggs] 打不开 bin: %s" % _bin_path)
		return false
	var count := int(f.get_length() / 240)
	_total = count
	f.close()
	var ply = PlyFileScript.new()
	ply.size = count
	rasterizer = Rasterizer.new(ply, get_viewport().get_size(), tex, cam)
	rasterizer.bin_path = _bin_path
	rasterizer.model_scale[0] = 1.0
	rasterizer.idle_skip = _idle_skip

	# 粗层：和细层同一个相机、同一个视口尺寸，只是点少、且不随窗口换。
	# 注意它必须是**独立的一份**（独立 bin_path / 独立纹理），否则换窗口时会被一起丢掉。
	if _coarse_path != "" and coarse_rasterizer == null and _coarse_total > 0:
		var cply = PlyFileScript.new()
		cply.size = _coarse_total
		var vs2: Vector2i = get_viewport().get_size()
		# `_release_campus()` 会把 coarse_tex 丢掉（见那里的说明），这里补回来。
		if coarse_tex == null:
			coarse_tex = Texture2DRD.new()
			if _quad_mat != null:
				_quad_mat.set_shader_parameter("coarse_texture", coarse_tex)
		coarse_rasterizer = Rasterizer.new(cply, vs2, coarse_tex, cam)
		coarse_rasterizer.bin_path = _coarse_path
		coarse_rasterizer.model_scale[0] = 1.0
		coarse_rasterizer.idle_skip = _idle_skip
		var sc2 := minf(1.0, max_render_w / maxf(float(vs2.x), 1.0))
		coarse_rasterizer.render_scale = [sc2]
		coarse_rasterizer.texture_size = vs2
		_coarse_done = true

	_ready_done = true
	return true

## scene_flow 在黑屏期间调它，把点云加载提前开始（本来 _process 第一帧也会做）。
func force_start() -> void:
	if _gave_up:
		return
	set_process(true)
	if not _ready_done:
		_make_bundle()


## 点云全部上传完 = 可以淡入了。起不来的情况直接算「就绪」，别让切场景干等。
func is_ready() -> bool:
	if _gave_up:
		return true
	# 玩家在厅里时不需要这块泼溅（大厅是实体网格，见 _process 的室内分支）：
	# 直接算「就绪」，否则 scene_flow 的切场景黑屏会一直等它，实测干等 20 s。
	if player != null and hide_inside_aabb.size != Vector3.ZERO \
			and hide_inside_aabb.has_point(player.global_position):
		return true
	if not _ready_done or rasterizer == null:
		return false
	return rasterizer.is_loaded == true


## 室内释放：停掉 GGS 调用，把光栅器用过的 RID/缓冲交还给 RenderingDevice。
## 出门后 _process 会重新 _make_bundle()，代价是一次 bin 重传（约 1.5 s）。
##
## `keep_coarse=true` 只丢**细层**（换分块窗口时用）：粗层是全校园的底，
## 换窗口时它必须留在显存里 —— 否则每次跨格都要重传 352 MB，
## 而且那 0.5 s 里画面就只剩天空，等于白做了两层。
func _release_campus(keep_coarse := false) -> void:
	_released = true
	_active = false
	if not keep_coarse:
		# 换窗口时**不动 quad / tex**：quad 继续画着，粗层那张纹理还在，
		# 新细层传好之前玩家看到的就是粗层 —— 不会黑一下（实测从空 4 帧降到 0 帧）。
		if quad != null:
			quad.queue_free()
			quad = null
		if tex != null:
			# ⚠️ 2026-11-06 修：这里**不能**再 `tex.texture_rd_rid = RID()`。
			#    给 `texture_rd_rid` 赋值是**拥有权转移**（会释放原来持有的 RID），
			#    而那个 RID 是细层光栅器建的 —— 下面 `ctx.free()` 会再释放一次，
			#    于是 `ERROR: Attempted to free invalid ID`。丢引用即可，
			#    纹理由光栅器自己还（`cleanup_gpu()` 已经先还纹理再放 context）。
			tex = null
	if rasterizer != null:
		if rasterizer.load_thread != null and rasterizer.load_thread.is_started():
			rasterizer.should_terminate_thread[0] = true
			rasterizer.load_thread.wait_to_finish()
		var ctx = rasterizer.context
		rasterizer = null
		if ctx != null:
			RenderingServer.call_on_render_thread(ctx.free)
	_ready_done = false
	if keep_coarse:
		# 细层没了但粗层还在：_make_bundle() 要能只重建细层，所以这里不动 coarse_*。
		#
		# ⚠️ 2026-11-06 修：这一段原来会报
		#    `ERROR: Attempted to free invalid ID`（每次换窗口一次，栈顶就是这行）。
		#    错在**给 `Texture2DRD.texture_rd_rid` 赋值是「拥有权转移」，不是改指针**：
		#    它会把原来持有的那个 RID **释放掉**。于是变成：
		#      ① `tex.texture_rd_rid = 粗层 RID`   → 释放细层那个 RID
		#      ② `RenderingServer.call_on_render_thread(ctx.free)`（上面几行）
		#                                          → 把同一批 RID 再释放一遍
		#    同一个 RID 被释放两次。而且这跟「悬空绑定」是两码事 ——
		#    **细层纹理本来就该由光栅器自己还**（`cleanup_gpu()` 里
		#    `render_texture.texture_rd_rid = RID()` 会还），这里根本不该碰 `tex`。
		#    quad 也不会采到悬空纹理：`fine_ready` 已经是 0，着色器整个跳过这次采样。
		return
	if coarse_rasterizer != null:
		if coarse_rasterizer.load_thread != null and coarse_rasterizer.load_thread.is_started():
			coarse_rasterizer.should_terminate_thread[0] = true
			coarse_rasterizer.load_thread.wait_to_finish()
		var cctx = coarse_rasterizer.context
		coarse_rasterizer = null
		_coarse_done = false
		if cctx != null:
			RenderingServer.call_on_render_thread(cctx.free)
	if coarse_tex != null:
		# ⚠️ 同上：赋值 `texture_rd_rid` 会释放原来持有的 RID，而粗层纹理的 RID 已经
		#    被上面的 `cctx.free()` 释放过了 ⇒ 双重释放。丢引用就够。
		coarse_tex = null


func _make_quad() -> void:
	quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	qm.flip_faces = true
	quad.mesh = qm
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.extra_cull_margin = 16384.0
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FileAccess.get_file_as_string("res://addons/ggs_campus/shaders/main_sky.gdshader")
	sm.shader = sh
	sm.set_shader_parameter("render_texture", tex)
	sm.set_shader_parameter("coarse_texture", coarse_tex)
	sm.set_shader_parameter("panorama", panorama)
	sm.set_shader_parameter("fine_ready", 0.0)
	quad.material_override = sm
	_quad_mat = sm
	add_child(quad)
	quad.visible = false
	print("[campus_ggs] %d 点，quad + 天空已就绪%s" % [
		_total, "（粗层 %d 点）" % _coarse_total if coarse_rasterizer != null else ""])
	quad.visible = false

func _process(_dt: float) -> void:
	var inside := player != null and hide_inside_aabb.size != Vector3.ZERO \
			and hide_inside_aabb.has_point(player.global_position)
	if inside:
		_outside_clock = 0.0
		_inside_clock += _dt
		if quad != null:
			quad.visible = false
		_active = false
		# ⚠️ 这条分支是 2026-11-03（a7ec536）加「室内释放」时进来的，当时漏了两件事，
		#    结果**出生点在厅里就是永久黑屏**：遮罩「校园渲染器加载中...」永不撤、
		#    还因为 is_ready() 一直 false 让切场景的黑屏干等 20 s。
		#    厅里本来就不需要这块泼溅（大厅是实体网格），遮罩必须照样撤。
		if _overlay != null and _overlay.visible:
			_overlay.visible = false
		if not _released and _inside_clock >= 0.3:
			_release_campus()
		return
	_inside_clock = 0.0
	_outside_clock += _dt
	if _released:
		if _outside_clock < 0.25:
			return
		_released = false
	# 分块模式：先把「离玩家最近的 9 块」拼成临时 bin，再交给 _make_bundle()
	_maybe_switch_window(_dt)
	# ⚠️ 窗口还没拼好时**绝对不能**去 _make_bundle() —— 那时 `_bin_path` 还是全量那份
	#    1406 MB，会白传一遍（实测第一版就是这样：启动瞬间 187 MiB 起步）。
	if _use_chunks and _window_names.is_empty():
		return
	if not _ready_done and not _make_bundle():
		return
	if cam == null or not is_instance_valid(cam):
		_ready_done = false
		return
	if cam.compositor != null:
		cam.compositor = null
	# 4K 最大化窗口会按 3504×2049 光栅化，实测只有 28 fps。泼溅纹理封顶 1920 宽，
	# 剩下的交给全屏 quad 线性放大（3× 的泼溅本来就糊，肉眼几乎看不出差别）。
	var vs: Vector2i = get_viewport().get_size()
	if _want_size != vs:
		_want_size = vs
		var sc := minf(1.0, max_render_w / maxf(float(vs.x), 1.0))
		rasterizer.render_scale = [sc]
		rasterizer.texture_size = vs
		if coarse_rasterizer != null:
			coarse_rasterizer.render_scale = [sc]
			coarse_rasterizer.texture_size = vs
	rasterizer.update_camera_matrices()
	if rasterizer.is_loaded:
		RenderingServer.call_on_render_thread(rasterizer.rasterize)
	else:
		RenderingServer.call_on_render_thread(rasterizer.pump_load)
	# ⚠️ 窗口尺寸一变，rasterizer 会**新建**一个 Texture2DRD（旧 RID 被释放），
	#    我们手里这个 tex 必须跟着换，否则 quad 指着已释放的贴图：
	#    校园整片不画，还会每帧刷 "Uniforms supplied for set (3)"。
	if rasterizer.render_texture != null 			and tex.texture_rd_rid != rasterizer.render_texture.texture_rd_rid:
		tex.texture_rd_rid = rasterizer.render_texture.texture_rd_rid
	# 粗层：同一套相机/尺寸，独立纹理。它**不随窗口换**，所以画面永远有底。
	if coarse_rasterizer != null:
		coarse_rasterizer.update_camera_matrices()
		if coarse_rasterizer.is_loaded:
			RenderingServer.call_on_render_thread(coarse_rasterizer.rasterize)
		else:
			RenderingServer.call_on_render_thread(coarse_rasterizer.pump_load)
		if coarse_rasterizer.render_texture != null and coarse_tex != null \
				and coarse_tex.texture_rd_rid != coarse_rasterizer.render_texture.texture_rd_rid:
			coarse_tex.texture_rd_rid = coarse_rasterizer.render_texture.texture_rd_rid
	if quad == null and tex != null and tex.texture_rd_rid.is_valid() \
			and panorama != null and panorama.get_rid().is_valid():
		_make_quad()
	if _overlay != null and _overlay.visible:
		var loaded := int(rasterizer.num_splats_loaded[0])
		_overlay_label.text = "校园渲染器加载中... %d%%" % (0 if _total == 0 else int(100.0 * loaded / _total))
		if rasterizer.is_loaded:
			_overlay.visible = false
	# 任一层就绪就能画：换窗口时细层在重传，粗层顶着，不能把 quad 藏起来（那就是黑一下）。
	var fine_ok: bool = rasterizer != null and rasterizer.is_loaded
	var any_loaded: bool = fine_ok \
		or (coarse_rasterizer != null and coarse_rasterizer.is_loaded)
	# 细层没就绪就**完全不采**它（`main_sky.gdshader` 的 `fine_ready`）：
	# 分帧上传之后「细层没传完」会持续很多帧，不挡这一下就会采到未初始化的纹理。
	if _quad_mat != null:
		var want_fine := 1.0 if fine_ok else 0.0
		if want_fine != _fine_ready:
			_fine_ready = want_fine
			_quad_mat.set_shader_parameter("fine_ready", want_fine)
	_active = player != null and player.global_position.z < -74.0 and any_loaded
	if quad != null:
		quad.visible = _active


# ─────────────────────────────────────────────────────────────
# 10×10 分块 + 3×3 窗口
# ─────────────────────────────────────────────────────────────

## 读离线生成的清单（块名 → 世界中心 / bin / 字节数）。
func _load_manifest() -> bool:
	if not FileAccess.file_exists(chunks_json):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(chunks_json))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var arr: Array = (parsed as Dictionary).get("chunks", [])
	if arr.is_empty():
		return false
	_chunk_list.clear()
	for d in arr:
		var dd: Dictionary = d
		var c: Array = dd.get("center", [0.0, 0.0, 0.0])
		_chunk_list.append({
			"name": String(dd.get("name", "")),
			"center": Vector3(float(c[0]), float(c[1]), float(c[2])),
			"bin": String(dd.get("bin", "")),
			"bytes": int(dd.get("bytes", 0)),
		})
	return _chunk_list.size() > 0


## 以玩家所在格子为中心取 `window_side`² 块（10×10 网格的 ±1 邻域）。
##
## 换掉原来「按 XZ 距离取最近 N 块」的理由（2026-11-05）：
##  - 最近 N 块拼出来的形状是斜的、玩家总在**边缘**，窗口外一抬眼就是黑；
##  - 距离序在格子交界处会反复抖动，每抖一次就是一次「重拼 bin + 重传」。
## 改成「中心格 ±1」后，窗口永远**居中**在玩家周围，而且只有跨过格子中线才换。
## 再加一道滞回（`hyst_m`）：新格子必须比现用中心近 4 m 以上才换，
## 站在格子交界处左右晃不会来回翻。
func _pick_window() -> PackedStringArray:
	var out := PackedStringArray()
	if player == null or _chunk_list.is_empty():
		return out
	var pp := player.global_position
	var best := ""
	var best_d := INF
	for c in _chunk_list:
		var d: Vector3 = (c["center"] as Vector3) - pp
		var dd := d.x * d.x + d.z * d.z
		if dd < best_d:
			best_d = dd
			best = String(c["name"])
	if best.is_empty():
		return out
	# 滞回：新中心格要比现用中心**近 4 m 以上**才换窗口。
	# ⚠️ 必须比「米」，不能比平方距离：格子间距约 20 m，平方距离一动就是上百，
	#    拿 2 m² 当余量等于没有滞回（第一版就是这么写错的）。
	if _center_name != "" and best != _center_name:
		var ce := _chunk_entry(_center_name)
		if not ce.is_empty():
			var cd: Vector3 = (ce["center"] as Vector3) - pp
			var cur_r := sqrt(cd.x * cd.x + cd.z * cd.z)
			if sqrt(best_d) + hyst_m >= cur_r:
				best = _center_name
	_center_name = best
	var ij := _parse_ij(best)
	if ij.is_empty():
		return out
	var half := window_side / 2
	var ci := int(ij["i"])
	var cj := int(ij["j"])
	for i in range(ci - half, ci + half + 1):
		for j in range(cj - half, cj + half + 1):
			var nm := "Chunk_%d_%d" % [i, j]
			if _chunk_entry(nm).is_empty():
				continue
			out.append(nm)
	out.sort()
	return out


## "Chunk_6_4" → {"i": 6, "j": 4}
func _parse_ij(nm: String) -> Dictionary:
	var parts := nm.split("_")
	if parts.size() != 3:
		return {}
	return {"i": int(parts[1]), "j": int(parts[2])}


func _chunk_entry(nm: String) -> Dictionary:
	for c in _chunk_list:
		if String(c["name"]) == nm:
			return c
	return {}


## 主线程**同步**把选中的几块拼成一个 bin。
## ⚠️ 现在只给探针用（`_probe_switch_hitch.gd` 拿它量「同步拷要多久」），
##    正式路径走 `_start_window_write()` + 后台线程，不再阻塞主线程。
func _write_window(names: PackedStringArray) -> int:
	var f := FileAccess.open(WINDOW_BIN_A, FileAccess.WRITE)
	if f == null:
		push_error("[campus_ggs] 写不了 %s" % WINDOW_BIN_A)
		return 0
	var written := 0
	for nm in names:
		var e := _chunk_entry(nm)
		if e.is_empty():
			continue
		var path := "res://" + String(e["bin"])
		var src := FileAccess.open(path, FileAccess.READ)
		if src == null:
			push_warning("[campus_ggs] 打不开 %s" % path)
			continue
		var left := int(e["bytes"])
		while left > 0:
			var n := mini(1048576, left)
			var buf := src.get_buffer(n)
			if buf.size() != n:
				break
			f.store_buffer(buf)
			left -= n
			written += n
		src.close()
	f.close()
	return written


## 后台线程：把 job 列表里的分块按字节拷进目标 bin。
## ⚠️ 这里**只做文件 I/O**：`_chunk_list` / `_chunk_entry()` 这些主线程数据结构一概不碰
##    （跨线程读不安全），路径与字节数都在主线程先解析好塞进 job。
## ⚠️ 也不在这里 `push_warning`：那会从 worker 线程写主线程的日志，会炸。
func _write_worker(jobs: Array, path: String) -> void:
	var written := 0
	var failed := false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		failed = true
	else:
		for j in jobs:
			var src := FileAccess.open(String(j["path"]), FileAccess.READ)
			if src == null:
				failed = true
				continue
			var left := int(j["bytes"])
			while left > 0:
				var n := mini(4 * 1024 * 1024, left)
				var buf := src.get_buffer(n)
				if buf.size() != n:
					failed = true
					break
				f.store_buffer(buf)
				left -= n
				written += n
			src.close()
		f.close()
	_write_mutex.lock()
	_write_bytes = written
	_write_failed = failed
	_write_done = true
	_write_mutex.unlock()


## 主线程：把窗口解析成 job 列表并起线程。返回 false = 这一轮放弃（下一 poll 再试）。
func _start_window_write(names: PackedStringArray) -> bool:
	var jobs: Array = []
	for nm in names:
		var e := _chunk_entry(nm)
		if e.is_empty():
			continue
		jobs.append({"path": "res://" + String(e["bin"]), "bytes": int(e["bytes"])})
	if jobs.is_empty():
		return false
	_write_path = WINDOW_BIN_B if _window_slot == 0 else WINDOW_BIN_A
	_write_mutex.lock()
	_write_bytes = 0
	_write_failed = false
	_write_done = false
	_write_mutex.unlock()
	_pending_window = names
	_write_thread = Thread.new()
	_write_thread.start(_write_worker.bind(jobs, _write_path))
	return true


## 后台写完了吗？写完了就切 `_bin_path` 并让下一帧重建细层。
func _poll_window_write() -> void:
	if _write_thread == null:
		return
	if not _write_done:
		return
	_write_thread.wait_to_finish()
	_write_thread = null
	var names := _pending_window
	_write_mutex.lock()
	var bytes := _write_bytes
	var failed := _write_failed
	_write_mutex.unlock()
	_pending_window = PackedStringArray()
	if failed or names.is_empty() or bytes <= 0:
		push_warning("[campus_ggs] 后台拼 bin 失败，这一轮窗口不换")
		return
	_window_names = names
	_bin_path = _write_path
	_window_slot = 1 - _window_slot
	# 重建细层：先放掉旧的 RID，再让 _process 里的 `_make_bundle()` 重来。
	# ⚠️ 必须 keep_coarse —— 粗层是全校园的底，换窗口时它留在显存里，
	#    这样细层重传的这段时间画面由粗层顶着，不会空。
	_release_campus(true)
	_released = false
	print("[campus_ggs] 窗口切换 → %d 块 / %.0f MB（后台拼好，主线程没停）" % [
		names.size(), float(bytes) / 1048576.0])


## 每 WINDOW_POLL 秒评估一次。窗口变了就**在后台**重拼 bin，拼好再重建细层。
func _maybe_switch_window(dt: float) -> void:
	if not _use_chunks:
		return
	# 上一次的后台写还没落地：这一帧什么都不做，也**不重新选窗口**
	# （重新选会推进 `_center_name`，白翻一次）。
	if _write_thread != null:
		_poll_window_write()
		return
	_window_timer += dt
	var first := _window_names.is_empty()
	if not first and _window_timer < WINDOW_POLL:
		return
	_window_timer = 0.0
	var want := _pick_window()
	if want.is_empty() or want == _window_names:
		return
	_start_window_write(want)
