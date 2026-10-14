extends Node3D
## Arisu 动画学习沙盒 —— 主控脚本
##
## 验证要点（导入后实测）：
##   - glb 里 3 个 skin 被 Godot 合并成 1 个 Skeleton3D（170 骨）
##   - 24 条动画 + 1 条自动生成的 RESET，共 25 条，全部在 AnimationPlayer 的默认库 ""
##   - 10 个 Mouth_* 网格各带 1 个 blend shape（morph_0），口型动画已烘进各条动作
##   - Aris_Original_Halo 无蒙皮（独立静态网格）

const GLB_PATH := "res://models/Arisu.glb"

var _anim_player: AnimationPlayer
var _skeleton: Skeleton3D
var _rig: Node3D
var _spring: SpringArm3D

var _list: ItemList
var _info: Label
var _current: Label
var _panel: PanelContainer
var _play_btn: Button
var _loop_toggle: CheckButton
var _speed_label: Label

var _names: PackedStringArray = []
var _index := 0
var _speed := 1.0
var _yaw := 0.0
var _pitch := 0.0
var _dist := 3.2
var _dragging := false


func _ready() -> void:
	_rig = $CameraRig
	_spring = $CameraRig/SpringArm3D
	_list = $HUD/Panel/Margin/VBox/AnimList
	_info = $HUD/Panel/Margin/VBox/Info
	_current = $HUD/Panel/Margin/VBox/Current
	_panel = $HUD/Panel
	_play_btn = $HUD/Panel/Margin/VBox/Playback/PlayPause
	_loop_toggle = $HUD/Panel/Margin/VBox/Playback/LoopToggle
	_speed_label = $HUD/Panel/Margin/VBox/Playback/SpeedLabel

	_collect_scene_data()

	_list.item_selected.connect(_on_item_selected)
	_play_btn.pressed.connect(_toggle_pause)
	_loop_toggle.toggled.connect(_on_loop_toggled)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_apply_camera()
	if _names.size() > 0:
		_list.select(_index)
		_play(_index)


func _collect_scene_data() -> void:
	_anim_player = _find_first(self, "AnimationPlayer") as AnimationPlayer
	_skeleton = _find_first(self, "Skeleton3D") as Skeleton3D

	var lines: PackedStringArray = []
	lines.append("源文件：models/Arisu.glb")
	lines.append("Skeleton3D 骨骼数：%d" % (_skeleton.get_bone_count() if _skeleton else 0))

	var mesh_count := 0
	var morph_count := 0
	for mi in _find_all(self, "MeshInstance3D"):
		mesh_count += 1
		if mi.mesh and mi.mesh.get_blend_shape_count() > 0:
			morph_count += 1
	lines.append("网格数：%d（其中 %d 个带形变）" % [mesh_count, morph_count])
	lines.append("材质组：18 个（贴图已解包到 models/）")

	if _anim_player == null:
		lines.append("!! 未找到 AnimationPlayer")
		_info.text = "\n".join(lines)
		return

	var lib := _anim_player.get_animation_library("")
	if lib == null:
		lines.append("!! 默认动画库为空")
		_info.text = "\n".join(lines)
		return


	for n in lib.get_animation_list():
		if n == &"RESET":
			continue
		_names.append(String(n))
	_names.sort()

	var stripped := _strip_root_motion(lib)

	lines.append("动画：%d 条（已滤掉自动生成的 RESET）" % _names.size())
	lines.append("插值：源文件含 CUBICSPLINE / LINEAR / STEP 三种")
	if stripped > 0:
		lines.append("已剥离根位移轨 %d 条（否则走路/撤退会跑出画面）" % stripped)
	_info.text = "\n".join(lines)

	for n in _names:
		var anim: Animation = lib.get_animation(n)
		_list.add_item("%s   %.2fs" % [n, anim.length])


func _play(i: int) -> void:
	if _anim_player == null or i < 0 or i >= _names.size():
		return
	_index = i
	var name := _names[i]
	_anim_player.play(name)
	var anim := _anim_player.get_animation(name)
	_current.text = "▶ %s\n时长 %.2f s ｜ 轨道 %d 条" % [name, anim.length, anim.get_track_count()]
	_anim_player.speed_scale = _speed
	if _loop_toggle:
		anim.loop_mode = Animation.LOOP_LINEAR if _loop_toggle.button_pressed else Animation.LOOP_NONE


func _toggle_pause() -> void:
	if _anim_player == null:
		return
	if _anim_player.is_playing():
		_anim_player.pause()
		_play_btn.text = "继续"
	else:
		_anim_player.play()
		_play_btn.text = "暂停"


func _on_loop_toggled(on: bool) -> void:
	if _anim_player == null:
		return
	var anim := _anim_player.get_animation(_anim_player.current_animation)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR if on else Animation.LOOP_NONE


func _on_item_selected(i: int) -> void:
	_play(i)
	_play_btn.text = "暂停"


func _step_anim(dir: int) -> void:
	var n := _names.size()
	if n == 0:
		return
	var next := wrapi(_index + dir, 0, n)
	_list.select(next)
	_list.ensure_current_is_visible()
	_play(next)
	_play_btn.text = "暂停"


func _set_speed(v: float) -> void:
	_speed = clampf(v, 0.1, 3.0)
	if _anim_player:
		_anim_player.speed_scale = _speed
	_speed_label.text = "%.2fx" % _speed


func _apply_camera() -> void:
	_rig.rotation.y = _yaw
	_spring.rotation.x = _pitch
	_spring.spring_length = _dist


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP:
				_step_anim(-1)
			KEY_DOWN:
				_step_anim(1)
			KEY_SPACE:
				_toggle_pause()
			KEY_R:
				_yaw = 0.0
				_pitch = 0.0
				_dist = 3.2
				_apply_camera()
			KEY_L:
				_loop_toggle.button_pressed = not _loop_toggle.button_pressed
			KEY_H:
				_panel.visible = not _panel.visible
			KEY_COMMA:
				_set_speed(_speed - 0.1)
			KEY_PERIOD:
				_set_speed(_speed + 0.1)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if _list.get_global_rect().has_point(event.position):
				_step_anim(-1)
			else:
				_dist = maxf(_dist - 0.25, 0.8)
				_apply_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if _list.get_global_rect().has_point(event.position):
				_step_anim(1)
			else:
				_dist = minf(_dist + 0.25, 12.0)
				_apply_camera()

	if event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch - event.relative.y * 0.005, -1.2, 1.2)
		_apply_camera()


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_A):
		_yaw += delta * 1.6
		_apply_camera()
	elif Input.is_key_pressed(KEY_D):
		_yaw -= delta * 1.6
		_apply_camera()
	if Input.is_key_pressed(KEY_W):
		_dist = maxf(_dist - delta * 2.0, 0.8)
		_apply_camera()
	elif Input.is_key_pressed(KEY_S):
		_dist = minf(_dist + delta * 2.0, 12.0)
		_apply_camera()


# --- 工具 ---

## 剥离根位移轨：源动作里 Aris_Original_Body / Bip001 带世界位移，
## 直接播放会让角色走出画面。这里把这两条轨的位移关键帧清零，
## 保留旋转与缩放。想用根位移（Root Motion）做位移驱动时，把本函数禁用即可。
const ROOT_MOTION_NODES := ["Bip001", "Aris_Original_Body"]

func _strip_root_motion(lib: AnimationLibrary) -> int:
	var stripped := 0
	for name in lib.get_animation_list():
		var anim: Animation = lib.get_animation(name)
		for t in anim.get_track_count():
			if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
				continue
			var np := anim.track_get_path(t)
			if not ROOT_MOTION_NODES.has(String(np.get_concatenated_names()).get_slice("/", -1)):
				continue
			var first: Vector3 = anim.position_track_interpolate(t, 0.0)
			for k in anim.track_get_key_count(t):
				anim.track_set_key_value(t, k, first)
			stripped += 1
	return stripped


func _find_first(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find_first(c, cls)
		if r:
			return r
	return null


func _find_all(n: Node, cls: String) -> Array:
	var out: Array = []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_all(c, cls))
	return out
