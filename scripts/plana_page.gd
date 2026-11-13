class_name PlanaPage
extends Control
## 电脑屏幕里的**普拉娜**（绿幕视频抠像后的 PNG 序列，逐帧播放）。
##
## 用户 2026-11-12：给了 `依旧送送送，普拉娜绿幕素材…_视频.mp4`，
## 要求「扣绿幕，输入 plana 就出现这」。
##
## ── 素材怎么来的 ──
## 源视频 720×786 / 30 fps / 29.53 s。用 ffmpeg 抠绿幕 + 去溢色：
##     chromakey=0x46E200:0.16:0.06     ← 绿幕实测就是 (70,226,0)，非常干净
##     despill=type=green:mix=1:expand=0.3   ← 不加这个，剪影边缘有一圈亮绿边
##     fps=15                            ← 30 → 15，动画感够、帧数减半
##     scale=360:-1:flags=lanczos
## 产出 `assets/plana_frames/f_0001.png … f_0443.png`（443 帧，43 MB，已 gitignore）。
##
## ── 为什么不用「带 alpha 的 .ogv」 ──
## 先试了 ogv（Theora，Godot 唯一支持的视频格式）：ffmpeg 能编
## `-c:v libtheora -pix_fmt yuva420p`，但**Godot 播出来 alpha 全是 255**
## （实测：帧格式确实是 RGBA8，可最小 alpha = 255、半透明采样 0 个），
## 而且 ffmpeg 自己回解这个 ogv 都报 `error in unpack_block_qpis`、解出来是 RGB。
## 所以视频这条路不通，只能序列帧。
##
## ── 为什么必须「流式」加载 ──
## 443 帧 × 360×393 × 4 字节 ≈ **250 MB 显存**，全量载入会把这个本来就吃显存的
## 项目再压垮。所以这里只保留 `CACHE_MAX` 帧的环形缓冲，需要哪帧才读哪帧；
## 并且用 `ResourceLoader.CACHE_MODE_IGNORE` —— 否则 ResourceLoader 自己会把
## 每次 `load()` 的结果都缓存住，等于又变成全量载入。

const FRAME_DIR := "res://assets/plana_frames"
const FPS := 15.0
## 环形缓冲保留多少帧。48 帧 ≈ 27 MB 显存，够覆盖 3 秒的来回播放
const CACHE_MAX := 48
const FONT_PATH := "res://assets/ui/font.ttf"

## 画面占屏幕高度的比例（剩下留给对话框）
const IMAGE_H_RATIO := 0.78
## 横向位置：0 = 最左，1 = 最右。0.62 让她偏右站，气泡留在左下
const IMAGE_X_RATIO := 0.62

## 台词（普拉娜语气：安静、话少、句尾软）—— 和 `arona_page.gd` 的元气形成对比
const LINES := [
	"……老师，我在这里。",
	"需要我做什么吗？",
	"这个屏幕，是我暂时的房间。",
	"……老师，你已经很久没休息了。",
	"我看见了哦。老师刚才在发呆。",
	"不用担心，我会一直看着的。",
	"……嗯。就这样，安静一会儿也好。",
]

const TYPE_SPEED := 22.0
const HOLD := 4.0

var _frames: Array[String] = []
var _cache := {}                 # int -> Texture2D
var _cache_order: Array = []     # 插入顺序，用来淘汰
var _t := 0.0
var _frame_i := -1

var _line_i := 0
var _typed := 0.0
var _hold := 0.0
var _blink := 0.0

var _font: Font
var _sb_bubble: StyleBoxFlat
var _sb_plate: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load(FONT_PATH) as Font if ResourceLoader.exists(FONT_PATH) \
		else ThemeDB.fallback_font

	_sb_bubble = StyleBoxFlat.new()
	_sb_bubble.bg_color = Color(0.07, 0.08, 0.13, 0.84)
	_sb_bubble.set_corner_radius_all(14)
	_sb_bubble.set_border_width_all(2)
	_sb_bubble.border_color = Color(0.72, 0.62, 0.92, 0.85)

	_sb_plate = StyleBoxFlat.new()
	_sb_plate.bg_color = Color(0.72, 0.62, 0.92, 0.22)
	_sb_plate.set_corner_radius_all(10)

	_scan_frames()
	visible = false
	set_process(false)


## 列出 `f_0001.png …`，按名字排序（补零了，字典序 = 帧序）
func _scan_frames() -> void:
	_frames.clear()
	var d := DirAccess.open(FRAME_DIR)
	if d == null:
		push_warning("[Plana] 缺帧目录 %s —— 用 _tools/fetch_plana_frames.ps1 重新生成" % FRAME_DIR)
		print("[Plana] !! 缺 %s" % FRAME_DIR)
		return
	var seen := {}
	for f in d.get_files():
		# 导出包里只有 `.png.import`（运行时靠它重映射到 .ctex），裸 .png 不进包
		var name := String(f)
		if name.ends_with(".png.import"):
			name = name.substr(0, name.length() - ".import".length())
		if not name.ends_with(".png") or seen.has(name):
			continue
		seen[name] = true
		_frames.append(FRAME_DIR.path_join(name))
	_frames.sort()
	print("[Plana] 帧序列就绪：%d 帧（%.1f s @ %.0f fps）"
		% [_frames.size(), float(_frames.size()) / FPS, FPS])


func frame_count() -> int:
	return _frames.size()


func open() -> void:
	visible = true
	set_process(true)
	_t = 0.0
	_frame_i = -1
	_line_i = randi() % LINES.size()
	_typed = 0.0
	_hold = 0.0
	_warm_cache(0)
	queue_redraw()


func close() -> void:
	visible = false
	set_process(false)
	# 退出就把纹理全放掉，别让 27 MB 一直占着
	_cache.clear()
	_cache_order.clear()


func feed(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	match k.keycode:
		KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_BACKSPACE:
			close_requested_safe()
			return true
		KEY_SPACE:
			_next_line()
			return true
	return true


func close_requested_safe() -> void:
	# 用信号通知上层（保持和 AronaPage 一致的用法）
	close_requested.emit()


signal close_requested


func _next_line() -> void:
	_line_i = (_line_i + 1) % LINES.size()
	_typed = 0.0
	_hold = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _frames.is_empty():
		return
	_t += delta
	var idx := int(_t * FPS) % _frames.size()
	if idx != _frame_i:
		_frame_i = idx
		_get_frame(idx)
	# 顺手把后面几帧读进来，避免卡顿
	_warm_cache((idx + 1) % _frames.size())

	# 台词
	var full := String(LINES[_line_i]).length()
	if _typed < float(full):
		_typed = minf(_typed + TYPE_SPEED * delta, float(full))
	else:
		_hold += delta
		if _hold >= HOLD:
			_next_line()
			return
	_blink += delta
	queue_redraw()


func _warm_cache(i: int) -> void:
	for k in 3:
		_get_frame((i + k) % _frames.size())


## 取一帧纹理；不在缓存里就现读（**不缓存模式**，交给自己的环形缓冲管）
func _get_frame(i: int) -> Texture2D:
	if _cache.has(i):
		return _cache[i]
	if _frames.is_empty() or i < 0 or i >= _frames.size():
		return null
	var tex := ResourceLoader.load(_frames[i], "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if tex == null:
		return null
	_cache[i] = tex
	_cache_order.append(i)
	while _cache_order.size() > CACHE_MAX:
		var old: int = _cache_order.pop_front()
		if old != i:
			_cache.erase(old)
	return tex


func _draw() -> void:
	# ⚠️ 不画整屏不透明底 —— 但这里没有 3D 垫底，所以要给个深色底 + 一点点舞台光
	var bg := Color(0.055, 0.06, 0.085)
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	# 底部渐深，衬托对话框
	var grad_h := 170.0
	var steps := 24
	for i in steps:
		var f := float(i) / float(steps - 1)
		draw_rect(Rect2(0, size.y - grad_h + grad_h * f, size.x,
			grad_h / float(steps) + 1.0), Color(0.02, 0.02, 0.04, 0.55 * f * f))

	# ── 帧 ──
	if _frame_i >= 0:
		var tex := _get_frame(_frame_i)
		if tex != null:
			var ts := tex.get_size()
			var target_h := size.y * IMAGE_H_RATIO
			var target_w := target_h * (ts.x / ts.y)
			var max_w := size.x * 0.62
			if target_w > max_w:
				target_w = max_w
				target_h = target_w * (ts.y / ts.x)
			# 水平按比例定位（以「图像中心」为准），垂直底边贴着对话框上方
			var cx := size.x * IMAGE_X_RATIO
			var top := size.y - 96.0 - target_h
			draw_texture_rect(tex,
				Rect2(cx - target_w * 0.5, top, target_w, target_h), false)

	# ── 名牌 ──
	var plate := Rect2(22.0, size.y - 132.0, 176.0, 34.0)
	draw_style_box(_sb_plate, plate)
	draw_string(_font, plate.position + Vector2(14.0, 23.0), "普拉娜",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.94, 0.94, 1.0))
	draw_string(_font, plate.position + Vector2(88.0, 22.0), "PLANA",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.78, 0.72, 0.98, 0.9))

	# ── 对话框 ──
	var bubble := Rect2(22.0, size.y - 92.0, size.x - 44.0, 62.0)
	draw_style_box(_sb_bubble, bubble)
	var full := String(LINES[_line_i])
	var shown := full.substr(0, int(_typed))
	var tx := bubble.position.x + 18.0
	var ty := bubble.position.y + 26.0
	draw_string(_font, Vector2(tx, ty), shown, HORIZONTAL_ALIGNMENT_LEFT,
		bubble.size.x - 36.0, 16, Color(0.95, 0.95, 1.0))
	if int(_typed) < full.length() or fmod(_blink, 1.0) < 0.5:
		var w := _font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_rect(Rect2(tx + w + 2.0, ty - 13.0, 8.0, 15.0),
			Color(0.78, 0.72, 1.0, 0.9))

	# ── 提示 ──
	draw_string(_font, Vector2(size.x - 250.0, size.y - 12.0),
		"Space 换一句 · Esc 退出", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.55, 0.60, 0.70))
