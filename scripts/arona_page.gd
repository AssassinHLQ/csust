class_name AronaPage
extends Control
## 电脑屏幕里阿洛娜的**界面层**：名牌 + 对话框 + 提示。
##
## ⚠️ 这一层**不画整屏背景** —— 它下面就是 `AroneStage` 那台 3D 相机渲染出来的画面，
##    铺一层不透明底色就把阿洛娜盖没了。只画名牌、气泡和一点点屏幕质感。
##
## 台词轮换 + 打字机效果：给人一种「她在说话」的感觉（模型本身没动画，
## 见 `arona_stage.gd` 头部的说明）。

signal close_requested

const FONT_PATH := "res://assets/ui/font.ttf"

## 台词池（轮换）。语气照阿洛娜：元气的学生会长代理 + 一点点吐槽。
const LINES := [
	"早上好，老师！今天也要一起加油哦～",
	"检测到老师已经连续工作很久了……要不要休息一下？",
	"这个终端是假的啦，什么都执行不了的哦。",
	"阿罗娜会一直在电脑里陪着老师的！",
	"老师，听说你上次又在高台上摔下去了……",
	"需要我帮你查一下「如何不被霸王龙追」吗？",
	"٩(๑•̀ω•́๑)۶ 老师今天也很努力呢！",
]

const TYPE_SPEED := 26.0        # 每秒显示几个字
const HOLD := 3.4               # 打完停多久换下一句

var _line_i := 0
var _typed := 0.0
var _hold := 0.0
var _font: Font
var _blink := 0.0

var _sb_bubble: StyleBoxFlat
var _sb_plate: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load(FONT_PATH) as Font if ResourceLoader.exists(FONT_PATH) \
		else ThemeDB.fallback_font

	_sb_bubble = StyleBoxFlat.new()
	_sb_bubble.bg_color = Color(0.06, 0.08, 0.12, 0.82)
	_sb_bubble.set_corner_radius_all(14)
	_sb_bubble.set_border_width_all(2)
	_sb_bubble.border_color = Color(0.42, 0.68, 0.95, 0.85)

	_sb_plate = StyleBoxFlat.new()
	_sb_plate.bg_color = Color(0.42, 0.68, 0.95, 0.22)
	_sb_plate.set_corner_radius_all(10)

	visible = false
	set_process(false)


func open() -> void:
	visible = true
	set_process(true)
	_line_i = randi() % LINES.size()
	_typed = 0.0
	_hold = 0.0
	queue_redraw()


func close() -> void:
	visible = false
	set_process(false)


func feed(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	match k.keycode:
		KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_BACKSPACE:
			close_requested.emit()
			return true
		KEY_SPACE:
			# 空格 = 直接叫下一句
			_next_line()
			return true
	return true


func _next_line() -> void:
	_line_i = (_line_i + 1) % LINES.size()
	_typed = 0.0
	_hold = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	_blink += delta
	var full := String(LINES[_line_i]).length()
	if _typed < float(full):
		_typed = minf(_typed + TYPE_SPEED * delta, float(full))
	else:
		_hold += delta
		if _hold >= HOLD:
			_next_line()
			return
	queue_redraw()


func _draw() -> void:
	# ⚠️ 不画整屏底 —— 见文件头。
	# 只在底部压一点渐变，让文字有承托（用几条横向的半透明矩形做软过渡）
	var grad_h := 150.0
	var steps := 24
	for i in steps:
		var f := float(i) / float(steps - 1)
		var a := 0.55 * f * f
		draw_rect(Rect2(0, size.y - grad_h + grad_h * f, size.x, grad_h / float(steps) + 1.0),
			Color(0.02, 0.03, 0.05, a))

	# 名牌（左下角）
	var plate := Rect2(22.0, size.y - 132.0, 176.0, 34.0)
	draw_style_box(_sb_plate, plate)
	draw_string(_font, plate.position + Vector2(14.0, 23.0), "阿洛娜",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.92, 0.96, 1.0))
	draw_string(_font, plate.position + Vector2(84.0, 22.0), "ARONA",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.78, 0.98, 0.9))

	# 对话气泡
	var bubble := Rect2(22.0, size.y - 92.0, size.x - 44.0, 62.0)
	draw_style_box(_sb_bubble, bubble)
	var full := String(LINES[_line_i])
	var shown := full.substr(0, int(_typed))
	var tx := bubble.position.x + 18.0
	var ty := bubble.position.y + 26.0
	draw_string(_font, Vector2(tx, ty), shown, HORIZONTAL_ALIGNMENT_LEFT,
		bubble.size.x - 36.0, 16, Color(0.94, 0.96, 1.0))
	# 打字机光标（打完就闪烁，还没打完就常亮）
	if int(_typed) < full.length() or fmod(_blink, 1.0) < 0.5:
		var w := _font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_rect(Rect2(tx + w + 2.0, ty - 13.0, 8.0, 15.0),
			Color(0.55, 0.80, 1.0, 0.9))

	# 提示（右下角）
	draw_string(_font, Vector2(size.x - 250.0, size.y - 12.0),
		"Space 换一句 · Esc 退出", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.55, 0.60, 0.70))
