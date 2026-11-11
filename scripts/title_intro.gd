extends Node
## 开场标题卡（2026-11-11 用户：「现在 做开始动画,开始动画怎么做合适呢」）。
##
## ── 用户选的口径 ──
##   · 先只做**标题卡**（不做镜头俯冲）；
##   · **任意键 / 点击可跳过**。
##
## ── 为什么是「标题卡」而不是真·过场动画 ──
## 主场景就是 `game.tscn`（`project.godot` 的 `run/main_scene`），一启动直接进第三人称，
## 中间没有任何可以挂演出的地方。要加真过场就得再开一个场景、改 `project.godot` ——
## 而这份工程的老规矩是**不动 `project.godot`**（autoload 都不加）。
## 所以这里做成**游戏场景内的一层 CanvasLayer**：零新场景、零配置改动。
##
## ── 顺带白赚一件事：它同时是**载入遮罩** ──
## 画室 609 的泼溅冷缓存要解 50 s（缓存命中也有 2.1 s），这段时间原来玩家看到的是
## 黑屏或者半张代理网格。现在标题卡正好盖在上面 —— 而且会**等世界真的就绪**才淡出
## （`world_ready` 这个 Callable 就是干这个的），所以不会演完了露出半成品。
##
##   ① 黑底 + 标题牌从左侧滑入（带回弹）
##   ② 底下那条 `#FFE433` 亮线从左往右刷出
##   ③ 副标题淡入
##   ④ 停 `HOLD` 秒（这期间如果世界还没就绪就一直等，最多 `SETTLE_MAX` 秒）
##   ⑤ 整体上滑淡出 → 黑幕淡出 → 自我释放
##
## ── 零贴图 ──
## 牌子的斜切、圆角、描边全部走 `UiSkin.title_tag_style()`（程序化 BA 皮肤），
## 不引用任何图片 —— 和 §13.12.1 同一条规矩（不碰游戏原始素材）。

## ── 三种"正片"，按优先级自动挑 ──────────────────────────────────────────
## 用户 2026-11-11：「这个不好看,我还是自己做cg吧」——所以这块的定位改了：
## **本喵画的那张只是兜底**，正片留给使用者自己的 CG。
##
## 优先级（先存在先赢）：
##   ① `assets/cg/opening.ogv`        —— 真·CG（Ogg Theora）。
##      ⚠️ Godot 4 的 `VideoStreamPlayer` **只认 .ogv**，mp4/webm 一律播不了
##         （引擎限制）。使用者的工具链多半导出 mp4，那就用
##         `_tools/mp4_to_ogv.sh` 转一下 —— **不用他手工处理**。
##   ② `assets/cg/opening/0001.png…` —— PNG 帧序列（`frame_0001.png` 这种也行）。
##      没有编码坑，时长和音画同步都好控；代价是文件多（`.gitignore` 掉即可）。
##   ③ 都没有 → 播本喵那张程序化标题卡（就是现在这版）。
##
## 三者共用同一套骨架：**盖住加载**（黑幕一直盖到 `world_ready()` 为真）、
## **按键只跳动画不跳加载**、播完淡出。换正片不该把这些重新踩一遍。
const CG_VIDEO := "res://assets/cg/opening.ogv"
const CG_FRAMES_DIR := "res://assets/cg/opening"

const UiSkin := preload("res://scripts/ui_skin.gd")

## 标题文字。改名字只改这里。
const TITLE_TEXT := "爱丽丝梦游长理"
const SUB_TEXT := "Blue Archive 二次创作 · 个人非商业作品"

const TAG_FONT := 66
const SUB_FONT := 21
## 动画时长（秒）
const TAG_IN := 0.55
const RULE_IN := 0.40
const SUB_IN := 0.38
## PNG 帧序列的播放帧率。24 = 电影感，30 = 常见录屏。
const FRAME_FPS := 24.0
## 全部就位后**停多久**再走（够看清标题，又不至于让人等）
const HOLD := 1.15
const OUT := 0.42
## 等世界就绪的上限（秒）。
##
## ⚠️ 2026-11-11 用户：「开始动画最好覆盖在609高斯泼溅加载上面,遮住我们加载的卡顿」。
##    这条就是那个需求的开关 —— **它必须比最慢的一次加载还长**。
##    实测：画室609 冷缓存在干净机器上要解 **50 s**（缓存命中 2.1 s）。
##    原来写的 12 s 是个错误的数字：12 秒一到标题卡自己撤了，刚好把最卡的那段露出去。
##    现在放到 `180 s`（= 纯粹的死等保护：万一 `loading` 因为 bug 永远不落 false，
##    也不至于把玩家钉死在标题画面上一辈子）。正常情况根本走不到这个上限。
const SETTLE_MAX := 180.0
## 超过这么久还没就绪就显示「载入中…」。用户要的是「遮住卡顿」，
## 不是「让你以为死机了」—— 一行小字说明还在干活，等起来才不慌。
const LOADING_HINT_AFTER := 1.2

var _layer: CanvasLayer
var _root: Control
var _black: ColorRect
var _tag: PanelContainer
var _tag_label: Label
var _rule: ColorRect
var _sub: Label
var _hint: Label
## 亮线的**完整宽度**。⚠️ 必须单独存：`_layout_ready()` 末尾为了做「从 0 刷出来」
## 把它清零了，之后再想拿"应该是多宽"就只剩 0。
var _rule_full_w := 0.0
## 牌子的**终点 x**（`_layout_ready()` 里存，跳过着陆时直接用它落位）
var _tag_x_final := 0.0
## 「载入中…」那条 Tween（只建一次；重复建会让 alpha 来回被打断）
var _hint_tw: Tween = null
## 跳过标记：任意键 / 点击都会把它置 true，各段 `await` 立刻收尾
var _skipped := false
var _playing := false


## 播一遍。`world_ready` 返回 true 表示「画面后面那个世界已经可以看了」
## （`game.gd` 传的是它自己的 `_splats_ready`）。
## 调用方 `await` 它，返回时画面已经干净，可以接着演剧情了。
##
## 自动挑正片（见 `CG_VIDEO` 那段）：有 CG 就播 CG，没有就播本喵那张标题卡。
## 三条路共用同一套「盖住加载 + 按键只跳动画」骨架。
func play(world_ready: Callable) -> void:
	if _playing:
		return
	_playing = true
	_black_only()          # 先上黑幕：不管播什么，第一帧都不能露出世界
	var kind := _pick_kind()
	match kind:
		"video":
			await _play_video(world_ready)
		"frames":
			await _play_frames(world_ready)
		_:
			await _play_procedural(world_ready)
	print("[TitleIntro] 正片 = %s" % kind)
	await _fade_black_out()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_playing = false


## 现在会播哪种（自检 / 日志用）
func _pick_kind() -> String:
	if ResourceLoader.exists(CG_VIDEO):
		return "video"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(CG_FRAMES_DIR)):
		return "frames"
	return "procedural"


# ── 骨架：黑幕 / 顶层容器 ────────────────────────────────────────────────

## 只把「层 + 全黑底」搭出来。三条路都从这儿起步。
##
## ⚠️ 本节点自己也要 `ALWAYS`：`create_tween()` 挂在自己身上，父链一暂停
##    Tween 就冻住。开场之后紧接着播的对话框会把 `get_tree().paused` 置 true。
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


# ── ① 真·CG：.ogv ──────────────────────────────────────────────────────

## Godot 4 只认 Ogg Theora。`VideoStreamPlayer` 自己带音轨、自己播完发 `finished`。
## 这里只管：全屏铺开、播完 → 等世界就绪 → 交给统一的淡出。
func _play_video(world_ready: Callable) -> void:
	var stream := load(CG_VIDEO) as VideoStream
	if stream == null:
		push_warning("[TitleIntro] %s 加载失败，退回标题卡" % CG_VIDEO)
		await _play_procedural(world_ready)
		return
	var vp := VideoStreamPlayer.new()
	vp.name = "Cg"
	vp.stream = stream
	# 铺满整个视口、保持比例（CG 一般是 16:9，视口可能不是）
	vp.expand = true
	vp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vp)
	# 黑幕还在上面：CG 从黑里淡出来比"啪"地出现舒服
	vp.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(vp, "modulate:a", 1.0, 0.35)
	await tw.finished
	vp.play()
	# 等播完（或按键跳过）。
	#
	# ⚠️ 必须有**超时兜底**：视频解码卡住（编码不被支持、文件截断、headless 下
	#    根本没有渲染/音频后端推不动时钟）时 `is_playing()` 会一直是 true，
	#    玩家就永远卡在开场、连游戏都进不去 —— 比"CG 不好看"严重得多。
	#    上限 = 视频时长 + 5 s；拿不到时长就退回 60 s。
	var length := vp.get_stream_length()
	var cap := (length + 5.0) if length > 0.0 else 60.0
	var el := 0.0
	while vp.is_playing() and not _skipped and el < cap:
		await get_tree().process_frame
		el += _delta()
	if el >= cap and vp.is_playing():
		push_warning("[TitleIntro] CG 播了 %.1f s 还没结束（时长 %s）—— 强制收尾"
			% [el, str(length)])
	vp.stop()
	print("[TitleIntro] CG 播到 %.2f / %s s（%s）" % [
		vp.stream_position, str(length), "看完" if not _skipped else "按键跳过"])
	await _hold_until_ready(world_ready)


# ── ② PNG 帧序列 ────────────────────────────────────────────────────────

## 目录里按文件名排序取所有 `*.png`，用 `FRAME_FPS` 逐帧推。
## 比视频稳：没有编码/容器问题，帧数就是时长。
func _play_frames(world_ready: Callable) -> void:
	var frames := _list_frames()
	if frames.is_empty():
		push_warning("[TitleIntro] %s 里没有 png，退回标题卡" % CG_FRAMES_DIR)
		await _play_procedural(world_ready)
		return
	var tex := TextureRect.new()
	tex.name = "Cg"
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(tex)
	tex.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(tex, "modulate:a", 1.0, 0.3)
	await fade.finished

	print("[TitleIntro] 帧序列 %d 帧 @ %.1f fps" % [frames.size(), FRAME_FPS])
	var acc := 0.0
	var i := 0
	while i < frames.size() and not _skipped:
		tex.texture = load(frames[i])
		i += 1
		var target := float(i) / FRAME_FPS
		while acc < target and not _skipped:
			await get_tree().process_frame
			acc += _delta()
	# `_skipped`（按键）跳到这里时，把最后一帧摆上 —— 不然后面是半截画面
	if i > 0 and i < frames.size():
		tex.texture = load(frames[frames.size() - 1])
	await _hold_until_ready(world_ready)


## 目录里的 png，按文件名排序（`0001.png` / `frame_0001.png` 都行）
func _list_frames() -> Array:
	var out: Array = []
	var abs_dir := ProjectSettings.globalize_path(CG_FRAMES_DIR)
	var d := DirAccess.open(abs_dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() == "png":
			out.append(CG_FRAMES_DIR.path_join(f))
	out.sort()
	return out


# ── ③ 兜底：程序化标题卡（本喵画的那版）─────────────────────────────────

func _play_procedural(world_ready: Callable) -> void:
	_build()
	await _layout_ready()
	await _animate_in()
	await _hold_until_ready(world_ready)
	await _animate_out()


# ── 搭建 ────────────────────────────────────────────────────────────────

func _build() -> void:
	var skin: Dictionary = UiSkin.pick()
	var font := UiSkin.ui_font()

	# ⚠️ 层和黑底**已经在 `_black_only()` 里建好了**（三条路共用），这里只搭内容。
	#    早先这段是重复建的，改成"CG 优先"之后会把黑幕建两层、还盖在 CG 上面。

	# 标题牌：白底斜切（`title_tag_style` 给的就是这个），字号大，字用深藏蓝
	_tag = PanelContainer.new()
	_tag.name = "Tag"
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag_sb := UiSkin.title_tag_style(skin)
	if not (tag_sb is StyleBoxEmpty):
		_tag.add_theme_stylebox_override("panel", tag_sb)
	_root.add_child(_tag)
	_tag_label = Label.new()
	_tag_label.text = TITLE_TEXT
	if font != null:
		_tag_label.add_theme_font_override("font", font)
	_tag_label.add_theme_font_size_override("font_size", TAG_FONT)
	_tag_label.add_theme_color_override("font_color", skin["text"])
	_tag.add_child(_tag_label)

	# 亮黄底划线
	_rule = ColorRect.new()
	_rule.name = "Rule"
	_rule.color = skin["yellow"]
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rule)

	# 副标题：黑底上要浅色（`story_subtext` 是给深藏蓝对话框的，这里自己取）
	_sub = Label.new()
	_sub.name = "Sub"
	_sub.text = SUB_TEXT
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font != null:
		_sub.add_theme_font_override("font", font)
	_sub.add_theme_font_size_override("font_size", SUB_FONT)
	_sub.add_theme_color_override("font_color", Color(0.66, 0.80, 0.92, 0.95))
	_root.add_child(_sub)

	# 「载入中…」：只在等太久时才显形
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "载入中…"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font != null:
		_hint.add_theme_font_override("font", font)
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.68, 0.80, 0.85))
	_hint.modulate.a = 0.0
	_root.add_child(_hint)


## 等一帧让 `PanelContainer` 算出自身最小尺寸，再按视口宽高算位置。
func _layout_ready() -> void:
	await get_tree().process_frame
	var vp := Vector2(_root.size)
	if vp.x < 32.0 or vp.y < 32.0:
		vp = Vector2(1600.0, 900.0)
	var tag_min := _tag.get_combined_minimum_size()
	# 牌子往两边各留 26 px：字贴边会把斜切吃掉
	tag_min.x += 52.0
	tag_min.y = maxf(tag_min.y, UiSkin.TITLE_TAG_HEIGHT)
	_tag.size = tag_min
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	# 整组稍微偏上一点：视觉重心比几何中心高才不显得往下坠
	var block_y := cy - tag_min.y * 0.5 - 26.0
	_tag_x_final = cx - tag_min.x * 0.5
	_tag.position = Vector2(_tag_x_final, block_y)

	var rule_w := tag_min.x * 0.92
	_rule_full_w = rule_w
	_rule.size = Vector2(rule_w, UiSkin.TITLE_RULE_HEIGHT)
	_rule.position = Vector2(cx - rule_w * 0.5, block_y + tag_min.y + 14.0)

	_sub.size = Vector2(vp.x, SUB_FONT * 2.0)
	_sub.position = Vector2(0.0, _rule.position.y + UiSkin.TITLE_RULE_HEIGHT + 20.0)

	_hint.size = Vector2(vp.x, 22.0)
	_hint.position = Vector2(0.0, _sub.position.y + SUB_FONT * 2.0 + 18.0)

	# 起始态：牌子在左侧外面、全透明；亮线宽度 0
	_tag.position.x -= 74.0
	_tag.modulate.a = 0.0
	_rule.size.x = 0.0
	_rule.modulate.a = 0.0
	_sub.modulate.a = 0.0


# ── 动画 ────────────────────────────────────────────────────────────────

func _animate_in() -> void:
	# ⚠️ 跳过语义（2026-11-11）：按键**只**让入场动画立刻落位，
	#    不缩短下面的「等世界就绪」。所以这里每个阶段都要问一次 `_skipped`，
	#    跳过了就把三样都摆到终点（`_snap_in()`），不能直接 return 了事 ——
	#    那样亮线和副标题会永远停在 alpha 0，画面上只剩一个光秃秃的牌子。
	if _skipped:
		_snap_in()
		return
	var tw := create_tween()
	tw.set_parallel(true)
	# 牌子：向左外缓动回来，带回弹（BA 那种"啪"地落位）
	tw.tween_property(_tag, "position:x", _tag_x_final, TAG_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_tag, "modulate:a", 1.0, TAG_IN * 0.6)
	await tw.finished
	if _skipped:
		_snap_in()
		return

	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(_rule, "size:x", _rule_full_w, RULE_IN) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_property(_rule, "modulate:a", 1.0, RULE_IN * 0.5)
	# 副标题晚一点，读起来是「标题 → 线 → 说明」
	tw2.tween_property(_sub, "modulate:a", 1.0, SUB_IN).set_delay(0.18)
	await tw2.finished
	if _skipped:
		_snap_in()


## 把「入场完成」那一帧的状态直接摆上去（跳过用）。
func _snap_in() -> void:
	_tag.position.x = _tag_x_final
	_tag.modulate.a = 1.0
	_rule.size.x = _rule_full_w
	_rule.modulate.a = 1.0
	_sub.modulate.a = 1.0


## 停一会儿；**世界没就绪就一直等**。
##
## ⚠️ 这里**故意不认 `_skipped`**（2026-11-11 用户：「遮住我们加载的卡顿」）。
##    「跳过」能跳过的是**入场动画**（牌子能不能立刻落位），
##    但**不能跳过加载** —— 逃过这一步，玩家看到的就是半张代理网格 + 泼溅一块块
##    蹦出来，正是他要本喵遮掉的东西。
##    所以按键只会让牌子瞬间就位，黑幕继续盖着，直到 `world_ready()` 为真。
func _hold_until_ready(world_ready: Callable) -> void:
	var el := 0.0
	while el < HOLD:
		await get_tree().process_frame
		el += _delta()
	var waited := 0.0
	while not bool(world_ready.call()) and waited < SETTLE_MAX:
		if waited >= LOADING_HINT_AFTER and _hint.modulate.a < 0.99 and _hint_tw == null:
			_hint_tw = create_tween()
			_hint_tw.tween_property(_hint, "modulate:a", 1.0, 0.35)
		await get_tree().process_frame
		waited += _delta()
	if waited > 0.0:
		var ok := bool(world_ready.call())
		print("[TitleIntro] 等世界就绪 %.1f s（%s）" % [
			waited, "就绪" if ok else "**超时**，照常淡出（这会把加载过程露出来）"])
		if not ok:
			push_warning("[TitleIntro] 等满了 %.0f s 还没就绪 —— 要么加载真的坏了，"
				% SETTLE_MAX + "要么该调大 `SETTLE_MAX`")
	# 再多给一帧「真的画完」，免得淡出时露出的还是没上屏的旧帧。
	#
	# ⚠️ 2026-11-11 栽过：`--headless` 下 `RenderingServer.frame_post_draw`
	#    **永远不会触发**（没有渲染后端），自检当场卡死（实测 10 分钟没动静，
	#    `_verify_mag.gd` 早就栽过同一个坑）。所以 headless 直接跳过这一句。
	#    正常游戏一定有渲染后端，这一句照旧生效。
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


## 只撤**程序化标题卡**那几样字（黑幕由 `_fade_black_out()` 统一收）。
## 「先撤字、再放开画面」的次序由调用方 `play()` 保证（先 `_animate_out()` 再淡黑幕）。
func _animate_out() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	for n in [_tag, _rule, _sub, _hint]:
		var c := n as Control
		if c == null:
			continue
		tw.tween_property(c, "position:y", c.position.y - 26.0, OUT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "modulate:a", 0.0, OUT * 0.9)
	await tw.finished


## 跳过：任意键 / 鼠标键 / 触摸都算。**每一段都查 `_skipped`**，所以按下之后
## 最迟在下一个 `await` 收尾就跳完了。
func _input(event: InputEvent) -> void:
	if not _playing or _skipped:
		return
	var key := event as InputEventKey
	if key != null and key.pressed:
		_skipped = true
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		_skipped = true


func _delta() -> float:
	return get_process_delta_time()


## 自检用：一帧都不用等，直接问「这层是不是已经撤掉了」
func is_playing() -> bool:
	return _playing


## 自检用：这一遍播的是哪种正片（"video" / "frames" / "procedural"）
func kind() -> String:
	return _pick_kind()


## 三条路共用的收尾：黑幕淡出。
## ⚠️ 程序化标题卡那版在 `_animate_out()` 里已经把字撤干净了，这里只剩黑幕；
##    CG 那两版是**画面还在、直接连黑幕一起淡**（CG 一般自己会淡到黑，不额外处理）。
func _fade_black_out() -> void:
	if _black == null or not is_instance_valid(_black):
		return
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 0.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
