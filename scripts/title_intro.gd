extends Node
## 开场 PV + 载入遮罩（2026-11-12 用户改版）。
##
## ── 用户口径（原话要点）──
##   · 做 PV，蔚蓝档案的做法：**图片从左往右缓慢地平移**；
##   · 替代原来的开始动画，在**高斯泼溅没加载完之前**先盖住加载过程；
##   · **加进度条**显示加载进度；
##   · 加载完在下方显示「开始游戏」，**点了才进游戏**（加载完的高斯泼溅 / 画室 609）；
##   · 后续有硬盘缓存会快很多，但**还是显示进度条与开始按钮**，点了才进 609；
##   · 「因为有人会听歌」→ 所以**不再做「任意键跳过」**：PV 和音乐一直放到
##     玩家自己点「开始游戏」为止，想听歌就听完。
##
## ── 为什么是「PV 当遮罩」而不是另开一个场景 ──
## 主场景就是 `game.tscn`（`project.godot` 的 `run/main_scene`），一启动直接进第三人称，
## 中间没有可以挂演出的地方；本工程的老规矩又是不动 `project.godot`。所以这里依旧是
## **游戏场景内的一层 CanvasLayer**：零新场景、零配置改动，而且天然盖在 3D 世界上，
## 泼溅那边照常在自己线程里解码 → 加载卡顿被 PV 遮掉。
##
## ── 和调用方的分工 ──
## 本脚本只管「画面 + 进度条 + 开始按钮」，**加载本身不在这里做**。
## 调用方传一个 `poll` Callable，返回：
##     {"ratio": float 0..1, "ready": bool, "names": Array}
##   · ratio  —— 当前加载进度（`game.gd` 从各个 SplatScene 的 `load_ratio` 汇总）
##   · ready  —— 世界真的就绪了没有（`game.gd::_splats_ready()`）
##   · names  —— 正在加载的场地名（显示成「正在载入 画室609」）
## `ready` 为真的那一刻，进度条强制满格并弹出「开始游戏」。
##
## ── 正片优先级（先有谁用谁）──
##   ① `res://assets/cg/pv/*.png`      ← 现在用的这套 BA 风 PV 图（按文件名排序循环）
##   ② `res://assets/cg/opening.ogv`    ← 整段 CG（没有 PV 图时用）
##   ③ `res://assets/cg/opening/*.png`  ← 帧序列（当 PV 图一样逐张平移）
##   ④ 都没有                            ← 渐变深蓝底 + 标题（缺素材也不耽误启动）
##
## ── 音乐 ──
## `res://assets/music/pv_theme.mp3`（「Constant Moderato（PV1）」）。循环播放，
## 点「开始游戏」时淡出，然后才放开被压住的房间 BGM（`Music.hold(false)`）。
##
## ⚠️ 素材不入库：图片与音乐都带第三方版权（BA 游戏内画面 / OST），
##    和 `assets/music/*.ogg`、`assets/story/*.jpg` 同一条规矩（见 `.gitignore`）。
##    克隆仓库没有素材时会自动走 ④，启动照常。

const UiSkin := preload("res://scripts/ui_skin.gd")

const PV_DIR := "res://assets/cg/pv"
## AI 超分后的同一套图（同一文件名）。存在就优先用 —— 实机截图本身很软，
## 4× Real-ESRGAN 再降采样到高 1440 显示起来明显清楚（见 `_tools/upscale_pv_images.ps1`）。
const PV_HD_DIR := "res://assets/cg/pv_hd"
const CG_VIDEO := "res://assets/cg/opening.ogv"
const CG_FRAMES_DIR := "res://assets/cg/opening"
const PV_MUSIC := "res://assets/music/pv_theme.mp3"

const TITLE_TEXT := "爱丽丝梦游长理"
const SUB_TEXT := "Blue Archive 二次创作 · 个人非商业作品"

## 每张 PV 图「从左往右扫一遍」用多久（秒）。用户要的是「缓慢」。
const SLIDE_SEC := 9.0
## 两张图之间交叉淡化多久（秒）。下一张在 `SLIDE_SEC - SLIDE_FADE` 时进场。
const SLIDE_FADE := 1.0
## 点开始之后整层淡出多久（秒）。
const FADE_OUT := 0.9
## 开场音乐音量 / 淡入 / 点开始后的淡出（秒）。
const MUSIC_DB := -7.0
const MUSIC_IN := 2.0
const MUSIC_OUT := 1.4
## 等世界就绪的**死等保护**（秒）。正常情况根本走不到：冷缓存 50 s、
## 暖缓存 2 s，都远小于它。只有加载逻辑真的坏了才会在这里兜底放行。
const SETTLE_MAX := 180.0
## 加载超过这么久还没完，才显示「首次会比较久」那行小字 ——
## 一上来就写会让人以为出问题了。
const HINT_AFTER := 4.0
## 进度条几何（逻辑 px）。
const BAR_W := 520.0
const BAR_H := 8.0
const BAR_INNER := BAR_W - 2.0
const BTN_SIZE := Vector2(240.0, 62.0)

## 每张 PV 图上的轻量调色：轻微锐化 + 胶片颗粒 + 暗角。
##
## 为什么还要它（图已经 AI 超分了）：实机截图原始信息就那么多，4× 超分之后
## 放大到 1600×900 仍会有「软」的观感；一点点 unsharp + 颗粒能把边缘读回来，
## 颗粒同时把残余的压缩块藏掉。**参数都很轻**，AI 图不会被锐成塑料感。
const PV_SLIDE_SHADER := """
shader_type canvas_item;

uniform float sharpen : hint_range(0.0, 1.5) = 0.22;
uniform float grain : hint_range(0.0, 0.10) = 0.018;
uniform float vignette : hint_range(0.0, 1.0) = 0.16;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 c = texture(TEXTURE, UV);
	vec3 blur = (texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb
		+ texture(TEXTURE, UV - vec2(px.x, 0.0)).rgb
		+ texture(TEXTURE, UV + vec2(0.0, px.y)).rgb
		+ texture(TEXTURE, UV - vec2(0.0, px.y)).rgb) * 0.25;
	vec3 rgb = c.rgb + (c.rgb - blur) * sharpen;
	float n = fract(sin(dot(UV * vec2(1943.0, 2761.0), vec2(12.9898, 78.233))) * 43758.5453);
	rgb += (n - 0.5) * grain;
	float d = distance(UV, vec2(0.5));
	rgb *= 1.0 - vignette * smoothstep(0.30, 0.85, d);
	COLOR = vec4(clamp(rgb, vec3(0.0), vec3(1.0)), c.a);
}
"""

var _layer: CanvasLayer
var _root: Control
var _black: ColorRect
var _backdrop: Control
var _scrim: TextureRect
var _title_plate: PanelContainer
var _title_rule: ColorRect
var _title_sub: Label
var _ui: Control
var _bar_track: Panel
var _bar_fill: Panel
var _progress_label: Label
var _load_hint: Label
var _start_button: Button
var _start_hint: Label

var _slides: Array[String] = []
var _kind := ""
var _slide_mat: ShaderMaterial
var _playing := false
var _ready_done := false
var _start_pressed := false
var _disp_ratio := 0.0
var _hint_tw: Tween
var _t_start := 0
var _relayout_queued := false
var _slideshow_gen := 0
var _music: AudioStreamPlayer
var _music_held := false


## 播一遍。`poll` 见文件头；`await` 它，返回时画面已经干净、玩家可以操作了。
func play(poll: Callable) -> void:
	if _playing:
		return
	_playing = true
	_t_start = Time.get_ticks_msec()
	_black_only()
	# ⚠️ 顺序要紧：黑底 → 正片（图/CG）→ 压暗 → 界面。
	#    UI 必须先挂 backdrop 之后才能压在图上（第一版反了，出图时整块界面都被图盖住）。
	_build_backdrop()
	_build_ui()
	# 布局要等一帧：Control 的尺寸在这之前还是 0。
	await get_tree().process_frame
	if _root == null or not is_instance_valid(_root):
		return
	_layout()
	_start_music()
	# 压住房间 BGM：`splat_scene.gd::_update_room_bgm()` 每帧都在调
	# `Music.play("room609")`，不压住就会和 PV 音乐叠在一起。
	Music.hold(true)
	_music_held = true
	_start_slideshow()
	print("[TitleIntro] 正片 = %s（%d 张图，音乐 %s）" % [
		_kind, _slides.size(), "有" if _music != null else "无"])

	await _run_loading(poll)
	await _wait_for_start()
	await _fade_out_all()

	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_playing = false
	print("[TitleIntro] 结束（开始按钮已点）")


## 现在会播哪种正片（自检 / 日志用）："pv" / "video" / "frames" / "fallback"
func kind() -> String:
	return _pick_kind()


## PV 图张数（自检用）
func slide_count() -> int:
	return _pv_slides().size()


## 有没有开场音乐（自检用）
func has_music() -> bool:
	return _music != null and is_instance_valid(_music)


## 自检 / 探针用：等价于玩家点了「开始游戏」（未就绪时无效）。
func press_start() -> void:
	_on_start_pressed()


# ── 骨架 ────────────────────────────────────────────────────────────────

## 层 + 全黑底。黑底一直垫在 PV 下面，直到最后整层淡出 ——
## 这样 PV 交叉淡化的空隙不会漏出后面的 3D 世界。
##
## ⚠️ 本节点自己要 `ALWAYS`：`create_tween()` 挂在自己身上，父链一暂停 Tween 就冻住；
##    而且开场之后紧接着播的对话框会把 `get_tree().paused` 置 true。
func _black_only() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.name = "TitleIntro"
	# 比 F3 性能浮层（200）、换场景黑幕（128）都高：开场时它必须在最上面
	_layer.layer = 230
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 黑底：**创建时就是全黑**。第一帧世界可能还没画出来，不能先露一帧再盖。
	_black = ColorRect.new()
	_black.name = "Black"
	_black.color = Color(0.0, 0.0, 0.0, 1.0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_black)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_on_viewport_resized)


# ── 正片：PV 图 / CG / 帧序列 / 兜底 ─────────────────────────────────────

func _pick_kind() -> String:
	if not _pv_slides().is_empty():
		return "pv"
	if FileAccess.file_exists(CG_VIDEO) or ResourceLoader.exists(CG_VIDEO):
		return "video"
	if not _list_images(CG_FRAMES_DIR).is_empty():
		return "frames"
	return "fallback"


## PV 实际要放的那组文件：`assets/cg/pv/` 里的每一张**优先换同名 HD 版**
## （`assets/cg/pv_hd/`，AI 超分产物）。HD 缺哪张就退回原图 —— 使用者换图后
## 只要重新跑一次 `_tools/upscale_pv_images.ps1`，没重跑时也不会少图。
func _pv_slides() -> Array[String]:
	var base := _list_images(PV_DIR)
	if base.is_empty():
		return _list_images(PV_HD_DIR)
	var hd := {}
	for p in _list_images(PV_HD_DIR):
		hd[p.get_file()] = p
	var out: Array[String] = []
	for p in base:
		var f := p.get_file()
		out.append(String(hd[f]) if hd.has(f) else p)
	return out


## 目录里的图片，按文件名排序、去重。`xxx.png` 与 `xxx.png.import` 两种列法都认 ——
## 桌面目录里两个都在，导出后的 PCK 里两种写法都可能出现。
## 支持 png / jpg / jpeg / webp（使用者换图时不用管格式）。
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp"]

func _list_images(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	var seen := {}
	for raw in d.get_files():
		var name := String(raw)
		var low := name.to_lower()
		var img := ""
		if low.ends_with(".import"):
			img = name.substr(0, name.length() - ".import".length())
		else:
			img = name
		var ext := img.get_extension().to_lower()
		if not IMAGE_EXTS.has(ext):
			continue
		if seen.has(img):
			continue
		seen[img] = true
		out.append(dir_path.path_join(img))
	out.sort()
	return out


func _build_backdrop() -> void:
	_kind = _pick_kind()
	_backdrop = Control.new()
	_backdrop.name = "Backdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 裁掉平移出画的部分（宽图放大后比屏幕宽）
	_backdrop.clip_contents = true
	_root.add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	match _kind:
		"pv":
			_slides = _pv_slides()
		"frames":
			_slides = _list_images(CG_FRAMES_DIR)
		"video":
			_build_video()
		_:
			_build_fallback()

	# 底部压暗：进度条与按钮压在任何图上都读得清
	_scrim = TextureRect.new()
	_scrim.name = "Scrim"
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	_scrim.texture = _bottom_gradient()
	_root.add_child(_scrim)


func _build_video() -> void:
	# ⚠️ Godot 4 的 VideoStreamPlayer 只认 Ogg Theora（.ogv）。
	var stream := load(CG_VIDEO) as VideoStream
	if stream == null:
		push_warning("[TitleIntro] %s 加载失败，退回渐变底" % CG_VIDEO)
		_kind = "fallback"
		_build_fallback()
		return
	var vp := VideoStreamPlayer.new()
	vp.name = "CgVideo"
	vp.stream = stream
	vp.expand = true
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(vp)
	vp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.modulate.a = 0.0
	# 不依赖 `loop` 属性（不同小版本行为不一）：播完就自己再 `play()`。
	vp.finished.connect(func() -> void:
		if is_instance_valid(vp):
			vp.play())
	vp.play()
	var tw := create_tween()
	tw.tween_property(vp, "modulate:a", 1.0, 0.9)


func _build_fallback() -> void:
	var tr := TextureRect.new()
	tr.name = "Fallback gradient"
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture = _fallback_gradient()
	_backdrop.add_child(tr)
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ── PV 图片：横向缓慢平移 ────────────────────────────────────────────────

## 循环放图：每张「窗口」从图片最左边移到最右边（内容看起来往左滑），
## 持续 `SLIDE_SEC` 秒，相邻两张交叉淡化 `SLIDE_FADE` 秒。
func _start_slideshow() -> void:
	if _slides.is_empty():
		return
	if _kind != "pv" and _kind != "frames":
		return
	_slideshow_gen += 1
	_loop_slides(_slideshow_gen)


func _restart_slideshow() -> void:
	if _slides.is_empty() or (_kind != "pv" and _kind != "frames"):
		return
	_slideshow_gen += 1
	if _backdrop != null and is_instance_valid(_backdrop):
		for child in _backdrop.get_children():
			child.queue_free()
	_loop_slides(_slideshow_gen)


func _loop_slides(gen: int) -> void:
	var i := 0
	while _playing and gen == _slideshow_gen and not _start_pressed and not _slides.is_empty():
		var tex := _load_texture(_slides[i % _slides.size()])
		i += 1
		if tex == null:
			continue
		_spawn_slide(tex)
		# 等到下一张该进场：留出交叉淡化的重叠时间。
		await get_tree().create_timer(maxf(SLIDE_SEC - SLIDE_FADE, 0.5)).timeout


## 生成一张图并挂两个 Tween：平移（整段）+ 淡入（开头）+ 淡出（结尾前）。
func _spawn_slide(tex: Texture2D) -> void:
	if _backdrop == null or not is_instance_valid(_backdrop):
		return
	var vp := Vector2(_backdrop.size)
	if vp.x < 64.0 or vp.y < 64.0:
		vp = Vector2(1600.0, 900.0)
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	# 等比放大到「盖满屏幕」，宽出来的部分就是平移行程
	var k := maxf(vp.x / ts.x, vp.y / ts.y)
	var w := ts.x * k
	var h := ts.y * k
	var travel := maxf(w - vp.x, 0.0)
	var tr := TextureRect.new()
	tr.name = "Slide"
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size = Vector2(w, h)
	# 从图片最左边开始（窗口 x=0），纵向居中
	tr.position = Vector2(0.0, (vp.y - h) * 0.5)
	tr.modulate.a = 0.0
	tr.material = _slide_material()
	_backdrop.add_child(tr)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(tr, "position:x", -travel, SLIDE_SEC) \
		.set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(tr, "modulate:a", 1.0, SLIDE_FADE)
	tw.tween_property(tr, "modulate:a", 0.0, SLIDE_FADE) \
		.set_delay(maxf(SLIDE_SEC - SLIDE_FADE, 0.01))
	tw.chain().tween_callback(tr.queue_free)


## 优先走 Godot 导入的纹理；没有导入缓存（clone 下来没跑过编辑器）就现场解 PNG。
func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var img := Image.new()
	var ok := false
	match path.get_extension().to_lower():
		"png":
			ok = img.load_png_from_buffer(bytes) == OK
		"jpg", "jpeg":
			ok = img.load_jpg_from_buffer(bytes) == OK
		"webp":
			ok = img.load_webp_from_buffer(bytes) == OK
		_:
			return null
	if not ok:
		return null
	return ImageTexture.create_from_image(img)


## 滑动图共用的调色材质（只建一次；同一份 Shader 给所有 Slide 用）。
func _slide_material() -> ShaderMaterial:
	if _slide_mat != null:
		return _slide_mat
	var sh := Shader.new()
	sh.code = PV_SLIDE_SHADER
	_slide_mat = ShaderMaterial.new()
	_slide_mat.shader = sh
	return _slide_mat


# ── 界面：标题 / 进度条 / 开始按钮 ──────────────────────────────────────

func _build_ui() -> void:
	var skin: Dictionary = UiSkin.pick()
	var font := UiSkin.ui_font()

	# ── 标题牌（左上角，BA 的斜切白牌 + 亮黄底划线）──
	_title_plate = PanelContainer.new()
	_title_plate.name = "TitlePlate"
	_title_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag_sb := UiSkin.title_tag_style(skin)
	if not (tag_sb is StyleBoxEmpty):
		_title_plate.add_theme_stylebox_override("panel", tag_sb)
	_root.add_child(_title_plate)
	var title_label := Label.new()
	title_label.name = "TitleLabel"
	title_label.text = TITLE_TEXT
	if font != null:
		title_label.add_theme_font_override("font", font)
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", skin["text"])
	_title_plate.add_child(title_label)

	_title_rule = ColorRect.new()
	_title_rule.name = "TitleRule"
	_title_rule.color = skin["yellow"]
	_title_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_title_rule)

	_title_sub = _make_label(SUB_TEXT, 15, Color(0.94, 0.97, 1.0, 0.92),
		Color(0.0, 0.06, 0.12, 0.65), 3)
	_title_sub.name = "TitleSub"
	_root.add_child(_title_sub)

	# ── 底部：进度条 + 开始按钮 ──
	_ui = Control.new()
	_ui.name = "Ui"
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_ui)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_progress_label = _make_label("载入中  0%", 20, Color(0.94, 0.97, 1.0, 1.0),
		Color(0.0, 0.06, 0.12, 0.72), 5)
	_progress_label.name = "ProgressLabel"
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui.add_child(_progress_label)

	_bar_track = Panel.new()
	_bar_track.name = "BarTrack"
	_bar_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_sb := StyleBoxFlat.new()
	track_sb.bg_color = Color(0.01, 0.05, 0.10, 0.78)
	track_sb.border_color = Color(0.55, 0.80, 0.95, 0.55)
	track_sb.set_border_width_all(1)
	track_sb.set_corner_radius_all(3)
	track_sb.anti_aliasing = true
	_bar_track.add_theme_stylebox_override("panel", track_sb)
	_ui.add_child(_bar_track)

	_bar_fill = Panel.new()
	_bar_fill.name = "BarFill"
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = UiSkin.BA_SKY
	fill_sb.set_corner_radius_all(2)
	fill_sb.anti_aliasing = true
	_bar_fill.add_theme_stylebox_override("panel", fill_sb)
	_bar_track.add_child(_bar_fill)

	_load_hint = _make_label("首次启动需要久一点（约 1 分钟）· 之后有缓存会快很多",
		15, Color(0.82, 0.90, 0.98, 0.82), Color(0.0, 0.06, 0.12, 0.6), 3)
	_load_hint.name = "LoadHint"
	_load_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_hint.modulate.a = 0.0
	_ui.add_child(_load_hint)

	# 开始按钮：BA 的亮青斜切块 + 深藏蓝字
	_start_button = Button.new()
	_start_button.name = "StartButton"
	_start_button.text = "开始游戏"
	if font != null:
		_start_button.add_theme_font_override("font", font)
	_start_button.add_theme_font_size_override("font_size", 26)
	_start_button.add_theme_color_override("font_color", skin["btn_text"])
	_start_button.add_theme_color_override("font_hover_color", skin["btn_text"])
	_start_button.add_theme_color_override("font_pressed_color", skin["btn_text"])
	_start_button.add_theme_stylebox_override("normal", UiSkin.button_style(skin, "normal"))
	_start_button.add_theme_stylebox_override("hover", UiSkin.button_style(skin, "hover"))
	_start_button.add_theme_stylebox_override("pressed", UiSkin.button_style(skin, "pressed"))
	_start_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_start_button.custom_minimum_size = BTN_SIZE
	_start_button.size = BTN_SIZE
	_start_button.visible = false
	_start_button.pressed.connect(_on_start_pressed)
	_ui.add_child(_start_button)

	_start_hint = _make_label("点击开始游戏 · 进入画室 609", 15,
		Color(0.86, 0.93, 1.0, 0.9), Color(0.0, 0.06, 0.12, 0.65), 3)
	_start_hint.name = "StartHint"
	_start_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_hint.visible = false
	_ui.add_child(_start_hint)


## 统一算版式（初次 + 窗口尺寸变化后都走这里）。
func _layout() -> void:
	if _root == null or not is_instance_valid(_root):
		return
	var vp := Vector2(_root.size)
	if vp.x < 64.0 or vp.y < 64.0:
		vp = Vector2(1600.0, 900.0)
	var cx := vp.x * 0.5

	# 标题：左上角，离边 56 / 44
	if _title_plate != null:
		var plate_min := _title_plate.get_combined_minimum_size()
		plate_min.x += 44.0
		plate_min.y = maxf(plate_min.y, UiSkin.TITLE_TAG_HEIGHT)
		_title_plate.size = plate_min
		_title_plate.position = Vector2(56.0, 44.0)
		if _title_rule != null:
			_title_rule.size = Vector2(plate_min.x * 0.86, UiSkin.TITLE_RULE_HEIGHT)
			_title_rule.position = Vector2(56.0, 44.0 + plate_min.y + 8.0)
		if _title_sub != null:
			_title_sub.size = Vector2(640.0, 26.0)
			_title_sub.position = Vector2(56.0, 44.0 + plate_min.y + 22.0)

	# 底部：进度条 + 按钮
	var bar_x := cx - BAR_W * 0.5
	var bar_y := vp.y - 190.0
	if _bar_track != null:
		_bar_track.position = Vector2(bar_x, bar_y)
		_bar_track.size = Vector2(BAR_W, BAR_H)
	if _bar_fill != null:
		_bar_fill.position = Vector2(1.0, 1.0)
		_bar_fill.size = Vector2(maxf(BAR_INNER * clampf(_disp_ratio, 0.0, 1.0), 0.0), BAR_H - 2.0)
	if _progress_label != null:
		_progress_label.size = Vector2(vp.x, 30.0)
		_progress_label.position = Vector2(0.0, bar_y - 40.0)
	if _load_hint != null:
		_load_hint.size = Vector2(vp.x, 24.0)
		_load_hint.position = Vector2(0.0, bar_y + BAR_H + 14.0)
	if _start_button != null:
		_start_button.size = BTN_SIZE
		_start_button.position = Vector2(cx - BTN_SIZE.x * 0.5, bar_y + BAR_H + 46.0)
		_start_button.pivot_offset = BTN_SIZE * 0.5
	if _start_hint != null:
		_start_hint.size = Vector2(vp.x, 24.0)
		_start_hint.position = Vector2(0.0, bar_y + BAR_H + 46.0 + BTN_SIZE.y + 12.0)

	if _scrim != null:
		var scrim_y := vp.y * 0.42
		_scrim.position = Vector2(0.0, scrim_y)
		_scrim.size = Vector2(vp.x, vp.y - scrim_y)

	_apply_bar()


func _on_viewport_resized() -> void:
	if not _playing or _relayout_queued:
		return
	_relayout_queued = true
	await get_tree().process_frame
	_relayout_queued = false
	if not _playing or _root == null or not is_instance_valid(_root):
		return
	_layout()
	# 宽图的缩放/平移行程是按屏幕尺寸算的，尺寸一变就得重排（否则会露边）。
	if not _ready_done:
		_restart_slideshow()


func _apply_bar() -> void:
	if _bar_fill != null and is_instance_valid(_bar_fill):
		_bar_fill.size = Vector2(
			maxf(BAR_INNER * clampf(_disp_ratio, 0.0, 1.0), 0.0), BAR_H - 2.0)


# ── 加载进度 ────────────────────────────────────────────────────────────

func _run_loading(poll: Callable) -> void:
	var started := Time.get_ticks_msec()
	var hint_on := false
	while true:
		var st: Dictionary = {}
		if poll.is_valid():
			var raw: Variant = poll.call()
			if raw is Dictionary:
				st = raw
		var target := clampf(float(st.get("ratio", 1.0)), 0.0, 1.0)
		var ready := bool(st.get("ready", true))
		if ready:
			target = 1.0
		# 显示的进度**只升不降**，并且按 0.9/s 追目标 —— 缓存的进度是
		# 0/1 → 1/2 → 2/2 三个大台阶，直接照抄会「唰」地跳。
		var step := _delta() * 0.9
		_disp_ratio = maxf(_disp_ratio, minf(target, _disp_ratio + step))
		if _progress_label != null and is_instance_valid(_progress_label):
			var pct := roundi(_disp_ratio * 100.0)
			var names: Array = st.get("names", [])
			if not names.is_empty():
				_progress_label.text = "正在载入 %s  %d%%" % [String(names[0]), pct]
			else:
				_progress_label.text = "载入中  %d%%" % pct
		_apply_bar()
		if not ready and not hint_on and _seconds_since(started) > HINT_AFTER:
			hint_on = true
			if _load_hint != null and is_instance_valid(_load_hint):
				_hint_tw = create_tween()
				_hint_tw.tween_property(_load_hint, "modulate:a", 1.0, 0.4)
		if ready:
			break
		if _seconds_since(started) > SETTLE_MAX:
			push_warning("[TitleIntro] 等满了 %.0f s 还没就绪 —— 兜底放行（会露出加载过程）"
				% SETTLE_MAX)
			break
		await get_tree().process_frame

	_disp_ratio = 1.0
	_apply_bar()
	_ready_done = true
	if _progress_label != null and is_instance_valid(_progress_label):
		_progress_label.text = "载入完成"
	if _load_hint != null and is_instance_valid(_load_hint):
		# 「首次启动久一点」那行只在**还没就绪**时有用；就绪时要立刻收掉，
		# 而且得先杀掉淡入 Tween —— 两个 Tween 同时改 alpha 会停在中间值。
		if _hint_tw != null and _hint_tw.is_valid():
			_hint_tw.kill()
		var tw2 := create_tween()
		tw2.tween_property(_load_hint, "modulate:a", 0.0, 0.25)
		tw2.tween_callback(func() -> void:
			if _load_hint != null and is_instance_valid(_load_hint):
				_load_hint.visible = false)
	await _reveal_start_button()


## 世界就绪：把「开始游戏」弹出来（玩家不点就不往下走）。
func _reveal_start_button() -> void:
	if _start_button == null or not is_instance_valid(_start_button):
		return
	_start_button.visible = true
	_start_button.disabled = false
	_start_button.modulate.a = 0.0
	_start_button.scale = Vector2(0.92, 0.92)
	_start_button.pivot_offset = _start_button.size * 0.5
	if _start_hint != null and is_instance_valid(_start_hint):
		_start_hint.visible = true
		_start_hint.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_start_button, "modulate:a", 1.0, 0.40)
	tw.tween_property(_start_button, "scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _start_hint != null and is_instance_valid(_start_hint):
		tw.tween_property(_start_hint, "modulate:a", 1.0, 0.5).set_delay(0.12)
	await tw.finished
	print("[TitleIntro] 载入完成，等玩家点「开始游戏」")


func _wait_for_start() -> void:
	while not _start_pressed and _playing:
		await get_tree().process_frame


func _on_start_pressed() -> void:
	if not _ready_done or _start_pressed:
		return
	_start_pressed = true
	Sfx.play("ui_press", -4.0)
	print("[TitleIntro] 开始游戏：点击（从开场到现在 %.1f s）" % _seconds_since(_t_start))


## 整层淡出 + 音乐淡出，最后放开被压住的房间 BGM。
func _fade_out_all() -> void:
	if _start_button != null and is_instance_valid(_start_button):
		_start_button.disabled = true
	var tw := create_tween()
	tw.set_parallel(true)
	if _root != null and is_instance_valid(_root):
		tw.tween_property(_root, "modulate:a", 0.0, FADE_OUT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _music != null and is_instance_valid(_music):
		tw.tween_property(_music, "volume_db", -60.0, MUSIC_OUT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	if _music != null and is_instance_valid(_music):
		_music.stop()
	if _music_held:
		_music_held = false
		Music.hold(false)


# ── 输入 ────────────────────────────────────────────────────────────────

## ⚠️ 只有**就绪之后**的 Enter / Space 才开始。
##    加载期间按任何键都**不跳过** —— 用户 2026-11-12：「因为有人会听歌」。
func _input(event: InputEvent) -> void:
	if not _playing or not _ready_done or _start_pressed:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER \
				or key.keycode == KEY_SPACE:
			_on_start_pressed()


# ── 音频 ────────────────────────────────────────────────────────────────

func _start_music() -> void:
	var stream := _load_music()
	if stream == null:
		return
	_music = AudioStreamPlayer.new()
	_music.name = "PvMusic"
	_music.stream = stream
	_music.bus = "Master"
	_music.volume_db = -22.0
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	_layer.add_child(_music)
	_music.play()
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", MUSIC_DB, MUSIC_IN)


## 优先 `load()`（用了导入缓存）；没导入就现场解 MP3 字节。
func _load_music() -> AudioStream:
	if not FileAccess.file_exists(PV_MUSIC):
		push_warning("[TitleIntro] 找不到开场音乐 %s（PV 照常放，只是没声音）" % PV_MUSIC)
		return null
	if ResourceLoader.exists(PV_MUSIC):
		var st := load(PV_MUSIC) as AudioStream
		if st != null:
			_set_stream_loop(st)
			return st
	var f := FileAccess.open(PV_MUSIC, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.is_empty():
		return null
	var mp3 := AudioStreamMP3.new()
	mp3.data = bytes
	mp3.loop = true
	return mp3


## 循环播放：有人在开始界面把歌听完。
func _set_stream_loop(st: AudioStream) -> void:
	var mp3 := st as AudioStreamMP3
	if mp3 != null:
		mp3.loop = true
		mp3.loop_offset = 0.0
		return
	var ogg := st as AudioStreamOggVorbis
	if ogg != null:
		ogg.loop = true
		ogg.loop_offset = 0.0
		return
	var wav := st as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD


# ── 小工具 ──────────────────────────────────────────────────────────────

func _make_label(text: String, font_size: int, color: Color,
		outline: Color = Color(0, 0, 0, 0), outline_size: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := UiSkin.ui_font()
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline_size > 0:
		label.add_theme_color_override("font_outline_color", outline)
		label.add_theme_constant_override("outline_size", outline_size)
	return label


func _fallback_gradient() -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(0.07, 0.16, 0.28, 1.0),
		Color(0.035, 0.09, 0.17, 1.0),
		Color(0.01, 0.03, 0.06, 1.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 8
	tex.height = 256
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	return tex


func _bottom_gradient() -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([
		Color(0.0, 0.02, 0.05, 0.0),
		Color(0.0, 0.03, 0.07, 0.80),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 8
	tex.height = 256
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	return tex


func _delta() -> float:
	return get_process_delta_time()


func _seconds_since(t_ms: int) -> float:
	return float(Time.get_ticks_msec() - t_ms) / 1000.0


## 自检用：一帧都不用等，直接问「这层还在不在放」。
func is_playing() -> bool:
	return _playing


## 自检用：开始按钮有没有弹出来。
func is_start_ready() -> bool:
	return _ready_done


func _exit_tree() -> void:
	if _music != null and is_instance_valid(_music):
		_music.stop()
	if _music_held:
		_music_held = false
		Music.hold(false)
