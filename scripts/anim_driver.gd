class_name AnimDriver
extends Node
## 动画驱动：直接用 AnimationPlayer 播动作，自己做状态切换与混合。
##
## 为什么不用 AnimationTree：
##   实测（Godot 4.7.1 + 这份 glTF 导入的骨架）AnimationTree 整体不驱动骨骼——
##   AnimationNodeBlendSpace1D、AnimationNodeBlend2、AnimationNodeBlendTree、
##   StateMachine 全都逐帧截图 0 像素差异；而同一个 AnimationPlayer 直接 play()
##   完全正常。为了不让玩法卡死，这里绕开 AnimationTree，用 AnimationPlayer 自己做。
##
## 状态：
##   LOCOMOTION  按速度在 Normal_Idle / Cafe_Walk / Move_Ing 之间切
##   FIRE        播一次 Normal_Attack_Ing，播完回 LOCOMOTION
##   RELOAD      播一次 Normal_Reload，播完回 LOCOMOTION
##
## ⚠️ **`Cafe_Walk` 用还是不用，来回翻过一次** —— 这条有历史，改动前务必看完下面
##    `CYCLE_SPEED` 那段注释：中途有一阵子「一律用战斗动画」（为了让大家走路也拿枪），
##    后来又按用户要求**改回真正的走路动作**（跑步姿势放慢 0.46 倍实在太别扭）。
##
## 标注速度：每个循环动画在某个移动速度下脚步最贴合，用它算播放速率，
## 避免「脚下打滑」。

enum State { LOCOMOTION, FIRE, RELOAD }

## 循环动画的标称速度（米/秒）——按这个速度播时脚步与位移最匹配
##
## ── 历史上翻过的两次 ──
## ① **用户报**：「为什么小桃小绿行走动作是拿游戏机的，还有好多角色行走也没有拿枪了」
##    → 查出 `Cafe_*` 是**咖啡厅模式**的动画，那一套里角色**不拿武器**：
##    素材是靠**把武器骨的 scale 缩到 ≈0** 来藏枪的。实测 8 个模型**全都如此** ——
##    `Cafe_Walk` 里的武器骨 scale.x 最小是
##      爱丽丝 0.038 / 未花 0.020 / 优香 0.143 + 0.107 / 诺亚 0.001 /
##      小桃 0.000 / 小绿 0.000 / 柚子 0.020 / 凯伊 0.001
##    而同一根骨在 `Move_Ing`（战斗移动）里是 **1.0**（拿枪）。
##    所以「走路不拿枪」**不是挑错了 clip，是素材本身如此**；小桃/小绿在咖啡厅姿势里
##    手里那个「游戏机」就是她们的招牌道具。
##    → 当时的修法：全用 `Move_Ing`，走 / 跑只靠 `speed_scale` 区分。
##      也试过「复制 `Cafe_Walk` 再把武器骨 scale 改回 1.0」，但枪**是挂在身侧的**、
##      两只手还在胸前捧着游戏机（那件道具不在武器骨下，改 scale 抠不掉），比原来更怪。
##      四种候选的对照图见 `scripts/_probe_armed_walk_shot.gd`。
##
## ② **用户再报**：「走路动作还是改回来吧」—— 全用 `Move_Ing` 的代价是
##    「走路 = 跑步姿势放慢到 0.46 倍」，上身前倾是跑步那一下，看着别扭。
##    于是**改回** `Cafe_Walk`，走 / 跑按 `WALK_THRESHOLD` 切。
##    **已知代价**：走路时武器被素材缩没了（见 ①）。要再翻回来，改这一段 + `_update_locomotion()`。
const CYCLE_SPEED := {
	"Normal_Idle": 0.0,
	"Cafe_Walk": 1.6,
	"Move_Ing": 5.2,
}
## 低于这个速度用 `Cafe_Walk`（漫步姿势），高于用 `Move_Ing`（战斗姿势）。
## ⚠️ 必须**大于** `player.gd` 的 `SPEED_WALK`（2.4），否则「走路」会去播跑步动画。
##    同伴用同一个阈值，它们的 `walk_speed = 2.2` 也仍在下面 ✓（2.4 → 2.8）。
const WALK_THRESHOLD := 2.8
## 低于这个速度就播待机
const IDLE_SPEED := 0.15
## 播放速率的上下限。
##
## ⚠️ 下限从 0.35 放到 **0.25**：蹲行（1.3 m/s）现在也走 `Move_Ing`（标称 5.2），
##    1.3 / 5.2 = 0.25。卡在 0.35 会让脚比地面快 40%（打滑），
##    而「步幅吻合」比「步频好看」重要 —— 播放速率是**按实际位移补脚步**的。
const SPEED_SCALE_MIN := 0.25
const SPEED_SCALE_MAX := 2.0
const FADE := 0.18               # 交叉淡入时间

## 一次性动作的播放倍速。
## Normal_Attack_Ing 原长 2.67 s，而枪的连发间隔是 0.075 s——
## 原速播的话一次射击动作要 2.67 秒才收招，手感「卡卡的」。
## 加速到 2.5 倍后约 1.07 s 收招，跟打空一梭 2.25 s 的节奏对得上。
const FIRE_SPEED := 2.5
const RELOAD_SPEED := 1.9

## 一次性动作（开火 / 换弹）**只叠上半身** —— 见下面 `_setup_upper_layer()` 那段。
##
## ⚠️ 为什么必须叠、不能整身切（用户报）：
##    「开枪跑打时为什么角色脚不动，需要静止开枪不动，但是跑步开枪脚还是要动」
##    原来 `request_fire()` 是把**整个** `AnimationPlayer` 切到 `Normal_Attack_Ing`，
##    而这条动作是**全骨架**的（实测爱丽丝 228 条轨道、其中**下半身 48 条**；
##    小桃 46 条、优香 26 条）—— 于是开火期间腿也被定格，人在地上滑。
##
## ⚠️ 而且**光滤下半身还不够**（用户报「跑打确实腿动了但是感觉身体倾斜了好多」）：
##    开火动作是**站桩**的，它的躯干（脊椎 / 胸）会把跑步的前倾一下掰成站桩——
##    实测差 **65°**。所以叠加层分两层：移动时再滤掉躯干，站定时保留。
##    细节见 `TRUNK_KEYWORDS` 与 `_setup_upper_layer()`。
##

## 「下半身」的判据：名字里带这些词的骨，其**开火轨道会被滤掉**。
## 裙骨（skirt）也算：腿在跑、裙子却按站桩姿势摆，一眼假。
const LOWER_KEYWORDS := ["thigh", "calf", "foot", "toe", "leg", "pelvis", "hip", "root", "skirt"]

## 「躯干」的判据：**移动时**的开火叠加层要再滤掉这些骨。
##
## ⚠️ 为什么必须滤（用户报「跑打确实腿动了但是感觉身体倾斜了好多」）：
##    `Normal_Attack_Ing` 是**站桩开火**的动作，它的脊椎 / 胸是按「站着」摆的；
##    而 `Move_Ing` 的躯干是**大幅前倾**的。实测 `Bip001 Spine1` 的「上」轴
##    （`_probe_fire_lean.gd` + `_probe_run_fire_pose_shot.gd`）：
##      · 只跑（`Move_Ing`）        (0.62, −0.76, −0.20)
##      · 跑 + 开火（只滤下半身）    (0.97, **+0.25**, −0.03)   ← **差 65°**
##    也就是上半身会在开火那一瞬间从「跑步的前倾」弹成「站桩的坐姿」。
##    滤掉这两根之后，跑打开火的躯干与「只跑」**逐位相同**（0.0°）。
##
## ⚠️ 但**站定开火要留着**：那是上一轮明确要的「静止开枪不动」，素材里那套站桩
##    姿势比「待机躯干 + 开火手臂」好看。所以叠**两层**，按当时速度选一层
##    （`_setup_upper_layer()` / `active_upper_layer()`）。
##
## ⚠️ 后来又加上了 `neck` / `head`（用户报「Shift 冲刺跑打时身体还是后倾」）：
##    只滤 spine / chest 时，**脖子和头仍然来自站桩开火姿势**（抬头、略后仰），
##    躯干明明和只跑一样前倾，可整条剪影看着就是往后仰 —— 头是最显眼的那一段。
##    把颈 / 头也滤掉之后，跑打开火的 `Spine1` 与 `Neck` 上轴和「只跑」**逐位相同**：
##      · 只跑            Spine1 (0.60, −0.65, −0.47)  Neck (0.56, −0.46, −0.69)
##      · 只滤 spine/chest Spine1 (0.60, −0.65, −0.47)  Neck (0.52, −0.43, −0.74)
##      · 再滤 neck/head   Spine1 (0.60, −0.65, −0.47)  Neck (0.56, −0.46, −0.69) ← 等于只跑
##    （四种候选的对照渲染见 `_probe_run_fire_pose_shot.gd`。）
const TRUNK_KEYWORDS := ["spine", "chest", "neck", "head"]

## 「手臂」的判据。移动层把这些也滤掉 —— 见 `ARM_FREEZE_WHY`。
const ARM_KEYWORDS := ["clavicle", "shoulder", "upperarm", "forearm",
	"deltoid", "twist", "arm", "hand", "finger"]

## 「武器」的判据。移动层也滤 —— 枪骨是**挂在右手指下**的，手臂已经由 `Move_Ing`
## 提供，若还让站桩层把武器骨再转一遍，枪就会相对新的手姿**再拧一个大角度**
## （实测 `bone_magazine` 140.8°、`bone_Railgunup_part_04` 93.1°），
## 那一大块白枪斜在身后，正是「后仰」剪影最显眼的那一笔。
const WEAPON_KEYWORDS := ["weapon", "railgun", "magazine", "muzzle", "point"]

## ⚠️ 为什么移动层连手臂都滤（用户第二轮报「跑打还是后仰」「还是没变呢」）：
##
##   前两轮修的是「躯干被站桩层掰走」（滤 spine/chest/neck/head + 中途换层），
##   数据上跑打开火的躯干已经和只跑一致（0.902 vs 0.899）。但用户看**剪影**：
##   跑打时枪被双臂端到胸前端平、两肘外张，从背后 / 头顶看，那条「横着一大块
##   枪 + 张开的肘」就是「后仰」的观感来源 —— 变的是轮廓，不是脊椎。
##
##   所以移动层改成「**上半身整体跟跑姿**」：只剩头发 / 眼 / 领子 / 领带 / 挂饰 /
##   武器这几簇骨随开火动（枪照抖、头发照飘），肩、臂、手全部由 `Move_Ing` 提供。
##   判据从「躯干角度」升级成「**全骨架逐骨最大夹角**」：改后跑打开火与只跑
##   只差武器那几根（见 `_probe_upper_freeze.gd`）。
const ARM_FREEZE_WHY := true

var state := State.LOCOMOTION
## 基础层：整体动画（`Normal_Idle` / `Move_Ing`），一直播着，包括开火期间。
var player: AnimationPlayer
## 叠加层（静止）：完整上半身的开火 / 换弹，含脊椎 / 胸 —— 站桩开火用这层。
## `process_priority` 比基础层大 ⇒ 后写、赢；下半身只有基础层写，所以腿照样跑。
var upper: AnimationPlayer
## 叠加层（移动）：在静止层的基础上**再滤掉躯干**，跑打开火用这层。
var upper_move: AnimationPlayer
var skeleton: Skeleton3D

var _speed := 0.0
var _aiming := false
var _auto_return := false
## 这一发正在播「单条跑打动作」（整身，自带腿）—— 此时 `_update_locomotion()` 不许插手
var _runfire_playing := false
## 滤掉的下半身轨道条数（自检用）
var lower_tracks_removed := 0
## 移动层额外滤掉的躯干轨道条数（自检用）
var trunk_tracks_removed := 0
## 这一发中途因为速度变化而换过几次层（自检用：跑打起手一次、停步一次）
var migrations := 0
## 移动层额外滤掉的**手臂 + 武器**轨道条数（自检用）
var arm_tracks_removed := 0
## `PoseFix.fix_run_lean()` 的报告（自检用：改了哪些骨、多少帧）
var lean_fix := {}
## `PoseFix.fix_head_roll()`：跑步时头往左偏的那 13.9°，掰正的报告
var roll_fix := {}
## `PoseFix.freeze_eyelids()`：停用眨眼（删掉眼睑骨轨道的报告）
var blink_fix := {}
## `FaceFix.separate_face_layers()`：脸皮/眼睛共面推开的报告
var face_fix := {}
## 「单独一条跑打开火动作」的并入报告（`AnimExtra.merge_glb()`）
var runfire := {}

## ── 跑打开火：**一条**动作，不再叠两层 ──
## 用户 2026-10-17：「跑打只能这样子了，单独做一个跑步加开火的动画，而不是叠加动画」。
## 生成脚本 `..\_blender_arisu\seed_runfire.py`（Blender 里把 `Move_Ing` 的下半身 +
## `Normal_Attack_Ing` 的手臂/枪拼成 64 帧 = 4 个跑步周期，正好等于一次开火的 2.667 s）。
## 它导出的 `models/RunFire.glb` **只有骨架 + 这一条动作**（0 网格），启动时并进动作库。
##
## ⚠️ 只有**主角**要在 `player.tscn` 里填 `extra_glb` —— 同伴也是 `AnimDriver`，
##    留空就不并，否则七只同伴各自把 1 MB 的 glb 读一遍、还会刷一堆「骨找不到」。
@export var extra_glb := ""
@export var extra_clip := "RunFire_Ing"


func _ready() -> void:
	player = get_node_or_null(animation_player_path) as AnimationPlayer
	skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	# 两个 NodePath 都留空时，先在**自己所在的模型子树**里找，再退回整棵树。
	# 同伴（companion.gd 运行时 new 出来的 AnimDriver）走的就是这条路：
	# 三只 GLB 的内部节点名互不相同，写死路径没法共用。
	if player == null or skeleton == null:
		var scope: Node = get_parent()
		if player == null:
			player = _find_player(scope)
			if player == null and get_tree():
				player = _find_player(get_tree().root)
		if skeleton == null:
			skeleton = _find_first(scope, "Skeleton3D") as Skeleton3D
	if player == null:
		push_error("[AnimDriver] 找不到 AnimationPlayer")
		return

	_configure_library()
	# 跑步前倾（用户报「跑步动画还是有点倾斜」）——数据级修正，见 `pose_fix.gd`。
	# 放在 `_configure_library()` 之后、开播之前：改的是动作关键帧本身，
	# 所以循环播放的每一帧都是修过的，不存在「被 AnimationPlayer 覆盖」。
	lean_fix = PoseFix.fix_run_lean(skeleton, player)
	# 跑步时头往左偏：绕标定轴补 −18.6°，实测 roll 从 −18.0° 压到 +0.26°（见 pose_fix.gd）
	roll_fix = PoseFix.fix_head_roll(skeleton, player)
	# 眨眼：整条停掉。
	# 2026-10-17 用户：「眼睛那里停止算了，不要眨眼的动画了」。
	# 把 `eye_L/R_1`、`eye_L/R_2` 上的轨道从**每个动作**里删掉 → 没有轨道就没人写它们，
	# 骨永远停在 rest（= 全开），进游戏之后不会再闭眼。
	# 上一版是 `fix_eyelid_sync()`（左右镜像），留着了，`_probe_face_shot.gd` 还在用它做 A/B。
	blink_fix = PoseFix.freeze_eyelids(skeleton, player)
	if int(blink_fix.get("tracks", 0)) > 0:
		print("[AnimDriver] 停用眨眼：删掉 %d 条眼睑轨道，涉及 %d 个动作" % [
			int(blink_fix["tracks"]), (blink_fix["clips"] as Array).size()])
	# 脸皮 / 眼睛两层共面 → z-fighting（用户报「双眼皮打架」）。把上面那层沿法线推开 0.14 mm。
	# 只推**不带形态键**的网格（嘴那 10 块必须留着形态键，见 `face_fix.gd` 文件头）。
	face_fix = FaceFix.separate_face_layers(get_parent())
	if int(face_fix.get("surfaces", 0)) > 0:
		print("[AnimDriver] 脸部层错开：%d 个 surface / %d 个顶点（跳过 %d 个带形态键的网格）" % [
			int(face_fix["surfaces"]), int(face_fix["verts"]), int(face_fix.get("skipped", 0))])
	_check_face_morphs()
	_setup_upper_layer()
	# 跑打开火：把 Blender 拼好的**单条**动作并进动作库（见 `extra_glb` 上面那段）。
	# 只并进基础层，两个叠加层不复制它 —— 它本来就是整身动作。
	if not extra_glb.is_empty():
		runfire = AnimExtra.merge_glb(player, extra_glb, extra_clip, skeleton)
		if bool(runfire.get("ok", false)):
			print("[AnimDriver] 并入跑打动作「%s」：%.3f s，%d 条轨道（前缀 %s → %s，骨架 %s/%d 骨）" % [
				extra_clip, float(runfire["seconds"]), int(runfire["tracks"]),
				str(runfire["head_from"]), str(runfire["head_to"]),
				str(runfire.get("sk_name", "")), int(runfire.get("sk_bones", 0))])
			var miss: Array = runfire["missing"]
			if not miss.is_empty():
				push_warning("[AnimDriver] 跑打动作有 %d 根骨在这具骨架上找不到（%s…）" % [
					miss.size(), str(miss.slice(0, 5))])
			# 这条动作是用**未修正的** Move_Ing 在 Blender 里拼的，得补上同样的前倾修正
			var lean := PoseFix.fix_extra_run_clip(skeleton, player, extra_clip)
			if bool(lean.get("applied", false)):
				print("[AnimDriver] 跑打动作补前倾修正：%s 共 %d 帧" % [
					str(lean["bones"]), int(lean["keys"])])
		else:
			push_warning("[AnimDriver] 跑打动作没并进来：%s" % str(runfire.get("error", "")))
	if player.has_animation("Normal_Idle"):
		player.play("Normal_Idle", -1.0, 1.0)
	player.animation_finished.connect(_on_finished)
	for l in [upper, upper_move]:
		if l != null:
			l.animation_finished.connect(_on_finished)


## 检查「嘴巴还在不在」。
##
## 爱丽丝有 **10 块** `Mouth_*` 网格，每块带一个 `target_0` 形态键，靠它把自己
## 整体挪走 0.6 m 藏进看不见的地方；同一时刻只有一块的权重是 0（露在脸上）。
## 谁要是重建了这些网格的 `ArrayMesh`，**blend shape 会一起没掉** → 10 张嘴
## 全贴回脸上（用户报的「多个嘴巴网格重叠」）。这条断言就是为了让这种回归
## **当场出声**，而不是等用户截图来报。
func _check_face_morphs() -> void:
	var mouths := 0
	var broken: Array[String] = []
	var stack: Array[Node] = [get_parent()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and String(n.name).begins_with("Mouth_"):
			var mi := n as MeshInstance3D
			mouths += 1
			if mi.mesh == null or mi.mesh.get_blend_shape_count() == 0:
				broken.append(String(n.name))
		for c in n.get_children():
			stack.append(c)
	if mouths == 0:
		return      # 同伴模型没有嘴部网格，正常
	if broken.is_empty():
		print("[AnimDriver] 嘴部形态键完好：%d 块 Mouth_* 都能靠形变藏起来" % mouths)
	else:
		push_error("[AnimDriver] %d / %d 块 Mouth_* **丢了形态键**：%s"
			% [broken.size(), mouths, ", ".join(broken)]
			+ " —— 这些嘴会同时贴在脸上（原因见 face_fix.gd 文件头）")


## 搭「上半身叠加层」：**两层**，把开火 / 换弹各复制一份、滤掉不该写的轨道。
##   · `UpperBody`     只滤下半身 —— **站桩开火**用它，素材里的站桩姿势完整保留
##   · `UpperBodyMove` 再滤躯干   —— **跑打开火**用它，躯干保持 `Move_Ing` 的前倾
##
## ── 为什么这么绕（三条都是量出来的）──
##   1. **`AnimationTree` 在这份骨架上根本不驱动骨骼**（§1.7：逐帧截图 0 像素差异），
##      所以官方那条「用 Blend2 + 骨骼遮罩」的路走不通；
##   2. `AnimationPlayer` 没有**逐轨道遮罩**，但**两个播放器写同一具骨架时，后写的赢** ——
##      于是「下半身只有基础层写、上半身叠加层写」正好拼出想要的叠加；
##   3. 实测开火动作是**全骨架**的（爱丽丝 228/228 条轨道，下半身 48 条；且
##      「移动有、攻击没有」的骨 **0 根**），所以**必须先滤掉下半身**，否则腿还是会被它按住。
##
## `process_priority` 是关键：基础层 0、两层都 1 ⇒ 两层都后处理 ⇒ 上半身以后写的为准
## （同一时刻只有一层在播，见 `active_upper_layer()`）。
func _setup_upper_layer() -> void:
	var host := player.get_parent()
	if host == null:
		return
	upper = _make_overlay(host, "UpperBody", [])
	# 移动层：躯干 + **手臂 + 武器**都滤掉（只剩头发/眼/领子/挂饰），见 `ARM_FREEZE_WHY`
	upper_move = _make_overlay(host, "UpperBodyMove",
		TRUNK_KEYWORDS + ARM_KEYWORDS + WEAPON_KEYWORDS)


## 造一层叠加层：轨道路径是相对 `root_node` 的字符串，两层必须指向**同一个**根节点。
func _make_overlay(host: Node, layer_name: String, extra: Array) -> AnimationPlayer:
	var ov := AnimationPlayer.new()
	ov.name = layer_name
	ov.root_node = player.root_node
	ov.process_priority = player.process_priority + 1
	# 库先装好（还没进树也能装），**不要**去 `get_animation_library("")` ——
	# 新建的 AnimationPlayer 没有默认库，那一句会返回 null 并报 ERROR。
	var lib := AnimationLibrary.new()
	for clip in ["Normal_Attack_Ing", "Normal_Reload"]:
		if not player.has_animation(clip):
			continue
		var a: Animation = player.get_animation(clip).duplicate(true)
		var low_n := 0
		var trunk_n := 0
		var arm_n := 0
		for t in range(a.get_track_count() - 1, -1, -1):
			var bone := _bone_of(String(a.track_get_path(t)))
			var is_low := _in_keywords(bone, LOWER_KEYWORDS)
			if is_low or _in_keywords(bone, extra):
				if is_low:
					low_n += 1
				elif _in_keywords(bone, TRUNK_KEYWORDS):
					trunk_n += 1
				else:
					arm_n += 1
				a.remove_track(t)
		# 两层滤掉的下半身是同一批，只统计一次；躯干 / 手臂只有移动层滤
		if extra.is_empty():
			lower_tracks_removed += low_n
		else:
			trunk_tracks_removed += trunk_n
			arm_tracks_removed += arm_n
		lib.add_animation(clip, a)
	ov.add_animation_library(&"", lib)
	# ⚠️ **必须延后一帧加进树**：`_ready()` 期间父节点还在装自己的孩子，
	#    直接 `add_child()` 会失败（"Parent node is busy setting up children"）——
	#    而失败是**静默**的：不在树里 ⇒ 一帧都不更新 ⇒ 上半身根本没叠上去、
	#    而且 `animation_finished` 永远不来（状态卡在 Fire，再也开不了下一枪）。
	#    本喵第一版就是这样：结构断言全绿，只有「右手在不在动」那条红了才露馅。
	host.add_child.call_deferred(ov)
	return ov


## 这一发该用哪一层：**在动**用「滤掉躯干」那层（躯干保持跑步的前倾），
## **站着**用完整上半身那层（素材里的站桩开火姿势）。
func active_upper_layer() -> AnimationPlayer:
	if _speed > IDLE_SPEED and upper_move != null:
		return upper_move
	return upper


## 把**正在播的那一发**挪到「当前速度该用的那一层」，位置和倍速都接着走。
##
## 为什么需要它：`_play_once()` 只在开火那一帧选一次层，选完这一发就定死了。
## 而 `_speed` 每帧都在变 —— 「站着扣扳机、立刻冲刺」是最常见的跑打起手，
## 恰恰是选错层的那一种：躯干会整段锁在站桩姿势（后仰）。
##
## 换层是**无缝**的：同一条 clip、同一个 `current_animation_position`、同一个
## `speed_scale`，`play(..., 0.0)` 淡入时间给 0，播放器不会露出中间帧。
func _migrate_upper_layer() -> void:
	if state == State.LOCOMOTION or skeleton == null:
		return
	var want := active_upper_layer()
	if want == null or not want.is_inside_tree():
		return
	# 找出「现在真在播这一发」的那一层（两层同一时刻只有一层在播）
	var cur: AnimationPlayer = null
	for l in [upper, upper_move]:
		if l != null and l != want and l.is_playing():
			cur = l
			break
	if cur == null:
		return
	var clip := String(cur.current_animation)
	if clip.is_empty() or not want.has_animation(clip):
		return
	var pos := cur.current_animation_position
	want.speed_scale = cur.speed_scale
	cur.stop()                       # `stop()` 不会发 `animation_finished`，不会误触收招
	want.play(clip, 0.0, 1.0)
	want.seek(pos, true)
	migrations += 1


func _in_keywords(bone: String, kws: Array) -> bool:
	if bone.is_empty():
		return false
	var low := bone.to_lower()
	for k in kws:
		if low.contains(String(k)):
			return true
	return false


## `Aris_Original_Mesh/bone_root/Bip001/Skeleton3D:bone_Railgunup_01` → `bone_Railgunup_01`
func _bone_of(path: String) -> String:
	var i := path.rfind(":")
	return path.substr(i + 1) if i >= 0 else ""


func _is_lower_bone(bone: String) -> bool:
	return _in_keywords(bone, LOWER_KEYWORDS)


func _configure_library() -> void:
	# 只给**用到的**两条循环动画设循环；`Cafe_Walk` 也在模型里，但本工程不播它
	# （理由见 CYCLE_SPEED 上面那段），所以不用管它。
	for n in ["Normal_Idle", "Move_Ing"]:
		if player.has_animation(n):
			player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in ["Normal_Attack_Ing", "Normal_Reload"]:
		if player.has_animation(n):
			player.get_animation(n).loop_mode = Animation.LOOP_NONE


# --- 接口 ---

func set_locomotion(speed: float, _on_floor: bool, _vertical_speed: float) -> void:
	_speed = speed
	if player == null:
		return
	# ⚠️ 速度一变，**正在连射的那一发也要换层**（见 `_migrate_upper_layer()`）。
	#    原来层是「开火那一瞬间」按 `_speed` 选死的：站着扣扳机 → 选 `upper`
	#    （完整站桩上半身，含脊椎/颈/头）→ 这一发剩下的 1.07 s 里你就算按 Shift
	#    跑起来，躯干仍然被站桩姿势锁着。实测「站着开火 → 第 10 帧起跑 6.8」：
	#      跑起来 +15/+30/+45 帧  躯干 up = 0.970 / 0.958 / 0.964
	#      而「跑起来再开火」对照组  躯干 up = 0.887 / 0.901 / 0.890
	#    前者就是用户报的「跑打身体后仰」—— 枪响时人还在站桩层里。
	_migrate_upper_layer()
	# 整身跑打动作在播：腿是它自带的，只跟着速度调倍速，别让 `_update_locomotion()`
	# 把动作切回 `Move_Ing`（那样这一枪就只剩「站着开火」了）。
	if _runfire_playing:
		if _speed <= IDLE_SPEED:
			_return_from_runfire()   # 停下来了，交回普通移动
		else:
			player.speed_scale = clampf(_speed / CYCLE_SPEED.get("Move_Ing", 5.2),
				SPEED_SCALE_MIN, SPEED_SCALE_MAX)
		return
	# ⚠️ **开火 / 换弹期间也必须继续更新基础层** —— 这正是「跑打时脚不动」的根因：
	#    原来这里有一句 `or state != State.LOCOMOTION` 就提前返回，于是开火那一秒
	#    基础层被冻住，腿停了。现在上半身在叠加层、下半身在基础层，两层互不干扰。
	#    只有**兜底路径**（没搭成叠加层）要保留旧的互斥，否则 `_update_locomotion()`
	#    会立刻把正在播的一次性动作顶掉。
	if upper == null and state != State.LOCOMOTION:
		return
	_update_locomotion()


func set_aiming(on: bool) -> void:
	_aiming = on


func is_aiming() -> bool:
	return _aiming


func request_fire() -> void:
	# 跑着开火 + 有「单条跑打动作」→ 整身播那一条（腿是它自带的，不再叠两层）
	if state == State.LOCOMOTION and has_runfire() and _speed > IDLE_SPEED:
		_start_runfire()
		return
	_play_once("Normal_Attack_Ing", State.FIRE)


## 有没有「单条跑打动作」（`extra_glb` 并进来的那条）
func has_runfire() -> bool:
	return player != null and not extra_clip.is_empty() and player.has_animation(extra_clip)


## 一个跑步周期多长（秒）。整身动作里腿也是这个节奏，切进切出时按它对齐相位。
func runfire_cycle() -> float:
	if player != null and player.has_animation("Move_Ing"):
		return player.get_animation("Move_Ing").length
	return 0.6667


## 切进「单条跑打动作」。
## ⚠️ 相位要**接着当前 `Move_Ing` 走**：从第 0 帧硬起会让脚在原地闪一下。
##    动作是 4 个跑步周期拼的，所以 `seek(当前位置 % 周期)` 正好落在同一相位上。
func _start_runfire() -> void:
	if player == null:
		return
	state = State.FIRE
	_auto_return = true
	_runfire_playing = true
	stop_upper_layer()               # 这条动作是整身的，叠加层必须让开
	var cyc := runfire_cycle()
	var pos := 0.0
	if player.current_animation == "Move_Ing":
		pos = player.current_animation_position
	player.play(extra_clip, 0.06, 1.0)
	player.seek(fmod(pos, cyc), true)
	player.speed_scale = clampf(_speed / CYCLE_SPEED.get("Move_Ing", 5.2),
		SPEED_SCALE_MIN, SPEED_SCALE_MAX)


## 从「单条跑打动作」回到移动：同样按相位接回 `Move_Ing`
func _return_from_runfire() -> void:
	var cyc := runfire_cycle()
	var pos := 0.0
	if player != null:
		pos = player.current_animation_position
	_runfire_playing = false
	state = State.LOCOMOTION
	_auto_return = false
	_update_locomotion()
	if player != null and player.current_animation == "Move_Ing":
		player.seek(fmod(pos, cyc), true)


func request_reload() -> void:
	_play_once("Normal_Reload", State.RELOAD)


func current_state_name() -> String:
	match state:
		State.FIRE:
			return "Fire"
		State.RELOAD:
			return "Reload"
		_:
			return "Locomotion"


func current_clip() -> String:
	return player.current_animation if player else ""


func blend_amount() -> float:
	return clampf(_speed / CYCLE_SPEED["Move_Ing"], 0.0, 1.0)


func fire_clip_length() -> float:
	if player and player.has_animation("Normal_Attack_Ing"):
		return player.get_animation("Normal_Attack_Ing").length
	return 0.5


func reload_clip_length() -> float:
	if player and player.has_animation("Normal_Reload"):
		return player.get_animation("Normal_Reload").length
	return 1.5


# --- 内部 ---

func _update_locomotion() -> void:
	# 慢速（走 / 蹲行）用 `Cafe_Walk` 的**漫步姿势**，快速（跑 / 冲）用 `Move_Ing` 的战斗姿势。
	# ⚠️ 这是「改回来」的一条：中间有一阵子全用 `Move_Ing`（为了让大家走路也拿枪），
	#    但那样「走路是跑步的姿势放慢 0.46 倍」，用户看着别扭，要求换回真正的走路动作。
	#    代价回到老样子：`Cafe_Walk` 里武器骨被缩到 ≈0，**走路时看不到枪**（素材如此）。
	var want := "Normal_Idle"
	if _speed >= WALK_THRESHOLD:
		want = "Move_Ing"
	elif _speed > IDLE_SPEED:
		want = "Cafe_Walk"

	if player.current_animation != want:
		player.play(want, FADE, 1.0)

	# 播放速率按实际速度 / 该动画的标称速度算 —— 这一条是**防脚底打滑**的：
	# `Move_Ing` 的标称是 5.2 m/s，跑 5.2 就播 1.0 倍；
	# `Cafe_Walk` 标称 1.6 m/s，走 2.4 就播 1.5 倍，一个循环的步幅仍然对得上地面。
	var nominal: float = CYCLE_SPEED.get(want, 0.0)
	if nominal > 0.01:
		player.speed_scale = clampf(_speed / nominal, SPEED_SCALE_MIN, SPEED_SCALE_MAX)
	else:
		player.speed_scale = 1.0


func _play_once(anim: String, new_state: State) -> void:
	if player == null or not player.has_animation(anim):
		return
	# 一次性动作播到一半就不打断，避免动作被腰斩
	if state != State.LOCOMOTION:
		return
	state = new_state
	_auto_return = true
	var speed := RELOAD_SPEED if new_state == State.RELOAD else FIRE_SPEED
	var layer := active_upper_layer()
	if layer != null and layer.is_inside_tree() and layer.has_animation(anim):
		# **主路径**：只在叠加层播，而且只有上半身 —— 下半身还是基础层的移动动画
		layer.speed_scale = speed
		layer.play(anim, 0.08, 1.0)
		return
	# 兜底（叠加层还没进树 / 模型里没这条动作）：老办法，整体切过去
	player.speed_scale = speed
	player.play(anim, 0.08, 1.0)


func _on_finished(anim_name: StringName) -> void:
	# ⚠️ 两个播放器都接了这个信号。循环动画每绕一圈也会发 `animation_finished`，
	#    所以靠 `_auto_return` 这个闸门区分「一次性动作播完了」和「循环动画又转了一圈」。
	if not _auto_return:
		return
	if state == State.FIRE and String(anim_name) == extra_clip:
		_return_from_runfire()
		return
	if state == State.FIRE and anim_name == "Normal_Attack_Ing":
		_return_to_locomotion()
	elif state == State.RELOAD and anim_name == "Normal_Reload":
		_return_to_locomotion()


func _return_to_locomotion() -> void:
	state = State.LOCOMOTION
	_auto_return = false
	# 停掉叠加层：它的骨头立刻会被基础层（每帧写全部骨）覆盖回去，不会留残影
	stop_upper_layer()
	_update_locomotion()


## 停叠加层（自检也会用；不在树里时 `stop()` 会报一串 ERROR，所以在这里挡一道）
## 两层都停：调用的时机（收招 / 自检复位）分不清刚才用的哪一层。
func stop_upper_layer() -> void:
	for l in [upper, upper_move]:
		if l != null and l.is_inside_tree():
			l.stop()


## 复位到「什么都没在播」的状态（自检用）。`_runfire_playing` 不清的话，
## `set_locomotion()` 会一直以为这一发还没结束、拒绝切回 `Move_Ing`。
func reset_state() -> void:
	stop_upper_layer()
	_runfire_playing = false
	_auto_return = false
	state = State.LOCOMOTION


# --- 自检用的读数 ---------------------------------------------------------------

func has_upper_layer() -> bool:
	return upper != null and upper_move != null


## 当前这一发实际在演哪一层（站定 / 移动由 `active_upper_layer()` 决定）。
func upper_clip() -> String:
	var l := active_upper_layer()
	return l.current_animation if l != null else ""


func upper_track_count(clip := "Normal_Attack_Ing", moving := false) -> int:
	var l := upper_move if moving else upper
	if l == null or not l.has_animation(clip):
		return -1
	return l.get_animation(clip).get_track_count()


func upper_lower_track_count(clip := "Normal_Attack_Ing", moving := false) -> int:
	var l := upper_move if moving else upper
	if l == null or not l.has_animation(clip):
		return -1
	var a := l.get_animation(clip)
	var n := 0
	for t in a.get_track_count():
		if _is_lower_bone(_bone_of(String(a.track_get_path(t)))):
			n += 1
	return n


## 这一层里还剩多少条**躯干**轨道（移动层应为 0，静止层应 > 0）。
func upper_trunk_track_count(clip := "Normal_Attack_Ing", moving := false) -> int:
	var l := upper_move if moving else upper
	if l == null or not l.has_animation(clip):
		return -1
	var a := l.get_animation(clip)
	var n := 0
	for t in a.get_track_count():
		if _in_keywords(_bone_of(String(a.track_get_path(t))), TRUNK_KEYWORDS):
			n += 1
	return n


## 一根骨在**骨架局部空间**里的位置（不含角色自身的位移/旋转）——
## 「脚在不在动」要量这个，量世界坐标会把「人往前跑」也算进去。
func bone_local_origin(bone: String) -> Vector3:
	if skeleton == null:
		return Vector3.ZERO
	var i := skeleton.find_bone(bone)
	if i < 0:
		return Vector3.ZERO
	return skeleton.get_bone_global_pose(i).origin


## 一根骨在**骨架局部空间**里的「上」轴 —— 「躯干有没有被开火动作掰走」量这个
## （§1.20：跑打开火时 `Bip001 Spine1` 的上轴必须与「只跑」一致）。
func bone_up_axis(bone: String) -> Vector3:
	if skeleton == null:
		return Vector3.UP
	var i := skeleton.find_bone(bone)
	if i < 0:
		return Vector3.UP
	return skeleton.get_bone_global_pose(i).basis.y.normalized()


func _find_first(n: Node, cls: String) -> Node:
	if n == null:
		return null
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find_first(c, cls)
		if r:
			return r
	return null


## 找**基础层**的播放器。
##
## ⚠️ 不能再用「第一个 `AnimationPlayer`」：§1.18 / §1.20 之后每个模型里有**三个** ——
##    基础层 + 两层叠加（`UpperBody` 静止 / `UpperBodyMove` 移动，它们只有开火 / 换弹、
##    没有 `Normal_Idle`）。按「有 `Normal_Idle`」来认，就不怕遍历顺序（也不怕将来再多一层）。
func _find_player(root_node: Node) -> AnimationPlayer:
	if root_node == null:
		return null
	var a := root_node as AnimationPlayer
	if a != null and a.has_animation("Normal_Idle"):
		return a
	for c in root_node.get_children():
		var r := _find_player(c)
		if r != null:
			return r
	return null


@export var skeleton_path: NodePath
@export var animation_player_path: NodePath
