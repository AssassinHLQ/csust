extends Node3D
## GGS 校园：GGS 渲染到纹理，全屏 quad 把「校园 + 同款全景天空」画在场景背景上；
## 大厅/玩家/广场按深度画在前面。没有 Compositor，所以保持 70+ fps。
##
## 2026-10-30 起**默认启用**（打包后也是这套），要回退 GDGS Compute：
##   -- --ggs-campus=off   或   -- --no-ggs-campus
## 1.4 GB 的 packed bin 现在放在项目里（res://campus_ggs.bin），导出才会带上；
## 项目里没有时退回开发机上的老绝对路径。

const BIN := "res://campus_ggs.bin"
## ⚠️ 2026-11-10：开发机绝对路径只在**编辑器/调试**下有效。
##   导出到别的机器后这个路径不存在，`_ready()` 的 `file_exists` 会把关，
##   不会拿错文件；但为了让发布版彻底不带这个死路径，用 `OS.has_feature` 包一层。
const BIN_DEV := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/campus_ggs.bin"
## 缓存子目录名（交给 `scripts/cache_dir.gd` 拼到 exe 同目录下的 `_cache/`）
const CACHE_SUBDIR := "window"
const CacheDir := preload("res://scripts/cache_dir.gd")
const PlyFileScript := preload("res://addons/ggs_campus/ply_file.gd")
const Rasterizer := preload("res://addons/ggs_campus/gaussian_splatting_rasterizer.gd")

var rasterizer
var cam: Camera3D
var player: Node3D
var quad: MeshInstance3D
var tex := Texture2DRD.new()
var _quad_mat: ShaderMaterial = null
var _fine_ready := -1.0
## 粗层「就绪」开关，同上：-1 = 还没设过（首帧一定写一次）
var _coarse_ready := -1.0
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
## 默认走哪套由 `_resolve_chunks_json()` 决定（空串 = 自动挑）。
var chunks_json := ""
## ⚠️ 2026-11-11：新那套 = **分块 SOG**（`splatdata/campus_sog/chunks.json`）。
##   旧那套 `campus_chunks10w/*.bin` 合计 1,406 MB 的世界坐标 raw，占了整个包的
##   一半以上；新那套只有 85 MB，运行时现场解码、再套一个**从数据反解出来**的
##   相似变换（`tools/fit_campus_frame.py`，残差 10 µm；`_verify_campus_sog.gd` 13/13）。
##   新那套不在时自动退回旧那套 —— 两台机器都能跑。
const CHUNKS_JSON_SOG := "res://splatdata/campus_sog/chunks.json"
const CHUNKS_JSON_RAW := "res://splatdata/campus_chunks10w/chunks.json"
const CHUNKS_JSON_OLD := "res://splatdata/campus_chunks10/chunks.json"
const WINDOW_SIDE := 3
## 实际使用的窗口边长，`--ggs-window=N` 可以临时改（量「多大才够看」用）。
## 3×3 ≈ 60×50 m，校园本体 ≈ 200×150 m —— 见 `_probe_campus_window_shot.gd` 的对照图。
var window_side := WINDOW_SIDE
## 双缓冲：换窗口时在**后台线程**把新窗口写进另一个文件，当前这份继续渲染。
## 单文件做不到 —— 写的时候会把正在读的那份覆盖掉，画面会闪一下破烂数据。
##
## ⚠️ 2026-11-10：从 `user://campus_window_a.bin` 挪到 **exe 同目录 `_cache/window/`**
##    （见 `scripts/cache_dir.gd`）。理由：用户要求「不要抢 AppData」，
##    而这两个文件实测占 **219.6 MB**（各 109.8 MB）。
##    它们是每次换窗口重写的临时物，放 exe 旁边删掉即净。
##    原来写成 `const`，现在改成函数 —— 因为路径要等 CacheDir 解析完才知道。
var _window_bin_a := ""
var _window_bin_b := ""

## 取双缓冲槽的文件路径（0 = A，1 = B）。首次调用时解析并缓存。
func _window_bin(slot: int) -> String:
	if _window_bin_a.is_empty():
		_window_bin_a = CacheDir.file_for(CACHE_SUBDIR, "campus_window_a.bin")
		_window_bin_b = CacheDir.file_for(CACHE_SUBDIR, "campus_window_b.bin")
		if _window_bin_a.is_empty():
			# 缓存不可用：退回 user://，至少还能跑
			_window_bin_a = "user://campus_window_a.bin"
			_window_bin_b = "user://campus_window_b.bin"
	return _window_bin_a if slot == 0 else _window_bin_b
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
var _write_path := ""
var _pending_window := PackedStringArray()
var _window_slot := 0

## ── 分块 SOG（2026-11-11）──
##
## SOG 块里是 `SogRuntime` 解出来的**模型绝对坐标**，而 GGS 光栅器要的是
## **世界坐标**（旧 `.bin` 是离线用 `Campus.splat_node.global_transform` 烘过的）。
## 两者差一个相似变换 A（旋转 × 75 倍均匀缩放 + 平移）：
##     p_world = A·p + origin        C_world = A·C·Aᵀ（A 已含 scale，别再乘 scale²）
## A 不是手算的 —— 手算要处理 `world_scale=75` 之外的 1.2° 节点旋转（500 m 上
## 就是 10 m），见 `tools/fit_campus_frame.py`。
##
## 解码与变换都在**已有的后台写窗口线程**里做，主线程一次都不停；每块变换完
## 落到 exe 旁边 `_cache/campus_<清单指纹>/`，下次回到这片区域直接字节拷贝
## （和 `.gdgsrt` 一个思路）。
const CACHE_SUBDIR_CAMPUS := "campus"
const SogRuntimeScript := preload("res://scripts/sog_runtime.gd")
const BYTES_PER_SPLAT := 240
var _frame_basis := Basis.IDENTITY
var _frame_origin := Vector3.ZERO
var _frame_scale := 1.0
## 分块共用的 shN 调色板（整张 2.26 MB；97 块各带一份会白多 219 MB）
var _palette := PackedByteArray()
## 缓存子目录（名字里带清单指纹：清单一变，旧缓存自然作废）
var _cache_subdir := ""
## 粗层也走 SOG 时的源文件与后台准备状态
var _coarse_sog := ""
var _coarse_points := 0
var _coarse_thread: Thread = null
var _coarse_mutex := Mutex.new()
var _coarse_flag := false
var _coarse_ok := false
var _coarse_cache := ""

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
## 椭球（协方差）缩放。由 `--ggs-cov=` 覆盖，见下面的参数解析。
##
## ── 为什么默认不是 1.0（2026-11-08，用户：「校园泼溅一片白 / 完全糊掉」）──
## 本喵先排掉了数据侧：三份 bin（细层 1.47 GB / 粗层 / 运行时窗口切片）的
## opacity 全在 [0,1]、协方差对角全为正、布局与 shader 结构体逐字节一致、
## `time` 字段全为 0 —— **数据是合规的**。剩下的只能是「椭球的世界单位」。
## 于是给 GGS 加了这个只作用于协方差的旋钮，然后出图扫描（`_probe_campus_cov_shot.gd`）：
##
##   cov = 1.0（原值）→ 巨大糊块，相机钻进去就是**整屏全白**（用户看到的样子）
##   cov = 0.3        → 拖出大片白色条纹，比 0.1 还糟
##   cov = 0.1        → **几何清清楚楚**：地面、楼、树、天空都认得出
##
## 所以默认取 0.1。⚠️ 2026-11-09 补记：0.1 只是**压住了白屏**，画面仍是稀疏点云 ——
## 用户又报「为什么校园泼溅还没有修好」。真正的病根是**协方差分布过宽**
## （离群点到 6.84 m），已经改用下面的逐点钳制（`COV_CAP` / `COV_REF`）解决，
## 并配合把本系数放回 1.0（钳制已经把量级接管了）。详见 `_cov_cap` 的注释。
var _cov_scale := 0.1
## ── 逐点协方差钳制（2026-11-09，用户：「为什么校园泼溅还没有修好」）──
##
## 本喵把 `campus_ggs.bin` 614 万点全量解出来量了（`_tools/diag_cov_dist.py`）：
##
##   · 最近邻点距 中位 **0.966 m**（p90 1.913 m）
##   · σ_iso 中位 **0.132 m** ⇒ σ/间距 ≈ 0.14 ⇒ 椭球只盖住间距的 1/7
##   · √λ 中位 0.187 m，p99 1.34 m，**最大 6.84 m**
##     （2.2% / 13 万个点 > 1 m，0.26% > 2 m）
##
## ⇒ 病根是**分布过宽**，一个全局系数只能二选一：
##    调大 = 中位够但离群糊成整屏白（cov 0.3 那张图）；调小 = 离群不糊但只剩点云（cov 0.1）。
##
## 所以改成两步：先逐点钳制把离群点拉回量级，再用中位数归一放大到能连成面。
## 实测（钳制后）：√λ 从 0.187/6.84 m 收到 0.187/0.36 m，分布窄了 19 倍。
##
## `--ggs-cov-clamp=0` 关掉（= 老行为），方便对照。
const COV_CAP := 0.09      # 特征值上限（m²）⇒ σmax 0.30 m
const COV_REF := 0.036     # 中位数特征值（m²）⇒ σ_ref 0.19 m
var _cov_cap := COV_CAP
var _cov_ref := COV_REF

## ── 2026-11-11：校园泼溅**默认关闭**（用户：「先去掉校园泼溅」）──
##
## 背景：校园泼溅的画质一直没调好（稀疏成点云 / 与知天下同类数据差一截），
## 而它又是包体最大的一块（细层 85 MB + 粗层 21 MB + 底层 SOG 87 MB）。
## 用户要求先去掉，把校园留成空景。
##
## 做法：**默认 `false`，命令行可开回来**（`--ggs-campus=on`），
## 不删代码、不动场景结构 —— 画质调好之后一行就能恢复。
##
## 关掉之后的行为：
##   · 本节点直接 `_gave_up`，不建光栅器、不占显存、不解码
##   · `next_level.gd` 会把 `Campus`（GDGS 那份）也一起关掉（见那里的 `_campus_splat_enabled()`）
##   · 校园区只剩实体网格（地板 / 桥 / 平台 / 碰撞），不会花屏也不会白屏
const CAMPUS_SPLAT_ENABLED := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--ggs-campus=on" or a == "--ggs-campus":
			# 显式要求打开：把下面的默认关闭顶掉
			set_meta("force_on", true)
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
		# 椭球（协方差）缩放：本喵 2026-11-08 排「校园泼溅糊成一片/全白」用的扫描旋钮。
		# 只作用于椭球大小，不动位置（见 GGS shader 里 `cov_scale` 那段）。
		if a.begins_with("--ggs-cov="):
			_cov_scale = clampf(float(a.substr(10)), 0.0001, 100.0)
		# 逐点钳制开关 / 参数（对照用）。0 = 关掉，退回只看 `--ggs-cov=` 的老行为。
		if a.begins_with("--ggs-cov-clamp="):
			_cov_cap = maxf(0.0, float(a.substr(16)))
			if _cov_cap <= 0.0:
				_cov_ref = 0.0
		if a.begins_with("--ggs-cov-ref="):
			_cov_ref = maxf(0.0, float(a.substr(14)))
	# headless（探针/自检）没有渲染设备，GGS 跑不起来，也别去读 1.4 GB 的 bin
	if DisplayServer.get_name() == "headless":
		_gave_up = true
		set_process(false)
		return
	# ── 2026-11-11：**默认关闭**（见 `CAMPUS_SPLAT_ENABLED` 那段）──
	# 必须放在参数解析**之后**：`--ggs-campus=on` 会先 set_meta("force_on")，
	# 放在前面的话会被这次默认关闭顶掉。
	if not CAMPUS_SPLAT_ENABLED and not has_meta("force_on"):
		_gave_up = true
		set_process(false)
		print("[campus_ggs] 校园泼溅默认关闭（要开：-- --ggs-campus=on）")
		return

	# 粗层：只有在分块模式下才有意义（单层全量本身就是「粗层」了）。
	# `--ggs-coarse=` 显式给了空串就关掉，方便对照。
	if _bin_override != "":
		_use_chunks = false
		_bin_path = _bin_override
		print("[campus_ggs] 指定 bin：%s" % _bin_path)
	else:
		if chunks_json.is_empty():
			chunks_json = _resolve_chunks_json()
		_use_chunks = _load_manifest()
	if _use_chunks:
		print("[campus_ggs] 分块模式：%d 块，窗口 %d×%d，源=%s" % [
			_chunk_list.size(), window_side, window_side,
			"SOG 块（运行时解码）" if not _palette.is_empty() else "raw bin"])
		if _coarse_sog != "" and not _coarse_off:
			# 粗层也是 SOG：先看有没有缓存好的 raw bin（有就直接用），
			# 否则起后台线程解（154 万点，实测约 8 s），解完再挂光栅器。
			_coarse_cache = CacheDir.file_for(_cache_subdir, "coarse.bin")
			if _coarse_cache != "" and FileAccess.file_exists(_coarse_cache):
				_coarse_path = _coarse_cache
			else:
				_start_coarse_prep()
		elif _coarse_path == "" and not _coarse_off:
			if FileAccess.file_exists(COARSE_BIN):
				_coarse_path = COARSE_BIN
			elif _is_dev_build() and FileAccess.file_exists(COARSE_BIN_DEV):
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
			if _coarse_sog != "":
				print("[campus_ggs] 粗层改由后台解码（%d 点），就绪前由细层顶着" % _coarse_points)
			else:
				push_warning("[campus_ggs] 没有粗层 bin，退回单层分块（窗外会空）")
	elif _bin_override == "":
		# ⚠️ 2026-11-10：发布版**不再打包** `campus_ggs.bin`（1.4 GB），只在分块失败时
		# 才会走到这里。这时候全量 bin 在 pck 里通常也不存在 —— 明确说明原因，
		# 免得看日志的人以为是自己删错了文件。
		if not FileAccess.file_exists(BIN) and _is_dev_build() and FileAccess.file_exists(BIN_DEV):
			_bin_path = BIN_DEV
			push_warning("[campus_ggs] 项目里没有 campus_ggs.bin，退回开发机路径")
		# 两处都没有就别硬撑：不碰 GDGS，让老泼溅照常工作（否则校园会整片消失）
		if not FileAccess.file_exists(_bin_path):
			push_error("[campus_ggs] 分块清单加载失败，且回退的全量 bin 也不在（%s）。" % _bin_path
				+ " 发布版不打包 campus_ggs.bin，所以这里只能回退 GDGS 泼溅。"
				+ " 检查 pck 里 splatdata/campus_chunks10w/ 是否完整。")
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


## 切场景专用：把校园这块泼溅的显存**当帧**放干净（不等 GC）。
##
## 为什么需要（2026-11-07 用户：「进入第二场景不释放第一场景的显存」）：
## 场景切换时 `_exit_tree()` 里的 `_release_campus()` 只是把光栅器对象丢掉，
## 而光栅器手里的 `context` 是 RefCounted，RID 攒在 `deletion_queue` 里等
## `NOTIFICATION_PREDELETE` 才 `free_rid` —— 真正落显存要等引擎回收。
## 粗层 153 万点一份就 656 MB（splats 352 + culled 70 + 两份 sort 各 117），
## 细层再加几百 MB，于是日志里「缓冲」那一栏跨场景几乎不动。
##
## `scene_flow.gd` 在「旧场景已 free、新场景还没 load」这个空档调本函数。
## 不用在这里等渲染线程：`RenderingServer.call_on_render_thread()` 后面紧跟
## `get_rendering_info()` 读回，队列一定已经排空。
##
## ⚠️⚠️ **千万别在这里 `set_process(false)`**（本喵第一版就是这么写的，结果
##    切过去之后校园整块没显示、只有天空）：`switch_scene()` 后面还会
##    `report_memory()` / 等预载 / 淡入十几帧，`_process` 一停，`_make_bundle()`
##    就永远不会被调用 —— 而 bundle 正是重建光栅器的那一步。
##    `_released = true` 本身已经保证下一帧会走「出门重建」分支。
func release_gpu_for_scene_change() -> void:
	_join_window_write()
	# 先摘掉 quad 和材质参数（同 `_exit_tree()` 的理由：别让材质指着要还的纹理）
	if quad != null:
		if _quad_mat != null:
			_quad_mat.set_shader_parameter("render_texture", null)
			_quad_mat.set_shader_parameter("coarse_texture", null)
		remove_child(quad)
		quad.free()
		quad = null
		_quad_mat = null
	# 收掉两条加载线程（它们由主线程驱动，join 必须在主线程做）
	for r in [rasterizer, coarse_rasterizer]:
		if r != null:
			if r.load_thread != null and r.load_thread.is_started():
				r.should_terminate_thread[0] = true
				r.load_thread.wait_to_finish()
	var fine = rasterizer
	var coarse = coarse_rasterizer
	rasterizer = null
	coarse_rasterizer = null
	_active = false
	_released = true
	_ready_done = false
	_coarse_done = false
	# ⚠️ 不清 `_outside_clock`：`_process` 的「出门重建」分支要有它 ≥ 0.25 s 才肯重建，
	#    而它在旧场景里早就攒够了 —— 清掉反而要多等四分之一秒。
	#    也不动 `_window_names`：那是「上次窗口选了哪 6 块」，重建时可以省一次拼 bin。
	# 再让渲染线程把 RID 当帧还掉
	RenderingServer.call_on_render_thread(func() -> void:
		if fine != null:
			fine.release_all_now()
		if coarse != null:
			coarse.release_all_now())
	# ⚠️ 4.7.1 没有 `RenderingServer.rendering_device_sync()`；读一次渲染信息
	#    把渲染线程队列排空，等价于「等它做完」。
	RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	tex = null
	coarse_tex = null
	print("[campus_ggs] 切场景：校园泼溅显存已当帧释放（细层 %s / 粗层 %s，游戏时间 %.1f s）" % [
		"有" if fine != null else "无", "有" if coarse != null else "无",
		Time.get_ticks_msec() / 1000.0])


## 给探针看的：这份校园现在到底有没有光栅器 / 是否已经上传完
func debug_state() -> Dictionary:
	var p: Variant = player
	return {
		"released": _released,
		"process": is_processing(),
		"gave_up": _gave_up,
		"ready_done": _ready_done,
		"chunks": _use_chunks,
		"player": "（空）" if p == null else str((p as Node3D).global_position),
		"fine": rasterizer != null,
		"coarse": coarse_rasterizer != null,
		"fine_loaded": rasterizer != null and bool(rasterizer.is_loaded),
		"coarse_loaded": coarse_rasterizer != null and bool(coarse_rasterizer.is_loaded),
		"outside_clock": _outside_clock,
		"window": _window_names.size(),
	}


func _exit_tree() -> void:
	_join_window_write()
	_join_coarse()
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
	rasterizer.cov_scale[0] = _cov_scale
	rasterizer.cov_limit[0] = _cov_cap
	rasterizer.cov_limit[1] = _cov_ref
	rasterizer.idle_skip = _idle_skip
	# ⚠️ 2026-11-11 修「换窗口后整屏白」的**真因**之一：
	#    这里必须按**当前视口**重设一次尺寸，不能让 `_process` 那段补。
	#    `_process` 的写法是 `if _want_size != vs:` 才补 —— 而换窗口时
	#    `_want_size` 早就等于 vs 了，整段被跳过 ⇒ 新建的光栅器**一直带着
	#    构造时的旧尺寸**，按 2560×1334 算投影却贴到 1727×900 的画面上，
	#    每颗泼溅被放大 1.48 倍、位置全偏 ⇒ 铺满整屏的白。
	#    实测（`_probe_campus_white_walk.gd`）：白屏那一格
	#      `视口=(1727,900)` 而 `rasterizer.texture_size=(2560,1334)`，
	#      分层诊断显示「只有细层 97.9% 白、只有粗层 3.7%」—— 白的就是细层。
	_sync_raster_size(rasterizer)

	_ensure_coarse_raster()

	_ready_done = true
	return true


## 建粗层光栅器（和细层同一个相机、同一个视口尺寸，只是点少、且不随窗口换）。
## 注意它必须是**独立的一份**（独立 bin_path / 独立纹理），否则换窗口时会被一起丢掉。
##
## 单独抽成函数，是因为粗层现在可能比细层**晚**就绪：分块 SOG 那套里粗层也要
## 现场解码（后台线程），`_process` 每帧 poll，解好了直接挂上，不用重建细层。
func _ensure_coarse_raster() -> void:
	if coarse_rasterizer != null or _coarse_path == "" or _coarse_total <= 0:
		return
	if cam == null or tex == null or not is_inside_tree():
		return
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
	coarse_rasterizer.cov_scale[0] = _cov_scale
	coarse_rasterizer.cov_limit[0] = _cov_cap
	coarse_rasterizer.cov_limit[1] = _cov_ref
	coarse_rasterizer.idle_skip = _idle_skip
	var sc2 := minf(1.0, max_render_w / maxf(float(vs2.x), 1.0))
	coarse_rasterizer.render_scale = [sc2]
	coarse_rasterizer.texture_size = vs2
	_sync_raster_size(coarse_rasterizer)
	_coarse_done = true


## 按**当前视口**把某个光栅器的渲染尺寸同步过去（新建之后必须调一次）。
## 见 `_make_bundle()` 里那段长注释：`_process` 的补丁只在 `_want_size` 变化时触发，
## 换窗口 = 新建光栅器而 `_want_size` 没变 —— 那条路径补不到。
func _sync_raster_size(r) -> void:
	if r == null or not is_inside_tree():
		return
	var vs: Vector2i = get_viewport().get_size()
	if vs.x <= 0 or vs.y <= 0:
		return
	var sc := minf(1.0, max_render_w / maxf(float(vs.x), 1.0))
	r.render_scale = [sc]
	r.texture_size = vs
	# 顺手把 `_want_size` 对齐，免得 `_process` 里立刻又跑一遍重复赋值
	_want_size = vs

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
	# ── 2026-11-11 修「再往前一步就整屏白」（本次复现：z = −124 处近白 97.8%）──
	#
	# 下面紧跟着会 `ctx.free()` 把**旧光栅器的纹理 RID 当帧还掉**，而 `keep_coarse`
	# 这条路径**故意不拆 quad/tex**（好让粗层顶着、不黑一下）。于是 quad 会在
	# 接下来若干帧里采一个**已释放的纹理 RID** —— 除非着色器整段跳过细层采样。
	#
	# 那个"跳过"靠的是 `fine_ready == 0`。但置 0 的代码在 `_process` 更后面，
	# 一旦那次 `_make_bundle()` 没走到那一步（早退 / cam 为空 / bin 打不开），
	# `fine_ready` 就**还停在 1.0**，正好落进上面那个坑 ⇒ 整屏白。
	# 实测证据：`_probe_campus_white_walk.gd` 长距离走位复现时，
	# 白屏那一格 `_window_names` 从 6 块变成 9 块（正在换窗口），而 `_fine_ready = 1.0`。
	#
	# ⇒ 不依赖后面那步：**在释放的这一瞬就把开关关掉**。
	#
	# ── 2026-11-11 第二轮：光关开关**不够**，必须把材质上的纹理也解绑 ──
	#    实测（`_probe_campus_white_walk.gd`）：白屏只在**换窗口**那一下出现，
	#    直接初始加载同一个 9 块窗口（3.7%）和之后停住 400 帧都不白 ⇒ 不是内容问题。
	#    原因是 `fine_ready = 0` 只让 **shader** 不采它，但 Godot 仍要把这个
	#    uniform（sampler）绑到 descriptor 上；而 `tex` 的 RID 已经被下面的
	#    `ctx.free()` 还掉了 ⇒ 绑一个失效纹理 ⇒ `Parameter "us" is null`
	#    ⇒ 整条绘制垮掉 ⇒ **整屏白**。（`742a15f` 报的就是这两行错，
	#    但当时只修了 `keep_coarse == false` 那条路径，换窗口这条漏了。）
	#    `7001`的注释也早写过：给 `texture_rd_rid` 赋值是**拥有权转移**，
	#    所以这里**只丢引用、不碰 RID**（纹理由光栅器自己还）。
	if _quad_mat != null and _fine_ready != 0.0:
		_fine_ready = 0.0
		_quad_mat.set_shader_parameter("fine_ready", 0.0)
	if _fine_ready != 0.0:
		_fine_ready = 0.0	# 换窗口（keep_coarse）时：解绑旧纹理 + 丢引用，让 `_make_bundle()` 建新的再绑回去。
	# 粗层那张（`coarse_texture`）**不动** —— 它就是这段时间撑画面的底。
	if keep_coarse and quad != null and _quad_mat != null:
		_quad_mat.set_shader_parameter("render_texture", null)
		tex = null
	if not keep_coarse:
		# 换窗口时**不动 quad / tex**：quad 继续画着，粗层那张纹理还在，
		# 新细层传好之前玩家看到的就是粗层 —— 不会黑一下（实测从空 4 帧降到 0 帧）。
		#
		# ⚠️ 2026-11-10 修「校园泼溅偶发整屏白 / 碎成针状」（用户报「一飞进泼溅区全白、
		#    回地面也不恢复、重开游戏才好」）：
		#    这里原来是 `quad.queue_free()` + 立刻 `ctx.free()`（下面第 534 行，走
		#    `call_on_render_thread` **当帧**就把纹理 RID 还掉）。问题是
		#    `queue_free()` 要等到**这一帧末尾**才真释放 —— 中间这段时间里
		#    quad 还活着、材质还指着刚被还掉的纹理，渲染管线重建 uniform set 时就会报
		#        `Texture (binding: 1, index 0) is not a valid texture`
		#        `Parameter "us" is null`
		#    那个 null 的 uniform set 之后**每帧都失败**，泼溅点按错误数据投影，
		#    表现就是整屏白 / 点被拉成针状散开，而且**坏掉就一直坏到重开游戏**。
		#    `_exit_tree()` 里早就踩过一次同样的坑（见那里的长注释），当时只在退出路径修了，
		#    运行时这条释放路径漏了。这里照同样的顺序同步拆干净：
		#      ① 先把材质里的纹理参数解绑（此时 RID 还有效，只是不用它了）
		#      ② 立刻 `free()` 掉 quad（不是 queue_free），保证它不会再被绘制
		#      ③ 最后才让光栅器去还纹理
		if quad != null:
			if _quad_mat != null:
				_quad_mat.set_shader_parameter("render_texture", null)
				_quad_mat.set_shader_parameter("coarse_texture", null)
			if quad.is_inside_tree():
				remove_child(quad)
			quad.free()
			quad = null
			_quad_mat = null
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
	# 粗层也先关掉：等 `_process` 里确认 `coarse_rasterizer.is_loaded` 才打开。
	# 不挡这一下，纹理还没建好时采到的是垃圾像素 → 整屏白。
	sm.set_shader_parameter("coarse_ready", 0.0)
	_fine_ready = 0.0
	_coarse_ready = 0.0
	quad.material_override = sm
	_quad_mat = sm
	add_child(quad)
	quad.visible = false
	print("[campus_ggs] %d 点，quad + 天空已就绪%s" % [
		_total, "（粗层 %d 点）" % _coarse_total if coarse_rasterizer != null else ""])
	quad.visible = false

func _process(_dt: float) -> void:
	# 粗层后台解码的 poll 放在最前面：玩家在厅里时这条路径才会走到，
	# 而粗层恰好就是「出厅之前要准备好」的东西。
	_poll_coarse_prep()
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
	# ⚠️ 粗层也可能是**后来才就绪**的（分块 SOG 那套要后台解码）：那时 `_make_bundle()`
	#    早就跑完了。这里补一次创建 —— 但**只在 `_ready_done` 之后**，
	#    也就是细层已经在位、处于已知安全的状态，不在释放/重建的中间态里动手。
	if coarse_rasterizer == null and _ready_done \
			and _coarse_path != "" and _coarse_total > 0 and not _coarse_off:
		_ensure_coarse_raster()
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
	# 粗层同理（`coarse_ready`）：它被释放/还没建好时无条件采样会拿到垃圾像素，
	# 混进 `mix(sky, coarse, coarse.a)` 就是整屏白（2026-11-10 修）。
	var coarse_ok: bool = coarse_rasterizer != null and coarse_rasterizer.is_loaded
	if _quad_mat != null:
		var want_fine := 1.0 if fine_ok else 0.0
		if want_fine != _fine_ready:
			_fine_ready = want_fine
			_quad_mat.set_shader_parameter("fine_ready", want_fine)
		var want_coarse := 1.0 if coarse_ok else 0.0
		if want_coarse != _coarse_ready:
			_coarse_ready = want_coarse
			_quad_mat.set_shader_parameter("coarse_ready", want_coarse)
	_active = player != null and player.global_position.z < -74.0 and any_loaded
	if quad != null:
		quad.visible = _active


# ─────────────────────────────────────────────────────────────
# 10×10 分块 + 3×3 窗口
# ─────────────────────────────────────────────────────────────

## 是否开发构建（编辑器或带调试的导出）。
## 开发机的绝对路径（`BIN_DEV` / `COARSE_BIN_DEV`）只在这两种构建下才允许用，
## 发布版里彻底不碰 —— 免得别人的机器上出现「指向本机桌面」的死路径。
func _is_dev_build() -> bool:
	return OS.has_feature("editor") or OS.has_feature("debug")


## 读离线生成的清单（块名 → 世界中心 / bin / 字节数）。
## ⚠️ 2026-11-10：加了**块文件存在性自检**。
##   原来只验 `chunks.json` 本身能不能解析，不验块文件真在不在。后果是
##   pck 漏打包某些 `Chunk_*.bin` 时，`_load_manifest()` 仍返回 true，
##   然后每次开窗口那几块**静默打不开**（`_merge_window_bins` 里只
##   `push_warning` 就跳过）—— 表现为「校园有一部分是空的」，不崩、难查。
##   现在缺块就直接返回 false，让上层回退 `campus_ggs.bin` 全量，画面至少完整。
func _load_manifest() -> bool:
	_frame_basis = Basis.IDENTITY
	_frame_origin = Vector3.ZERO
	_frame_scale = 1.0
	_palette = PackedByteArray()
	_cache_subdir = ""
	_coarse_sog = ""
	_coarse_points = 0
	_chunk_list.clear()
	if not FileAccess.file_exists(chunks_json):
		return false
	var text := FileAccess.get_file_as_string(chunks_json)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var man: Dictionary = parsed
	var arr: Array = man.get("chunks", [])
	if arr.is_empty():
		return false

	# ---- 相似变换（只有分块 SOG 那套清单才带）----
	var fr: Dictionary = man.get("frame", {})
	var axes: Array = fr.get("axes", [])
	if axes.size() == 3:
		_frame_basis = Basis(
			_v3(axes[0]), _v3(axes[1]), _v3(axes[2]))
		_frame_origin = _v3(fr.get("origin", [0.0, 0.0, 0.0]))
		_frame_scale = float(fr.get("scale", 1.0))
	var pal_rel := String(man.get("centroids", ""))
	if pal_rel != "":
		_palette = FileAccess.get_file_as_bytes("res://" + pal_rel)
		if _palette.is_empty():
			push_error("[campus_ggs] 清单里的共享调色板读不到：%s" % pal_rel)
			return false

	# ---- 缓存子目录名带清单指纹：清单一变，旧缓存自然作废 ----
	_cache_subdir = "%s_%d" % [CACHE_SUBDIR_CAMPUS, text.hash()]

	for d in arr:
		var dd: Dictionary = d
		var c: Array = dd.get("center", [0.0, 0.0, 0.0])
		_chunk_list.append({
			"name": String(dd.get("name", "")),
			"center": Vector3(float(c[0]), float(c[1]), float(c[2])),
			"sog": String(dd.get("sog", "")),
			"bin": String(dd.get("bin", "")),
			"points": int(dd.get("points", 0)),
			"bytes": int(dd.get("bytes", 0)),
		})
	if _chunk_list.is_empty():
		return false

	# ---- 粗层（SOG 那套才有）----
	var co: Dictionary = man.get("coarse", {})
	if not co.is_empty():
		_coarse_sog = String(co.get("sog", ""))
		_coarse_points = int(co.get("points", 0))

	# 块文件存在性自检：空块允许不存在 —— 那是 10×10 网格里落在校园范围外的
	# 格子，切分脚本会写 0 字节占位。
	var missing: PackedStringArray = PackedStringArray()
	for c in _chunk_list:
		var sog := String(c["sog"])
		if sog != "":
			if not FileAccess.file_exists("res://" + sog):
				missing.append(sog)
			continue
		if int(c["bytes"]) <= 0:
			continue
		if not FileAccess.file_exists("res://" + String(c["bin"])):
			missing.append(String(c["bin"]))
	if not missing.is_empty():
		push_error("[campus_ggs] 分块清单里有 %d 块找不到文件（pck 漏打包了？），回退全量 bin。前 3 个：%s"
			% [missing.size(), ", ".join(missing.slice(0, 3))])
		_chunk_list.clear()
		return false
	return true


## 挑用哪套分块清单：优先分块 SOG，没有就退回旧的 raw 分块。
## `--ggs-chunks=` 显式给了路径时不走这里（调用方已经设好了）。
func _resolve_chunks_json() -> String:
	for p in [CHUNKS_JSON_SOG, CHUNKS_JSON_RAW]:
		if FileAccess.file_exists(p):
			return p
	return CHUNKS_JSON_SOG


func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## `Basis` → 9 个标量的行主序矩阵（`p' = M·p`）。
## 逐点建 Basis/Vector3 会分配对象，600 万点会被拖死，所以展开成标量。
static func _frame_matrix(b: Basis) -> PackedFloat32Array:
	return PackedFloat32Array([
		b.x.x, b.y.x, b.z.x,
		b.x.y, b.y.y, b.z.y,
		b.x.z, b.y.z, b.z.z])


## 原地把一块 SOG 解码结果从模型坐标换到世界坐标：
##   p' = M·p + o        C' = M·C·Mᵀ（M 已含 scale，别再乘 scale²）
static func _transform_blob(blob: PackedByteArray, count: int, m: PackedFloat32Array, o: Vector3) -> void:
	var m00 := m[0]; var m01 := m[1]; var m02 := m[2]
	var m10 := m[3]; var m11 := m[4]; var m12 := m[5]
	var m20 := m[6]; var m21 := m[7]; var m22 := m[8]
	for i in count:
		var off := i * BYTES_PER_SPLAT
		var px := blob.decode_float(off)
		var py := blob.decode_float(off + 4)
		var pz := blob.decode_float(off + 8)
		blob.encode_float(off, m00 * px + m01 * py + m02 * pz + o.x)
		blob.encode_float(off + 4, m10 * px + m11 * py + m12 * pz + o.y)
		blob.encode_float(off + 8, m20 * px + m21 * py + m22 * pz + o.z)

		var c00 := blob.decode_float(off + 16)
		var c01 := blob.decode_float(off + 20)
		var c02 := blob.decode_float(off + 24)
		var c11 := blob.decode_float(off + 28)
		var c12 := blob.decode_float(off + 32)
		var c22 := blob.decode_float(off + 36)
		var d00 := m00 * c00 + m01 * c01 + m02 * c02
		var d01 := m00 * c01 + m01 * c11 + m02 * c12
		var d02 := m00 * c02 + m01 * c12 + m02 * c22
		var d10 := m10 * c00 + m11 * c01 + m12 * c02
		var d11 := m10 * c01 + m11 * c11 + m12 * c12
		var d12 := m10 * c02 + m11 * c12 + m12 * c22
		var d20 := m20 * c00 + m21 * c01 + m22 * c02
		var d21 := m20 * c01 + m21 * c11 + m22 * c12
		var d22 := m20 * c02 + m21 * c12 + m22 * c22
		blob.encode_float(off + 16, d00 * m00 + d01 * m01 + d02 * m02)
		blob.encode_float(off + 20, d00 * m10 + d01 * m11 + d02 * m12)
		blob.encode_float(off + 24, d00 * m20 + d01 * m21 + d02 * m22)
		blob.encode_float(off + 28, d10 * m10 + d11 * m11 + d12 * m12)
		blob.encode_float(off + 32, d10 * m20 + d11 * m21 + d12 * m22)
		blob.encode_float(off + 36, d20 * m20 + d21 * m21 + d22 * m22)


## 取一块解好码、变换到世界坐标的 240 B/点记录。
## 优先读缓存；没有就解码 + 变换，然后写缓存（写失败不影响本次结果）。
## ⚠️ 这个函数**在工作线程里被调**：只碰传进来的参数和自己开的内存，
##    不读主线程状态、也不 push_warning / print（那会从 worker 写主线程日志）。
static func _decode_and_transform(sog_path: String, points: int, m: PackedFloat32Array,
		o: Vector3, palette: PackedByteArray, cache_path: String) -> PackedByteArray:
	if cache_path != "" and FileAccess.file_exists(cache_path):
		var cf := FileAccess.open(cache_path, FileAccess.READ)
		if cf != null:
			var cached := cf.get_buffer(cf.get_length())
			cf.close()
			if cached.size() == points * BYTES_PER_SPLAT:
				return cached
	var r: Dictionary = SogRuntimeScript.load_sog(sog_path, {
		"cache": "off", "center": Vector3.ZERO, "centroids": palette})
	if not bool(r.get("ok", false)):
		return PackedByteArray()
	var blob: PackedByteArray = r["resource"].get("point_data_byte")
	var n := int(r.get("count", 0))
	if n <= 0 or blob.size() < n * BYTES_PER_SPLAT:
		return PackedByteArray()
	_transform_blob(blob, n, m, o)
	if cache_path != "" and n == points:
		var wf := FileAccess.open(cache_path, FileAccess.WRITE)
		if wf != null:
			wf.store_buffer(blob)
			wf.close()
	return blob


## 分块解码的并行度上限。
## 权衡的是**瞬时内存**：一块 33 万点的块，解码时同时存在 240 B×n 的 blob
## 和同一份 float 展开数组，单条约 160 MB。6 条 ≈ 1 GB 峰值，本机 16 逻辑核
## 实测 4 条拿 2.1×、6 条拿到 ~2.5×（再往上被内存带宽吃掉了）。
const MAX_DECODE_THREADS := 6


## 把 job 里需要解码的块摊到几个工作线程上，返回与 `jobs` **同序**的 blob 数组
## （raw bin 那几项留空，由调用方自己拷）。
##
## ⚠️ 线程之间**不共享任何可写结构**：每个线程只拿到自己那几块，
##    结果通过 `Thread.wait_to_finish()` 的返回值汇总。
##    （踩过的坑：Packed*Array 跨线程写同一容器是不安全的。）
static func _decode_jobs_parallel(jobs: Array, m: PackedFloat32Array,
		origin: Vector3, palette: PackedByteArray) -> Array:
	var out: Array = []
	out.resize(jobs.size())
	var todo: Array = []
	for i in jobs.size():
		if jobs[i].has("sog"):
			todo.append([i, jobs[i]])
	if todo.is_empty():
		return out
	if todo.size() == 1:
		var only: Array = todo[0]
		out[int(only[0])] = _decode_and_transform(String(only[1]["sog"]), int(only[1]["points"]),
			m, origin, palette, String(only[1].get("cache", "")))
		return out
	var n := mini(MAX_DECODE_THREADS, todo.size())
	var slices: Array = []
	slices.resize(n)
	for w in n:
		slices[w] = []
	for k in todo.size():
		slices[k % n].append(todo[k])
	var threads: Array = []
	for w in n:
		var t := Thread.new()
		threads.append(t)
		t.start(_decode_slice.bind(slices[w], m, origin, palette), Thread.PRIORITY_NORMAL)
	var merged: Array = []
	for t in threads:
		merged.append_array(t.wait_to_finish())
	for pair in merged:
		out[int(pair[0])] = pair[1]
	return out


## 一个工作线程负责的那几块。返回 `[[job 下标, blob], …]`，顺序无所谓 —— 调用方按下标归位。
static func _decode_slice(items: Array, m: PackedFloat32Array,
		origin: Vector3, palette: PackedByteArray) -> Array:
	var res: Array = []
	for it in items:
		var job: Dictionary = it[1]
		res.append([int(it[0]), _decode_and_transform(
			String(job["sog"]), int(job["points"]), m, origin, palette,
			String(job.get("cache", "")))])
	return res


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
	var dst := _window_bin(0)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		push_error("[campus_ggs] 写不了 %s" % dst)
		return 0
	var written := 0
	var m := _frame_matrix(_frame_basis)
	for nm in names:
		var e := _chunk_entry(nm)
		if e.is_empty():
			continue
		if String(e["sog"]) != "":
			var blob := _decode_and_transform("res://" + String(e["sog"]), int(e["points"]),
				m, _frame_origin, _palette, _chunk_cache_path(e))
			if blob.is_empty():
				push_warning("[campus_ggs] SOG 块解不出来：%s" % String(e["sog"]))
				continue
			f.store_buffer(blob)
			written += blob.size()
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


## 后台线程：把 job 列表里的分块写进目标 bin。
## ⚠️ 这里**只做文件 I/O 和数据变换**：`_chunk_list` / `_chunk_entry()` 这些主线程
##    数据结构一概不碰（跨线程读不安全），路径 / 点数 / 相似变换 / 调色板都在
##    主线程先解析好塞进 job 或参数。
## ⚠️ 也不在这里 `push_warning`：那会从 worker 线程写主线程的日志，会炸。
func _write_worker(jobs: Array, path: String, m: PackedFloat32Array,
		origin: Vector3, palette: PackedByteArray) -> void:
	var written := 0
	var failed := false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		failed = true
	else:
		# ⚠️ 实测：3×3 窗口最密的一份是 184 万点，单线程解码+变换要 **12.2 s**。
		#    解码是纯 CPU、各块之间零共享，所以这里把它摊到几个工作线程上，
		#    主线程只按原顺序写盘（顺序不能变，否则块会错位）。
		var blobs := _decode_jobs_parallel(jobs, m, origin, palette)
		for i in jobs.size():
			var j: Dictionary = jobs[i]
			if j.has("sog"):
				var blob: PackedByteArray = blobs[i]
				if blob.is_empty():
					failed = true
					continue
				f.store_buffer(blob)
				written += blob.size()
				continue
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
		if String(e["sog"]) != "":
			jobs.append({
				"sog": "res://" + String(e["sog"]),
				"points": int(e["points"]),
				"cache": _chunk_cache_path(e),
			})
		else:
			jobs.append({"path": "res://" + String(e["bin"]), "bytes": int(e["bytes"])})
	if jobs.is_empty():
		return false
	# 双缓冲：写另一槽，当前渲染的那份不动
	_write_path = _window_bin(1) if _window_slot == 0 else _window_bin(0)
	_write_mutex.lock()
	_write_bytes = 0
	_write_failed = false
	_write_done = false
	_write_mutex.unlock()
	_pending_window = names
	_write_thread = Thread.new()
	_write_thread.start(_write_worker.bind(jobs, _write_path,
		_frame_matrix(_frame_basis), _frame_origin, _palette))
	return true


## 某一块变换后 raw bin 的缓存路径（exe 旁边 `_cache/campus_<指纹>/`）。
## 空串 = 缓存不可用（只影响速度，不影响正确性）。
func _chunk_cache_path(e: Dictionary) -> String:
	if _cache_subdir.is_empty():
		return ""
	return CacheDir.file_for(_cache_subdir, "%s.bin" % String(e["name"]))


## ── 粗层后台准备（只有 SOG 那套才需要）──
##
## 粗层是「全校园的底」，154 万点。同步解会卡启动约 8 s，所以起个线程解完写进
## `_cache/campus_<指纹>/coarse.bin`，`_process` 里 poll 到就挂光栅器。
func _start_coarse_prep() -> void:
	if _coarse_sog == "" or _coarse_points <= 0:
		return
	# 路径自己兜底算一次（`_ready` 的早期返回路径不会走到那里）
	if _coarse_cache.is_empty():
		_coarse_cache = CacheDir.file_for(_cache_subdir, "coarse.bin")
	_coarse_flag = false
	_coarse_ok = false
	_coarse_thread = Thread.new()
	_coarse_thread.start(_coarse_worker.bind(
		"res://" + _coarse_sog, _coarse_points, _coarse_cache,
		_frame_matrix(_frame_basis), _frame_origin, _palette), Thread.PRIORITY_LOW)
	print("[campus_ggs] 粗层：后台解码 %s（%d 点）" % [_coarse_sog.get_file(), _coarse_points])


func _coarse_worker(sog_path: String, points: int, cache_path: String,
		m: PackedFloat32Array, origin: Vector3, palette: PackedByteArray) -> void:
	var blob := _decode_and_transform(sog_path, points, m, origin, palette, cache_path)
	_coarse_mutex.lock()
	_coarse_ok = not blob.is_empty()
	_coarse_flag = true
	_coarse_mutex.unlock()


## 主线程 poll：粗层解好了就把路径/点数定下来，下一帧 `_ensure_coarse_raster()` 会挂上。
func _poll_coarse_prep() -> void:
	if _coarse_thread == null:
		return
	_coarse_mutex.lock()
	var done := _coarse_flag
	var ok := _coarse_ok
	_coarse_mutex.unlock()
	if not done:
		return
	_coarse_thread.wait_to_finish()
	_coarse_thread = null
	if not ok:
		push_warning("[campus_ggs] 粗层 SOG 解码失败，本次只有细层分块")
		return
	_coarse_path = _coarse_cache
	if _coarse_path == "" or not FileAccess.file_exists(_coarse_path):
		push_warning("[campus_ggs] 粗层解出来了但缓存文件不在，跳过粗层")
		return
	_coarse_total = _coarse_points
	print("[campus_ggs] 粗层就绪：%s（%d 点 / %.0f MB）" % [
		_coarse_path, _coarse_total, float(_coarse_total) * 240.0 / 1048576.0])
	_coarse_off = false
	# ⚠️ 2026-11-11：这里**不要**直接 `_ensure_coarse_raster()`。
	#    原版粗层只在 `_make_bundle()` 里建 —— 那是「和细层一起、顺序已知安全」的时机。
	#    本喵一开始在 poll 里就地建，等于给 `coarse_tex` 的创建/绑定开了第二条路径；
	#    虽然没抓到它出问题，但半死光栅器正是上一次「整屏白」的病灶
	#    （见 742a15f），不该在释放/重建的中间态里再插一条。现在只把路径挂上，
	#    由 `_process` 里那段「粗层段」在 `_ready_done` 之后再建。


func _join_coarse() -> void:
	if _coarse_thread != null:
		_coarse_thread.wait_to_finish()
		_coarse_thread = null


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
