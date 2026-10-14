extends CanvasLayer
## HUD：弹药、状态、速度、换弹进度条、准星随瞄准/移动扩张。

@onready var crosshair: Control = $Crosshair
@onready var dot: ColorRect = $Crosshair/Dot
@onready var t: ColorRect = $Crosshair/T
@onready var b: ColorRect = $Crosshair/B
@onready var l: ColorRect = $Crosshair/L
@onready var r: ColorRect = $Crosshair/R
@onready var ammo: Label = $Panel/Margin/VBox/Ammo
@onready var state: Label = $Panel/Margin/VBox/State
@onready var speed: Label = $Panel/Margin/VBox/Speed
@onready var reload_bar: ProgressBar = $Panel/Margin/VBox/Reload

var _player: Player
var _weapon: Weapon
var _spread := 8.0
## 左上角泼溅状态行：**一份场地一行**，每行 {label: Label, title: String, done: bool}
var _splat_rows: Array[Dictionary] = []
## 顶部 Boss 血条组：一个 Boss 一行，每行 {name: Label, bar: ProgressBar, title: String}
var _boss_rows: Array[Dictionary] = []

## SogRuntime 的进度阶段 → 给人看的文案
const SPLAT_PHASE := {
	"textures": "解码 SOG 纹理",
	"center": "计算场景中心",
	"decode": "展开高斯点",
	"pack": "打包 GPU 数据",
	"cache": "写展开缓存",
}


func _ready() -> void:
	# 泼溅状态行不在这里建：见 bind_splats()，要按场上实际有几份场地来排行数。
	# （校园 615 万点首次要解码约 50 s，不给状态行玩家会以为卡死了。）
	# Boss 血条同理：见 bind_bosses()，要按场上实际有几位来排行数。
	# ⚠️ 这里不能只有注释 —— GDScript 要求每个函数体至少有一条语句。
	pass


## 顶部居中的 Boss 血条组。**一个 Boss 一行**，自上而下按索引排。
## 加同伴那一轮场上变成两位 Boss（霸王龙优香 / 飞猪优香），所以从单条改成一组。
const BOSS_ROW_HEIGHT := 38.0
const BOSS_BAR_WIDTH := 440.0


func bind_bosses(bosses: Array) -> void:
	_boss_rows.clear()
	var index := 0
	for b in bosses:
		var boss := b as Boss
		if boss == null:
			continue
		_add_boss_row(index, boss.display_name)
		boss.health_changed.connect(_on_boss_health.bind(index))
		_on_boss_health(boss.health, boss.max_health, index)
		index += 1


## 只接一位 Boss 的旧写法（保留，自检里还在用）
func bind_boss(boss: Boss) -> void:
	bind_bosses([boss])


func _add_boss_row(index: int, title: String) -> void:
	var top := 18.0 + float(index) * BOSS_ROW_HEIGHT

	var label := Label.new()
	label.name = "BossName%d" % index
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.75, 0.95))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.offset_left = -BOSS_BAR_WIDTH * 0.5
	label.offset_right = BOSS_BAR_WIDTH * 0.5
	label.offset_top = top
	label.offset_bottom = top + 20.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	var bar := ProgressBar.new()
	bar.name = "BossBar%d" % index
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_left = -BOSS_BAR_WIDTH * 0.5
	bar.offset_right = BOSS_BAR_WIDTH * 0.5
	bar.offset_top = top + 22.0
	bar.offset_bottom = top + 36.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.13, 0.16, 0.85)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.92, 0.42, 0.34)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)

	_boss_rows.append({"name": label, "bar": bar, "title": title})


func _on_boss_health(current: float, maximum: float, index: int) -> void:
	if index < 0 or index >= _boss_rows.size():
		return
	var row: Dictionary = _boss_rows[index]
	var bar: ProgressBar = row["bar"]
	var label: Label = row["name"]
	var ratio := 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	bar.value = ratio
	label.text = "%s　%d / %d" % [row["title"], int(ceil(current)), int(maximum)]
	# 血量见底时闪红
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		fill.bg_color = Color(1.0, 0.25, 0.2) if ratio < 0.25 else Color(0.92, 0.42, 0.34)


func bind_splat(splat: SplatScene) -> void:
	if splat == null:
		return
	bind_splats([splat])


## 顶部左上的泼溅状态组。**一份场地一行**，自上而下按传入顺序排。
## 加「画室609」那一轮场上变成两份泼溅（校园 615 万 + 画室 277 万），所以从
## 单行改成一组 —— 两份同时解码时能分清是哪一份在等、哪一份已经就绪。
const SPLAT_ROW_HEIGHT := 20.0


func bind_splats(splats: Array) -> void:
	# 先把上一次的标签和连线都撤掉。
	# ⚠️ 不撤会报 "Signal 'progress' is already connected to given callable"：
	#    `.bind(0)` 两次得到的 Callable 是**相等**的，Godot 认为是同一个回调。
	#    （自检里先绑一份、再绑两份就会撞上；玩家侧虽然只绑一次，但接口得能重入。）
	for row in _splat_rows:
		var old: Label = row["label"]
		if is_instance_valid(old):
			old.queue_free()
		# ⚠️ 这里必须用 Variant 接：场地已经被 free 掉时，`var x: SplatScene = row["splat"]`
		#    这句本身就会报 "Trying to assign invalid previously freed instance"。
		var old_splat: Variant = row["splat"]
		if is_instance_valid(old_splat):
			_unbind_splat(old_splat as SplatScene, int(row["index"]))
	_splat_rows.clear()
	var index := 0
	for item in splats:
		var splat := item as SplatScene
		if splat == null:
			continue
		var label := Label.new()
		label.name = "SplatStatus%d" % index
		label.position = Vector2(18, 16 + index * SPLAT_ROW_HEIGHT)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.86, 0.91, 1.0, 0.92))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.visible = false
		add_child(label)
		_splat_rows.append({
			"label": label,
			"splat": splat,
			"index": index,
			"title": "%s泼溅" % splat.display_name,
			"done": false,
		})
		# ⚠️ 信号参数是 (phase, done, total) / (info) / (message)，bind 是**追加**
		#    在最后，所以下面三个 handler 的**行号参数写在形参表末尾**。
		splat.progress.connect(_on_splat_progress.bind(index))
		splat.loaded.connect(_on_splat_loaded.bind(index))
		splat.failed.connect(_on_splat_failed.bind(index))
		index += 1


func _unbind_splat(splat: SplatScene, index: int) -> void:
	var pairs := [
		[splat.progress, _on_splat_progress.bind(index)],
		[splat.loaded, _on_splat_loaded.bind(index)],
		[splat.failed, _on_splat_failed.bind(index)],
	]
	for pair in pairs:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


## 取第 index 行；越界（场地被 --venue 跳过时信号不会来，但保险）返回空字典
func _splat_row(index: int) -> Dictionary:
	if index < 0 or index >= _splat_rows.size():
		return {}
	return _splat_rows[index]


func _on_splat_progress(phase: String, done: int, total: int, index: int) -> void:
	var row := _splat_row(index)
	if row.is_empty() or bool(row["done"]):
		return
	var label: Label = row["label"]
	if not is_instance_valid(label):
		return
	label.visible = true
	var ratio := 0.0 if total <= 0 else clampf(float(done) / float(total), 0.0, 1.0)
	label.text = "%s：%s… %d%%（%s / %s 点）" % [
		row["title"], SPLAT_PHASE.get(phase, phase), int(ratio * 100.0),
		_fmt_int(done), _fmt_int(total)]


func _on_splat_loaded(info: Dictionary, index: int) -> void:
	var row := _splat_row(index)
	if row.is_empty():
		return
	row["done"] = true
	var label: Label = row["label"]
	if not is_instance_valid(label):
		return
	label.visible = true
	label.text = "%s：就绪　%s 点　%.1f s（缓存 %s）" % [
		row["title"],
		_fmt_int(int(info.get("point_count", 0))),
		float(info.get("elapsed", 0.0)),
		"命中" if bool(info.get("from_cache", false)) else "首次解码"]
	# ⚠️ 闭包只捕获**行号**，不要捕获 Label 节点：重绑时旧标签会被 queue_free，
	#    8 秒后定时器触发会报 "Lambda capture at index 0 was freed"。
	#    （正常玩只绑一次，但自检会重绑，日志要干净。）
	get_tree().create_timer(8.0).timeout.connect(func() -> void:
		var row2 := _splat_row(index)
		if row2.is_empty():
			return
		var l: Label = row2["label"]
		if is_instance_valid(l):
			l.visible = false)


func _on_splat_failed(message: String, index: int) -> void:
	var row := _splat_row(index)
	if row.is_empty():
		return
	row["done"] = true
	var label: Label = row["label"]
	if not is_instance_valid(label):
		return
	label.visible = true
	label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	label.text = "%s：失败　%s" % [row["title"], message]


static func _fmt_int(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


func bind(player: Player, weapon: Weapon) -> void:
	_player = player
	_weapon = weapon
	weapon.ammo_changed.connect(_on_ammo)
	weapon.reload_started.connect(func() -> void: reload_bar.visible = true)
	weapon.reload_finished.connect(func() -> void: reload_bar.visible = false)
	_on_ammo(weapon.current_ammo, weapon.magazine_size)
	reload_bar.visible = false


func _on_ammo(current: int, maximum: int) -> void:
	ammo.text = "%d / %d" % [current, maximum]
	ammo.modulate = Color(1, 0.45, 0.4) if current == 0 else Color.WHITE


func _process(_delta: float) -> void:
	if _player == null:
		return

	# 准星随瞄准收拢、随移动扩散
	var moving := Vector2(_player.velocity.x, _player.velocity.z).length()
	var target := 3.0 if _player.aiming else 7.5 + moving * 1.6
	_spread = lerpf(_spread, target, 0.18)
	var s := _spread
	t.offset_top = -s - 5.0
	t.offset_bottom = -s
	b.offset_top = s
	b.offset_bottom = s + 5.0
	l.offset_left = -s - 5.0
	l.offset_right = -s
	r.offset_left = s
	r.offset_right = s + 5.0
	dot.modulate = Color(1, 1, 1, 0.95 if _player.aiming else 0.8)

	var moving_state := ""
	if _player.crouching:
		moving_state = "蹲行"
	elif _player.aiming:
		moving_state = "瞄准"
	elif _player.sprinting:
		moving_state = "跑动"
	else:
		moving_state = "腰射"
	if _weapon and _weapon.is_reloading():
		moving_state = "换弹中"
	elif _weapon and _weapon.is_turning():
		moving_state = "转向中"
	state.text = moving_state
	speed.text = "%.1f m/s" % moving

	if _weapon:
		reload_bar.value = _weapon.reload_progress()
