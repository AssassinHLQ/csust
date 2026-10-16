extends SceneTree
## 探针：把「行走该拿什么」的几种候选**渲出来对照**（每个角色一张，前后两排）。
##
## 已确认的事实（`_probe_companion_anim.gd` 量的）：
##   · 8 个模型的 5 条 clip 全都在，没有缺；
##   · 道具是**靠骨的 scale 缩到 0 来隐藏**的；
##   · `Cafe_Walk`（咖啡厅漫步）在**每一个**模型里都把武器骨缩到 ≈0
##     （爱丽丝 0.038 / 未花 0.020 / 优香 0.143+0.107 / 诺亚 0.001 /
##       小桃 0.000 / 小绿 0.000 / 柚子 0.020 / 凯伊 0.001）；
##   · `Move_Ing`（战斗移动）里武器骨是 1.0（拿枪）。
##   ⇒「行走不拿枪」是**素材本身的设计**（咖啡厅里当然不拿枪），不是挑错了 clip；
##     小桃小绿手里那个「游戏机」就是她们在咖啡厅姿势里的招牌道具。
##
## 于是问题变成「**改用哪条 clip 走路**」。四种候选各摆一个：
##   A  `Cafe_Walk` 原样（现状：不拿枪）
##   B  `Cafe_Walk` + 把「Move_Ing 显示、Cafe_Walk 藏起来」的骨改回 1.0
##      —— 想保住漫步的腿部动作，同时把枪塞回身上
##   C  `Move_Ing` 降速播（拿枪，步态是战斗里的移动）
##   D  `Normal_Idle`（参照：战斗待机，拿枪）
##
## 排版：**上排正面、下排转 40°**（枪在侧面/背后才看得出来）。
##
## ⚠️ 判「这根骨在 Move_Ing 里是显示的」不能用 `>= 0.9`：未花的武器骨正好是
##    0.900，浮点存下来略小于 0.9，于是整根骨被跳过、B 列看起来和 A 列一模一样
##    （第一版就是这么被骗过去的）。门槛放到 0.5。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_armed_walk_shot.gd -- --splat=off
##
## 输出：…/_arisu_captures/_armedwalk/01_momoi.png 等

const OUT_SUB := "_armedwalk"
const RIG := Vector3(200, 0, 0)
const GAP := 0.95
const ROW2_Z := 1.35
const ROW2_YAW := 40.0
const WHO := [
	{"tag": "01_momoi", "file": "res://models/companions/Momoi.glb"},
	{"tag": "02_midori", "file": "res://models/companions/Midori.glb"},
	{"tag": "03_mika", "file": "res://models/companions/Mika.glb"},
	{"tag": "04_arisu", "file": "res://models/Arisu_ext.glb"},
]

var _cam: Camera3D
var _out: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)
	for n in ["HUD", "SettingsMenu", "DialogueBox"]:
		var c := game.get_node_or_null(n) as CanvasLayer
		if c != null:
			c.visible = false
	for child in game.get_children():
		if child is Node3D and not (child is WorldEnvironment) \
				and not (child is DirectionalLight3D) and not (child is SplatScene):
			(child as Node3D).visible = false

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.near = 0.05
	_cam.far = 500.0
	root.add_child(_cam)
	_cam.make_current()

	for w in WHO:
		await _shot_row(game, String(w["tag"]), String(w["file"]))
	print("\n出图目录：%s" % _out)
	quit(0)


func _shot_row(game: Node, tag: String, file: String) -> void:
	if not ResourceLoader.exists(file):
		print("!! 模型不在：%s" % file)
		return
	var holder := Node3D.new()
	holder.position = RIG
	game.add_child(holder)
	var notes: Array[String] = []
	for row in 2:
		for i in 4:
			var model := (load(file) as PackedScene).instantiate() as Node3D
			model.position = Vector3((float(i) - 1.5) * GAP, 0.0,
				ROW2_Z if row == 1 else 0.0)
			if row == 1:
				model.rotation.y = deg_to_rad(ROW2_YAW)
			holder.add_child(model)
			var ap := _find(model, "AnimationPlayer") as AnimationPlayer
			if ap == null:
				continue
			var label := _apply(ap, i)
			if row == 0:
				notes.append(label)
	await _wait(6)
	_cam.global_position = RIG + Vector3(0.0, 1.30, 5.6)
	_cam.look_at(RIG + Vector3(0.0, 0.92, 0.62), Vector3.UP)
	await _wait(6)
	root.get_texture().get_image().save_png(_out.path_join(tag + ".png"))
	print("[armedwalk] %s（上排正面 / 下排转 %.0f°）：%s"
		% [tag, ROW2_YAW, " | ".join(PackedStringArray(notes))])
	holder.queue_free()
	await _wait(2)


func _apply(ap: AnimationPlayer, i: int) -> String:
	match i:
		0:
			_play(ap, "Cafe_Walk", 1.0)
			return "A Cafe_Walk 原样"
		1:
			var armed := _make_armed_walk(ap)
			var lib := ap.get_animation_library(&"")
			if lib != null:
				lib.add_animation("ArmedWalk", armed)
			_play(ap, "ArmedWalk", 1.0)
			return "B 漫步+补武器%s" % str(armed.get_meta("patched", []))
		2:
			_play(ap, "Move_Ing", 0.46)      # 2.4 / 5.2
			return "C Move_Ing@0.46x"
		_:
			_play(ap, "Normal_Idle", 1.0)
			return "D Normal_Idle"


func _play(ap: AnimationPlayer, clip: String, speed: float) -> void:
	if not ap.has_animation(clip):
		return
	ap.play(clip, -1.0, speed)
	ap.seek(0.33 * ap.get_animation(clip).length, true)
	ap.pause()


## 造一份「拿枪走路」的 Cafe_Walk：
## 把**在 Move_Ing 里是显示的（≥0.5）、在 Cafe_Walk 里被缩到 ≈0（<0.2）**的
## 那些骨的 scale 轨道全改成 1.0。
##
## ⚠️ 判据必须两边一起看：凯伊的 `bone_prop_root` 在**三条 clip 里都是 0.001**
##    （那是个一直藏着的道具），只看 Cafe_Walk 会把它也抠出来、凭空多一个道具。
func _make_armed_walk(ap: AnimationPlayer) -> Animation:
	var copy: Animation = ap.get_animation("Cafe_Walk").duplicate(true)
	var patched: Array[String] = []
	var shown := _visible_bones(ap, "Move_Ing")
	for t in copy.get_track_count():
		if copy.track_get_type(t) != Animation.TYPE_SCALE_3D:
			continue
		var bone := _bone_of(String(copy.track_get_path(t)))
		if bone.is_empty() or not shown.has(bone):
			continue
		if _min_scale(copy, t) >= 0.2:
			continue
		for k in copy.track_get_key_count(t):
			copy.track_set_key_value(t, k, Vector3.ONE)
		patched.append(bone)
	copy.set_meta("patched", patched)
	return copy


func _visible_bones(ap: AnimationPlayer, clip: String) -> Dictionary:
	var out := {}
	if not ap.has_animation(clip):
		return out
	var anim := ap.get_animation(clip)
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_SCALE_3D:
			continue
		var bone := _bone_of(String(anim.track_get_path(t)))
		if bone.is_empty():
			continue
		if _min_scale(anim, t) >= 0.5:
			out[bone] = true
	return out


func _min_scale(anim: Animation, track: int) -> float:
	var lo := INF
	for k in anim.track_get_key_count(track):
		lo = minf(lo, anim.track_get_key_value(track, k).x)
	return lo


## `Aris_Original_Mesh/bone_root/Bip001/Skeleton3D:bone_Railgunup_01` → `bone_Railgunup_01`
func _bone_of(path: String) -> String:
	var i := path.rfind(":")
	return path.substr(i + 1) if i >= 0 else ""


func _find(n: Node, cls: String) -> Node:
	if n == null:
		return null
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
