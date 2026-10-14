# 长沙理工：2067（Godot 4.7 学习沙盒）

> 工程与窗口标题：`长沙理工：2067`（`project.godot` 的 `config/name`）。
> 下面是这个学习沙盒里做过的事。

> **A third-person shooter sandbox in Godot 4.7** — over-the-shoulder camera, turn-to-aim
> firing gate, 60-round magazine with auto-reload, a hand-rolled animation driver, and a
> **3D Gaussian Splatting campus** (floating platform above a sunken scan).
> Code and docs are **MIT**; the character model and the splat data are *not* included.

一个用 Godot 4.7 手搓的**第三人称射击原型**：越肩相机、开火转身门控、60 发弹匣连发、
动画驱动、以及**高斯泼溅（3DGS）校园场景**（悬浮记忆平台 + 下沉校园）。

**许可：除模型与美术素材外，本仓库全部以 [MIT](LICENSE) 授权。** 详见
[THIRD_PARTY.md](THIRD_PARTY.md)。

> ⚠️ **模型与泼溅数据不在本仓库里**（`.gitignore` 已排除，克隆后需自行补齐，
> 见 `models/README.md` 与 `splatdata/README.md`）。
> `models/Arisu.glb` / `Arisu_ext.glb` 是从《碧蓝档案》(Blue Archive) 提取的模型，
> 角色形象、模型、贴图与动作版权归 **NEXON / Yostar** 所有，**没有任何可商用授权**；
> 校园泼溅扫描由使用者提供，权利状态未核实。两者都**不得再分发**。
> 本工程刻意独立于工作区里任何要发布的项目，**不要把这里的模型或贴图搬进发行版**。

| 场景 | 用途 |
|---|---|
| `scenes/game.tscn` | **第三人称射击原型**（默认启动场景，F5 直接玩） |
| `scenes/main.tscn` | 动画查看器：24 条动作逐条播、切镜头 |

没有素材也能跑射击部分：

```powershell
& <godot> --path . -- --splat=off     # 跳过高斯泼溅（没有 .sogdata 时也建议加）
```

---

# 一、第三人称射击原型

## 1.1 操作

| 按键 | 动作 |
|---|---|
| `W A S D` / 方向键 | 相对相机移动 |
| `Shift` | 跑动（5.2 m/s） |
| `Ctrl` | 蹲行（1.1 m/s） |
| `空格` | 跳跃 |
| 鼠标右键（按住） | **开镜**：相机拉近过肩、FOV 62→34、散布收窄、移速降到 1.6 m/s |
| **鼠标左键（按住）** | **开火**：约 13 发/秒，**60 发弹匣**。打空自动换弹，**换完不用再点一次，按住就继续射**。**背对准星时不会开枪，会先转身** |
| `R` | 手动换弹（1.05 s）。手动换弹同样不打断「按住」状态 |
| 鼠标移动 | 视角；`Esc` 释放/捕获鼠标 |
| 滚轮 | 拉近拉远 |

HUD 右下角：弹药 / 当前状态（腰射 / 瞄准 / 跑动 / 蹲行 / 换弹中 / **转向中**）/ 实际速度 / 换弹进度条。
准星会随移动扩散、随瞄准收拢。左上角是**校园泼溅状态行**（解码进度 / 就绪信息）。

子弹是**可见弹丸**：从枪口沿弹道以 260 m/s 飞行，弹着火花等弹丸真的飞到才炸开。

**场地是「悬浮记忆平台」**：40 × 40 m 的竞技场悬在空中，**没有护栏**（走出去就会掉下去，
掉到 y < −60 由保险送回出生点）。平台上摆着一间真人尺度的画室609（有墙碰撞、朝场地
开了一个门洞），脚下的平台下方是下沉的校园泼溅。
下方 12 m 是一片 ×25 的**校园高斯泼溅**（211 × 160 m，6,150,154 点），
走到平台边缘低头就能看见。接法与取舍见**第六节**。

**开局是标准越肩视角**：镜头在角色**背后**（后脑勺对着你），
画面正前方就是靶区（`z = -3 … -16` 的 5 个靶子），一进场就能开打。
实现是 `player.gd` 的 `_ready()` 里 `_yaw = 0` + `_facing_yaw = _yaw + PI`。

⚠️ 这里曾经设成 `_yaw = PI`（想要「一进场看到正脸」），结果相机绕到了角色**正面**、
朝着空旷方向看，画面里一个靶子都没有。**「看到正脸」和「能看到靶场」在第三人称里
是互斥的**，需求确认后取后者。相机绕角与视线的换算见 §1.4。

## 1.2 代码结构

```
scenes/game.tscn          竞技场：地面 + 3 根石柱 + 5 个靶子 + 2 位 Boss + 3 名同伴 + 灯光 + HUD
scenes/player.tscn        Player(CharacterBody3D)
                          ├─ Collision   胶囊
                          ├─ Arisu       模型节点（绕 Y 转 180°，见 §1.4）
                          │  └─ Model    Arisu.glb 实例
                          │     └─ AnimDriver   动画驱动
                          ├─ Weapon      武器逻辑 + Muzzle 挂点
                          └─ CameraRig → SpringArm3D → Camera3D
scenes/companion.tscn     Companion(CharacterBody3D)：Collision + Rig（模型运行时装进 Rig）
scripts/player.gd         移动积分、相机、朝向、开火转身门控
scripts/companion.gd      同伴跟随：站位 / 走近跑近 / 朋友层（第八节）
scripts/anim_driver.gd    动画驱动（直接用 AnimationPlayer）
scripts/weapon.gd         射线命中、弹药、换弹、弹丸、开火门控、特效
scripts/target.gd         可击毁靶子（掉血 → 闪白 → 塌下 → 4 秒重生）
scripts/boss.gd           Boss 木桩基类（霸王龙 + 飞猪共用，第七节）
scripts/hud.gd            准星、弹药、状态、速度、换弹条、Boss 血条组
scripts/game.gd           玩法总控（按类型收 Boss / 同伴）
scripts/main.gd           动画查看器主控
```

## 1.3 ⚠️ 输入为什么写在 `_input` 而不是 `_unhandled_input`

**实测：`_unhandled_input` 收不到鼠标事件。**

在 Godot 4.7.1 真窗口下（`Input.mouse_mode = 2` 已捕获、`window_is_focused() = true`）：

```
_unhandled_input 里注入鼠标移动 → yaw 完全不变，左键也收不到
_input 里注入同样事件         → yaw 正常转，左键正常开火
```

所以 `player.gd` 把视角、开镜、开火、换弹全放在 `_input`（它在 GUI 之前收到事件，
不会被 UI 消费）。左键的「按下 / 松开」用事件里的 `pressed` 判定，另外每帧用
`Input.is_mouse_button_pressed()` 兜底纠正一次，防止丢事件导致扳机卡住。

## 1.4 ⚠️ 角色朝向（踩过三轮坑，改动前务必看这段）

骨架局部坐标系的实测事实（模型局部坐标，单位 m）：

| 量 | 值 | 含义 |
|---|---|---|
| `L Foot` | z = -0.299 | 脚在骨盆 −Z 侧 |
| `L Toe0` | z = -0.344 | 脚趾更靠 −Z |
| `Move_Ing` 触地期脚 | z 从 -0.237 → -0.150 | 脚朝 **+Z** 迈 |

**铁证（把相机放到角色 +Z 侧渲图，看到的是正脸）**：

```
model_root.rotation.y = 0   →  脸朝世界 +Z      （相机在 +Z 侧拍到正脸）
model_root.rotation.y = PI  →  脸朝世界 -Z      （相机在 +Z 侧拍到后背）
```

所以「脸朝向」= `(sin(rotation.y), cos(rotation.y))`，
要让脸对着方向 `dir`，就是 **`rotation.y = atan2(dir.x, dir.z)`**。

> ⚠️ 骨架局部的「脚趾指向 -Z」和「脸朝 +Z」并存，说明这套骨骼的局部轴跟直观不一样。
> **别用 肩线叉乘 / 节点 basis 推脸的方向**，本喵在这上面错了三轮。
> 唯一可靠判据是**渲图看**；眼睛骨只能做定性核对（有约 46° 固有偏差，见 §1.11）。

### 1.4.1 ⚠️ 相机视线 = `-(sin(_yaw), cos(_yaw))`（差 180° 就会「转身转反」）

实测（`_probe_view.gd` 打印 + 四方位渲图）：

```
cam 在 rig 本地坐标 = (-0.42, 0.17, +4.2)    ← 挂在 rig 的 +Z 侧
相机看向 rig 的 -Z
→ 相机视线 camera_forward() = -(sin(_yaw), 0, cos(_yaw))
→ 角色脸朝向               =  (sin(_facing_yaw), 0, cos(_facing_yaw))
→ 「朝着准星、背对镜头」就是 _facing_yaw = _yaw + PI
```

**相机视线和角色脸朝向的正负号是反的**，代码里用常量 `CAMERA_FORWARD_OFFSET := PI` 表达。
写成 `_facing_yaw = _yaw` 正好差 180°，表现就是这两个 bug：

| 现象 | 原因 |
|---|---|
| 一进场看不见靶子（镜头朝空场地） | `_ready()` 里 `_yaw = PI` → 视线 = +Z，靶区在 -Z |
| 开火前强制转身却「转过去面对镜头」 | `_facing_yaw = _yaw` → 脸朝 `-(视线)` = 朝镜头 |
| 按 W 朝前跑时点左键，人整个翻过来 | 同上：移动朝向用的是 `atan2(vel.x, vel.z)`（= 视线方向），一开火被改成 `_yaw`（= 反方向） |

另一个坑：判定「转到位了没」必须**现算**，不能读上一物理帧缓存的 `_facing_yaw`。
甩镜头 + 点左键时，`_input` 先跑（`_fire_held` 立刻为 true），武器的 `_process`
可能排在角色 `_physics_process` 之前 —— 那一刻缓存的还是旧朝向，就会「朝旧方向漏出一发」。
所以 `player.gd` 有：

```gdscript
func aim_facing_yaw() -> float:
    if aiming or _fire_held:
        return _yaw + CAMERA_FORWARD_OFFSET   # 现算，不看缓存
    return _facing_yaw
```

`is_aim_aligned()` / `align_error_deg()` 都走这个函数。

当前朝向逻辑（`player.gd`）：

```gdscript
## 角色自己的朝向。必须独立于 _yaw ——
## 否则松开移动键后 horiz 归零，朝向会回落成相机朝向，角色自己转回去面对镜头。
var _facing_yaw := 0.0

# 出生：相机绕角 0 → 相机在背后、视线 -Z，靶区正好在正前方
func _ready() -> void:
    _yaw = 0.0
    _facing_yaw = _yaw + CAMERA_FORWARD_OFFSET   # = PI
    model_root.rotation.y = _facing_yaw
    rig.rotation.y = _yaw

# 每帧：开火/开镜时必对准准星；在移动就朝行进方向；都不满足则保持不动
var want_face_aim := aiming or _fire_held
if want_face_aim:
    _facing_yaw = _yaw + CAMERA_FORWARD_OFFSET
elif horiz.length_squared() > 0.25:
    _facing_yaw = atan2(horiz.x, horiz.z)
var turn_speed := TURN_SMOOTH_FIRE if want_face_aim else TURN_SMOOTH
model_root.rotation.y = _lerp_angle_smooth(model_root.rotation.y, _facing_yaw, turn_speed, delta)
```

注意 `atan2(horiz.x, horiz.z)` 这条**不需要**加偏移：移动方向 `horiz` 本身就是
「相机视线方向」（按 W 时 `dir = -rig.basis.z`），它和脸朝向用的是同一套 `(sin, cos)` 约定，
两者天然一致 —— 所以「朝前跑时开火不会突然转身」。

> ⚠️ 骨架局部的「脚趾指向 -Z」和「脸朝 +Z」并存，说明这套骨骼的局部轴跟直观不一样。
> **别用 肩线叉乘 / 节点 basis 推脸的方向**，本喵在这上面错了三轮。
> 可靠判据只有两个：**渲图看**，或者用**眼睛骨**做定性核对（有约 46° 固有偏差，见 §1.11）。

**「停止后不回退」就是靠「只在真的移动（或开火/开镜）时才更新 `_facing_yaw`」实现的**：
松开按键后两个分支都不进，朝向自然冻结。实测：

```
松开后 3 帧:  facing_yaw=1.5708  model.rot.y=-4.7124  相机_yaw=0.0000
再等 180 帧: facing_yaw=1.5708  model.rot.y=-4.7124  相机_yaw=0.0000
[PASS] facing_yaw 停止后不变（角色没有转回去）
[PASS] 转视角时角色朝向不动（相机转了 -158.8 度，角色只漂 1.8 度）
```

## 1.5 ⚠️ 开火前强制转身（不能背对靶子把子弹打出去）

`player.gd` 把「朝向目标」的条件从「开镜」扩到「开火或开镜」（代码见 §1.4），
`weapon.gd` 的 `shoot()` 里加一道闸门：

```gdscript
## 角色还没转向准星方向就先不开火。扳机保持按住，转到位后自然放行。
if _player and not _player.is_aim_aligned():
    _turning = true
    return false
_turning = false
```

转身速度用更快的 `TURN_SMOOTH_FIRE = 26`（平时 14），否则「点了没反应」的迟滞感明显。
真机 60fps 下 180° 转身约 0.15~0.2 秒。HUD 在卡住时显示「转向中」。

⚠️ **转身目标必须是准星方向 `_yaw + PI`，不是 `_yaw`** —— 写成 `_yaw` 就会「转过去面对镜头」，
见 §1.4.1。这一轮修的就是这个。

实测（`_verify_turnfire.gd`，模拟「背对准星时扣扳机」）：

```
相机视线 = (0.0, 0.0, -1.0)    目标朝向 = _yaw + PI = 3.142 rad
当前 model_root.rotation.y = 0.000 rad
[PASS] 起手确实是「背对准星」
扣扳机后 2 帧射出 0 发（应 0）
[PASS] 没转到位前不出子弹
[PASS] 没转到位前靶子不掉血
[PASS] 是「先转身、后开火」而不是同帧开火
开火时旋转误差在容差内（16.5 度）
[PASS] 对准后连发正常
[PASS] 子弹朝着准星飞（靶子掉血）      ← 这条同时证明转身目标没反
失败 0 项
```

另有一组「甩镜头 + 按住左键」的真实鼠标事件测试（`_verify_spawnview.gd`），
专门覆盖 `_input` 与 `_physics_process` 的时序：

```
甩镜头后 _yaw = -2.112 rad（-121 度）
此刻「准星方向」= _yaw+PI = 1.030 rad   角色朝向 = -3.142 rad   差 121.0 度
点后第 11 帧开出第一枪   曾出现「转向中」= true
★ 开火瞬间：align_error = 12.5 度（容差 22）   脸·准星方向 = +0.976
[PASS] 开火瞬间角色朝着准星方向（旧 bug 时是 -1）
[PASS] 转身目标是背对镜头
失败 0 项
```

## 1.6 ⚠️ 连发与自动换弹（踩过的坑）

需求：「按住左键打空 → 自动换弹 → 换完继续射，不用再点一次」。

```gdscript
## ❌ 错的：换弹时把「按住」状态清掉，换完必须重新点鼠标
func try_reload() -> void:
    _reloading = true
    _reload_timer = reload_time
    _trigger = false          # ← 就是这一行毁掉了连续射击
```

正解是**全程不动 `_trigger`**：

```gdscript
func try_reload() -> void:
    _reloading = true
    _reload_timer = reload_time
    # 不要清 _trigger！保持不动，换完弹 _process 里那句 shoot() 会自动接上
    reload_started.emit()

func _process(delta):
    if _reloading:
        _reload_timer -= delta
        if _reload_timer <= 0.0:
            _finish_reload()
        return
    if _trigger and auto_fire and _cooldown <= 0.0:
        shoot()

func shoot() -> bool:
    if _reloading or _cooldown > 0.0:
        return false
    if current_ammo <= 0:
        try_reload()          # 打空自动换弹
        return false
    ...
```

`_finish_reload()` 里给 `_cooldown` 垫一个 `post_reload_delay`（默认 0.12 s），
让收招动作播完再吐子弹，避免视觉上「动作被腰斩」。该延迟不影响连续射击。

实测（`_verify_mag.gd`）：

```
弹药归零（第 529 帧）  _trigger = true
[PASS] 60 发全部打完
[PASS] 打空后自动进入换弹（没让玩家手动按 R）
[PASS] 换弹期间左键仍是「按住」状态
换弹结束（第 174 帧）  弹药 = 60 / 60
[PASS] 换完弹自动继续射击（不用再点一次鼠标）
[PASS] 松开左键后停火
```

## 1.7 动画驱动为什么不使用 AnimationTree

**实测结论：在这套场景里，AnimationTree 完全不驱动骨骼。**

| 试过的做法 | 结果 |
|---|---|
| `AnimationNodeBlendSpace1D` 做 Locomotion | 走动时骨骼不动，逐帧截图 0 像素差异 |
| `AnimationNodeBlend2` + `AnimationNodeBlendTree` | 同样 0 像素差异 |
| `AnimationNodeAnimation`（直接播单一动作） | 同样 0 像素差异 |
| **`AnimationPlayer.play()` 直接播** | **正常**，每个动作 40/40 帧姿态都不同 |

所以 `anim_driver.gd` 退回到最朴素的做法：**直接用 `AnimationPlayer`**，
自己按速度在 `Normal_Idle` / `Cafe_Walk` / `Move_Ing` 之间切（带 0.18 s 交叉淡入），
用 `speed_scale` 让播放速率跟着实际速度走。一次性动作用 `animation_finished` 回落。

**动作命名与实际内容相反**（按脚的摆幅和时长判定）：

- `Cafe_Walk`（1.27 s，脚摆 ±0.03 m）= **走路**
- `Move_Ing`（0.67 s，脚摆 ±0.16 m）= **跑步**
- 切换阈值 `WALK_THRESHOLD = 2.4 m/s`

开火/换弹这类一次性动作给了倍速（`FIRE_SPEED = 2.5`、`RELOAD_SPEED = 1.9`），
否则 2.67 秒的开火动作配 13 发/秒的射速，手感很卡。

## 1.8 ⚠️ 怎么判断「骨骼到底有没有动」

**这是个坑：`get_bone_pose().origin` 对旋转轨是恒定的。**

这套动作里绝大多数骨骼的**位移轨只有 1 个关键帧**（origin 永远不变），
真正在变的是**旋转轨**。所以：

```gdscript
# ❌ 错：判定恒为「没动」
skel.get_bone_pose(bone).origin

# ✅ 对：看旋转
skel.get_bone_pose_rotation(bone)
# ✅ 或看子骨的全局位置
skel.get_bone_global_pose(child_bone).origin
```

更硬的判据：**连续截图逐像素比对**。走动时相邻帧差异像素应远大于 0。

## 1.9 ⚠️ 瞄准姿态问题（这个模型的硬伤）

**Arisu.glb 的枪不在手上，24 条动作里枪始终挂在身体以外约 0.6 m 处。**

实测（`_probe_muzzle.gd` / `_probe_timeline.gd`）：

| 动作 | 枪口到右手骨距离 |
|---|---|
| `Normal_Idle` | 0.607 m |
| `Normal_Attack_Ing` | 整条时间线稳定 0.606 m |
| `Move_Ing` | 0.547 m |
| `Vital_Death` | 0.762 m |

原因：`Bip001_Weapon` 是**骨架的根级骨骼**（170 根骨里索引 147，父级为空），
武器网格单独绑在这套 Weapon 骨上。导出 glTF 时这套骨被拍平到根，
每条动作只烘了它的世界变换——**枪的位置是世界坐标动画，不跟随右手**。

由此引出**弹道起点不能走枪口**：枪口在腰侧（y≈0.45），相机在眼睛高度（y≈1.5），
「枪口 → 准星远点」这条线在近距离会擦着目标过去，表现为
**「准星明明压在靶子上，开枪就是不掉血」**。

改成 `相机位置 + muzzle_offset` 作为弹道起点，起点落在准星那条线上：

```
[raycast] origin=(5.82, 1.6, -0.15) dir=(0.0, -0.02, -1.0)
在 z=-10 平面上 y = 1.400        （靶子碰撞盒 y 范围 0.80 ~ 1.95）
[raycast] hit Target1 @ (5.82, 1.41, -9.73)      ← 满血 100 → 82
```

枪口火光与弹丸仍从真实枪口骨出来，观感不受影响。

**想要真正的 TPS 枪感**（枪管指着弹道方向），需要额外做一步：

1. 武器网格改成 `BoneAttachment3D` 挂到 `Bip001 R Hand`，运行时手调偏移摆正
2. 运行时用 `SkeletonModifier3D` 覆盖 `Bip001_Weapon` 的朝向
3. 换原生 TPS 骨架的模型

## 1.10 已知观感问题：跑动前倾偏大

> **已解决（走下面的方案 1：重做动作数据）**，并且**已在 `scenes/player.tscn` 里启用**
> （`Model` 现在引用 `Arisu_ext.glb`，见 §5.1）。
> Blender 侧：胸腔前倾 **+13.5°（峰值 +19.4°）→ +5.2°（峰值 +11.0°）**。
> Godot 侧复测（`_probe_ext_glb.gd`，度量方式不同所以绝对值不同，看差值）：
> **+36.5°（峰值 +40.1°）→ +29.6°（峰值 +32.5°）**，即改善约 7~8°，与 Blender 的 −8.3° 吻合。
> 剪影叠加对照图：`_arisu_captures/_lean_side/overlay.png`（红=修正前，蓝=修正后）。
> 下面这段保留为问题分析与当时的排查记录。

`Move_Ing`（跑动）的躯干前倾明显偏大，加上长发向后飘，视觉上更夸张。

**本喵试过但无效**：给 `Bip001 Pelvis` / `Bip001 Spine` 加 ±10°~30° 的反向旋转
（各轴都试了）。原因是这套 Biped 骨在动画里被当成近似 armature 空间驱动
（实测 `Pelvis→Head` 在动画里几乎是恒定的 +Z 方向，不管怎么转骨盆都不变），
**局部加旋转传导不到躯干**。所以运行时用 `SkeletonModifier3D` 修不了这个。

**可用的调节手段**（按效果排序）：

1. **重做跑动动作** —— 走 `..\_blender_arisu\build_anim.py` 那套管线（见第五节），
   把躯干前倾角度改小。这是根治办法。
2. **换一条动作** —— `Move_End_Normal` / `Public01` / `Cafe_Walk` 的前倾都比 `Move_Ing` 小。
   把 `anim_driver.gd` 里 `_update_locomotion()` 的 `"Move_Ing"` 换成其中一条即可，
   **但它们的步频/脚程与 5.2 m/s 不一定匹配，可能要一并调 `speed_scale`**。
3. **调相机** —— `player.gd` 的 `hip_height`（默认 1.62）与 `_pitch`（默认 -0.04）。
   俯角越小、相机越平，前倾看起来越轻。

## 1.11 自检与截图

一条命令全量自检（真渲染，不要 `--headless`）：

```powershell
$g    = "D:\SOFTWARE\Godot-4.7.1-dotnet\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"
$p    = "C:\Users\WY157\Desktop\GODOT\_arisu_learn"
$data = "C:\Users\WY157\Desktop\GODOT\_godot_editor_data"
$env:APPDATA = "$data\Roaming"; $env:LOCALAPPDATA = "$data\Local"

& $g --path $p --script res://scripts/_verify_final.gd      # 17 项：输入/移动/朝向/动画/命中/换弹
& $g --path $p --script res://scripts/_verify_facing.gd     # 9 项：出生越肩视角/停止保持朝向/开镜朝向
& $g --path $p --script res://scripts/_verify_mag.gd        # 12 项：开局视角/弹匣/自动换弹/连续射击
& $g --path $p --script res://scripts/_verify_turnfire.gd   # 8 项：开火前强制转身（连子弹都必须朝准星飞）
& $g --path $p --script res://scripts/_verify_spawnview.gd  # 12 项：初始视角 + 甩镜头点左键的真实鼠标时序
& $g --path $p --script res://scripts/_verify_boss.gd       # 19 项：霸王龙木桩（第七节）
& $g --path $p --script res://scripts/_verify_boss_pig.gd   # 32 项：飞猪木桩 + HUD 双血条（§7.6）
& $g --path $p --script res://scripts/_verify_companion.gd  # 100 项：七名同伴跟随 + 不挡镜头 + 朝向/接地（第八节）
& $g --path $p --script res://scripts/_verify_splat.gd      # 14 项：泼溅摆放 / 悬浮平台 / 走出边缘会掉（第六节）
& $g --path $p --script res://scripts/_verify_room.gd       # 57 项：画室609 摆放/轴对齐/裁剪/墙碰撞/门洞 + 玩家朝向（§6.8）
& $g --path $p --script res://scripts/_probe_view.gd         # 诊断：打印视线/朝向数值，并从四方位渲图
```

合计 **280 项**（2026-10-14 实测 280 PASS / 0 FAIL）。

除 `_verify_splat` 外建议都加 `-- --splat=off`：615 万点的逐帧光栅化会让这些渲染相关用例
慢很多（第六节实测，`_verify_final` 第 5 节甚至会卡住）。`_verify_splat` 要开着泼溅跑。

> ⚠️ **自检里「等」什么，都要按状态或真实秒数，不要按帧数。**
> 帧率在**两个方向**上都坑过本喵：
>
> - **headless 极低**（约 6 fps）：等 60 帧其实只推进了 0.1 s
> - **真渲染窗口极高**（实测能到约 2000 fps）：等 4000 帧只过了 2 秒 ——
>   `_verify_mag` 的「60 发打空」因此只打出 41 发就被判失败，连带
>   「自动换弹 / 换弹后满弹 / 自动续射」假红 6 条；`_verify_final` 的换弹等待同理
>
> 所以：等状态用 `while not cond: await process_frame`，
> 等时长用 `while Time.get_ticks_msec() - t0 < 毫秒: await process_frame`。
>
> ⚠️ 另一个坑：**测试自己驱动武器时，必须先关掉玩家的输入处理。**
> `player.gd` 的 `_input()` / `_poll_mouse_buttons()` 只要收到真实鼠标左键「松开」，
> 就会调 `weapon.trigger_up()`。本喵跑全量回归时手上正好有鼠标动作，`_trigger` 被打断
> （日志里白纸黑字写着 `_trigger = false`），「按住不放」相关的用例集体假红。
> 处理办法：`player.set_process_input(false)` —— 但**要测转身就不能关
> `_physics_process`**，转身逻辑跑在里面。

其它工具（都靠环境变量触发，平时空转）：

```powershell
$env:ARISU_PLAY = "1";    & $g --path $p res://scenes/game.tscn   # 玩法全流程截图 → _play/
$env:ARISU_CAPTURE = "1"; & $g --path $p res://scenes/main.tscn   # 24 条动作取样帧
$env:ARISU_POSE = "1";    & $g --path $p res://scenes/main.tscn   # 多机位姿势检查
& $g --headless --path $p --script res://scripts/_probe_ext_glb.gd   # 两个 glb 的动作/时长/前倾对比
& $g --path $p --script res://scripts/_probe_lean_side.gd            # 跑动侧视 4 相位（做前倾对照）
& $g --path $p --script res://scripts/_probe_platform.gd            # 泼溅摆放调参：扫缩放/下沉量
& $g --path $p --script res://scripts/_probe_fps.gd                 # 泼溅吃多少 fps
& $g --path $p --script res://scripts/_probe_splat_render.gd -- --scale=25 --cache=auto
```

---

# 二、导入验证：Arisu.glb 到底导进来了什么

## 2.1 骨骼

| 项 | GLB 源文件 | Godot 导入后 |
|---|---|---|
| skin 数量 | **3** | **1 个 Skeleton3D**（Godot 自动合并） |
| 关节数 | 139 + 19 + 1 | **170 根骨** |
| 蒙皮网格节点 | 13 | 14（含 1 个无蒙皮） |
| 骨架根 | `Bip001 Pelvis` + 8 个独立裙骨根 + `Bip001_Weapon` | 统一挂在 `bone_root/Bip001` 下 |

Godot 自动把 3 个 skin 合成一套 Skeleton3D，不用像 UE 那样手动合并。
骨骼名（`Bip001 L Finger01`、`bone_skirtF_L_01` 这类带空格和大小写的名字）**原样保留**。

节点层级：

```
Arisu                       Node3D      ← 180° 旋转节点
└─ Model                    (Arisu.glb 实例根)
   ├─ Aris_Original_Mesh    Node3D
   │  ├─ Aris_Original_Body MeshInstance3D
   │  ├─ bone_root/Bip001
   │  │  └─ Skeleton3D                    ← 170 根骨都在这
   │  │     ├─ Mouth_401 … Mouth_705      ← 10 个口型网格挂骨骼下
   │  │     └─ Aris_Original_Body2 / Weapon2 / FX_… / Halo2
   ├─ Aris_Original          Node3D
   └─ AnimationPlayer                    ← 25 条动画都在默认库 ""
```

## 2.2 动画

默认库 `""` 里 **25 条**：24 条来自源文件 + 1 条自动生成的 `RESET`（T-pose 复位）。
每条 **385 条轨道**。源文件混用 `CUBICSPLINE` / `LINEAR` / `STEP` 三种插值，全部按原样转换。

| # | 动作 | 时长 | # | 动作 | 时长 |
|---|---|---|---|---|---|
| 0 | Cafe_Idle | 3.20 s | 12 | Normal_Attack_Ing | 2.67 s |
| 1 | Cafe_Reaction | 3.67 s | 13 | Normal_Attack_Start | 0.67 s |
| 2 | Cafe_Walk | 1.27 s | 14 | Normal_Callsign | 1.50 s |
| 3 | Exs | 4.00 s | 15 | Normal_Idle | 2.80 s |
| 4 | Exs_Cutin | 4.00 s | 16 | Normal_Reload | 2.00 s |
| 5 | Exs_Root | 4.00 s | 17 | Public01 | 2.00 s |
| 6 | Formation_Idle | 3.20 s | 18 | Victory_End | 3.20 s |
| 7 | Formation_Pickup | 5.07 s | 19 | Victory_Start | 3.00 s |
| 8 | Move_End_Normal | 2.00 s | 20 | Vital_Death | 1.80 s |
| 9 | Move_Ing | 0.67 s | 21 | Vital_Dying_Ing | 1.00 s |
| 10 | Normal_Attack_Delay | 1.00 s | 22 | Vital_Panic | 1.00 s |
| 11 | Normal_Attack_End | 0.67 s | 23 | Vital_Retreat | 1.67 s |

## 2.3 口型 / 表情形变

10 个 `Mouth_*` 网格各带 **1 个 blend shape**（Godot 命名为 `morph_0`）。
每条动画都有 **10 条 `weights` 通道**打在这些网格上，**口型烘进每条动作里**。

实测（`scripts/_probe_morph.gd`，`Normal_Callsign` / `Mouth_401`）：

```
t=0.000s  morph_0=1.0000      ← 张嘴
t=0.214s  morph_0=1.0000
t=0.429s  morph_0=0.0000      ← 闭嘴
```

值在 0/1 之间跳变 → 源文件是 **STEP 插值**的口型切换，Godot 原样保留。
嘴网格挂在骨骼节点下：`Arisu/Model/Aris_Original_Mesh/bone_root/Bip001/Skeleton3D/Mouth_401`

## 2.4 网格与材质

- 14 个 MeshInstance3D：`Aris_Original_Body`(5 面)、`Weapon`(1)、`FX_Weapon`(1)、
  `Halo`(1，**无蒙皮**)、10 个 Mouth
- 18 个材质，全部 `StandardMaterial3D`、`PER_PIXEL`、`albedo_color` 纯白（靠贴图出颜色）
- `Aris_Original_EyeMouth` 的 `transparency=2`(ALPHA)，眼嘴靠 alpha 抠
- 16 张贴图已解包到 `models/` 下的独立 PNG

**注意**：源文件的卡通材质被导成普通 `StandardMaterial3D`，所以现在是**受光的塑料感**，
不是原片的赛璐璐描边。想要原作画风得自己写 toon `ShaderMaterial`。

## 2.5 导入参数（`models/Arisu.glb.import`）

| 参数 | 改成 | 为什么 |
|---|---|---|
| `animation/import_rest_as_RESET` | `true` | 生成 RESET 姿态，方便复位 |
| `animation/remove_immutable_tracks` | `false` | 别删「不变」的轨道——口型有些帧不变，删了就丢 |
| `meshes/generate_lods` | `false` | 170 骨的蒙皮网格自动 LOD 容易出问题 |

改完参数要重新导入：`& $g --headless --path $p --import`

---

# 三、目录结构

```
_arisu_learn/
├─ project.godot            主场景=game.tscn；输入映射；autoload 挂工具；[gdgs] 后端=Raster
├─ LICENSE                  MIT（除模型与美术素材外的全部内容）
├─ THIRD_PARTY.md           第三方组件与素材许可说明（哪些不随仓库分发）
├─ .gitignore               排除私有素材（模型 / 泼溅数据）与 Godot 缓存
├─ addons/
│  └─ gdgs/                 GDGS 3.3.0 高斯泼溅插件（**纯 GDScript，无 DLL**，MIT，第六节）
├─ models/
│  ├─ README.md             说明：要放什么模型、版权与换模型的三个注意点
│  ├─ Arisu.glb             原模型（24 条动作）※不随仓库分发
│  ├─ Arisu_ext.glb         **实际使用**的模型（27 条动作，见第五节）※不随仓库分发
│  ├─ school.collision.glb  校园碰撞网格（默认不挂，见 §6.5）※不随仓库分发
│  ├─ Arisu*_*.png          自动解包的贴图 ※不随仓库分发
│  ├─ companions/           七名同伴（第八节）※不随仓库分发
│  │  ├─ Mika.glb           未花（145 骨、33 动作）
│  │  ├─ Yuuka.glb          优香（108 骨、38 动作）
│  │  ├─ Noa.glb            诺亚（135 骨、31 动作）
│  │  ├─ Momoi.glb          小桃（105 骨、37 动作）
│  │  ├─ Midori.glb         小绿（105 骨、31 动作）
│  │  ├─ Yuzu.glb           柚子（122 骨、30 动作）
│  │  └─ Kei.glb            凯伊（166 骨、32 动作，另有 3 个附属 skin）
│  ├─ boss/                 霸王龙优香 FBX + 贴图（第七节）※不随仓库分发
│  └─ boss_pig/             飞猪优香 FBX + 贴图 + 作者的对照渲染图（§7.6）※不随仓库分发
├─ splatdata/
│  ├─ README.md             说明：泼溅数据要求与摆放参数
│  ├─ school_playable.sogdata  **实际加载**的校园泼溅（清理版，86.6 MB）※不随仓库分发
│  ├─ school_raw.sogdata       原始未清理扫描（仅存档）※不随仓库分发
│  └─ room609.sogdata          「画室 609」扫描（40.7 MB / 2,774,116 点，裁后 2,769,851）※不随仓库分发
├─ scenes/
│  ├─ game.tscn             玩法场景（40×40 悬浮平台 + 下沉校园 + 平台上的画室609
│  │                        （§6.8，有墙碰撞和门洞）+ 2 位 Boss + 7 名同伴；**无护栏**）
│  ├─ player.tscn           玩家（模型 + 动画 + 武器 + 相机）
│  ├─ companion.tscn        同伴（模型由 companion.gd 按 model_path 运行时实例化）
│  └─ main.tscn             动画查看器
├─ scripts/
│  ├─ player.gd             移动 / 相机 / 朝向 / 开火转身门控
│  ├─ companion.gd          同伴跟随：站位 / 走近跑近 / 朋友层（第八节）
│  ├─ anim_driver.gd        动画驱动（直接 AnimationPlayer）
│  ├─ weapon.gd             开火 / 弹药 / 换弹 / 弹丸 / 特效 / 子弹穿透朋友层
│  ├─ boss.gd               Boss 木桩基类：骨架盒 or 网格盒定尺寸、贴图表、血条信号（第七节）
│  ├─ splat_scene.gd        高斯泼溅接入器：后台线程解码 + 自动摆放 + 锚点摆放 + 裁剪（第六节）
│  ├─ sog_runtime.gd        运行时 SOG 解码器（绕开编辑器导入器，第六节）
│  ├─ target.gd / hud.gd / game.gd / main.gd
│  │                        （hud.gd 的泼溅状态、Boss 血条都是**一份场地/一位 Boss 一行**）
│  ├─ _verify_*.gd          [工具] 自检（见 §1.11、§7.6、§8.4、§6.8）
│  ├─ _capture.gd           [工具] 24 条动作取样帧
│  ├─ _pose_shots.gd        [工具] 多机位姿势检查
│  ├─ _play_shots.gd        [工具] 玩法全流程截图
│  ├─ _probe_ext_glb.gd     [工具] 两个 glb 的动作/时长/前倾对比
│  ├─ _probe_companion.gd   [工具] 七名同伴的骨架/动画/**朝向**（含「骨骼空间 vs 模型空间」的对照）
│  ├─ _probe_companion_row.gd [工具] 七人合影：一次看清朝向 + 接地 + 动画是否真在动
│  ├─ _probe_slot.gd        [工具] 扫同伴站位候选（投影到屏幕，含与已在场者的间距）
│  ├─ _probe_boss_pig.gd    [工具] 飞猪 FBX 导入后拿到了什么（材质/贴图/尺寸）
│  ├─ _probe_room_layout.gd [工具] 把任意 .sog 当点云渲结构（地面/主轴/高度图/离群点）
│  ├─ _probe_room_on_platform.gd [工具] 在真实游戏相机下扫泼溅场景的缩放与朝向
│  ├─ _probe_lean_side.gd   [工具] 跑动侧视渲图（做前倾对照）
│  ├─ _probe_platform.gd    [工具] 扫缩放×下沉量（泼溅摆放调参）
│  ├─ _probe_splat.gd       [工具] 探测引擎有没有原生 3DGS
│  └─ _probe_*.gd           [工具] 一次性探针（口型/枪口/时间线/泼溅渲染/FPS）
└─ .godot/                  导入缓存（已被 .gitignore 排除）

…\GODOT\
├─ _arisu_captures\         所有产出图（故意放工程外，免得被当素材导入）
├─ _godot_editor_data\      Godot 编辑器缓存重定向目录（沙箱用）
├─ _godot\                  辅助脚本（glb 包围盒、SOG 尺度、剪影拼图等 Python 工具）
└─ _blender_arisu\          Blender 生成脚本（第五节，不在本仓库内）
```

---

# 四、跑命令行 Godot 的注意事项

## 4.1 必须重定向 APPDATA

Godot 启动时往 `user://`（默认 `%APPDATA%\Godot`）写日志与缓存。
在 DSH 沙箱下这个路径不可写，Godot 4.7.1 会**直接段错误崩溃**
（`Could not create directory: 'user://logs'` → `signal 11`）。

```powershell
$env:APPDATA      = "C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Roaming"
$env:LOCALAPPDATA = "C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Local"
```

`_godot_editor_data` 约 10 MB，纯缓存，随时可整个删掉。

## 4.2 ⚠️ 绝对不要用 PowerShell 改本工程里的文本文件

本喵在这上面栽了**五次**。`Get-Content`（含 `-Raw`）会把 UTF-8 中文按 ANSI 解码，
再用 `Set-Content` 写回去就全是乱码：

- GDScript 文件 → Godot 报 `invalid unicode (UTF-8)` 拒绝加载，整个类都解析不了
- Markdown 文档 → 163 行注释变乱码，只能整份重写

**第五次是 BOM**：用 `Set-Content -Encoding UTF8` 写回 `scenes/game.tscn` 之后，
文件头多了 `EF BB BF`，于是编辑器扫描时报

```
ERROR: res://scenes/game.tscn:1 - Parse Error: Expected '['.
```

（`.tscn` 解析器不跳 BOM，第 1 行就不是 `[gd_scene` 了。运行时加载反而能过，
所以自检全绿、只有编辑器报错 —— 更阴。）

**改脚本/文档一律用编辑器工具**（读全文 → 写全文），不要用 PowerShell 的
文本替换或 `Set-Content`。

万一已经中招，查/清 BOM 用纯字节操作（不解码就不会二次损坏）：

```powershell
$f="…\game.tscn"
$b=[System.IO.File]::ReadAllBytes($f)
if($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF){
  [System.IO.File]::WriteAllBytes($f, $b[3..($b.Length-1)])   # 剥掉 3 字节 BOM
}
```

全工程扫一遍（排除 `.godot`）：凡是 `.tscn/.gd/.md` 首三字节是 `EF BB BF` 的都要剥。

---

# 五、新增动作：跳跃 / 落地 / 翻滚闪避

`models/Arisu_ext.glb` 是扩展版：**27 条动作，1 个 skin（170 骨已合并）**，
比原版多三条 —— `Jump_Start`、`Jump_Land`、`Dodge_Roll`。

## 5.1 已经启用

`scenes/player.tscn` 的 `Model` 现在**直接引用 `Arisu_ext.glb`**（不再是 `Arisu.glb`）。
其余文件一行没动：**骨骼名完全一致**（都是 170 骨、同名），所以 `AnimDriver` 与 `Weapon`
上那两个 `@export` 的 `NodePath` 依然有效。

切换前用 `scripts/_probe_ext_glb.gd` 逐条比对过（`--headless` 就能跑）：

| 检查项 | 结果 |
|---|---|
| 驱动器引用的 5 条动作 | `Normal_Idle` / `Cafe_Walk` / `Move_Ing` / `Normal_Attack_Ing` / `Normal_Reload` **两边全在** |
| `Move_Ing` / `Normal_Attack_Ing` / `Normal_Reload` 时长 | **完全一致**（0.6667 / 2.6667 / 2.0000 s）→ `CYCLE_SPEED` 表不用改 |
| `Normal_Idle` / `Cafe_Walk` | 只差 0.5 / 1.0 帧（≤1.3%，无感） |
| `RESET` | 只有原版有；它是 glTF 的 rest pose，驱动器从不引用 |
| 骨骼数 | 都是 170 |
| 动画总数 | 25（24 + RESET）→ 27（24 + 三条新动作） |

切完 5 套玩法自检（58 项）与泼溅自检（15 项）全绿，见 §1.11。

## 5.2 生成脚本（`..\_blender_arisu\`）

| 脚本 | 作用 |
|---|---|
| `probe_rig.py` / `probe_axes3.py` | 标定骨架：骨名、父子、局部轴、位移幅值 |
| `build_anim.py` | **主脚本**：定义姿势 → 打关键帧 → 贴地求解 → 导出 glb |
| `verify_anim3.py` | 逐帧（含插值帧）检查本体穿地量 |
| `shots.py` | 侧视渲染关键帧，用于肉眼复核 |
| `restore_scene.py` | 还原 Blender 现场（NLA 开关 / 活动动作 / 当前帧） |

三个关键技术点：

1. **轴选择不写死**。这套 Biped 骨架的 `bone.tail` 是退化值（`Bip001 L Thigh` 的 tail
   指向正前方，并不是膝盖位置），所以「绕哪个局部轴转等于抬腿」必须用**子骨 head
   当力臂**反推。姿势因此可以用解剖学方向描述（向前/向上/向左），代码自动挑轴与符号。
2. **两骨平面 IK**。给定骨盆下沉量与脚踝目标反解大腿/小腿角度，并让脚底保持水平；
   蹲下与落地过程中脚**一步都不滑**（实测脚踝高度全程稳定在 0.299–0.301）。
3. **贴地求解**。只对「实体顶点」求最低点（排除头发/裙摆/领带/头颈组，另加头颈球体约束），
   逐关键帧把骨盆抬到刚好贴地，再补一遍插值帧消除贝塞尔过冲；
   最终**全帧最大下陷 ≤ 4 mm**（角色总高约 0.45，即 < 1%）。

另外：`Bip001_Weapon`（枪）在原文件里是世界坐标动画；这两条新动作里改成
**跟随骨盆的固定偏移**（偏移量取自 `Normal_Idle` 第 0 帧），因此跳跃、翻滚时枪跟着身体走。

## 5.3 已知取舍

- **翻滚是「原地」转 360°**，前进位移留给游戏代码，避免与 `player.gd` 的速度积分打架。

## 5.4 修正 `Move_Ing` 的躯干前倾

源文件的 `Move_Ing`（跑动）**胸腔**平均前倾 **+13.5°**（峰值 +19.4°），而待机是 −3.3°、
走动是 −11.3°，也就是跑起来比站着多趴 17~25°。已用
[`..\_blender_arisu\fix_lean.py`](../_blender_arisu/fix_lean.py) 修正并重新导出：

| 指标 | 修正前 | 修正后 |
|---|---|---|
| 躯干前倾（骨盆→颈，平均 / 峰值） | +6.2° / +13.0° | **+1.8° / +8.6°** |
| 胸腔前倾（Spine1 朝向，平均 / 峰值） | +13.5° / +19.4° | **+5.2° / +11.0°** |
| 头部俯仰 | +7.6° ~ +21.8° | +9.5° ~ +23.3°（基本不变） |

做法：`Bip001 Spine` 与 `Bip001 Spine1` 各**向后再转 4.25°**，同时 `Bip001 Neck`
**向前转 8.5°** 做补偿——于是胸腔变直、头的世界朝向不变。
关键帧的插值句柄一起平移，曲线形状完全不变（不是重打关键帧）。

脚本是**幂等**的：原始四元数关键帧（含句柄）存在 `move_ing_backup.json`，
每次运行先还原再施加新修正量，所以反复调参不会越修越歪。
想改修正幅度就改脚本顶部的 `TOTAL_DEG` 再跑一次。

### 5.4.1 在 Godot 里复测（确认修正真的进了导出文件）

Blender 的数字不能直接当证据 —— 得确认导出的 glb 里就是改过的数据。
`scripts/_probe_ext_glb.gd`（`--headless` 可跑）逐帧 seek 采样，量
「骨盆→颈」与「Spine1→颈」两个方向相对竖直的偏角（模型脸朝 +Z，向前为正）：

| 指标（`Move_Ing` 24 帧采样） | `Arisu.glb` | `Arisu_ext.glb` |
|---|---|---|
| 躯干 骨盆→颈（均值 / 峰值） | +36.8° / +38.2° | **+33.1° / +34.3°** |
| 胸腔 Spine1→颈（均值 / 峰值） | +36.5° / +40.1° | **+29.6° / +32.5°** |
| 基线：`Cafe_Walk` 胸腔 | −11.7° | −11.8°（应基本不变 ✓） |
| 基线：`Normal_Idle` 胸腔 | +0.6° | +0.7°（应基本不变 ✓） |

绝对值比 Blender 那份大，是因为这里量的是「Spine1 骨头 → 颈骨头」这条弦、
参考系也不同；**看差值与基线稳定性**：跑动改善 7~8°，两条基线纹丝不动 ✓。
（`Cafe_Walk` 的 −11.7° 与 Blender 的 −11.3° 很接近，可作口径核对。）

侧视剪影对照：`scripts/_probe_lean_side.gd` 渲图（固定机位、4 个相位），
再用 `..\_godot\make_lean_overlay.py` 叠成
`_arisu_captures/_lean_side/overlay.png`。

> 注意：这条修正是**动作数据级**的，所以 §1.10 里「运行时给骨骼加反向旋转」被
> `AnimationPlayer` 每帧覆盖的问题不存在。
> 另外 `Cafe_Walk` 的胸腔是 **−11.3°（后仰）**，走动时略显后倾，需要的话可以用同一脚本调。

---

# 六、高斯泼溅校园（GDGS 3.3.0）

## 6.1 结论速查

| 项 | 值 |
|---|---|
| 插件 | GDGS 3.3.0（`ReconWorldLab/godot-gaussian-splatting`，MIT），**纯 GDScript**：55 个 `.gd` + 8 个 `.glsl` + 2 个 `.gdshader`，**没有 DLL / GDExtension** |
| 引擎侧 | Godot 4.7.1 **没有原生 3DGS**：ClassDB 1057 个类里没有一个 splat/gauss 类，也没有对应导入器（`_probe_splat.gd` 实测） |
| 后端 | 项目设置 `[gdgs] rendering/backend="Raster"`（只有 Compute 后端才需要挂 CompositorEffect） |
| 数据 | `splatdata/school_playable.sogdata`：6,150,154 点，86.6 MB（SOG v2 = zip + webp 贴图） |
| 首次解码 | **50 s**，内存约 1.5 GB（`point_data_byte` = 点数 × 240 B） |
| 缓存命中 | **1.0 s** |
| 摆放 | ×25（内容世界尺寸 211 × 160 m）；水平居中；顶面沉到平台下方 **12 m** |

## 6.2 ⚠️ 为什么把文件叫 `.sogdata` 而不是 `.sog`

GDGS 的 EditorImportPlugin 会把 `.sog` 展开成 GaussianResource 写进
`res://.godot/imported/*.res`：6,150,154 点 × 60 float × 4 B ≈ **2.89 GB**，
导出时整份塞进 PCK，exe 直接膨胀到 3 GB。

所以数据统一命名成 **`.sogdata`**：Godot 不认识这个后缀 → 不触发导入器 →
只当普通文件随包携带 → 运行时由 `scripts/sog_runtime.gd` 现场解码。

`SOG_NAMES` 的查找顺序是 `school_playable.sogdata` → `school.sogdata`
（`SogRuntime.find_source()`），所以**清理版优先**；想切回原始版改文件名即可。

`sog_runtime.gd` 与导入器的差异（有意为之，数学逐式对齐、有自检比对）：

1. 只产出渲染真正需要的字段（`point_count` / `point_data_byte` / `xyz` / `aabb`）；
   编辑器碰撞管线用的 `point_data_float` 不生成，省掉 6.15M × 240 B ≈ 1.48 GB 重复副本
2. 解码与打包融合成同一遍循环，不保留 canonical 中间数组（导入器那份 SH 系数单独就 1.18 GB）
3. 缓存默认 `off`，每次启动重新展开

## 6.3 点数据布局（要抽样或自己写解析时看这段）

每个高斯 **60 个 float = 240 B**（`addons/gdgs/importers/builders/gaussian_resource_builder.gd:82`）：

| 偏移(float) | 含义 |
|---|---|
| 0..2 | 位置 xyz，**已经减掉中心** |
| 3 | 恒 0 |
| 4..9 | 3D 协方差（6 个） |
| 10 | 不透明度（0..1） |
| 11 | 恒 0 |
| 12..59 | 48 个 SH 系数 |

`SplatScene.content_bounds()` 就是抽样这个数组算分位数包围盒的
（原始 `aabb` 会被离群 floaters 撑到 15.8 × 3.0 × 12.0，内容实际只有 8.5 × 0.7 × 6.4）。

## 6.4 ⚠️ 这份扫描是「俯拍航拍」，只有从上方看才干净

| 视角 | 结果 |
|---|---|
| 上方 30° 俯瞰 | 干净清晰 |
| 贴地平视（相机 1.6 m 高） | 高斯被拉成长条，严重拖影 |

原因是航拍重建出来的高斯都是朝向天空的扁椭球，从侧面看就被拉长。
**这跟缩放无关，是角度问题** —— 所以「Arisu 站在校园里、越肩相机平视」
这种接法必然糊（本喵渲过四方位对照图，见 `_arisu_captures/_splat/`）。

## 6.5 采用的方案：悬浮记忆平台 + 下沉校园

```
        竞技场 40×40 悬浮平台（y = 0，**无护栏**：走出去就掉下去）
   ──────────────────────────────────────────
                    ↓ 12 m
        校园泼溅 ×25（211 × 160 m，水平居中）
```

- `game.tscn` 的 `Floor` 从 80×80 缩到 40×40 —— 靶子/柱子坐标全在 ±20 内，**一个都没动**
- ⚠️ **原来那四面隐形护栏（`WallPX / WallNX / WallPZ / WallNZ`，高 0.7 m）已经删除**
  （2026-10-14 用户要求）。现在平台没有边界：走出 40 × 40 就往下掉，掉到 y < −60
  由 `game.gd` 的 `FALL_LIMIT` 保险送回出生点。`_verify_splat.gd` 现在验的是
  「护栏确实不在了」+「走出边缘真的会掉」+「掉太深会被送回来」
  - 历史：那圈护栏刻意只做 0.7 m（跳跃顶点 0.87 m），好让助跑起跳能翻出去看校园；
    再早还做过 4 m 高，结果「怎么跳都出不去」
- 新增 `SplatScene` 节点：`world_scale = 25`、`auto_place = true`、`top_gap = 12`、`cache_mode = "auto"`
- 新增 `Room609` 节点：真人尺度（×1.8）的画室，**带墙碰撞和门洞**（§6.8）
- 相机与跑打手感**一点没改**
- `game.gd` 加了保险：掉到 y < −60 就送回出生点
- HUD 左上角状态行显示解码进度（一场一行）；底部提示加了「屋内是画室609，平台下是校园」

### 几何上的取舍（本喵量过的）

从平台上平视时，校园被**平台自己的边缘**挡住，只有「地平线 ~ 平台远边」这条带可见。
可见性判据：

```
校园远边到相机距离  >  平台远边到相机距离 × (1 + 下沉量 / 眼高)
```

眼高 1.79 m、走到平台边缘（平台远边距相机约 8 m）时：

- 下沉 **12 m** → 需要校园延伸 > 63 m ✓（×25 的校园半深 80 m，够）
- 下沉 **40 m** → 需要 > 190 m ✗（那时低头也看不到校园了）

**所以 12 m 差不多是 ×25 下的最大下沉量。** 本喵扫过 ×8 / ×12 / ×15 / ×25 四组
（工具 `_probe_platform.gd`），×8 虽然能把 floaters 全压到平台下方，但校园太小，
从边缘也看不到；×25/12 m 是甜点。

## 6.6 性能实测（RTX 4060 Laptop，1600 × 900）

| 配置 | 平均 fps | 最低 | 静态内存 |
|---|---|---|---|
| 显示泼溅（615 万点） | **108.9** | 18 | 1665 MB |
| 隐藏泼溅 | 128.8 | 101 | — |

即插 615 万点大约吃 **20 fps**，日常完全够用（工具 `_probe_fps.gd`）。

⚠️ 但**渲染相关的自检用例会明显变慢**（每帧都要光栅化 615 万点 + 回读截图；
`_verify_final.gd` 第 5 节的逐帧像素比对实测卡住不动）。所以玩法自检统一加
`-- --splat=off` 跳过泼溅加载：

```powershell
& $g --path $p --script res://scripts/_verify_final.gd -- --splat=off
```

`SplatScene` 支持三个命令行覆盖：`-- --splat=off`（完全不加载）、
`-- --splat-cache=auto|off|refresh`（展开缓存策略）、
`-- --venue=room|campus|all`（只加载指定场地，见 §6.8）。

## 6.7 运行

```powershell
& $g --path $p
```

- 首次启动解码 615 万点约 **50 s**（窗口不冻，左上角有进度条式的状态行）；
  之后 `cache_mode = "auto"` 命中 `user://splat_cache`，**1.0 s** 就位
- 想每次都从压缩包现场展开（发行设置），把 `SplatScene.cache_mode` 改成 `"off"`
- 走到平台边缘低头看，就是整片校园

### 已知瑕疵

数据里 >99.9‰ 的 floaters 被 ×25 放大后高到 y ≈ +24 m，在平台上方表现为
几团白色光斑（像云）。想根治需要用 `splat-transform` 重新过滤数据；
把下沉量拉到 37 m 以上也能压住，但那样校园就看不见了。

## 6.8 「画室609」：平台上的第二块场地

第二份扫描 `splatdata/room609.sogdata` 是**教室内部**（不是航拍），所以它跟校园那份
的接法完全不同：校园只能从上方俯瞰，画室是**站在里面**玩的。它是**真人尺度**、
带**墙碰撞和一个门洞**，并且**罩着出生点**摆（原因见下）。

| 项 | 值 |
|---|---|
| 数据 | `splatdata/room609.sogdata`：2,774,116 点 / 40.7 MB（SOG v2） |
| 裁后点数 | **2,769,851**（丢 4,265，其中椭球过大的 4 个） |
| 首次解码 / 缓存命中 | ≈ 21 s / ≈ 1.5 s |
| `world_scale` | **5.0** → 世界 **28.1 × 9.8 × 32.0 m**（包围盒）、**室内净高 6.32 m** |
| `yaw_degrees` | **248.6**（把房间矩形转成轴对齐，见下） |
| 摆放 | `auto_place = false` + `use_anchor = true`，把源坐标的地板中心 (0.022, −0.333, −0.121) 对到 **(0, 0.03, 4.25)** |
| 地板平面（实测） | y = **0.062** |
| 房间范围（实测） | x ∈ [−14.5, 13.6]，z ∈ [−12.0, 20.0] —— 正好**不探出** 40 × 40 平台 |
| 顶面 / 相机 | 顶面 y = 6.38，玩家相机 y = 1.79 → **头顶余量 4.59 m** |
| 碰撞 | `build_box_collision`：四面墙（厚 0.3 m）+ **朝靶场那面（z−）开 1.6 m 门洞** |
| 帧率 | 现在场上**只有这一份**泼溅（校园已搬走），独占那 ≈ 2.9 GiB 的显存预算 |

### 为什么是 ×5（以及 ×6.4 / ×2.0 都试过）

* ×6.4：房间 36 × 41 m，铺满平台，但桌椅 2~4 m 对 Arisu 1.4 m 是「巨人画室」
* ×1.8~2.0：真人尺度（11 × 13 m、净高 2.5 m），但**这份扫描偏扁**
  （高 ÷ 进深 ≈ 0.20，真实教室约 0.36），×1.8 时相机到天花板只剩 **0.39 m**，
  上半屏糊成一片灰
* **×5.0（当前）**：用户定的 ——「就当是房间被神秘力量放大了」。房间 28.1 × 32.0 m、
  净高 6.32 m、相机余量 4.59 m，桌椅 2.5 倍，是个宽敞的室内场地

⚠️ 想再调时记住两条量出来的硬约束（都在 `_verify_room.gd` §3 里当断言验）：

1. **相机到天花板 > 0.6 m**（相机 y = 1.79）。少于这个数上半屏会糊。
   ⚠️ 量它**必须等 `SpringArm3D` 伸展完**，否则读到 0.57 m 这种假值。
2. **出生点必须在房间的 xz 范围内** —— 否则第三人称相机（玩家背后 3.5 m）会落到
   墙外，开局看到的是房间外墙（这份扫描只扫了室内，外面是糊的）。

### ⚠️ ×5 下的几何冲突（量过，别忽略）

房间在 ×5 时很大，和场上原有物件会打架。当前用 `anchor_world.z = 4.25`
把房间摆成「z ∈ [−12.0, 20.0]」，于是：

| 物件 | 位置 | 状态 |
|---|---|---|
| Target3 / Pillar3 | z = −16 | 在**门外**（走出去就能打）✅ |
| Target1 / Target2 / Pillar1 / Pillar2 | z = −10 / −11 | 在房间**里面** |
| Target4 / Target5 | z = −4 / −3 | 在房间**里面** |
| 两位 Boss | x = ±13, z = −8 | 在房间里面；⚠️ **霸王龙的碰撞盒（宽 2.12 m）会被 +X 墙切掉 0.72 m** |

想让「靶子和 Boss 都在门外」，把 `world_scale` 改成 **4.25 以下**即可
（那时房间半宽 11.95 m < Boss 的 13 − 1.06），一个数字的事，不用动别的参数。
本喵保留了 ×5 是因为用户明确要 5。

### 为什么房间要「罩着出生点」而不是摆在平台正中央

这是缩放改小之后才暴露的问题：出生点在 (0, 0.05, 6)，而第三人称相机在玩家
**背后 3.5 m**。房间只有 12.8 m 深，如果把它摆在平台正中央（z ∈ [−5.9, 5.6]），
出生点就正好贴在 z+ 的墙上，**相机（z ≈ 9.5）会落到房间外面**，开局看到的是
房间的**外墙** —— 而这份扫描只扫了室内，从外面看是一片糊（`73_door_from_outside.png`
就是这个观感）。

所以 `anchor_world` 用 (0, 0.03, **6**)，房间罩住出生点：房间 z ∈ [−0.5, 12.3]，
相机 z ≈ 9.5 稳稳在室内。门开在 **z−**（朝靶场那一面），出生时面朝 −Z 就正对着门，
走出去再走几米就是靶子和 Boss。

`_verify_room.gd` 把这条当成断言验：**出生点必须在房间的 xz 范围内**。

### 房间碰撞：四面盒 + 一个门洞

`game.tscn` 里 `Room609` 打开 `build_box_collision`：

| 导出项 | 值 | 说明 |
|---|---|---|
| `build_box_collision` | `true` | 用**内容包围盒**生成盒碰撞，不需要碰撞 GLB |
| `box_wall_thickness` | `0.3` | 墙厚，从包围盒面**往房间里长**（外表面正好在包围盒上） |
| `box_door_side` | `"z-"` | 门开哪一面（枚举含 `"none"` = 四面封死） |
| `box_door_width` / `box_door_center` | `1.6` / `0` | 门洞尺寸与位置 |

为什么不用 GDGS 自带那条「从点云生成碰撞网格」的管线：那要给 277 万点建体素索引
再 marching cubes，慢且结果不可控；这间房**已经轴对齐**、形状就是个矩形，
四面盒子又稳又快，而且哪面是门可以明确指定。

⚠️ 关于「门开在哪一面」本喵量过、量不出来，最后是**按玩法定的**：先试着在
「地板面 ~ +1.2 m」这条带里找墙上的空缺，结果发现这条带里**全是桌椅**（打出来的
XZ 占用图里能看到两排桌椅和中间的走道），墙在 1.2 m 以下几乎没有点；改用包围盒面
去找更糟 —— 包围盒两端那 0.1% 的离群点把面推到了墙外面（x− 面附近 0.35 m 内
**一个点都没有**）。所以门的位置是**设计选择**（朝靶场、正对出生点），不是量出来的，
换数据别指望这段代码能自动找到门。

`_verify_room.gd` §5 会真跑物理验证：撞 x+ 墙被挡在墙内面（实测停在 x = 4.86 =
墙内面 5.16 − 胶囊半径 0.3），以及从门洞走出去（z 从 6 跑到 −1.47）。

### ⚠️ 裁剪：这份数据的 floaters 必须裁，不能靠下沉

俯拍重建里总有少量又大又远的离群椭球（本份实测 0.2% 的点，单个椭球尺度可达
15.13 源单位）。校园那份靠 `top_gap = 12` 把它们顶到平台上方就看不见了，
但**摆在平台上的房间没有这个余量**，放大后它们就是糊满屏的大白团。

所以 `splat_scene.gd` 加了 `crop_enabled / crop_margin / crop_max_scale`：
按内容 1‰~99.9‰ 分位盒外扩 0.5 源单位、再丢掉椭球标准差 > 0.5 的点。
实现按**连续段**整段复制（`slice` + `append_array`），277 万点只花约 0.3 s。
⚠️ 这两个阈值是**源坐标单位**，所以和 `world_scale` 无关 —— 改缩放不用重调裁剪。

### ⚠️ 轴对齐：上一版把 288.1 当成对齐角，其实歪了 39.5°

这是本项目第二个「量法本身错了」的坑，值得单独记：

`_probe_room_layout.gd` 打印的「主轴偏角 −18.10°」是 XZ 协方差主轴 **相对 +X**
的角度，却被当成「相对 +Z」用了；而且地板只有 4.87 × 5.40 源单位，**接近正方形**，
主轴本身就不稳定。结果上一版挑的四个候选角（18.1 / 108.1 / 198.1 / 288.1）
**全都歪了 39.5°** —— 房间里所有桌椅都是斜的，出生点还正好卡在一张桌子里面。

换的量法：**墙直方图的峰值集中度** `Σn²/N²`。把点云绕 Y 转一个角度后按 x（和 z）
打 0.25 m 直方图，轴对齐时两面墙会叠进同一格形成尖峰，歪了峰就摊平。
实测：

```
墙直方图集中度（x 峰 + z 峰）
  转 0°（288.1）: 0.0188      转 −39.5°（248.6）: 0.0307
  x 轴 0.00994 → 0.02106      z 轴 0.00889 → 0.00967
```

（这组绝对值是在 ×6.4 下量的，换个缩放就变 —— ×1.8 下是 0.0925；但**要转多少度与
缩放无关**，所以角度结论照用。）

矫正后角谱在 **mod 90° 上严格重复**（矩形特征），峰正落在 0°。

这个判据自带一个**合成自检**：把点云人为转 +23°，扫描必须正好少给 23°
（实测差 0.00°），这样才不会又把符号搞反 —— 本喵在同伴朝向那轮已经栽过一次。
自检在 `_verify_room.gd` §3，换数据或换角度后重跑它，**别凭眼睛调 yaw**。

### ⚠️ 显存：两份泼溅同时加载是按「点数之和」算的

GDGS 把场上所有 `GaussianSplatNode` 的点**合并成一个 GPU 缓冲**
（`addons/gdgs/runtime/render/compute/gaussian_scene_registry.gd` 的
`merged_point_data`），而且 Compute 后端还会按总点数分配裁剪 / 排序 / 实例索引
缓冲。也就是说：

```
校园 6,150,154 + 画室 2,769,851 ≈ 892 万点
点数据        892 万 × 240 B ≈ 2.04 GiB
裁剪缓冲      892 万 × 64 B  ≈ 0.53 GiB
排序键 + 值   892 万 × 10 × 4 × 2 × 2 ≈ 1.36 GiB
                        ─────────────────
                        合计 ≈ 4 GiB（还没算渲染贴图与驱动开销）
```

本机是 RTX 4060 Laptop（8 GB），这个量级要小心。所以 `SplatScene` 加了
**场地标签** `venue` 和命令行开关：

```powershell
& $g --path $p                                            # 两份都加载（默认）
& $g --path $p -- --venue=room                            # 只加载画室609
& $g --path $p -- --venue=campus                          # 只加载校园
& $g --path $p -- --venue=all                             # 等同默认
```

⚠️ `visible = false` **不等于**释放显存：节点还在场、还在注册表里，
GPU 缓冲照样占着。要省显存就得真的按 `--venue` 只加载一份。

### 已知取舍

- **房间有碰撞、但只有四面墙**：地板靠平台自己的 `Floor`（房间地板泼溅不参与物理），
  桌椅、画架**都没有碰撞**（点云不生成碰撞网格），所以你会穿过桌子 —— 只有墙挡得住
- **天花板离相机只有 0.78 m**：真人尺度下天花板不可避免会占掉画面上部，而高斯
  在掠射角会糊（`70_spawn.png` 上半屏那片灰就是这个）。要缓解只能加大 `world_scale`
  （×2.6 → 3.3 m 天花板）或降低相机高度
- **从房间外面看是糊的**：这份扫描只扫了室内，外墙背面没有重建。所以门是朝靶场开的、
  房间罩着出生点，尽量让你少看外墙
- **墙是「内容包围盒」做的盒子**，比可视墙面可能差十几厘米：包围盒是 1‰~99.9‰
  分位盒，两端那 0.1% 的离群点会把面往外推一点。要更贴就调 `box_wall_thickness`
  或者以后接 GDGS 的碰撞管线
- **门是设计出来的，不是量出来的**（见上面那节）。门在 z−、宽 1.6 m、正对出生点
- **出生点在房间里、面朝门**：出生点 (0, 0.05, 6) 在房间中段，正前方是过道、再往前
  是门；想换个开场位置就改 `game.tscn` 里 Player 的 transform —— 但那会影响
  §1.11 里几条射击自检的弹道，改之前先看 §1.4 和 §7.2 的注释
- **平台没有护栏**（用户要求删掉）：走出 40 × 40 就掉下去，y < −60 由保险送回出生点
- HUD 左上角是**一场一行**（`hud.gd` 的 `bind_splats()`），两份同时解码时
  能分清是哪一份在等

### 自检

```powershell
& $g --path $p --script res://scripts/_verify_room.gd      # 57 项
```

它会在**入树前**把校园那份摘掉（`_ready()` 是 `add_child` 时才跑的，此刻摘掉就不会
开始解码），然后验：场景结构 / 点数与裁剪统计 / 地板 y 与质心 / **出生点在房间里** /
**相机到天花板的余量** / 世界尺寸 / 轴对齐（含合成自检）/ floaters 是否真裁干净 /
**墙碰撞与门洞（真跑物理）** / HUD 多行是否按行号路由 / Arisu 的朝向 / 7 张渲图。

---

# 七、Boss（木桩阶段）：霸王龙优香 + 飞猪优香

两位 Boss 都是「木桩」：站在平台上、吃得下子弹、受击闪白、打光后扑倒并在数秒后站起来；
AI / 冲撞 / 吐息留待后续。两者**共用 `scripts/boss.gd`**，但在「怎么量尺寸」上是两条路（见 §7.6）。

|  | 霸王龙优香 | 飞猪优香 |
|---|---|---|
| 来源 | `压缩文件_by_一个睿智_….rar` → `优香霸王龙.fbx` | `飞猪优香 (2)_by_一个睿智_….zip` → `猪猪优香.fbx` |
| 有骨骼吗 | ✅ 73 根（名字全是 `Bone`/`Bone.001`… 未命名） | ❌ 纯静态网格 |
| 有动画吗 | ❌ 空动画栈 | ❌ 没有 |
| 定尺寸靠 | **骨架**包围盒 `_bone_box()` | **网格**包围盒 `_mesh_box()` |
| 本体朝向 | +Z | +Z（鼻子 z=+2.17、尾巴 z=−1.95） |
| 场上位置 | `(13, 0, −8)`，绕 Y −90° 朝 −X | `(−13, 0, −8)`，绕 Y +90° 朝 +X |
| 身高 / 血量 | 4.5 m / 3000 | 2.6 m（含光环）/ 1800 |

## 7.1 这个 FBX 里有什么

| 你可能会问 | 答案 |
|---|---|
| 有 glb 吗 | ❌ 没有，是 **FBX**（版本 7400，12.1 MB）+ 3 张 PNG 贴图 |
| 有动画吗 | ❌ **没有**。Godot 导入后连 `AnimationPlayer` 都没有；二进制里 `AnimStack = 1` 但 `KeyTime`/`KeyValueFloat` **全是 0**，也没有 `AnimCurveNode`/`AnimLayer` —— 是 Blender 导出时留下的**空动画栈** |
| 有什么 | 73 根骨骼（名字全是 `Bone`/`Bone.001`… 未命名）、9 个网格、约 **31 万三角形**、5 个材质、4 个 `BoneAttachment3D` 挂件 |

诊断工具：`scripts/_probe_boss.gd`（节点树/骨骼/动画/材质）、
`..\_godot\probe_fbx.py`（不导入直接扫二进制）。

## 7.2 ⚠️ 两个坑（都踩过，改参数前务必看）

**① 网格顶点在「绑定空间」，跨度是骨架的约 298 倍 —— 必须保留蒙皮。**

- 网格顶点算出来的世界包围盒是 **8732** 单位，而**蒙皮后**的模型只有 **29.3 高 / 82 长**
- 本喵按 8732 取景 → 渲出来是「一个像素点」，一度以为模型塌了
- 反过来把 `skin = null` 想当刚性网格用 → 形状散成一片「刀刃」（顶点靠蒙皮才成型）
- **正确做法**：用 **骨架的世界包围盒**（`get_bone_global_pose`）归一化

**② 材质里没有 albedo 贴图 → 整只白模，而且必须「按材质分别绑」。**

3 张贴图跟 3 个材质名是一一对应的（认名字 + 看内容都能对上）：

| 材质 | 贴图 | 内容 |
|---|---|---|
| `材质`（4 个身体部件共用） | `tex/boss_body.png`（原 `身1.png`，71 KB） | 紫皮躯体展开图（UV 岛形状就是一条龙），带优香的白衬衫/黑马甲/蓝领带 |
| `2501_other`（胸牌） | `tex/boss_props_atlas.png`（原 `other_BaseColor.png`，1.9 MB） | MILLENNIUM 校徽 + 工牌条码 + 皮带扣图集 |
| `材质.001`（球/嘴） | `tex/boss_mouth.png`（原 `材质.001 Base Color.png`，53 KB） | 淡紫底 + 锯齿牙齿 |

❌ 本喵第一版把 1.9 MB 的 `props_atlas` 糊到**身体**上 → 整只变成"一件校服"。
排 3! = 6 种组合渲图对比后（`scripts/_probe_boss_texperm.gd`，
对照图 `_arisu_captures/_boss/90_texperm_sheet.png`），正确的就是**组合 5**：
身体=`身1`、胸牌=`other`、球=`材质.001`。

**③ 挂件不用隐藏（本喵之前判断错了）。** 光环/胸牌/球/方块按**真实渲染尺度**都是合理的：

- 光环 1.31 × 0.64 × 1.36 m，飘在头顶 `y = 5.59`（身体高 4.5）
- 胸牌 0.13 m 在胸前，球 0.68 m 在头侧，方块 0.6~0.8 m

之前判成「缩放差 1~2 个数量级」是拿**蒙皮前的 8732** 当参照算的，参照系就是错的。
`boss.gd` 的 `hide_accessories` 现在默认 `false`（想只留身体再打开）。

还有一个更隐蔽的坑：归一化的偏移量必须在 **Boss 节点自己的局部空间**里算。
`game.tscn` 里 Boss 绕 Y 转了 −90°，本喵第一版在世界空间量框、却当局部坐标用，
结果水平居中歪 1.8 m、长短轴被转错（12.6 m 长轴记到 x 上）、碰撞盒跟着变形。

## 7.3 现在的接法

`scripts/boss.gd`（`class_name Boss`，`extends StaticBody3D`）：

| 参数 | 默认 | 说明 |
|---|---|---|
| `display_name` | `霸王龙优香` | HUD 血条上显示的名字 |
| `model_path` | `res://models/boss/优香霸王龙.fbx` | |
| `TEXTURES`（常量表） | 见 §7.2 ② | **霸王龙的默认**材质名 → 贴图路径表 |
| `texture_map` | `{}`（空 = 用上面的表） | 逐实例覆盖；飞猪就是靠它绑自己那 4 个材质（§7.6） |
| `height` | **4.5 m** | 目标身高，脚本按包围盒自动缩放（约 2.6 个 Arisu） |
| `max_health` | 3000 | 顶部血条显示 |
| `respawn_time` | 6.0 s | 扑倒后多久站起来 |
| `hide_accessories` | **false** | 想只留身体（隐藏光环/胸牌/球/方块）就打开 |
| `body_name_prefix` | `Tyrannosaurus` | 上面那个开关**只保留**名字带这个前缀的网格 |
| `collision_factors` | `(0.55, 0.85, 0.62)` | 碰撞盒 = 归一化尺寸 × 这三个系数 |

- 位置：`game.tscn` 里 `(13, 0, -8)`，绕 Y −90° 朝 **−X**（正对场地中心；模型自身脸朝 +Z）
  - ⚠️ **x 不能小于 13**：放在 x=9 时它的碰撞盒（约 7.8 m 长）会横在
    「玩家 (6,−4) → Target1 (6,−10)」的弹道上，把每一发都吃掉。
    本喵就是这么踩的 —— 加完 Boss 后 3 套自检同时红，弹道日志里每发都写着「命中 Boss」
- 碰撞：一个随 `visual_size` 自动算的 `BoxShape3D`（约 2.1 × 3.8 × 7.8 m，只盖身体不含尾巴）
- 受击：即时闪白 + 渐退；`take_damage(amount, pos, dir)` 与 `Target` **同一套契约**，
  所以 `weapon.gd` 不用改一行就能打它
- 血条：HUD 顶部**一位 Boss 一条**（`hud.gd` 的 `bind_bosses`，按场景里 Boss 子节点的顺序排行；
  旧的单条 `bind_boss` 保留着）。加第二位 Boss 时就是把单条改成了一组

自检 `scripts/_verify_boss.gd`（19 项，含「从玩家位置打射线必须命中 Boss 本体」）：

```powershell
& $g --path $p --script res://scripts/_verify_boss.gd -- --splat=off
```

## 7.4 想调大小 / 位置

- **大小**：改 `game.tscn` 里 Boss 节点的 `height`（2.5 就差不多一辆车那么大，
  6.0 会把平台压得很满；实测 4.5 时占 3.85 × 4.5 × 12.6 m）
- **位置/朝向**：改 Boss 节点的 `transform`。模型脸朝 +Z，所以绕 Y −90° 就是朝 −X
- **血量**：`max_health`；血条会自动跟着变（低于 25% 变红）

## 7.5 下一步（行为）

现在没有骨骼动画（两个模型本身都没动作），所以「活起来」只能靠位移 + 特效 + 程序化微动：

- **霸王龙**：73 根骨还在，所以「张嘴 + 摆尾 + 点头」这类程序化动作是有戏的
- **飞猪**：没有骨，只能在节点层级上做（上下漂浮 / 滚过来撞人 / 光环自转）

本喵给过的三个方向：冲撞型 / 远程吐息型 / 站桩强化型 —— 你当时选了先看木桩，
要继续的话说一声即可。

## 7.6 第二位 Boss：飞猪优香（纯静态网格）

来源：`飞猪优香 (2)_by_一个睿智_….zip`（作者：**一个睿智**）→ `猪猪优香.fbx` + `uv/` 6 张图。
`uv/1.png` 与 `uv/2.png` 是**作者的成品渲染图**（1920×1080，FBX 并没引用它们），
已挪到 `models/boss_pig/ref/author_render_1.png` 当作贴图分配的对照基准。

**为什么它不用改玩法代码就能当第二个 Boss** —— 三条实测结论：

1. **没有骨骼、没有动画。** 二进制里 `Deformer = 0`、`KeyTime = 0`；Godot 导入后是
   4 个网格 / 1.27 万三角形 / 没有 `Skeleton3D` / 没有 `AnimationPlayer`。
   所以尺寸只能靠**网格包围盒**量 —— `boss.gd` 现在分两条路：
   有 `Skeleton3D` 走 `_bone_box()`，没有走 `_mesh_box()`。
   ⚠️ 两条路**别用混**：拿网格盒去量霸王龙会得到 8732 单位的荒唐大盒子（见 §7.2 ①）。
2. **Godot 的 ufbx 其实已经把 4 个材质的贴图各自绑好了**（`uv\xxx.png` 这种相对路径也解析
   成功了），但工程里仍然用 `texture_map` **显式再绑一次**，免得依赖 FBX 里的路径能不能解析：

   | 网格 | 材质名 | 贴图 |
   |---|---|---|
   | `立方体`（身体） | `材质` | `tex/pig_untitled1.png`（原 `未标题-1.png`，5670×4251） |
   | `立方体_001`（鼻子） | `材质.001` | `tex/pig_nose.png`（原 `鼻子.png`） |
   | `贝塞尔曲线`（尾巴） | `材质.002` | `tex/pig_tail.png`（原 `尾巴.png`） |
   | `Yuuka_Original_Halo_0`（光环） | `Yuuka_Original_Halo_0Mat` | `tex/pig_halo.png`（512×512） |

   材质名的命名习惯（`材质` / `材质.001`）跟霸王龙**一模一样，含义却完全不同** ——
   照抄霸王龙那张表会把猪贴成一团。这就是 `texture_map` 做成逐实例覆盖的原因。
3. **本体朝 +Z**，与霸王龙同一套约定，不需要补 180°。判据是网格中心而不是肉眼：
   鼻子 `立方体_001` 在 z = +2.17、尾巴 `贝塞尔曲线` 在 z = −1.95、光环在 y = 1.44。
   所以节点绕 Y 转 +90° 就朝 +X（面向场地中心）。

**位置为什么是 x = −13。** 霸王龙当初放在 x=9 时吃掉了「玩家(6,−4) → Target1(6,−10)」那条
自检弹道（§7.3 里那条教训），所以这次先算再摆：猪长轴沿世界 X、占 x ∈ [−15.0, −11.0]、
z ∈ [−9.2, −6.8]，离 x = 6 有 5 m 余量。`_verify_boss_pig.gd` 现在**常驻**这条回归断言。

归一化结果：**2.33 × 2.6 × 4.11 m**（目标身高 2.6 m 含光环，约 1.5 个 Arisu 高），
碰撞盒 **1.98 × 2.08 × 3.08 m** —— `collision_factors = (0.85, 0.8, 0.75)`，
比霸王龙那套（0.55/0.85/0.62）宽：猪的身体占自身包围盒的比例大得多（没有长尾巴和长脖子）。

自检 `scripts/_verify_boss_pig.gd`（33 项，含贴图逐条核对、朝向、双血条互不串台）：

```powershell
& $g --path $p --script res://scripts/_verify_boss_pig.gd -- --splat=off
```

⚠️ 写这个自检时踩的一个坑：**别靠遍历顺序认血条。**
`_all()` 是拿栈做的深度遍历，弹出来是**倒序**，所以 `bars[0]` 其实是 `BossBar1`。
本喵先试了 `bars.sort_custom(func(a, b): return a.name < b.name)`，**实测没生效**（顺序照旧），
于是连着两轮把「打霸王龙掉的是飞猪那条」误判成游戏的 bug —— 其实 `hud.gd` 一直是对的
（日志里写着「打霸王龙 300 后：第 1 条 1.000，第 2 条 0.900」，掉血的是霸王龙那条）。
最后改成 `hud.get_node("BossBar0")` **按名字取**，既明确又顺便验了命名约定。

对照图：`_arisu_captures/_boss/94_pig_front.png`（正面）、`95_pig_three_quarter.png`
（3/4，与作者的 `author_render_1.png` 同角度）、`93_pig_from_spawn.png`（出生点视角，两位 Boss 同框）。

---

# 八、同伴（跟随 NPC）：未花 / 优香 / 诺亚 / 小桃 / 小绿 / 柚子 / 凯伊

**七名同伴****只跟随、不开火**（你选的「纯观赏」）。模型用 `tools\Find-BlueArchiveModel.cmd`
从 BlueArchiveModels 里取的**初始形态**（不带 `(Swimsuit)` / `(Battle)` / `(Cut-in)` /
`(Maid)` / `(Pajama)` / `(Prototype)` 那些变体）：

| 同伴 | 模型 | 骨架 | 动画数 | 站位（玩家局部坐标） |
|---|---|---|---|---|
| 未花 Mika | `Mika.glb` | 145 骨 | 33 | `(−2.0, 0, +0.9)` 左后 |
| 优香 Yuuka | `Yuuka.glb` | 108 骨 | 38 | `(+2.0, 0, +0.9)` 右后 |
| 诺亚 Noa | `Noa.glb` | 135 骨 | 31 | `(−3.0, 0, −3.2)` 左前 |
| 小桃 Momoi | `Momoi.glb` | 105 骨 | 37 | `(+3.0, 0, −3.2)` 右前 |
| 小绿 Midori | `Midori.glb` | 105 骨 | 31 | `(+2.4, 0, −4.6)` 右侧更远 |
| 柚子 Yuzu | `Yuzu.glb` | 122 骨 | 30 | `(−2.4, 0, −4.6)` 左侧更远 |
| 凯伊 Kei | `Kei.glb` | 166 骨 | 32 | `(−5.2, 0, −1.4)` 最左 |

七只都自带 `Normal_Idle` / `Cafe_Walk` / `Move_Ing`，所以直接复用了主角那套 `AnimDriver`。
（`Move_Jump` 只有前四只有，但跟随逻辑没用到它。）

> 这批 GLB 的**贴图是内嵌的**（`glb_info.py` 实测：Momoi 13 张、Kei 22 张 image 全部走
> bufferView），所以只要拷 `.glb`，不用像早期那样连 PNG 一起搬。

`Find-BlueArchiveModel.cmd` 的匹配规则是 `^Mika(?:\s|$)` 这种前缀，
所以 `未花` 会同时命中 `Mika.glb`、`Mika (Swimsuit).glb`、`Mika (Cut-in).glb` ——
`-CopyTo` 会把三个都复制过去，只要初始形态的话得自己挑（两次都是这么挑的：
`Mika.glb` / `Momoi.glb` / `Midori.glb` / `Yuzu.glb` / `Kei.glb`）。

> 凯伊有 **4 个 skin / 2 个 Skeleton3D**（`Kei.glb`：166 + 21 + 6 + 1 骨）。
> `AnimDriver` 找的是「树里第一个」而不是「骨头最多的那个」，所以别只看骨头数 ——
> 用 `_probe_companion_row.gd` 量**骨骼姿态随时间的变化**（实测 166 骨那个在动，30.2°）。

## 8.1 ⚠️ 同伴必须待在单独的「朋友层」（`collision_layer = 2`）

这是加同伴最容易踩的地方，两个理由：

1. **子弹要穿透同伴。** `weapon.gd` 的射线是 `PhysicsRayQueryParameters3D.create(origin, end)`，
   它的 `collision_mask` 默认是**全部层**。同伴贴着玩家走，不屏蔽的话玩家会一直打在
   自己人背上（表现是「明明瞄着靶子，却一发都打不中」）。所以：
   ```gdscript
   q.collision_mask = 0xFFFFFFFF & ~Companion.LAYER   # 除朋友层之外全都要
   ```
   自检里有一条**反向对照**：不屏蔽时射线确实命中同伴 —— 证明这条屏蔽不是多余的。
2. **玩家和相机不该被同伴顶住。** 玩家的 `collision_mask` 是默认的 1，相机的
   `SpringArm3D.collision_mask` 也是 1，都碰不到第 2 层。于是同伴只跟世界层
   （地板 / 画室609 的墙 / 靶子 / Boss）碰撞，彼此之间也不挤。

## 8.2 ⚠️ 站位不能落在「相机 ↔ 玩家」之间

相机挂在玩家背后 3.4~4.2 m，`fov = 62°`（垂直；16:9 换算成水平半视角约 47°）。
本喵第一版把第三名同伴放在**正后方 2.4 m** —— 它距相机只剩 1.8 m，一块 1.6 m 高的人形
在画面里能占掉近一半高度，视野直接被自己人糊住。

所以七只都在**侧前方/侧后方**：横向 2.0~5.2 m、纵向 −4.6~+0.9 m。
`_verify_companion.gd` 第六节守这条约束，量的是四件事：

- **离相机 > 2.5 m**（不许糊脸）
- **屏幕高度 < 视口高的 60%**
- **不在画面正中央 20% 宽度内**（不挡准星）
- **两两屏幕间距 > 60 px**（七个人互相不重叠）

> **还有一条是加完之后才发现的**：站位是跟着**相机绕角**转的，所以两个人的
> 「侧向 ÷ 纵深」比例只要相同，在屏幕上就会**永远重叠** —— 相机怎么转都分不开。
> 诺亚原来在 `(−2.9, +0.9)`，与未花的 `(−2.0, +0.9)` 几乎同一条视线，
> 屏幕 x 分别是 451 / 463（白加一个人）；加到七个人时更要小心，因为可用的
> 屏幕宽度要分给七条视线。
>
> 站位别手算三角函数 —— 本喵算了两次都错（相机实际在玩家背后 **4.20 m**、
> 横向 **−0.42 m**、高 **1.79 m**，FOV 的换算也不是「垂直 62° 直接除」）。
> 用 `scripts/_probe_slot.gd` **扫一遍候选**最省事，它把每个 slot 投到屏幕上，
> 并给出「与**已在场那几位**的最小屏幕间距」这一列：

| slot (x, z) | 屏幕 x | 与已有最小间距 | 离相机 | 离玩家 |
|---|---|---|---|---|
| `(−2.0, +0.9)` 未花（已有） | 442 | — | 4.23 m | 2.19 m |
| `(+2.0, +0.9)` 优香（已有） | 1348 | — | 4.62 m | 2.19 m |
| `(−3.0, −3.2)` 诺亚（已有） | 539 | — | 8.24 m | 4.39 m |
| **`(−5.2, −1.4)` 凯伊（采用）** | **161** | **281 ✓** | 7.57 m | 5.39 m |
| **`(−2.4, −4.6)` 柚子（采用）** | **632** | **93 ✓** | 9.19 m | 5.19 m |
| **`(+2.4, −4.6)` 小绿（采用）** | **1040** | **308 ✓** | 9.41 m | 5.19 m |
| **`(+3.0, −3.2)` 小桃（采用）** | **1146** | **202 ✓** | 8.34 m | 4.39 m |
| `(+5.2, −1.4)` ❌ 太靠边 | 1551 | 203 ✓ | 8.13 m | 5.39 m（离右边缘只剩 49 px） |
| `(−4.4, −3.0)` ❌ 撞诺亚 | 386 | 56 ✗ | 8.42 m | 5.33 m |
| `(−1.4, −4.6)` ❌ 挡准星 | 717 | 178 ✓ | 9.03 m | 4.81 m（偏离中心只有 83 px） |

> 判据：**偏离画面中心 > 160 px**（不挡准星）、**两两间距 > 60 px**（都看得见）、
> **离相机 > 2.5 m**。这三条现在都写进 `_verify_companion.gd` 第六节了。
> 最终七人的屏幕 x = **[161, 442, 539, 632, 1040, 1146, 1348]**，两两最小间距 **93 px**。

> 判据为什么不是「不许进画面中心 50% 区域」：水平 FOV 有 94°，中心 50% 宽对应 ±28°，
> 而侧后方站位本来就在 20~25°，用固定矩形会把**正常站位**判红 —— 本喵第一版就这么
> 假红了三条。

## 8.3 跟随逻辑（`scripts/companion.gd`）

- 目标点 = 玩家位置 + `slot` 按**玩家相机绕角**旋转。用相机绕角而不是角色朝向，
  是为了甩视角时同伴绕到新的侧后方，而不是绕进画面正中央
- `walk_speed = 2.2`、`run_speed = 6.4`
  - ⚠️ `walk_speed` 刻意压在 **2.4 以下**：`AnimDriver` 在 2.4 m/s 才切到 `Move_Ing`，
    高过它的话「站位差 1 m」这种微调也会播跑步动画，看起来像在打滑
- 站住不动时**跟玩家看同一个方向**（像一队人），走动时朝行进方向
- 两条保险：离站位 > 26 m、或掉到 y < −60（跟 `game.gd` 的 `FALL_LIMIT` 同源）→ 直接拉回
- 动画驱动：`player.tscn` 里 `AnimDriver` 是写死 NodePath 的，但三只 GLB 的内部节点名
  互不相同。所以给它加了兜底：**两个 NodePath 都留空时，先在自己所在的模型子树里找**
  `AnimationPlayer` / `Skeleton3D`（见 `anim_driver.gd::_ready`）

## 8.4 自检

```powershell
& $g --path $p --script res://scripts/_verify_companion.gd -- --splat=off
```

**100 项**：模型/骨架/动画绑定、朋友层、子弹穿透（含反向对照）、跟随（玩家瞬移 14 m 后
七名都跟到位）、站定回 Idle、掉出平台被拉回、不挡镜头（离相机远近 / 屏占比 / 偏离中心 /
两两屏幕间距）、**朝向 + 接地**（见 §8.5）、两张渲图
（`_arisu_captures/_companion/80_spawn_with_companions.png` / `81_companions_group.png`）。

⚠️ 写这类「移动类」断言时的两个坑（都踩过）：

1. **瞬移完玩家必须等同伴走回来再量。** 第一版量到的是还在 14 m 外往回赶的三个小点，
   屏幕坐标全挤在画面中心，白红三条。
2. **等物理要用 `await physics_frame`，不要用 `await process_frame` 数帧。**
   渲染帧率一高，「等 200 帧」可能只过了几十毫秒；补间动画同理，要按**真实时间**等
   （`_verify_boss_pig.gd` 里等重生那段就是按 `Time.get_ticks_msec()` 等的）。

## 8.5 ⚠️ 同伴曾经「倒着走」——判朝向时漏了一层坐标变换

**现象**：七只同伴跟着你走的时候，是**背朝行进方向**的（脸看着镜头往前走）。

**根因**：`companion.gd` 给 `Rig` 补了 180°，依据是上一轮 `_probe_companion.gd`
量出来的「这批 GLB 本体朝 −Z」。而那条结论是**错的**，错在量 `(Toe − Foot)` 时
只用了骨骼空间：

```gdscript
# ❌ 错的：bone_global_pose 是**骨骼空间**的
var d := skel.get_bone_global_pose(toe).origin - skel.get_bone_global_pose(foot).origin
# ✅ 对的：要乘 skeleton 的 global_transform 才是模型/世界方向
var xf := skel.global_transform
var d := xf * skel.get_bone_global_pose(toe).origin - xf * skel.get_bone_global_pose(foot).origin
```

这批 GLB 的 **`Skeleton3D` 节点自带 180°**，所以骨骼空间与模型空间正好差一个符号 ——
量出来是 −Z，实际是 **+Z**。于是 Rig 被多翻了 180°，而 `_physics_process` 又把
「节点 +Z」设成移动方向 → 脸朝的就是移动方向的**反面**。

**三条独立判据都指向 +Z**（改的时候一条就够，但三条一起才敢下结论）：

1. **单独实例化 GLB**（不套 `companion.tscn`、Rig 不参与）：世界坐标下
   「两眼中点 − 头骨」= `(0, 0, 0.056)`，**正好 +Z 且几乎没有横向偏移** —— 七只全一样
   （`_probe_companion.gd` 的「眼骨判据」行）
2. **躯干朝向**：绑定姿态下「右腿 − 左腿」× 上方向（`_verify_companion.gd::_rest_torso_forward`）
3. **渲图**：同一排人，相机在 **+Z** 侧看到的是**正脸**、在 −Z 侧是后脑勺
   （`scripts/_probe_companion_row.gd` 的 `row_front.png` / `row_back.png`，
   一次渲七个，一眼就能比出来）

**修法**：`rig.rotation.y = PI` → `0.0`（`companion.gd::_build_model`）。
玩家 Arisu 不受影响：`player.gd` 每帧直接写 `model_root.rotation.y`，
`player.tscn` 里那个历史遗留的 180° 会被覆盖掉，`_verify_facing.gd`（世界坐标、眼骨）
也一直是过的。

### 判朝向的量法：三个坑

| 坑 | 症状 | 正确做法 |
|---|---|---|
| 漏乘 `skeleton.global_transform` | 符号整个反（就是上面这个 bug） | 一律换成世界坐标再比 |
| 用**当前姿态**量 | 动画把脑袋转过去，点积被带偏 60°（未花/诺亚量到 +0.49/+0.38） | 用绑定姿态 `get_bone_global_rest`，或至少只判半轴 |
| **叉乘写反** | `右 × 上 = −前`，七只集体判成「反了」 | 面朝 +Z 的人右手在 −X 侧 → **前 = 上 × 右** |

**回归锁**：`_verify_companion.gd` 第七节，每只同伴断言
「躯干朝向 · 节点+Z > 0.2」+「眼骨方向 > 0.2」+「脚骨世界 y 在 ±0.15 内」。
阈值取 0.2 而不是 0.5：这批骨骼判据有固有残差（眼骨横向偏移、绑定姿态不是 T-pose），
实测在 **+0.35 ~ +1.00** 之间浮动；而判反的那一版是 **−0.35 ~ −1.00**，
符号完全分开，0.2 这条线抓得住。

> 顺便修正了一个**旧文档结论**：`companion.gd` 文件头和 README §8.1 原来都写着
> 「三只 GLB 的本体都朝 −Z（跟 Arisu 同一套导出）」—— 现在是「本体朝 +Z，Rig 不要动」。

## 8.6 想再加一名同伴

1. 把 glb 放进 `models/companions/`（已在 `.gitignore` 里，不会进仓库）
2. 在 `game.tscn` 里复制一个 `CompanionMika` 节点，改 `display_name` / `model_path` / `slot`
3. 跑一次 `--import` 刷新类缓存（新 `class_name` 必须先导入才认），再跑 `_verify_companion.gd`

`game.gd` 是**按类型**收同伴与 Boss 的（不遍历写死的节点名），所以加人不用改代码。

---

# 九、下一步

1. ~~**重做 `Move_Ing`** —— 跑动前倾偏大（见 §1.10），走 Blender 管线改躯干角度~~
   **已完成并启用**：`Move_Ing` 胸腔前倾 Blender 侧 +13.5° → +5.2°、
   Godot 侧复测 +36.5° → +29.6°；`player.tscn` 已切到 `Arisu_ext.glb`（§5.1 / §5.4.1）
2. **接跳跃/翻滚动画** —— `Jump_Start` / `Jump_Land` / `Dodge_Roll` 就在现在引用的
   `Arisu_ext.glb` 里（`anim_driver.gd` 加两个 `_play_once` 状态即可），
   但 `player.gd` 的跳跃目前是纯物理、没有动画；翻滚还没实现
3. **把枪修到手上** —— 见 §1.9 三种方案，观感提升最明显
4. **写 toon 着色器** —— 18 个材质换 `ShaderMaterial`，加描边和硬边明暗
5. **动画分层** —— 现在开火会整体覆盖跑动；想「边跑边射」需要 upper/lower body 分层
6. **清掉泼溅的 floaters** —— 见 §6.5 已知瑕疵，用 `splat-transform` 重新过滤数据
7. **换原创素材** —— 换掉模型与泼溅数据后本工程才能真正对外发布（见第十节）

---

# 十、开源与许可

## 10.1 结论

**除模型与美术素材外，本仓库全部以 [MIT](LICENSE) 授权。**
逐项清单见 [THIRD_PARTY.md](THIRD_PARTY.md)。

| 内容 | 许可 | 在仓库里？ |
|---|---|---|
| 本项目作者编写的全部代码与文档（`scripts/`、`scenes/`、`project.godot`、README…） | **MIT** | ✅ |
| `addons/gdgs/`（GDGS 3.3.0，ReconWorldLab） | MIT（作者原许可保留在 `addons/gdgs/LICENSE`） | ✅ |
| `models/Arisu*.glb` + 解包贴图 | © NEXON Games / Yostar，**专有** | ❌ 被 `.gitignore` 排除 |
| `models/companions/*.glb`（未花 / 优香 / 诺亚 / 小桃 / 小绿 / 柚子 / 凯伊） | 同上，**专有** | ❌ 被 `.gitignore` 排除 |
| `models/boss/优香霸王龙.fbx` + 贴图 | 派生自 Blue Archive，**专有** | ❌ 被 `.gitignore` 排除 |
| `models/boss_pig/`（飞猪优香 FBX + 贴图，作者：一个睿智） | 派生自 Blue Archive，**专有** | ❌ 被 `.gitignore` 排除 |
| `splatdata/*.sogdata`、`models/school.collision.glb` | 权利状态未核实 | ❌ 被 `.gitignore` 排除 |
| `icon.png` | 待仓库作者确认 | ✅（如非原创请替换） |

## 10.2 克隆者怎么跑起来

```powershell
git clone <你的仓库>
cd <仓库目录>
# ① 放入你自己合法获得的角色模型（必需）
#    models/Arisu_ext.glb     见 models/README.md
# ② 可选：七名同伴（没有就删掉 game.tscn 里那七个 Companion 节点）
#    models/companions/{Mika,Yuuka,Noa,Momoi,Midori,Yuzu,Kei}.glb
# ③ 可选：两位 Boss（没有就删掉 Boss / BossPig 节点）
#    models/boss/优香霸王龙.fbx + 贴图、models/boss_pig/猪猪优香.fbx + 贴图
# ④ 可选：放入泼溅数据（没有就用 --splat=off；只想留一份就用 --venue=，见 §6.8）
#    splatdata/school_playable.sogdata、splatdata/room609.sogdata   见 splatdata/README.md

& <godot 4.7 mono 版> --path .              # 有泼溅数据
& <godot 4.7 mono 版> --path . -- --splat=off   # 没有泼溅数据
```

第一次打开时 Godot 会自动导入 glb / fbx 并解包贴图，然后就能 F5。

## 10.3 发布自己的版本前的检查表

- [ ] `models/` 换成**你有权分发**的模型（或明确许可允许再分发的模型），
      含 `models/companions/` 与 `models/boss_pig/` 这两处新加进来的
- [ ] `splatdata/` 换成你有权分发的场景数据，或删掉该目录并只用 `--splat=off`
- [ ] 确认 `models/README.md` 里那三个换模型注意点（骨名 / 动作名 / 朝向约定）都过了
- [ ] `LICENSE` 里的版权行改成你的名字与年份
- [ ] `THIRD_PARTY.md` 删掉已不适用的条目，补上你新引入的第三方资源
- [ ] `icon.png` 换成你自己的图标
- [ ] 检查 `.gitignore`：`git status` 里**不该**出现任何 `.glb` / `.sogdata` / 大体积贴图
- [ ] 顺手确认没把 `..\_blender_arisu\`（专有模型的派生数据）一起推上去

## 10.4 关于截图

`_arisu_captures/` 里的截图是在本机渲染的、含专有角色形象，
**不建议**放进公开仓库的 README（截图是模型形象的派生作品）。
想放演示图，请先用**你有权分发的素材**重新渲一遍。
