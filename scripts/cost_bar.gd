extends Control
## BA（蔚蓝档案）风格的 **COST 量** —— 纯 `_draw()` 自绘，**不引用任何一张贴图**。
##
## 为什么自绘、不搬原作素材：
##   《蔚蓝档案》国服项目组《二创指引》「创作不被允许，禁止的事项」第 1 条：
##     「直接使用、描改、复制、局部改动、剪辑游戏原始素材，进行同人作品的创作或宣传」
##   是**明确不允许**的。而**几何比例与配色是规格，不是素材** —— 照着比例自己画出来，
##   既拿到原作观感，又不用把解包贴图塞进（公开的）仓库。
##
## ── 三层结构与比例是哪来的（不是本喵猜的）──
##
## 出处：社区还原项目 `ywhdzrb/BlueArchiveUI`（**代码部分 MIT**）的
##       `src/ba_progress_bar.cpp`。它按官方 `Common_Bg_Raius5px` 量出的规格是：
##
##   · 官方基准高 **31 px**；
##   · 三层：**外底白 → 内槽深蓝 (0.19, 0.27, 0.40) → 彩色填充**；
##   · 内槽在外底上**左右各内缩 4.5k、上下各内缩 3.0k**，填充再各内缩 **3.5k**
##     （k = 实际高 / 31）；
##   · 每一层的**端部斜切量 = 该层自己的高 × 0.42**、**转角圆角 = 该层自己的高 × 0.18**。
##
## ⚠️ 最后那条「按**各自的**高度取比例」是关键，不是随便写的：三层高度不同，
##    用**同一个绝对像素值**会让三层的斜边**不平行** —— 出来的效果是「填充是斜的、
##    边框却是正的」，很脏。原作者在注释里专门记了这个坑。
##
## ── 色板（同项目的 `ba_style.h`，BA 官方 UI 取色）──
##
##   accent() = #4EC3F5 青蓝高亮 · sky() = #77DEFF · deep() = #003153 深藏蓝
##   yellow() = #FFE433 装饰黄 · track = #40454F→#23272E · progressFill = #C7F0FF→#96DCFA
##   chipBlack() = #252F41「数值消耗片」深蓝黑底
##
## ── 本喵自己加的两处（原作没有，不许当成原作规格）──
##
##   ① **10 格刻度线**：原版那条是连续条，不分格。但 COST 本来就是「1~10 的整数」
##      （上限 10、每秒回 1），画上刻度才看得出「再攒 4 点能放 EX」。见 `show_ticks`。
##   ② **攒满换色**：满了（>= max）时填充换成 BA 的装饰黄 #FFE433，表示「EX 可以放了」。
##      原版没有这个反馈。见 `_fill_pair()`。
##
## 谁用它：`hud.gd::_build_cost_row()` 建一个、`_refresh_cost()` 每帧喂值。

# ── 官方基准（`ba_progress_bar.cpp` 的常量，别随手改）────────────────────────
const BASE_H := 31.0      ## 官方基准高，k = 实际高 / 它
const SLOPE := 0.42       ## 端部斜切量 = **该层**高 × 它（三层才会互相平行）
const CORNER := 0.18      ## 转角圆角   = **该层**高 × 它
const INSET_X := 4.5      ## 外底 → 内槽：左右各内缩（× k）
const INSET_Y := 3.0      ## 外底 → 内槽：上下各内缩（× k）
const FORE_PAD := 3.5     ## 内槽 → 填充：四边再各内缩（× k）

# ── 色板（`ba_style.h` 的官方取色）────────────────────────────────────────
const C_OUTER := Color(1.0, 1.0, 1.0)              ## 外底：官方白
const C_TROUGH := Color(0.19, 0.27, 0.40)          ## 内槽：官方深蓝
const C_FILL_HI := Color("#c7f0ff")                ## 填充亮端（progressFill 上）
const C_FILL_LO := Color("#96dcfa")                ## 填充暗端（progressFill 下）
const C_FULL_HI := Color("#ffe433")                ## 攒满：装饰黄
const C_FULL_LO := Color("#ffc95c")
const C_TICK := Color(1.0, 1.0, 1.0, 0.22)         ## 刻度线（本喵加的）

## 当前值（**小数**：原作那条是连续填的，只在显示数字时取整）。
var value := 0.0
## 上限。COST 是 10。
var max_value := 10.0
## 画不画分格刻度线（本喵加的，见文件头 ①）
var show_ticks := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = maxf(custom_minimum_size.y, BASE_H)


## 喂值。**必须走这个**，直接写 `value` 不会重画（普通变量没有 setter）。
func set_cost(v: float) -> void:
	if is_equal_approx(value, v):
		return
	value = v
	queue_redraw()


## 当前比例 0~1
func ratio() -> float:
	return clampf(value / maxf(max_value, 1.0), 0.0, 1.0)


func _draw() -> void:
	var h := size.y
	if h < 4.0 or size.x < 12.0:
		return
	var k := h / BASE_H

	# 三层矩形（比例全部来自官方量测，见文件头）
	var outer := Rect2(Vector2.ZERO, size)
	var back := Rect2(
		outer.position + Vector2(INSET_X * k, INSET_Y * k),
		outer.size - Vector2(2.0 * INSET_X * k, 2.0 * INSET_Y * k))
	var pad := FORE_PAD * k
	var fore := Rect2(
		back.position + Vector2(pad, pad),
		back.size - Vector2(2.0 * pad, 2.0 * pad))
	if fore.size.x <= 4.0 or fore.size.y <= 2.0:
		return

	# ① 外底白 ② 内槽深蓝 —— 斜量与圆角**各自按自己的高度**取，三层才平行
	draw_colored_polygon(_rounded(_cut(outer, h * SLOPE), h * CORNER), C_OUTER)
	draw_colored_polygon(
		_rounded(_cut(back, back.size.y * SLOPE), back.size.y * CORNER), C_TROUGH)

	# ③ 填充：按比例截出的斜切块，斜量与槽同比例（斜边互相平行）
	var fw := fore.size.x * ratio()
	var cut_fore := fore.size.y * SLOPE
	if fw > cut_fore + 2.0:
		var fr := Rect2(fore.position, Vector2(fw, fore.size.y))
		var pts := _rounded(_cut(fr, cut_fore), fore.size.y * CORNER)
		var pair := _fill_pair()
		var cols := PackedColorArray()
		cols.resize(pts.size())
		for i in pts.size():
			# 竖向渐变：亮在上、暗在下（原作填充就是个上亮下暗的渐变）
			var t := clampf((pts[i].y - fr.position.y) / maxf(fr.size.y, 1.0), 0.0, 1.0)
			cols[i] = pair[0].lerp(pair[1], t)
		draw_polygon(pts, cols)

	if show_ticks:
		_draw_ticks(fore, back, k)


## 攒满换成 BA 的装饰黄（本喵加的反馈，原作没有）
func _fill_pair() -> PackedColorArray:
	if ratio() >= 0.999:
		return PackedColorArray([C_FULL_HI, C_FULL_LO])
	return PackedColorArray([C_FILL_HI, C_FILL_LO])


## 单位刻度线（本喵加的）。
##
## ⚠️ 横向用 **`fore`（填充层）的宽度**算，不用 `back`（内槽）——
##    填充是按 `fore.size.x` 映射值域算出来的，刻度只有用同一个矩形，
##    第 i 格边界才和填充边缘**严丝合缝**。用 `back` 会整体偏最多一个 `FORE_PAD`：
##    `back.left + back.w·f` vs `fore.left + fore.w·f` 差 `3.5k·(1-2f)`，两端各偏 3.5k。
## ⚠️ 纵向仍旧撑在**内槽**上（`back`），刻度才上下贯通、不缩在填充那一条里。
## ⚠️ 画在**最后**：盖在填充上面，浅色底（青 / 黄）和深色槽都看得见。
func _draw_ticks(fore: Rect2, back: Rect2, k: float) -> void:
	var n := int(round(max_value))
	if n < 2 or n > 40:
		return
	var w := maxf(1.0, floorf(k))         # 细条也别细过 1 px
	var y0 := back.position.y + back.size.y * 0.22
	var y1 := back.position.y + back.size.y * 0.78
	for i in range(1, n):
		# ⚠️ 用 `floorf` 不用 `floor`：后者返回 Variant，`:=` 会踩
		#    「类型从 Variant 推断」那条警告（本工程警告即错误）。
		var x: float = floorf(fore.position.x + fore.size.x * float(i) / float(n))
		draw_rect(Rect2(x, y0, w, y1 - y0), C_TICK, true)


## 斜切平行四边形：上下边水平，左右边**同向**倾斜 `cut` 像素。
func _cut(r: Rect2, cut: float) -> PackedVector2Array:
	# 斜量不能超过自己宽度的一半，否则四边形自交
	var c := minf(cut, r.size.x * 0.45)
	return PackedVector2Array([
		Vector2(r.position.x + c, r.position.y),
		Vector2(r.end.x, r.position.y),
		Vector2(r.end.x - c, r.end.y),
		Vector2(r.position.x, r.end.y),
	])


## 给凸多边形每个顶点倒圆角（二次贝塞尔采样），返回可直接 `draw_colored_polygon` 的点列。
## 这就是 `ba_progress_bar.cpp` 里 `roundedPolygon()` 的等价物：
## 半径自动收敛到「相邻两边较短者的一半」，避免自交。
func _rounded(pts: PackedVector2Array, radius: float, seg := 6) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var prev: Vector2 = pts[(i + n - 1) % n]
		var cur: Vector2 = pts[i]
		var nxt: Vector2 = pts[(i + 1) % n]
		var v1 := prev - cur
		var v2 := nxt - cur
		var l1 := v1.length()
		var l2 := v2.length()
		if l1 < 0.000001 or l2 < 0.000001:
			continue
		v1 /= l1
		v2 /= l2
		var r := minf(radius, minf(l1, l2) * 0.5)
		var p1 := cur + v1 * r
		var p2 := cur + v2 * r
		out.append(p1)
		for s in range(1, seg):
			var t := float(s) / float(seg)
			var mt := 1.0 - t
			out.append(mt * mt * p1 + 2.0 * mt * t * cur + t * t * p2)
		out.append(p2)
	return out
