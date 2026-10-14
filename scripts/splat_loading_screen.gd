extends Control
## 高斯数据加载界面 —— 拾忆校园
##
## 运行时展开 615 万个高斯点要几十秒，放在主线程会把窗口冻住，所以：
##   - 展开在工作线程里跑（sog_runtime.gd 全程只碰 FileAccess/Image/资源对象）
##   - 本界面每帧从互斥锁保护的共享变量里读进度，负责显示
##   - 展开完成/失败后抛出 finished(result)，由 game.gd 决定下一步

signal finished(result: Dictionary)

const SogRuntime := preload("res://scripts/sog_runtime.gd")

## 各阶段在总进度条上的 [起点, 跨度]，decode 是绝对大头
const PHASE_SPAN := {
	"textures": [0.00, 0.02],
	"center": [0.02, 0.08],
	"decode": [0.10, 0.82],
	"pack": [0.92, 0.08],
}

const PHASE_LABEL := {
	"textures": "解码 SOG 纹理",
	"center": "计算场景中心",
	"decode": "展开高斯点",
	"pack": "打包 GPU 数据",
}

var source: String = ""

var _thread: Thread = null
var _mutex := Mutex.new()
var _phase: String = ""
var _done: int = 0
var _total: int = 0
var _result: Dictionary = {}

var _overall := 0.0
var _start_ms := 0
var _decode_start_ms := 0
var _tick := 0

var _title: Label
var _status: Label
var _bar: ProgressBar
var _detail: Label
var _hint: Label
var _spinner: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func begin(sog_source: String) -> void:
	source = sog_source
	_start_ms = Time.get_ticks_msec()
	_hint.text = "每次启动都会从随包 SOG 重新展开 615 万个高斯点；请耐心等待"

	_thread = Thread.new()
	_thread.start(_worker)


func _worker() -> void:
	var result: Dictionary = SogRuntime.load_sog(source, {
		"cache": "off",
		"progress": Callable(self, "_on_progress_from_thread"),
	})
	_mutex.lock()
	_result = result
	_mutex.unlock()


## 注意：这个回调在**工作线程**里执行，只能写共享变量，绝不能碰 UI 节点。
func _on_progress_from_thread(phase: String, done: int, total: int) -> void:
	_mutex.lock()
	if phase != _phase and phase == "decode":
		_decode_start_ms = Time.get_ticks_msec()
	_phase = phase
	_done = done
	_total = total
	_mutex.unlock()


func _process(_delta: float) -> void:
	if _thread == null:
		return

	_mutex.lock()
	var phase := _phase
	var done := _done
	var total := _total
	var decode_start := _decode_start_ms
	_mutex.unlock()

	if phase != "":
		var span: Array = PHASE_SPAN.get(phase, [0.0, 0.05])
		var ratio := 0.0 if total <= 0 else clampf(float(done) / float(total), 0.0, 1.0)
		_overall = maxf(_overall, float(span[0]) + float(span[1]) * ratio)
		_title.text = "展开高斯记忆场"
		_status.text = "%s…" % PHASE_LABEL.get(phase, phase)
		_bar.value = _overall * 100.0

		var detail := "总进度 %d%%" % int(_overall * 100.0)
		if phase == "decode" and done > 0 and decode_start > 0:
			var elapsed := float(Time.get_ticks_msec() - decode_start) / 1000.0
			if elapsed > 0.5:
				var rate := float(done) / elapsed
				var eta := float(total - done) / maxf(rate, 1.0)
				detail += "　·　已展开 %s / %s 点" % [_fmt_int(done), _fmt_int(total)]
				detail += "　·　预计还需 %d 秒" % int(ceil(eta))
		_detail.text = detail

	_tick += 1
	_spinner.text = ".".repeat((_tick / 20) % 4)

	if not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
		_mutex.lock()
		var result := _result
		_mutex.unlock()
		_bar.value = 100.0
		finished.emit(result)


func elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _start_ms) / 1000.0


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.075, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var grad := TextureRect.new()
	var grad_tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.09, 0.12, 0.24))
	g.set_color(1, Color(0.30, 0.17, 0.22))
	grad_tex.gradient = g
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(0, 1)
	grad_tex.fill = GradientTexture2D.FILL_LINEAR
	grad.texture = grad_tex
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grad)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	_title = Label.new()
	_title.text = "展开高斯记忆场"
	_title.add_theme_font_size_override("font_size", 38)
	_title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	_status = Label.new()
	_status.text = "正在准备…"
	_status.add_theme_font_size_override("font_size", 17)
	_status.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86))
	row.add_child(_status)

	_spinner = Label.new()
	_spinner.text = ""
	_spinner.custom_minimum_size.x = 28
	_spinner.add_theme_font_size_override("font_size", 17)
	_spinner.add_theme_color_override("font_color", Color(1.0, 0.80, 0.48))
	row.add_child(_spinner)

	var bar_bg := PanelContainer.new()
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.10, 0.12, 0.20, 0.92)
	bar_style.border_color = Color(0.91, 0.68, 0.34, 0.55)
	bar_style.set_border_width_all(1)
	bar_style.set_corner_radius_all(6)
	bar_style.content_margin_left = 2
	bar_style.content_margin_right = 2
	bar_style.content_margin_top = 2
	bar_style.content_margin_bottom = 2
	bar_bg.add_theme_stylebox_override("panel", bar_style)
	box.add_child(bar_bg)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 16
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.98, 0.74, 0.38)
	fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("fill", fill)
	var track := StyleBoxEmpty.new()
	_bar.add_theme_stylebox_override("background", track)
	bar_bg.add_child(_bar)

	_detail = Label.new()
	_detail.text = "总进度 0%"
	_detail.add_theme_font_size_override("font_size", 15)
	_detail.add_theme_color_override("font_color", Color(0.85, 0.83, 0.80))
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_detail)

	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	box.add_child(gap)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.62))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)


static func _fmt_int(value: int) -> String:
	var s := str(value)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
