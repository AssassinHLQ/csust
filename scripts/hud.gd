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
var _splat_label: Label
var _splat_done := false
var _boss_name: Label
var _boss_bar: ProgressBar

## SogRuntime 的进度阶段 → 给人看的文案
const SPLAT_PHASE := {
	"textures": "解码 SOG 纹理",
	"center": "计算场景中心",
	"decode": "展开高斯点",
	"pack": "打包 GPU 数据",
	"cache": "写展开缓存",
}


func _ready() -> void:
	# 校园泼溅要解码 615 万点（首次约 50 s），给个左上角状态行，别让玩家以为卡死了
	_splat_label = Label.new()
	_splat_label.name = "SplatStatus"
	_splat_label.position = Vector2(18, 16)
	_splat_label.add_theme_font_size_override("font_size", 14)
	_splat_label.add_theme_color_override("font_color", Color(0.86, 0.91, 1.0, 0.92))
	_splat_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_splat_label.add_theme_constant_override("shadow_offset_x", 1)
	_splat_label.add_theme_constant_override("shadow_offset_y", 1)
	_splat_label.visible = false
	add_child(_splat_label)

	_build_boss_bar()


## 顶部居中的 Boss 血条（木桩阶段就有，方便看伤害）
func _build_boss_bar() -> void:
	_boss_name = Label.new()
	_boss_name.name = "BossName"
	_boss_name.text = "霸王龙优香"
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_font_size_override("font_size", 15)
	_boss_name.add_theme_color_override("font_color", Color(1.0, 0.88, 0.75, 0.95))
	_boss_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_boss_name.add_theme_constant_override("shadow_offset_x", 1)
	_boss_name.add_theme_constant_override("shadow_offset_y", 1)
	_boss_name.anchor_left = 0.5
	_boss_name.anchor_right = 0.5
	_boss_name.offset_left = -220.0
	_boss_name.offset_right = 220.0
	_boss_name.offset_top = 18.0
	_boss_name.offset_bottom = 38.0
	_boss_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_name)

	_boss_bar = ProgressBar.new()
	_boss_bar.name = "BossBar"
	_boss_bar.min_value = 0.0
	_boss_bar.max_value = 1.0
	_boss_bar.value = 1.0
	_boss_bar.show_percentage = false
	_boss_bar.anchor_left = 0.5
	_boss_bar.anchor_right = 0.5
	_boss_bar.offset_left = -220.0
	_boss_bar.offset_right = 220.0
	_boss_bar.offset_top = 40.0
	_boss_bar.offset_bottom = 54.0
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.92, 0.42, 0.34)
	fill.set_corner_radius_all(3)
	_boss_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.13, 0.16, 0.85)
	bg.set_corner_radius_all(3)
	_boss_bar.add_theme_stylebox_override("background", bg)
	add_child(_boss_bar)


func bind_boss(boss: Boss) -> void:
	if boss == null:
		return
	boss.health_changed.connect(_on_boss_health)
	_on_boss_health(boss.health, boss.max_health)


func _on_boss_health(current: float, maximum: float) -> void:
	if _boss_bar == null:
		return
	var ratio := 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	_boss_bar.value = ratio
	_boss_name.text = "霸王龙优香　%d / %d" % [int(ceil(current)), int(maximum)]
	# 血量见底时闪红
	var fill := _boss_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		fill.bg_color = Color(1.0, 0.25, 0.2) if ratio < 0.25 else Color(0.92, 0.42, 0.34)


func bind_splat(splat: SplatScene) -> void:
	if splat == null:
		return
	_splat_label.visible = true
	_splat_label.text = "校园泼溅：准备中…"
	splat.progress.connect(_on_splat_progress)
	splat.loaded.connect(_on_splat_loaded)
	splat.failed.connect(_on_splat_failed)


func _on_splat_progress(phase: String, done: int, total: int) -> void:
	if _splat_done:
		return
	var ratio := 0.0 if total <= 0 else clampf(float(done) / float(total), 0.0, 1.0)
	_splat_label.text = "校园泼溅：%s… %d%%（%s / %s 点）" % [
		SPLAT_PHASE.get(phase, phase), int(ratio * 100.0),
		_fmt_int(done), _fmt_int(total)]


func _on_splat_loaded(info: Dictionary) -> void:
	_splat_done = true
	_splat_label.text = "校园泼溅：就绪　%s 点　%.1f s（缓存 %s）" % [
		_fmt_int(int(info.get("point_count", 0))),
		float(info.get("elapsed", 0.0)),
		"命中" if bool(info.get("from_cache", false)) else "首次解码"]
	get_tree().create_timer(8.0).timeout.connect(func() -> void:
		if is_instance_valid(_splat_label):
			_splat_label.visible = false)


func _on_splat_failed(message: String) -> void:
	_splat_done = true
	_splat_label.visible = true
	_splat_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	_splat_label.text = "校园泼溅：失败　%s" % message


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
