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
| `W A S D` / 方向键 | 相对相机移动（**四个方向都能跑**，见 §1.15） |
| `Shift` | 跑动（**6.8 m/s**，比走路快 2.8 倍） |
| `Ctrl` | 蹲行（1.3 m/s） |
| `空格` | 跳跃（峰值 **1.32 m**、滞空 0.70 s，见 §1.15） |
| 鼠标右键（按住） | **开镜**：相机拉近过肩、FOV 62→34、散布收窄、移速降到 1.9 m/s |
| **鼠标左键（按住）** | **开火**：约 13 发/秒，**60 发弹匣**。打空自动换弹，**换完不用再点一次，按住就继续射**。**背对准星时不会开枪，会先转身** |
| `R` | 手动换弹（1.05 s）。手动换弹同样不打断「按住」状态 |
| 鼠标移动 | 视角 |
| `Esc` | **打开 / 关闭设置界面**（打开时暂停游戏并释放鼠标，便于用鼠标拖滑块；再按一次回到游戏）。见 §1.12 |
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
scenes/mesh_hut.tscn      手工网格小屋：基元 + CSG（§1.13）
scenes/parkour.tscn       跑酷路线：10 块落脚板 + 窄梁 + 信号塔岛（§1.16，**世界坐标**写的）
scripts/player.gd         移动积分、相机、朝向、开火转身门控
scripts/companion.gd      同伴跟随：站位 / 走近跑近 / 朋友层（第八节）
scripts/parkour.gd        跑酷总控：路线顺序 + 摔落回检查点 + 回平台传送台（§1.16）
scripts/anim_driver.gd    动画驱动（直接用 AnimationPlayer）
scripts/weapon.gd         射线命中、弹药、换弹、弹丸、开火门控、特效
scripts/target.gd         可击毁靶子（掉血 → 闪白 → 塌下 → 4 秒重生）
scripts/boss.gd           Boss 基类（建模 / 碰撞 / 贴图 / 血量 / 受击闪白 / 倒地重生）
scripts/boss_attacker.gd  Boss 攻击机制：预警圈 = 伤害区、冷却、击退（§7.5）
scripts/trex_boss.gd      霸王龙优香（重击型）：参数 + 蓄力低头（§7.5）
scripts/pig_boss.gd       飞猪优香（骚扰型）：参数 + 蓄力上蹦（§7.5）
scripts/companion_gun.gd  同伴的枪：自己选目标开火，不误伤 / 不隔墙（§8.7）
scripts/hud.gd            准星、弹药、状态、速度、换弹条、Boss 血条组
scripts/game_settings.gd  全局设置：存值 / 落盘 / 广播（**静态类**，§1.12）
scripts/settings_menu.gd  Esc 设置界面：代码构建 UI + 暂停 + 像素皮肤（§1.12）
scripts/ui_skin.gd        界面皮肤（两套）+ 血条 / MC Boss 条样式 + 中文字体（§1.12 / §9.5）
scripts/story_script.gd   剧情剧本解析 + 校验（**静态类**，第九节）
scripts/dialogue_box.gd   剧情对话框：打字机 / 翻页 / 播放时暂停世界（第九节）
scripts/game.gd           玩法总控（按类型收 Boss / 同伴；进关卡开播剧情）
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
自己按速度在 `Normal_Idle` / `Move_Ing` 之间切（带 0.18 s 交叉淡入），
用 `speed_scale` 让播放速率跟着实际速度走。一次性动作用 `animation_finished` 回落。

**动作命名与实际内容相反**（按脚的摆幅和时长判定）：

- `Move_Ing`（0.67 s，脚摆 ±0.16 m）= **跑 / 走都用它**（战斗移动动画）
- `Cafe_Walk`（1.27 s，脚摆 ±0.03 m）= 蓝档咖啡厅的**漫步** —— **本工程不用**，
  因为它**不拿武器**（素材把武器骨 scale 缩到 ≈0），§1.17 有完整的实测与取舍

> ⚠️ 这条「按速度切 `Cafe_Walk` / `Move_Ing`」曾经存在过（阈值 `WALK_THRESHOLD = 2.8`），
> 后来**删掉了**：它会让走动时把手里的枪藏起来，小桃/小绿还会多出个游戏机。
> 现在走 / 跑 / 蹲 / 开镜**都播 `Move_Ing`**，快慢只靠 `speed_scale` 区分。
> 详见 **§1.17**。

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
2. **换一条动作** —— `Move_End_Normal` / `Public01` 的前倾都比 `Move_Ing` 小。
   ⚠️ **`Cafe_Walk` 不能选**：它不拿武器（§1.17），为了减前倾把枪藏起来不值当。
   把 `anim_driver.gd` 里 `_update_locomotion()` 的 `"Move_Ing"` 换成其中一条即可，
   **但它们的步频/脚程与 6.8 m/s 不一定匹配，可能要一并调 `speed_scale`**。
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
& $g --path $p --script res://scripts/_verify_facing.gd     # 14 项：出生越肩视角/停止保持朝向/开镜朝向
& $g --path $p --script res://scripts/_verify_mag.gd        # 16 项：开局视角/弹匣/自动换弹/连续射击/光弹几何
& $g --path $p --script res://scripts/_verify_turnfire.gd   # 8 项：开火前强制转身（连子弹都必须朝准星飞）
& $g --path $p --script res://scripts/_verify_spawnview.gd  # 12 项：初始视角 + 甩镜头点左键的真实鼠标时序
& $g --path $p --script res://scripts/_verify_settings.gd   # 29 项：Esc 设置界面（开关 / 各项真的生效 / 落盘 / 恢复默认 + 渲图，§1.12）
& $g --path $p --script res://scripts/_verify_boss.gd       # 19 项：霸王龙模型/碰撞/受击/倒地重生（第七节）
& $g --path $p --script res://scripts/_verify_boss_pig.gd   # 40 项：飞猪模型 + HUD 双血条 + 它也会攻击（§7.5 / §7.6）
& $g --path $p --script res://scripts/_verify_trex_attack.gd   # 9 项：Boss 攻击预警圈 / 伤害 / 击退 / 躲避（§7.5）
& $g --path $p --script res://scripts/_verify_companion_attack.gd # 10 项：同伴开火 + 不误伤 / 不隔墙 / 背后停火（§8.7）
& $g --path $p --script res://scripts/_verify_companion.gd  # 100 项：七名同伴跟随 + 不挡镜头 + 朝向/接地（第八节）
& $g --path $p --script res://scripts/_verify_splat.gd      # 24 项：泼溅摆放 / 悬浮平台 / 走出边缘会掉（第六节）
& $g --path $p --script res://scripts/_verify_room.gd       # 49 项通过 + 3 项**已知失败**（§6.8 那三条门洞相关的）
& $g --path $p --script res://scripts/_verify_story.gd      # 88 项：剧本解析/报错/编码/排版 + 对话框播放与暂停交接 + **角色表/场景表**（第九节）
& $g --path $p --script res://scripts/_verify_sfx.gd        # 44 项：音效库/素材/调用点对账 + 真场景接线（§1.14）
& $g --path $p --script res://scripts/_verify_move_feel.gd  # 19 项：移动手感（四方向速度/加速/跳跃/空中机动/转向，§1.15）
& $g --path $p --script res://scripts/_verify_attack_move.gd # 22 项：开火/换弹只叠上半身 —— 站定开火脚不动、跑动开火脚还在跑（§1.18）
& $g --path $p --script res://scripts/_verify_parkour.gd    # 58 项：跑酷路线（结构/胶囊/实测跳跃能力/逐跳回放/反例/不打架/终点，§1.16）
& $g --path $p --script res://scripts/_verify_mesh_hut.gd   # 31 项：手工网格小屋（门洞能走/墙能挡/网格纪律/不撞既有东西，§1.13）
& $g --path $p --script res://scripts/_probe_view.gd         # 诊断：打印视线/朝向数值，并从四方位渲图
```

合计 **609 项**（全量实测：**609 PASS / 3 FAIL**）。那 3 项 FAIL **全部**来自
`_verify_room` 的门洞那三条，是**已知、且与本次改动无关**的既有失败（§6.8）；
其余 18 套一律 0 失败。

> ⚠️ **截图那一步曾经把一套自检挂死过**：`await RenderingServer.frame_post_draw`
> 是**无界**的 —— 窗口没画出新帧时它永远不返回（被最小化 / 被别的窗口遮住 /
> GPU 被另一个 Godot 抢着）。2026-10 的全量回归就这么卡在 `_verify_boss` 第 4 节
> 19 分钟。现在两头都堵：脚本里先等 `Engine.get_frames_drawn()` 动一格、2 s 等不到
> 就跳过那张图（`_verify_boss`），运行器再给每套加 6 分钟进程级看门狗（超时强杀、
> 记 exit 124、后面的套件照跑）。

逐套件的实测 PASS 数（合计数以这张表为准）：

| 套件 | PASS | 套件 | PASS |
|---|---|---|---|
| `_verify_final` | 17 | `_verify_trex_attack` | 9 |
| `_verify_facing` | 14 | `_verify_companion_attack` | 10 |
| `_verify_mag` | 16 | `_verify_companion` | 100 |
| `_verify_turnfire` | 8 | `_verify_story` | 88 |
| `_verify_spawnview` | 12 | `_verify_sfx` | 44（§1.14） |
| `_verify_settings` | 29 | `_verify_splat` | 24 |
| `_verify_boss` | 19 | `_verify_mesh_hut` | 31（§1.13） |
| `_verify_boss_pig` | 40 | `_verify_move_feel` | 19（§1.15） |
| | | `_verify_attack_move` | 22（§1.18） |
| | | `_verify_parkour` | 58（§1.16） |
| | | `_verify_room` | 49（另 3 FAIL） |
| | | **合计** | **609** |

> ⚠️ 上面命令行注释里写的项数是**各套件自己标的**（比如 `_verify_room` 标 54、
> 实测 52 条断言），和实测对不上时**以实测为准** —— 旧版本的合计数写成过 352，
> 那是个没对上的错数字。

除 **`_verify_splat`、`_verify_room`、`_verify_mesh_hut`** 三套外，建议都加
`-- --splat=off`：615 万点的逐帧光栅化会让这些渲染相关用例慢很多（第六节实测，
`_verify_final` 第 5 节甚至会卡住）。那三套自己就要泼溅数据 —— `_verify_splat`
验的是校园那份、`_verify_room` 验的就是画室本身、`_verify_mesh_hut` 第 4 节要拿
画室的**真 footprint** 对账（不加载就是零，整节变成空跑）。

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
>
> ⚠️ 还有一条**环境**要求：**跑自检时别碰鼠标和键盘。**
> 移动鼠标会直接改 `player._yaw`（`_verify_spawnview` 第 1 节量的就是出生朝向，会红）；
> 按 `Esc` 更糟 —— 设置界面（§1.12）会**暂停游戏**，之后所有移动 / 动画 / 站位类断言
> 会一起变红，看起来像大面积回归，其实只是被暂停了。
>
> ⚠️ **还有一条「刀刃式」断言**（不是环境问题，跑几次就会撞上）：
> `_verify_companion` 的「同伴不在画面正中央 20% 宽度内」用
> `|屏幕 x − 800| > 160`，而**柚子**的站位恰好压在 160 这条线上 ——
> 隔离重跑实测 161 px（过），连跑 13 套时 151 px（红），**余量只有 1 像素**。
> 撞上时先隔离重跑该套件确认；**根治要动站位** —— 即 `scenes/game.tscn` 里各
> `Companion*` 节点的 `slot` 导出（`scripts/companion.gd` 的 `slot_position()`
> 会把它按相机绕角旋转）。**不要放宽阈值** —— 那条断言表达的是
> 「同伴不许挡住准星」，是真要求。
>
> ⚠️ 补充：`game.tscn` 第 327 行那段注释里，**小绿与柚子的实测屏幕 x 互相写反了**
> （注释记「小绿 632 / 柚子 1040」，实测是「小绿 ≈1062 / 柚子 ≈649」）。
> 所以注释里「都离画面中心 > 160 px」这句对**柚子已经不成立** ——
> 实际就在 640 这条线上，只有 1~9 px 余量。改站位前先跑 `_probe_slot.gd` 重扫，
> 别信那段注释。

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
& $g --path $p --script res://scripts/_probe_collapse.gd -- --sog=res://splatdata/collapse_test.sogdata `
      --scale=2.5 --mode=staggered --stagger=0.6 --brown=0.02 --t=0,0,0.4,0.7,0.9,1.0   # 动态 3DGS（§6.9）
& $g --path $p --script res://scripts/_probe_collapse.gd -- `
      --rise=0.6 --risejitter=0.8 --risespan=1.5 --riseloop=0 --risestep=0.3 --t=0,0,0,0  # 粒子上升（§6.9）
& $g --headless --path $p --script res://scripts/_probe_sort_cost.gd  # Raster 排序耗时 + 源顺序局部性（§6.10）
& $g --path $p --script res://scripts/_probe_stale_order.gd          # 转身后排序表多久才更新（§6.10）
& $g --headless --path $p --script res://scripts/_probe_room_collision.gd  # 导出房间碰撞的 5 个盒（§6.8）
& $g --path $p --script res://scripts/_probe_gameplay_shot.gd -- --tag=story --story --splat=off
                                                       # 剧情对话框出图 + 量「有没有压住右下角弹药面板」（第九节）
& $g --path $p --script res://scripts/_probe_platform_free.gd   # 量平台上还剩哪块空地（§1.13，**不加 --splat=off**）
& $g --path $p --script res://scripts/_probe_hut_shot.gd -- --splat=off   # 给网格小屋出 5 张图（§1.13）
```

## 1.12 设置界面（`Esc`）

按 `Esc` 呼出，**打开时暂停游戏并释放鼠标**（不然拖不动滑块），再按一次回到游戏。

| 设置项 | 作用对象 | 说明 |
|---|---|---|
| 鼠标灵敏度 | `player.mouse_sensitivity` | 0.0005 ~ 0.0060 |
| 视野 FOV | `player.hip_fov` / `aim_fov` | 开镜按固定比例跟着走（`AIM_FOV_RATIO = 0.55`） |
| 主音量 | `AudioServer` 的 **Master** 总线 | 拉到 0 走 `set_bus_mute`，**不是** `-inf dB` |
| 同伴开火 | 7 把 `CompanionGun` | 关掉后同伴只跟随、不开枪（§8.7） |
| Boss 攻击 | 两位 `BossAttacker` | 关掉后 Boss 只挨打、不还手（§7.5） |
| **画质** | 渲染分辨率 + SSAO/辉光 + 限帧 | **省电用，见下**；默认「高」= 本工程验证过的画面 |

### 画质档位（为什么需要它，以及它**到底省不省电**）

档位定义在 `game_settings.gd` 的 `QUALITY`（顺序就是界面上的顺序）：

| 档位 | 3D 缩放 | SSAO | 辉光 | 限帧 | 何时用 |
|---|---|---|---|---|---|
| 极致 | 1.00 × | 开 | 开 | 垂直同步 | 插电、要最好画面 |
| **高**（默认） | **1.00 ×** | **开** | **开** | **60 fps** | 与 §6.6/§6.11 的对照图同一档 |
| 中 | 0.85 × | 关 | 开 | 60 fps | 笔记本开始吵 |
| 低 | 0.70 × | 关 | 关 | 60 fps | 电池 |
| 省电 | 0.60 × | 关 | 关 | **30 fps** | 只想看剧情 / 续航优先 |

实现在 `game.gd::_apply_quality()`，由 `GameSettings.listen` 驱动，**改完立刻生效**
并存盘。`scaling_3d_scale = _fit_render_scale 的自动上限 × 档位系数`（只乘，不放大过 1.0）。

#### ⚠️ 实测：**降分辨率几乎不省电，限帧才省**

每档跑一次真实游戏，用 `nvidia-smi` 采 8 秒平均（本机 RTX 4060 Laptop，2560×1440@60）：

| 档位 | GPU | 功耗 | 温度 | 显存 |
|---|---|---|---|---|
| 极致 | 100% | 94.6 W | 71 °C | 6419 MiB |
| **高** | **100%** | **94.8 W** | 72 °C | 6432 MiB |
| 中 | 100% | 94.2 W | 72 °C | 6186 MiB |
| 低 | 100% | **93.5 W** | 72 °C | 6176 MiB |
| **省电** | **74%** | **78.2 W** | 70 °C | 6178 MiB |

**1.00× → 0.70×（像素只剩 49%）只省 1.4%；60 → 30 fps 省 17.5%。**

原因是 Compute 后端的分工：**逐高斯的投影（`gsplat_projection.glsl`）与 GPU 基数排序
是分辨率无关的固定成本** —— 277 万个高斯每帧都要过一遍；只有最后的瓦片光栅化跟像素数
走。所以只要目标还是 60 fps，显卡就被那段固定成本填满，降像素腾不出多少。

> 推论：**想真正大幅省电，得减「点数」（crop / 降采样泼溅），不是减「像素」。**
> 另外注意 78.2 W 已经≈桌面基线（本机空闲 76~78 W），也就是**游戏在 30 fps 下几乎
> 不额外花钱，在 60 fps 下多花约 17 W**。

> ⚠️ **GPU 爆满通常不是游戏造成的**。实测本机「桌面空闲 + 编辑器开着、没开游戏」就已经
> **64~69% / 76~78 W / SM 频率钉在 2625 MHz**：**Godot 编辑器的 3D 视口在逐帧光栅化
> 277 万高斯**（GDGS 是 `@tool` 插件），外加 Wallpaper Engine（785 MB）、OBS、
> 15 个 Firefox + 20 个 WebView2 进程。**编辑脚本时把编辑器切到 Script / 2D 标签页**，
> 比调任何画质档都管用。
>
> ⚠️ `nvidia-smi` 的 `utilization.gpu` 在有常驻渲染时是**饱和**的 —— 五档里四档都读 100%，
> 只有「省电」掉到 74%。要分辨差别请看**功耗**。
>
> ⚠️ `Engine.max_fps` 是**进程级**的。`scripts/_probe_splat_perf.gd` 因此显式把它清成 0 ——
> 否则所有超过 60 的档位都会被截到 60，帧率对照表就废了。

改完即时生效，并存到 `user://settings.cfg`（`ConfigFile` 纯文本，坏档直接删掉重启即可）。
「恢复默认」就是把 `DEFAULTS` 整张表重铺一遍。

### ⚠️ 为什么设置类是**静态类**，而不是 autoload

`game_settings.gd` 是 `class_name GameSettings extends RefCounted` + **全静态成员**。
原因只有一个，但很硬：

> 自检是用 `godot --script res://scripts/_verify_xxx.gd` 跑的，而**在这个模式下
> autoload 的名字不是编译期可见的全局标识符**。第一版写成了 autoload，结果产品脚本里的
> `GameSettings.value(...)` 直接报
> `Compile Error: Identifier not found: GameSettings` → `player.gd` 整份编译失败 →
> Player 退化成裸 `CharacterBody3D` → **所有自检一起崩**。
> 而 `--script` 以外的启动方式一切正常，所以**只有自检中招**，非常难查
> （从现象看像是「自检卡死」，其实是编译期就废了）。

代价：静态类**不能声明 `signal`**，所以变更广播改成了一个静态回调表
（`GameSettings.listen(callable)`，回调签名 `func(key, value) -> void`）。

### ⚠️ 为什么 `Esc` 的监听在菜单里，而不是留在 player

菜单一打开就把游戏 `paused = true`，而 **`player.gd` 在暂停时收不到输入** ——
它没法负责「关掉菜单」。所以由 `settings_menu.gd` 自己用 `PROCESS_MODE_ALWAYS` 监听
`Esc`（暂停也收得到）；原来 `player.gd` 里那段「`Esc` 来回切鼠标捕获」已经删掉了。

### UI 与皮肤（**可整套切换**）

UI 全部**代码构建**（和 `hud.gd` 里 Boss 血条同一套做法）。皮肤是**一整套**：
一个目录 + 一套配色 + 九宫格边距，定义在 **`ui_skin.gd`** 的 `SKINS` 里
（原来写在 `settings_menu.gd`，HUD 也要跟着换皮时抽出来了，免得两边配色走散），
**按优先级**挑第一套文件齐的。两套皮肤的文件名刻意保持一致，所以换皮肤只是换目录：

| 皮肤 | 目录 | 授权 | 仓库里有吗 |
|---|---|---|---|
| **Sprout Lands**（优先） | `assets/ui_sprout/` | 免费，但**限非商业 + 禁止再分发** | ❌ 本地自备 |
| Kenney（兜底） | `assets/ui/` | CC0 / OFL | ✅ 随仓库分发 |

文件名约定（两套一致）：`panel.png`、`button.png`、`button_pressed.png`、
可选的 `button_hover.png`、`font.ttf`。

⚠️ **字体不归皮肤管**（这一条是换显示字体那轮改的）：皮肤只管面板九宫格和配色，
**整套 UI 的字**由 `ui_skin.gd` 的 `UI_FONT_CANDIDATES` 决定，优先级是
`assets/ui_font/*`（本地自备）→ `assets/ui/font.ttf`（OFL 兜底）→ 皮肤自带字体。
所以换皮肤时对话框的木头板会跟着换，**字不变**。见 §9.5 坑 1。

⚠️ **Sprout Lands 那套为什么不在仓库里**：它的授权原文写着
`You can not redistribute or resale, even if modified.` —— 提交进仓库就等于「再分发」。
所以 `.gitignore` 把它排除了，需要自己从
[itch](https://cupnooble.itch.io/sprout-lands-ui-pack) 取得后放进 `assets/ui_sprout/`。
**没有它会自动回退到 Kenney 那套**，不报错、也不缺图。
同样处理的还有 `assets/ui_font/`（现在放的是商用需授权的「Aa暗夜深渊」）。

现在 `assets/ui_sprout/` 里用的是从 `可用素材_待接入` 裁出来的三样：
`Setting menu.png` 的空白面板（106×122，九宫格边距取 12）、
`Square Buttons 26x26.png` 的 normal / pressed 两格（各 48×48）、
以及官方 `pixelFont-7-8x14-sproutLands.ttf`（118 KB —— 比 Kenney 那套的 7 MB 中文字体小得多）。

### ⚠️ 这里踩过的四个坑

1. **面板切片可能是「中空边框」**（中心 `alpha = 0`）。Kenney 的 `tile_0008.png` 就是，
   直接当面板用会让背后的游戏画面透上来压着文字（第一版截图里能清楚看到后面的同伴）。
   已把中心填成白色，颜色完全交给 `modulate_color`。**裁新素材前务必先查中心像素 alpha。**
2. **`CheckButton` 不能给 `SIZE_EXPAND_FILL`**：开关会跟着撑满整行、变成一条长绿条。
   固定小尺寸（`76 × 28`）+ `SIZE_SHRINK_END` 才对。
3. **滑块刻意不用九宫格素材**：槽只有约 8 px 高，而九宫格边距有 8~12 px，一拉伸就错位。
   改用与皮肤同色系的平色块 + 代码生成的方块 grabber。
4. **不要在运行时改 `FontFile` 的 `antialiasing` / `hinting`**：会触发字形缓存重建，
   中文字体字形多、很慢。用字体原生的设计尺寸即可；真要关抗锯齿请去**导入设置**里配。

自检 `_verify_settings.gd`（29 项），会顺带渲一张
`_arisu_captures/_ui/96_settings_menu.png` 供人眼核对皮肤。

---

## 1.13 手工网格场景：小屋子（`MeshHut`）

平台上的**第三块场地**。前两块都是**扫描数据**（泼溅），这一块是**一格一格摆出来的**：
`scenes/mesh_hut.tscn`，47 个 `Node3D` / **1 个网格资源** / 8 个材质，全部由 Godot
内置基元（方块 + 一个圆柱）+ CSG 布尔拼成，**不依赖任何外部素材** ——
所以它也是克隆者（没有模型、没有泼溅数据）一定看得见的那块场地。

| | |
|---|---|
| 位置 | 平台**东北空场** `(14, 0, −15.5)`，门朝**西**（对着场地中心，走过去正好看见门） |
| 体量 | 屋壳 6.6 × 3.0 × 5.6，屋顶 7.4 × 0.2 × 6.4 往外挑 0.4 m，总高 3.20；灯柱顶 3.70 |
| 屋里 | 桌子（台面 1.6 × 0.8、高 0.80）、带靠背的凳子、三层货架 |
| 屋外 | 三只木箱（两只并排 + 一只叠上去）、一盏灯柱、门上一个雨篷 |
| 碰撞 | 屋壳（CSG 的 `use_collision`）+ 家具粗盒 + 木箱 + 灯柱杆；**室内地板薄板故意没有碰撞**（见坑 ①） |

出图：`_arisu_captures/_hut/`（5 个机位，`_probe_hut_shot.gd` 生成，
`10_outside` / `11_door` / `12_top` / `13_inside` / `14_window`）。

### 怎么搭的：三条规矩

1. **整份场景只有一个网格资源。** `Box_unit`（1 × 1 × 1）被 40 多个节点共用，
   每件东西靠节点的 `scale` 拉伸成需要的尺寸 —— 所以「尺寸」写在 `scale` 里。
   只有灯柱用 `CylinderMesh`，因为它是圆的。
2. **所有位置与尺寸都落在 0.05 m 网格上。** 这不是审美，是**可执行的纪律**：
   `_verify_mesh_hut.gd` 第 2 节逐个核对（现在 47 个位置 + 36 个尺寸），
   把「手改成 1.5234」这种手滑当场抓出来。
3. **只有屋壳用 CSG。** 因为要在墙上掏出「门 + 两扇窗」—— 这正是不做布尔运算就
   干不成的事。桌子/凳子/货架只是几个方块，直接 `MeshInstance3D` + 一个粗碰撞盒，
   比 CSG 更省、也更好改。

### ⚠️ 六个坑（都踩过）

**① 抬高的地板 = 台阶，而 `CharacterBody3D` 不会自己上台阶。**
这一版最反直觉的一条，是量出来的：`_verify_mesh_hut` 第 3 节在门口临时放一道
**10 cm** 的坎，胶囊的 `cast_motion` 安全比例从 **1.000 掉到 0.387** —— 人就被挡在
门外了。所以屋壳的「掏空」盒**往下捅穿**（到 y = −0.20），屋里**没有地板**，
直接踩平台地面，也就没有台阶。

室内那块好看的混凝土地面是一块 **0.05 厚、没有碰撞**的薄板（中心在 y = 0，
顶面 +0.025）：没有碰撞 ⇒ **绝不可能挡人**，代价只是玩家的小腿陷进去 2.5 cm
（4 m 外的越肩相机上约 2~3 px）。「正确」的做法是照 `game.gd` 给画室609 挖地板洞
那样把小屋 footprint 里的平台地板也挖掉（§6.8），但那条路要改
`_carve_fallback_floor()`，而且 `--splat=off` 时不挖洞、两块地面会共面闪烁。
原型阶段不值当 —— 真要正经用，就走挖洞那条。

**② CSG 的碰撞要 `use_collision = true` 才生成，默认是关的。**
忘了开 = 房子能穿墙、子弹也打不中。而且**碰撞只在 CSG 树的根节点上生成**，
设在子节点上没有用。现在射线打中的 `collider` 就是 `/root/Game/MeshHut/Hut`。

**③ 减法节点上的 `material` 决定「挖出来的那些面」用什么材质。**
不给的话门套/窗套是 Godot 的默认白灰，在暖色墙上格外突兀（第一版截图一眼就能看出）。
现在门窗都给了 `Mat_trim`，读起来是特意做的框。

**④ 布尔顺序错了不会崩，只会让屋顶中间多一个洞。**
Godot 按**子节点顺序**依次合并。`Cavity`（掏空）必须排在 `Roof`（屋顶）之前 ——
它往上捅到 y = 3.40，排在屋顶后面就会把屋顶也挖掉一块，而这在编辑器里相当不显眼。
所以第 1 节两头都验：看子节点下标，再用一条**垂直射线**确认屋顶没通。

**⑤ 别把 `Light3D` 算进「场景包围盒」。**
`Light3D` 是 `VisualInstance3D`，它的 `get_aabb()` 返回的是**光照影响范围**
（`omni_range = 14` → 28 m 的立方体）。本喵第一版算进去了，于是小屋的包围盒变成
`x ∈ [−4.2, 23.8]、y ∈ [−10.8, 17.2]`，「不与既有东西相交」那四条断言**集体假红**。
只收 `GeometryInstance3D` 与 `CollisionShape3D`，并且**跳过 `CSGBox3D`** ——
那些是布尔运算的原料（掏空盒比屋子还大、还捅到地下 0.2 m），不是几何本身。

**⑥ 写测试时，带 `await` 的函数忘了 `await` 调用 = 白丢几条断言。**
`_test_walkway()` 里有 `await`（等物理帧），不 `await` 调用它就是个协程：
跑到第一个 `await` 就把控制权交回来，**后面三条检查永远轮不到**，而输出里只是
「少了几行」——极容易看漏。本喵第一版就是这么丢掉三条的（26 项 vs 应有 29 项）。

### 摆哪儿：先跑探针，别手算

平台只有 40 × 40，上面已经挤着画室609（**斜的**）、两位 Boss、3 根柱子、5 个靶子，
还有一条**不能碰的自检弹道**（玩家(6,−4) → 靶1(6,−10)，§7.3 踩过：猪猪当初摆在
x = 9 就吃掉了它，害得 3 套自检集体变红）。所以先量再摆：

```powershell
& $g --path $p --script res://scripts/_probe_platform_free.gd
```

它打印三样东西：

1. 每个障碍物的世界 AABB（画室那份来自 `content_world_aabb()`，不是猜的）；
2. 平台的 **40 × 40 ASCII 地图**，一格 1 m —— 画室画的是**真旋转矩形**而不是包围盒
   （它的包围盒 23.9 × 27.2 m 比房间自己大一圈，四个角其实是空的）；
3. 「这块 footprint 能放哪些格点」按净距排序的表 + 第二张地图。

判交用的是**分离轴**（旋转矩形 ↔ 轴对齐矩形），不是拿包围盒糊弄。
**以后往平台上摆任何东西，先跑它。**

量出来的结果：`(14, −15.5)` 与最近障碍留 **2.92 m**（Pillar1 的碰撞盒），
离平台东边缘 1.35 m，且完全避开了那条弹道。

> ⚠️ 改小屋位置要同时改**三处**：`game.tscn` 的 `MeshHut` 节点、
> `_verify_mesh_hut.gd` 的 `EXPECT_POS`、`story/设定.md` 场景表里那一行
> （`_verify_story` 会拿表和场景对账）。

### 自检

```powershell
& $g --path $p --script res://scripts/_verify_mesh_hut.gd      # 31 项
```

⚠️ **这一套不要加 `--splat=off`**（和别的套件相反）：第 4 节要和画室609 的**真实**
footprint 对账，而那来自 `content_min/max` —— 不加载泼溅就是零，整节变成空跑。

五节分别是：结构（布尔顺序 + 屋顶射线 + 单一网格资源）、网格纪律、
**门洞能走 / 墙能挡**（真胶囊 shape cast + 反向对照）、不与既有东西打架、
子弹与灯。其中「门能走」那一条用的是抬起来 5 cm 的胶囊 —— 真玩家的胶囊底面正好
贴在地面 y = 0 上，一放上去就和地板接触，`cast_motion()` 会立刻返回 0，
什么都验不出来（坑 ① 里那道 10 cm 的坎就是这条的反向对照，证明它真的量得出来）。

### 性能

47 个节点 / 1 个 `BoxMesh` / 8 个材质 / 2 盏**关着阴影**的 `OmniLight3D`，
帧率上看不出变化 —— 和它对面那两块「277 万 / 615 万点」的泼溅不在一个量级上。
这正是搭它的初衷：**不想再扫一份数据的时候，手工搭一块是可行的。**

---

## 1.14 音效（Kenney CC0 + 静态音效库）

在这之前，**工程里一个音频文件都没有**（`master_volume` 那条设置一直就在，只是没东西可听）。
现在第一批接了**用户选的两组**：武器（枪声 / 换弹两头 / 空仓扣扳机）和界面（按钮 / 开关 / 滑条 / 开关菜单）。

| | |
|---|---|
| 素材 | 13 个 `.ogg`，共 **102.7 KB**，全部来自 Kenney 的三个音频包（Interface Sounds / Sci-fi Sounds / RPG Audio） |
| 许可 | **CC0** —— 所以**故意提交进仓库**，克隆者不用做任何事就有声音（见 `assets/sfx/LICENSE_Kenney_CC0.md`） |
| 库 | `scripts/sfx.gd`：9 个逻辑名 → 候选文件 + 基准音量 + 音高抖动 + 最小间隔 |
| 接线 | `weapon.gd` 三处（开火 / 换弹开始 / 换弹完成 / 空仓）、`settings_menu.gd` 五处（开 / 关 / 按钮 / 开关 / 滑条） |
| 音量 | 直接走**已有的** `master_volume`（设置界面那个滑条，作用在 `Master` 总线上）—— 没有新增设置 |

```
weapon.gd / settings_menu.gd          ← 调用点只写「逻辑名」：Sfx.play("fire")
        │
        └─ scripts/sfx.gd  SPEC 表      ← 逻辑名 → 候选文件 + db + pitch + gap_ms
                │
                └─ assets/sfx/*.ogg     ← 真正的文件（Kenney 原始文件名，便于追溯来源）
```

### 三条刻意的取舍

1. **文件缺失 = 静默。** 加载不到只 `push_warning` 一次并记进 `missing_files()`，
   绝不影响玩法 —— 克隆者删掉整个 `assets/sfx/` 也照样能跑。
2. **暂停时照样响。** 宿主与播放器的 `process_mode` 都是 `ALWAYS`：设置菜单一开
   `get_tree().paused = true`，而那正是 UI 音效最需要响的时候。自检第 5 节拿**真场景**
   验了这条（`世界已暂停（true），ui_open 照样响了`）。
3. **玩家自己的枪走 2D（非定位）。** 枪永远「在耳边」，用 3D 定位反而会随镜头左右漂；
   世界里的声音（命中 / Boss / 脚步，下一批）走 `Sfx.play_at(name, pos)`。

### 加一条新音效 = 两处

1. `.ogg` / `.wav` 丢进 `assets/sfx/`（**保持原始文件名**，来源可查）；
2. `scripts/sfx.gd` 的 `SPEC` 里加一行；然后 `--headless --path . --import`。

**调用点不用改，别的代码也不用改。** 反过来，调用点里写错一个字母会被自检抓出来
（见下面第 2 节）—— 这条是整套音效自检里最值钱的一项：**声音加了没接、或者接的名字
打错了，两种错都不会报错、也不会有声音，自己几乎发现不了。**

### ⚠️ 四个坑（都踩过）

**① 静态函数**绝对不能**叫 `reset_state()` —— 引擎会静默接管。**
这是本工程踩过最阴的一个坑，也是这一节最该记住的一条：

**`Script` / `GDScript` 自带一个原生方法就叫 `reset_state`**（实测
`ClassDB.class_has_method("Script", "reset_state") == true`，而 `Object` 没有）。
而 `class_name Sfx` 的**类名本身就是那个脚本对象** —— 于是 `Sfx.reset_state()`
解析到了**原生方法**上去：自己写的静态函数**一行都不执行，也不报任何错**。
本喵当时在自检里连函数体第一行的 `print` 都看不到，查了三轮才用 `ClassDB` 问出来。
（第 3 节现在把这两条钉成了断言，免得以后有人再起这个名字。）

> 推论：给 `class_name` 脚本的静态函数起名时，要避开的是**`Script` / `GDScript`
> 的原生方法名**，不是 `Object` 的。`play` / `stop_all` / `has` / `names` 这些都没事。

**② `[&"Master"] == ["Master"]` 是 `false`。**
`AudioStreamPlayer.bus` 的类型是 **`StringName`**，而数组的 `==` 不放过元素类型差异。
自检里「播放器都走 Master 总线」那条因此假红过一次 —— 比较前必须 `String(bus)`。

**③ 时长下限别写太严。** Kenney 的 `click_002.ogg` 只有 **10 ms**（就是个「嗒」），
本喵第一版把「合理时长」下限写成 20 ms，把它判成了坏文件。

**④ 别把 `play()` 和 `last_reason()` 塞进同一个表达式。**
实参求值顺序不能想当然，读到的可能是**上一次**调用留下的说明 —— 本喵就因此被一条
假线索带偏了一轮。**先取值、再 `_check()`** 是这里的规矩。

### 自检

```powershell
& $g --path $p --script res://scripts/_verify_sfx.gd -- --splat=off   # 44 项
```

五节：素材与库表（文件都在、能加载、时长正常）、**调用点 ↔ 库表双向对账**、
播放机制（真能响 / 多声不互切 / gap 节流 / 3D 定位 / **暂停时也响**）、
与设置系统的接线（主音量拉 0 真的静音，且**测完改回原值**）、
**真场景里的接线**（菜单开→关、开一枪、走一次换弹，各验「真的响了」）。

⚠️ 要加 `--splat=off`（第 5 节会 instantiate `game.tscn`），
而且**不要用 `--headless`** —— headless 的音频驱动是空的，「真的在播」测不出东西。

### 还没接的（第二批候选，文件都在本地、表也留好了位置）

命中（`impactMetal_light` / `impactWood_medium`）、打爆靶子、Boss 蓄力预警、
玩家受伤、脚步（`footstep_concrete` 走平台 / `footstep_wood` 走进画室609）、
剧情打字机逐字声（`tick_001`）、小屋那块场地的室内嗡鸣。
**加它们只需要往 `SPEC` 里加行 + 在对应事件里加一次 `Sfx.play*()`。**

---

## 1.15 移动手感（调过一轮，有自检守着）

用户报了一组主观问题：「加速度少了 / 机动性差 / 跳的不高 / 速度要快点 /
**为什么往后走不能跑步** / 转向时角色需要更灵活」。
这一节把**主观感受量成数字**（`_verify_move_feel.gd`），顺便防止以后改回去。

### 实测手感一览（`_verify_move_feel.gd` 每次都会打这张表）

| | 现在 | 改之前 |
|---|---|---|
| 跑（**任意方向**，含后退） | **6.80 m/s** | 5.20（**后退只有 2.00**） |
| 走（不按 Shift） | 2.40 m/s | 2.00 |
| 蹲行 | 1.30 m/s | 1.10 |
| 开镜 | 1.90 m/s | 1.60 |
| 静止 → 90% 满速 | **250 ms** | 约 570 ms |
| 松开 → 停住 | 217 ms | 约 300 ms |
| 跳跃峰值 / 滞空 | **1.32 m / 700 ms** | 0.87 m / 560 ms |
| 空中横改（0.2 s 内） | **1.80 m/s** | 0.60 m/s |
| 换向收到 5° 以内 | **100 ms** | 约 240 ms |

### 改了哪四组数（`player.gd` 顶部）

```gdscript
SPEED_WALK 2.0 → 2.4      SPEED_RUN 5.2 → 6.8      SPEED_CROUCH 1.1 → 1.3   SPEED_AIM 1.6 → 1.9
ACCEL_GROUND 12 → 26      ACCEL_AIR 3 → 9          FRICTION 20 → 30
GRAVITY 22 → 20           JUMP_VELOCITY 6.2 → 7.1
TURN_SMOOTH 14 → 24       TURN_SMOOTH_FIRE 26 → 34
```

### ⚠️ 改这组数之前必须知道的四条约束

1. **动画那边只有 `Normal_Idle` / `Move_Ing` 两条循环**：走 / 跑 / 蹲 / 开镜都用
   `Move_Ing`（战斗动画 = 两只手在枪上），快慢只靠 `speed_scale`。
   **不要再按速度去切 `Cafe_Walk`** —— BA 的咖啡厅动画不拿武器（§1.17）。
   （这条以前写的是「`SPEED_WALK` 必须小于 `WALK_THRESHOLD` 2.8」，那个阈值已删。）
2. **改了速度不要跟着改 `CYCLE_SPEED`。** `anim_driver.gd` 的
   `speed_scale = 速度 / CYCLE_SPEED[clip]` 是**按实际位移补脚步**的（防脚底打滑）——
   `CYCLE_SPEED` 是「这条动画按多快的地面速度录的」，不是「想让玩家跑多快」。
   6.8 / 5.2 = 1.31 倍播放，步幅不变，只是踩得更快。
3. 跳跃高度 = `JUMP² / (2 × GRAVITY)`、滞空 = `2 × JUMP / GRAVITY`。
   现在 `7.1² / 40 = 1.26 m`（实测 1.32，多出来的是物理步进的量化）。
4. 转身是**指数逼近**（每帧 `lerp(TURN_SMOOTH × delta)`），不是恒速：
   24 在 60 fps 下每帧走 40%，约 5 帧收到 5° 以内。**帧率无关**（`exp(-speed × T)`），
   所以高刷窗口下手感一致。

### 「往后不能跑步」的真凶

`sprinting` 里原本有一句 **`input.y < 0.1`**，本意是「不许倒着跑」。但
`Input.get_vector(..., "move_forward", "move_back")` 里 **`move_back` 的 `input.y` 是 +1** ——
于是按 `S` 永远拿不到跑速，表现就是「往后走不能跑步」。现在四个方向一视同仁。

> 这一条在 `_verify_move_feel.gd` 里有**专门一条**盯着（而且失败信息里直接写着
> 「以前这里恒为 2.40」），别再把它加回来。

### 转向为什么「更灵活」了：朝向改成跟**输入**走

原来角色朝向跟的是**速度方向**：

```gdscript
elif horiz.length_squared() > 0.25:        # horiz = 当前速度
	_facing_yaw = atan2(horiz.x, horiz.z)
```

速度受加速度限制，换向时要拖小半秒才拐过去 —— 那正是「转向不灵活」的观感。
现在**有输入就立刻朝意图方向**：

```gdscript
elif dir.length_squared() > 0.01:          # dir = 相对相机的输入方向
	_facing_yaw = atan2(dir.x, dir.z)
elif horiz.length_squared() > 0.25:        # 没输入但在滑行：保持朝滑行方向
	_facing_yaw = atan2(horiz.x, horiz.z)
```

第二条 `elif` 不能删：松手后不能回落到相机朝向，否则又会出现 §1.4 那个
「松开移动键后角色自己转回去面对镜头」的老毛病。`_verify_facing.gd` 第 3 节
（「松开后 `facing_yaw` 完全冻结」）守着这件事；`_verify_final` §4
（「跑动时脸朝移动方向」）在稳态下两种写法等价，所以不受影响。

自检里最漂亮的一条是这个**分叉判据**：先朝 −Z 跑满速，再突然换成 +X，
30 ms 后量「朝向离目标多远」与「速度方向离目标多远」——
实测 **32° vs 84°**，证明朝向确实**领先于速度**（若还是跟速度走，两个数会几乎相等）。

### 自检

```powershell
& $g --path $p --script res://scripts/_verify_move_feel.gd -- --splat=off   # 19 项
```

六节：四个方向的稳态速度（都带 Shift）、加速度与刹车、跳跃高度与滞空、
空中机动、转向灵活性、各档位速度的递增关系。

⚠️ 两条纪律（`--script` 里量物理量最容易在这里翻车）：
**等真实时间不等帧数**（真渲染窗口能跑到 1000+ fps），
以及**开局把鼠标设成 `VISIBLE`**（`player._input` 只在 CAPTURED 时吃鼠标移动，
否则跑自检时碰一下鼠标就把视角带歪、把转向测量搞脏）。

---

## 1.16 跑酷路线：从平台跳出去，到「信号塔岛」

**一句话**：从平台**西边缘**（`x = −20`）跳出去，**10 跳 + 1 段窄梁**，
一路爬到 `y = +5.70`，最后一下**下跳**落到 56 m 外的悬浮岛（16 × 16 m，
台面 `y = +4.70`）—— 那就是「下一个区域」。文件：`scenes/parkour.tscn`
（**按世界坐标写**，不是道具那样带自己的原点）+ `scripts/parkour.gd`。

```
Launcher(平台上的跑道) → P1 → P2 → P3 → 窄梁 → P4 → P5 → P6 → P7 → P8 → P9 → 信号塔岛
   0.03m               0.40 0.90 0.90  0.90  1.70 2.50 3.30 4.10 4.90 5.70   4.70
   ← 平跳 3.5 → 3.0 → 4.0（最难）→ 走 5m 窄梁 → 2.5 → 2.8 → 2.8 → 2.4 → 2.2 → 2.2 → 下跳 4.0 →
```

### 设计依据：这一跳到底跳不跳得过去

跑酷是**唯一一种「几何算对了也未必能过」**的东西，所以这一节的每个数都是量的
（`_verify_parkour.gd` 每次都会重量一遍，在空域里二分法试跳）：

| 量 | 实测 | 解析 | 说明 |
|---|---|---|---|
| 平跳最远 | **5.09 m** | 4.83 m | `跑速 × 2v/g`；实测多 5%（起跳点能站到边缘外、离地后还在加速） |
| 抬升 0.80 m 最远 | **4.23 m** | 3.87 m | 抬升吃掉射程，这是「上坡跳」便宜不了的原因 |
| 落差 1.00 m 最远 | —— | 5.65 m | 往下跳能跳得**更远**，所以终点那一下给到 4.00 m |
| 挂边容忍 | **+0.20 ~ +0.30 m** | +0.30 m | 见下面那条「几何定死」的注释 |
| 0.80 m 窄梁上，人能偏多少 | **中心 ±0.60 m** | —— | 梁半宽 0.40 + 挂边；所以「窄」其实比看上去宽容 |

每一跳的余量（`必须跨过的距离` vs `实测能力`，要求 ≥ 0.40 m）：

| 这一跳 | 必须跨 | 抬升 | 余量 | 这一跳 | 必须跨 | 抬升 | 余量 |
|---|---|---|---|---|---|---|---|
| 跑道→P1 | 3.50 | +0.38 | 1.17 | P4→P5 | 2.80 | +0.80 | 1.28 |
| P1→P2 | 3.00 | +0.50 | 1.52 | P5→P6 | 2.80 | +0.80 | 1.17 |
| **P2→P3** | **4.00** | 0.00 | **1.09** | P6→P7 | 2.40 | +0.80 | 1.61 |
| P3→窄梁 | 0.00 | 0.00 | 走过去 | P7→P8 | 2.20 | +0.80 | 1.88 |
| 窄梁→P4 | 2.50 | +0.80 | 1.58 | P8→P9 | 2.20 | +0.80 | 1.88 |
| | | | | P9→岛 | 4.00 | **−1.00** | 1.95 |

> 「余量」的算法：**实测标定一个系数 `k = 平跳实测 / 平跳解析 ≈ 1.054`**，
> 任意抬升的预期射程 = `解析射程 × k`，再减掉「必须跨过的距离」。
> 只要两次标定（平跳 + 一次抬升）就能把每一跳都管住 —— 自检第 3 节就是这么算的，
> 它同时会核对 `抬升 0.80` 的实测值与模型值对不对得上（要求 ≤ 0.45 m）。
> 而**真的跳给看**是第 4 节：每一跳都拿真输入跑一遍，还比对解析落点。

> ⚠️ **改了 `player.gd` 的 `SPEED_RUN` / `JUMP_VELOCITY` / `GRAVITY`，必须重跑
> `_verify_parkour.gd`。** 第 3 节会先「空域二分法量出实测能力」，再拿它去核对
> 每一跳 —— 余量掉到 0.40 m 以下就红。这条线的难度是**绑定在移动手感上的**，
> §1.15 那次提速（5.2 → 6.8 m/s）如果晚做，这条路线就得整体重排。

### 三条物理结论（跑酷直接吃它们）

1. **挂边容忍是几何定死的 = 胶囊半径。** `floor_max_angle` 45°、
   胶囊半径 0.30 ⇒ 球心站到面外 `0.30 × tan45° = 0.30 m` 时接触法线正好 45°，
   再远一毫米就不算「地面」了。实测 **+0.20 ~ +0.30**：轻放能到 0.30，
   从 2.5 m 高摔下来只有 0.20（临界点上跟落地那一下的动能有关）。
   **所以落脚板的有效面积比它看上去大一圈**（每边 +0.2~0.3 m）。
2. **`CharacterBody3D` 不会上台阶**（§1.13 那条）。所以：
   - 跑道/传送台**一律不能有台唇** —— 跑道就是画在地上的标记板，**故意没有碰撞**
     （2.5 cm 的坎就够把人挡在外面）；传送台是 10 cm 厚的**发光贴面**，同样没有碰撞。
   - 每一块落脚板的碰撞形状都用**同一个 1×1×1 的 `BoxShape3D` + 节点的 `scale`**
     拉出来（实测可行：正中和内沿都精确站在台面 `+0.000`）。好处是「一块板多大」
     只有 `scale` 这一处真相，网格和碰撞不可能走散（自检第 1 节逐个核对两者 AABB）。
3. **跳跃高度 1.26 m 是硬顶。** 所以全程单跳抬升都压在 **+0.80 m 以下**，
   而且抬升越大给的间距越短（
   `+0.80 → 3.87 m`、`+0.50 → 4.29 m`、`0 → 4.83 m`、`−1.00 → 5.65 m`）。

### 摔下去怎么办：检查点 + 传送台

整条线是**上坡**的（0 → +5.70），回头跳不回去。所以：

- `parkour.gd` 把「掉出路线」的兜底线从 `game.gd` 的 `y < −60` **抬到 `y < −12`**，
  并把人送回**最近踩过的那个落脚点**。没有这一步，每摔一次都要从出生点重新跑 70 m
  （穿过画室、绕过两位 Boss），跑酷地图根本没法玩。
- **解除武装的条件是「站在主平台上、且脚下不是路线上的落脚点」** —— 否则一个
  只是在平台边上失足的路人会被凭空塞到跑酷中段。
- 岛上那台**「传送台：回平台」**不是装饰：检查点会把人一直留在岛上，
  没有它玩家到了终点就**再也回不来**（16 × 16 m 的孤岛，四周是真的真空）。
- 崩线之外还有 `game.gd` 的老兜底：不在跑酷里摔下去，照样送出生点。

### 怎么跑 / 怎么验

```powershell
& $g --path $p --script res://scripts/_probe_parkour.gd      -- --splat=off  # 设计表 + 每一跳余量 + 俯视 ASCII 图
& $g --path $p --script res://scripts/_verify_parkour.gd     -- --splat=off  # 58 项，含真输入逐跳回放
& $g --path $p --script res://scripts/_probe_parkour_shot.gd -- --splat=off  # 8 张机位图 → _arisu_captures/_parkour/
```

`_verify_parkour.gd` 七节：结构（网格↔碰撞 AABB 一致、0.05 网格、碰撞层）、
胶囊与台面（挂边 / 窄梁，真物理量）、**实测跳跃能力（二分法）+ 逐跳余量核对**、
逐跳回放（真输入真物理，每跳还比对「解析预测落点 vs 实际落点」，实测差 ≤ 0.15 m）、
反例（不按跳过不去、摔落回检查点、传送台能回平台）、与平台既有东西不打架、
终点区域（岛够大、落点四周净空、灯不多、指路牌在）。

其中最有说服力的一条是**连续通关**：不重置、不停顿、不松键，从跑道一路打到岛上
（10 跳 + 1 段窄梁一气呵成，`检查点 12/12`）。

### 本轮踩的三个坑（都留了断言或注释）

1. **新建 `class_name` 要先用编辑器扫一次。** `--script` 是拿
   `.godot/global_script_class_cache.cfg` 认全局类名的，新写的
   `parkour.gd` 不在里面 —— 探针直接 `Could not find type "Parkour"`。
   跑一次 `godot --path <工程> --headless --editor --quit` 就登记上了。
2. **挂边探针不能拿 P3 的*西*边缘测**：窄梁紧贴着它（同高、从 `x = −38.50` 开始），
   人根本不是「挂在边上」，是**站在梁上** —— 量出来 `+0.40 m`，
   比几何极限还大，一眼假。改测南边缘才是真数。
3. **「走过去」的那一站第一版压根没跑。** `_run_hop()` 里 `var jumped := walk`
   把「这一站要跳」和「这一站已经处理完了」当成了同一个布尔量，
   于是窄梁那一段直接跳到「等落地」—— 人还站在 P3 上就判定失败。
   布尔量兼作状态标志，会把整整一段逻辑吃掉。

### 岛上有什么（「下一个区域」的毛坯）

16 × 16 m 混凝土板、**四角警示柱**（边界提示）、**信号塔**（4 腿 + 顶台 + 桅杆 +
信标灯，塔顶 `y = +15.1`，从平台就能看见）、**掩体**（三面墙 + 顶，朝南开口，
人能走进去）、两只货箱、**传送台**、两块 Label3D 指路牌。
灯只加了 2 盏（塔顶 + 掩体），都关阴影 —— 这条线本来就在大太阳底下，
本项目对功耗敏感（§6.6）。

---

## 1.17 ⚠️ 手里拿什么：BA 素材是**用「骨的 scale」藏道具**的

用户报：「为什么小桃小绿**行走动作是拿游戏机的**，还有好多角色**行走也没有拿枪了**」。

### 先量，再猜

`scripts/_probe_companion_anim.gd` 把 8 个模型（主角 + 七名同伴）的 clip 清单、
以及**每条循环动画对「道具骨」做了什么**全打出来。结论很清楚：

1. **clip 一条都不缺** —— 8 个模型都自带 `Normal_Idle` / `Cafe_Walk` / `Move_Ing` /
   `Normal_Attack_Ing` / `Normal_Reload`（个别 30~38 条，只是多了跪姿/胜利那些）。
   所以**不是挑错了 clip、也不是枪没挂上**。
2. **道具是「把骨的 scale 缩到 ≈0」藏起来的**（不是 `visible`、不是 blend shape）。
3. `Cafe_Walk`（咖啡厅漫步）在**每一个**模型里都把武器骨缩到 ≈0：

| | `Cafe_Walk` 里武器骨 scale.x 最小 | `Move_Ing` 里同一根骨 |
|---|---|---|
| 爱丽丝（主角） | **0.038** | 1.000 |
| 未花 | **0.020** | 0.900 |
| 优香 | **0.143 + 0.107**（左右各一把） | 1.000 |
| 诺亚 | **0.001** | 1.100 |
| 小桃 | **0.000** | 1.000 |
| 小绿 | **0.000** | 1.000 |
| 柚子 | **0.020** | 1.000 |
| 凯伊 | **0.001** | 0.900 |

⇒ **「走路不拿枪」是素材本身的设计**：BA 的 `Cafe_*` 是**咖啡厅模式**的动画，
在咖啡厅里当然不拿枪；小桃/小绿在那个姿势里手里那个「游戏机」就是她们的招牌道具。
这也解释了为什么只有她们俩「拿游戏机」—— 那是角色道具，不是动画挑错了。

### 试过并否掉的修法（有对照图）

把 `Cafe_Walk` 复制一份、把「`Move_Ing` 里显示、`Cafe_Walk` 里藏起来」的骨 scale
改回 1.0（想保住漫步步态、只把枪补回身上）。**枪确实回来了，但是挂在身侧的**，
两只手还在胸前捧着游戏机 —— 那件道具**不在武器骨下**，改 scale 抠不掉它。
四种候选（A 原样 / B 补武器 / C 用 `Move_Ing` 降速 / D 战斗待机）的对照渲染见
`scripts/_probe_armed_walk_shot.gd`，输出在 `_arisu_captures/_armedwalk/`
（上排正面、下排转 40°，一眼看出 B 不行、C 两只手都在枪上）。

> 顺便踩到一个**浮点门槛**的坑：判「这根骨在 `Move_Ing` 里是显示的」原本写
> `>= 0.9`，而未花的武器骨正好是 **0.900**，存下来略小于 0.9 ⇒ 整根骨被跳过、
> B 列看起来和 A 列一模一样，白看一轮。门槛放到 0.5 才对。

### 采用的修法：**整局都只用战斗动画**

```gdscript
const CYCLE_SPEED := { "Normal_Idle": 0.0, "Move_Ing": 5.2 }   # Cafe_Walk 删掉
const IDLE_SPEED := 0.15
# speed_scale = clamp(速度 / 5.2, 0.25, 2.0)   ← 走 / 跑 / 蹲 / 开镜 全靠它区分
```

- **主角和七名同伴一起改**（同一个 `AnimDriver`），所以「好多角色」一次修完；
- **步幅仍然吻合**（这是 `speed_scale` 的本职）：`Move_Ing` 标称 5.2 m/s、
  一个循环 3.47 m；走 2.4 m/s 播 0.46 倍 ⇒ 一个循环仍是 3.48 m，脚不打滑。
  代价只是「走路用的是跑步的**姿势**」——上身前倾是跑步那一下；
- `SPEED_SCALE_MIN` 从 0.35 放到 **0.25**：蹲行 1.3 m/s 现在也走 `Move_Ing`，
  1.3/5.2 = 0.25，卡在 0.35 会让脚比地面快 40%；
- 这也正是 BA 自己的做法：战斗里只有 `Move_Ing`，`Cafe_*` 只在咖啡厅界面出现。

### 守着它的断言

- `_verify_move_feel.gd` 第 1 节：**「走路 2.40 m/s 播的是 `Move_Ing`、播放速率
  0.46（≈ 2.4 / 5.2）」** —— 这条原来写的是「走路速度必须低于动画阈值」（正好反了）。
  ⚠️ 读法上有个坑：必须**注入速度后当场读**，一旦让过一个物理帧，
  `player.gd` 会用**真实速度**再调一次 `set_locomotion()`，注入值被冲掉
  （第一版量到 0.25 —— 那是人已经停下、速度掉到 1.3 时的速率）。
- `_verify_companion.gd` 第 1 节：七只都**必须**有 `Normal_Idle` + `Move_Ing`
  （以前查的是 `Cafe_Walk`，那正是「查了个不用的动画」）。
- `scripts/_probe_companion_anim.gd`（量 clip 与道具骨）与
  `scripts/_probe_armed_walk_shot.gd`（四种候选的对照图）都留在仓库里，
  换模型（再加同伴）时先跑前者。

---

## 1.18 ⚠️ 开火 / 换弹只叠**上半身**（跑打时腿要还在跑）

用户报：「开枪跑打时为什么角色脚不动，需要**静止开枪不动**，但是**跑步开枪脚还是要动**」。

### 病根：一次性动作是**整身**切的

`request_fire()` 原来把**整个** `AnimationPlayer` 切到 `Normal_Attack_Ing`，而这条动作是
**全骨架**的 —— 实测（`scripts/_probe_attack_clip.gd`）：

| 模型 | `Normal_Attack_Ing` 轨道 | 其中下半身（thigh/calf/foot/toe/pelvis/skirt…） | 「移动有、攻击没有」的骨 |
|---|---|---|---|
| 爱丽丝（主角） | 228 | **48 根** | 0 根 |
| 小桃 | 220 | **46 根** | 0 根 |
| 优香 | 155 | **26 根** | 0 根 |

⇒ 开火那一秒腿也被它按住，人在地上滑。**两条动作覆盖的骨完全一样**，所以也不能靠
「谁的轨道少」来偷懒。

### 修法：第二个 `AnimationPlayer` + 滤掉下半身轨道

```
基础层 player  ：Normal_Idle / Move_Ing  —— 每帧写**全部**骨（包括腿）
叠加层 upper   ：开火 / 换弹的副本，**下半身轨道全删掉**  —— 只写上半身
                 process_priority = 1 ⇒ **后写、赢**（上半身以它为准）
```

三条都是量出来的：

1. **不能用 `AnimationTree`** —— 它在这份骨架上根本不驱动骨骼（§1.7，逐帧截图 0 像素差异），
   所以官方那条「Blend2 + 骨骼遮罩」的路走不通；
2. `AnimationPlayer` **没有逐轨道遮罩**，但**两个播放器写同一具骨架时后写的赢** ——
   于是「下半身只有基础层写、上半身两层都写，叠加层后处理」正好拼出想要的叠加；
3. 因为动作是全骨架的，**必须先滤掉下半身**（实测爱丽丝一条动作滤掉 57 条轨道：
   228 → 171，滤完下半身轨道 **0 条**）。

`set_locomotion()` 里那句 `or state != State.LOCOMOTION` 也一并删了 —— 就是它让
「开火期间基础层停止更新」的（兜底路径仍然保留互斥，否则会把正在播的一次性动作顶掉）。

### 实测（`_verify_attack_move.gd`，量的是一只脚在**骨架局部空间**里的往返，米）

| | 脚往返 | 说明 |
|---|---|---|
| 站定（对照） | 0.014 | 本来就不动 |
| **站定 + 开火** | **0.013** | 用户要的那一半：**不动** ✓ |
| 跑（对照） | 0.228 | |
| **跑 + 开火** | **0.418** | 用户要的另一半：**还在跑** ✓ |
| 跑 + 换弹 | 0.402 | 同一个毛病，同一套修法 ✓ |

同一窗口里右手挪了 **0.094 m**（≥ 0.08）—— 证明站定开火时叠加层**真的在写上半身**，
不是「什么都没播」。另外：跑动开火时基础层仍是 `Move_Ing`、跑速仍是 6.80 m/s。

### 两个坑

1. **`_ready()` 里 `add_child()` 会失败，而且是静默的。**
   父节点那一刻「正忙」（`Parent node is busy setting up children`）⇒ 叠加层**没进树**
   ⇒ 它一帧都不更新 ⇒ 上半身根本没叠上去，而且 `animation_finished` 永远不来
   （状态卡在 `Fire`，**再也开不了下一枪**）。本喵第一版就是这样：7 条结构断言全绿，
   只有「站定开火时右手在不在动」那条红了才露馅。
   修法：库先装好、`host.add_child.call_deferred(upper)`；`_play_once()` 再要求
   `upper.is_inside_tree()`，没进树就走兜底（整体播），**状态机永远能往前走**。
   > 同一个坑 `companion_gun.gd` 的文件头也记着（特效根节点那一段），是这个工程的常客。
2. **别用 `get_animation_library("")` 去拿「默认库」**：新建的 `AnimationPlayer`
   **没有**默认库，那句会返回 null 并连报 9 条 ERROR。直接
   `AnimationLibrary.new()` + `add_animation_library(&"", lib)` 才对。

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

## 2.3 口型 / 表情切换

10 个 `Mouth_*` 网格各带 **1 个 blend shape**（Godot 命名为 `morph_0`），
每条动画都有 **10 条 `weights` 通道**打在这些网格上，**口型切换烘进每条动作里**。

⚠️ **这个 morph 不是「张嘴 / 闭嘴」，而是「把这一块口型缩没」**。直接读 GLB 的形态键增量
（`..\_blender_arisu\glb_morph_collapse.py`）实测：每块 25 个顶点，权重 = 1 时所有顶点被拉到
基准包围盒中心、残余半径只剩原来的 **11.3%**（凯伊是 8.4%）—— 等同于隐藏。

所以切换口型的机制是：**每条动画把 10 块里的 9 块压到 1（藏起来），只留 1 块为 0（显示）**；
要换表情就把「留 0 的那块」换成另一块。实测（`scripts/_probe_mouth_state.gd`，凯伊 14 块）：

| 动画 | 时刻 | 留 0（= 可见）的是 |
|---|---|---|
| `Normal_Idle` | 全程 | `Mouth_401` |
| `Normal_Callsign` | 0.00 s | `Mouth_402` |
| `Normal_Callsign` | 1.25 s | `Mouth_602` ← 动画中途换了表情 |

值在 0/1 之间跳变 → 源文件是 **STEP 插值**的口型切换，Godot 原样保留。
嘴网格挂在骨骼节点下：`Arisu/Model/Aris_Original_Mesh/bone_root/Bip001/Skeleton3D/Mouth_401`

> 这里早先把 `morph_0=1` 记成「张嘴」、`0` 记成「闭嘴」，方向是反的：**1 是藏起来**。
> `Normal_Callsign` 里 `Mouth_401` 从 1 变 0，意思是「换成了 401 这个表情」，不是「张开嘴」。

### 2.3.1 想要的话，口型是可以自由换的

- **换口型（不改模型）**：直接改这 10（凯伊 14）条 `morph_0` 权重，或干脆用 `visible` 显隐 ——
  两条路等价（morph 就是「缩没」）。和骨骼动作完全解耦，不会打架。
- **加新口型**：复制任意一块 `Mouth_*` 网格 + 换一张贴图 + 保留那个「缩没」形态键即可，
  结构和其他块一模一样（25 顶点、1 个 morph）。凯伊那 14 张 `Character_Mouth_X_Y.png`
  每张就是**一个完整口型**画在透明底上，自己做一张同规格的就能加。
- **注意顺序**：14 块是**共面叠在同一处**的，靠 morph 藏掉 13 块。所以任何时候都必须保证
  「只有一块权重为 0」，否则会叠出多张嘴。
- **眉毛 / 眼型不是贴图切换，是骨骼**：凯伊有 25 根 `bone_eye_*` / `eye_L/R(_1/_2)` /
  `Xtra_eyebrowL1/L2` / `Xtra_eyebrowR1/R2` / `Xtra_eyeL/R` / `bone_Eyering_L/R_01..03` /
  `bone_Mouth`。几何长在身体网格里（`Mouth_*` 之外没有单独的眼/眉网格），
  **形状画在 `CH0335_Face` / `Aris_Original_Face` 贴图上** —— 所以能抬眉、皱眉、眯眼、转眼，
  但想换「眉形」得换那张脸贴图。
- **瞳色 / 眼白**：`CH0335_EyeMouth` / `Aris_Original_EyeMouth`（一张 128×128 的单眼图，
  两只眼共用、其中一只镜像）。换瞳色就是换这张图。

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
├─ project.godot            主场景=game.tscn；输入映射；autoload 挂工具；[gdgs] 后端=Compute（§6.11）
├─ LICENSE                  MIT（除模型与美术素材外的全部内容）
├─ THIRD_PARTY.md           第三方组件与素材许可说明（哪些不随仓库分发）
├─ .gitignore               排除私有素材（模型 / 泼溅数据）与 Godot 缓存
├─ addons/
│  └─ gdgs/                 GDGS 3.3.0 高斯泼溅插件（**纯 GDScript，无 DLL**，MIT，第六节）
├─ assets/
│  ├─ ui/                   界面**内置**皮肤：Kenney 九宫格（CC0）+ FusionPixel 中文字体（OFL，§1.12）
│  ├─ ui_font/              **界面显示字体投放目录**：放进来就整套 UI 换字
│  │  └─ README.md          说明（字体本身被 .gitignore 排除，只留这份说明）
│  ├─ ui_sprout/            Sprout Lands 皮肤 ※不随仓库分发（授权禁止再分发，§1.12）
│  └─ sfx/                  **音效**：13 个 Kenney .ogg（**CC0，随仓库分发**，§1.14）
│     ├─ README.md          逻辑名 ↔ 文件对照 + 怎么加新音效
│     └─ LICENSE_Kenney_CC0.md  来源与许可（为什么这批能进仓库而模型不行）
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
│  │  ├─ Kei.glb            凯伊原模型（166 骨、32 动作，另有 3 个附属 skin）
│  │  └─ Kei_ext.glb        凯伊**实际使用**的模型（同上，跑动前折已修，见 §8.8）
│  ├─ boss/                 霸王龙优香 FBX + 贴图（第七节）※不随仓库分发
│  └─ boss_pig/             飞猪优香 FBX + 贴图 + 作者的对照渲染图（§7.6）※不随仓库分发
├─ splatdata/
│  ├─ README.md             说明：泼溅数据要求与摆放参数
│  ├─ school_playable.sogdata  **实际加载**的校园泼溅（清理版，86.6 MB）※不随仓库分发
│  ├─ school_raw.sogdata       原始未清理扫描（仅存档）※不随仓库分发
│  └─ room609.sogdata          「画室 609」扫描（40.7 MB / 2,774,116 点，裁后 2,769,851）※不随仓库分发
├─ story/
│  ├─ 开场.txt              **剧情剧本**（UTF-8 纯文本，改这个文件就能改剧情，第九节）
│  └─ 设定.md               **角色表 / 场景表**（人看着写 + `story_script.gd` 解析来校验说话人，§9.8）
├─ scenes/
│  ├─ game.tscn             玩法场景（40×40 悬浮平台 + 平台上的画室609（§6.8，有墙碰撞和门洞）
│  │                        + 手工搭的**网格小屋**（§1.13）+ 2 位 Boss + 7 名同伴 + 对话框；
│  │                        **无护栏**；校园**不在**这里）
│  ├─ mesh_hut.tscn         手工网格场景：基元 + CSG 的小屋子（§1.13，不依赖任何外部素材）
│  ├─ campus_venue.tscn     校园泼溅的**独立场地**（已从 game.tscn 搬出，按需实例化，§6.5）
│  ├─ player.tscn           玩家（模型 + 动画 + 武器 + 相机）
│  ├─ companion.tscn        同伴（模型由 companion.gd 按 model_path 运行时实例化）
│  └─ main.tscn             动画查看器
├─ scripts/
│  ├─ player.gd             移动 / 相机 / 朝向 / 开火转身门控
│  ├─ companion.gd          同伴跟随：站位 / 走近跑近 / 朋友层（第八节）
│  ├─ anim_driver.gd        动画驱动（直接 AnimationPlayer）
│  ├─ weapon.gd             开火 / 弹药 / 换弹 / 弹丸 / 特效 / 子弹穿透朋友层
│  ├─ boss.gd               Boss 基类：骨架盒 or 网格盒定尺寸、贴图表、血条信号（第七节）
│  ├─ boss_attacker.gd      Boss 攻击机制：预警圈 = 伤害区 + 冷却 + 击退（§7.5）
│  ├─ trex_boss.gd          霸王龙优香（重击型）的参数与表现（§7.5）
│  ├─ pig_boss.gd           飞猪优香（骚扰型）的参数与表现（§7.5）
│  ├─ companion_gun.gd      同伴的枪：自己选目标开火，不误伤 / 不隔墙（§8.7）
│  ├─ game_settings.gd      全局设置：存值 / 落盘 / 广播（**静态类**，§1.12）
│  ├─ settings_menu.gd      Esc 设置界面：代码构建 UI + 暂停 + 像素皮肤（§1.12）
│  ├─ story_script.gd       剧情剧本的**解析 + 校验**（含角色表/场景表，纯静态类，逐行报错，第九节）
│  ├─ dialogue_box.gd       剧情对话框：打字机 / 翻页 / 播放时暂停世界（第九节）
│  ├─ ui_skin.gd            界面皮肤（两套）+ 血条样式 + MC 风格 Boss 条 + **中文字体**（§1.12）
│  ├─ sfx.gd                **音效库**：逻辑名 → 候选文件 + 音量/音高/节流 + 播放池（静态类，§1.14）
│  ├─ splat_scene.gd        高斯泼溅接入器：后台线程解码 + 自动摆放 + 锚点摆放 + 裁剪（第六节）
│  ├─ sog_runtime.gd        运行时 SOG 解码器（绕开编辑器导入器，第六节）
│  ├─ target.gd / hud.gd / game.gd / main.gd
│  │                        （hud.gd 的泼溅状态、Boss 血条都是**一份场地/一位 Boss 一行**）
│  ├─ _verify_*.gd          [工具] 自检（见 §1.11、§7.6、§8.4、§6.8、§9.4）
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
│  ├─ _probe_collapse.gd    [工具] 动态 3DGS 三效果（坍缩/布朗/上升）验证 + 出图，§6.9
│  ├─ _probe_sort_cost.gd   [工具] Raster 排序耗时 + **源顺序空间局部性**（纯 CPU），§6.10
│  ├─ _probe_stale_order.gd [工具] 量「快速转身后排序表多久才更新」+ 组顺序精度质检，§6.10
│  ├─ _probe_room_collision.gd [工具] 把画室609 的**生成式房间碰撞**导成可粘的 .tscn 文本，§6.8
│  ├─ _probe_platform_free.gd [工具] 量平台上还剩哪块空地（ASCII 地图 + 分离轴判交 + 候选落点表），§1.13
│  ├─ _probe_hut_shot.gd    [工具] 给网格小屋出 5 个机位的图，§1.13
│  ├─ _probe_splat_quality.gd [工具] 同一视角拍「当前 / 原生 / 关后处理 / 关 MSAA」四档对照图，§6.6
│  ├─ _probe_splat_perf.gd   [工具] **可信的**帧率表（关垂直同步 + 预热 + 交错重复 3 轮），§6.6/§6.11
│  ├─ _probe_splat_backend.gd [工具] Raster vs Compute 后端同视角出图 + 深度剔除偏置扫描，§6.11
│  ├─ splat_compositor.gd    autoload：给当前相机自动挂 CompositorEffect（Compute 后端必需），§6.11
│  └─ _probe_*.gd           [工具] 一次性探针（口型/枪口/时间线/泼溅渲染/FPS）
├─ tools/
│  └─ font/                 [工具] 查字体有没有你要的那些字（纯标准库 Python，§9.5 坑 1）
│     ├─ font_needed.py       把「游戏里实际会显示的每个字」对着 cmap 查一遍
│     └─ font_cmap_check.py   底层 cmap 解析 + 覆盖率区块统计
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
| 驱动器引用的 4 条动作 | `Normal_Idle` / `Move_Ing` / `Normal_Attack_Ing` / `Normal_Reload` **两边全在**（`Cafe_Walk` 也在模型里，但本工程不播它，§1.17） |
| `Move_Ing` / `Normal_Attack_Ing` / `Normal_Reload` 时长 | **完全一致**（0.6667 / 2.6667 / 2.0000 s）→ `CYCLE_SPEED` 表不用改 |
| `Normal_Idle` / `Cafe_Walk` | 只差 0.5 / 1.0 帧（≤1.3%，无感） |
| `RESET` | 只有原版有；它是 glTF 的 rest pose，驱动器从不引用 |
| 骨骼数 | 都是 170 |
| 动画总数 | 25（24 + RESET）→ 27（24 + 三条新动作） |

切完 5 套玩法自检（**当时** 58 项）与泼溅自检（**当时** 15 项）全绿，见 §1.11。

> ⚠️ 上面这两个数字是**那次替换时**的，套件后来扩过好几轮。
> **当前**每套各多少项、合计多少，以 §1.11 的清单为准（现在合计 305 项）。

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
| 后端 | 项目设置 `[gdgs] rendering/backend="Compute"` + autoload `SplatCompositor` 自动给当前相机挂 `CompositorEffect`。**为什么必须选 Compute（而不是插件的另一套 Raster），见 §6.11** |
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
  - 历史：那圈护栏刻意只做 0.7 m（当时的跳跃顶点 0.87 m），好让助跑起跳能翻出去看校园；
    （跳跃手感在 §1.15 调过一轮，现在是 **1.32 m** —— 护栏早就删了，这条只作历史记录）
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

### ⚠️ 分辨率、MSAA 与「物理时间稀释」：全屏会让 WASD 看起来失灵

> **病根订正**：本节原先把下面的 2.0 fps 归咎于**渲染面积**，是错的。那组测量本身
> 没问题，但**真凶是 `msaa_3d = MSAA_4X`**。当时据此加的「按面积开方缩小 3D 分辨率」
> 补丁等于把开销从错的地方挪到另一个错的地方 —— 画面被降了 4 倍高频细节，MSAA 的
> 开销却一点没省。订正后的数字见下面「真凶是 MSAA 4×」那一节。

`project.godot` 现在默认**最大化窗口**（`window/size/mode = 2`）。刚打开全屏时，
本喵在画室609（277 万高斯）上量到一组极具误导性的数字：

| 渲染尺寸 | 渲染 fps | **物理帧/秒** | 按 1.5 s 的位移 | 实际速度 |
|---|---|---|---|---|
| **2560 × 1440（全屏）** | **2.0** | **16**（额定 60） | 0.17 m | **0.11 m/s** ⚠️ |
| 1600 × 900 | 20.0 | 64 | 3.0 m | 1.98 m/s ✅ |

**关键在物理那一列**：Godot 每帧最多只跑 `max_physics_steps_per_frame`（默认 **8**）
步物理，所以渲染掉到 2 fps 时 1 秒只推进 2 × 8 = 16 步 —— 只有额定 60 步的 1/3.75，
**物理时间被稀释**，玩家真实速度被打成 **1/18**。症状是「WASD 按了几乎不动」，
和「输入坏了」一模一样。本喵因此**误判过一整轮**：先用 `Input.action_press()`
测出能走 1.93 m，就断定「输入没问题」—— 可那次是**窗口化**跑的，换成全屏才暴露。

> ⚠️ **诊断办法**：位移必须和**帧率、物理帧数**一起报，否则分不清
> 「物理被稀释」和「被碰撞卡住」这两种病。`scripts/_probe_gameplay_input.gd`
> 就是干这个的。另外 `Input.action_press()` **绕过了键盘**，只证明移动逻辑没问题，
> 证明不了「按键能到游戏」—— 要验那条链路得用 `Input.parse_input_event(InputEventKey)`。

#### 真凶是 MSAA 4×，修法是关掉它

用 `scripts/_probe_splat_perf.gd`（**关垂直同步**、每档**预热 15 帧再连测 40 帧**、
三档**交错重复 3 轮**）重测同一台机器、2560×1334：

| 配置 | 三轮 fps | 中位 |
|---|---|---|
| `scale 0.649` + **MSAA 4×** + ACES/辉光/SSAO/雾/调色 | 58.9 / 53.9 / 54.0 | **54.0** |
| `scale 1.000` + **无 MSAA** + 同上后处理 | 43.2 / 42.0 / 44.2 | **43.2** |
| `scale 1.000` + **无 MSAA** + 只留 ACES | 44.0 / 44.4 / 40.4 | **44.0** |

> ℹ️ 这张表是在**后端 = Raster** 时测的（那时它是默认）。切到 Compute 之后
> C1 那一档（0.649 + MSAA 4×）会崩到 **12 fps** —— 见 §6.11 的雷区警告；
> 本工程实际用的 C2/C3 在 Compute 下反而更快。
>
> ⚠️ 量法本身也很关键：第一版探针（`_probe_splat_quality.gd`）开着垂直同步、只测
> 一轮，同一档三次跑差了 **2~30 倍**。那列 fps 是噪声，别引用。

三条结论：

1. **MSAA 4× 即使缩到 0.649 也要生成 1662×866×4 = 576 万采样**，比原生无 MSAA 的
   2560×1334 = 341 万还多 —— 分辨率一直是被 MSAA 挤掉的，不是它自己太贵。
2. **MSAA 对泼溅几乎不涨锐度**：它的作用范围只有 quad 的几何边缘，而高斯的柔边
   来自 fragment 里的 alpha 衰减（`alpha_to_coverage` 也没开）。
3. 辉光 / SSAO / 雾 / 调色在**原生分辨率**下测不出代价（43.2 vs 44.0），可以留着。

所以现在改成：`project.godot` 的 `rendering/anti_aliasing/quality/msaa_3d = 0`，
`game.gd::_fit_render_scale()` 的触发阈值从「面积比 < 0.8」放宽到
`RENDER_SCALE_AREA_RATIO_MIN = 0.16`（≈6 倍设计面积，只有 4K 以上才会碰到）。
净效果：**同一取景下黑板那块的高频能量涨 4.06 倍**（右墙海报 2.14 倍），
只付 −20% 帧率，物理仍有 43 / 7.5 ≈ **5.7 倍余量**。

| 取景区域（同一视角、同一裁切） | 订正前（0.649 + MSAA 4×） | 订正后（原生 + 无 MSAA） |
|---|---|---|
| 黑板（约 12 m 外） | 99.8 | **405.2（4.06×）** |
| 右墙海报（约 8 m 外） | 22.9 | **49.1（2.14×）** |
| 吊扇（约 9 m 外） | 1.4 | 1.9（1.37×） |

读数是「拉普拉斯方差」（裁同一块区域算高频能量，越大越锐）；对照图与逐项读数在
`_arisu_captures/_quality/_compare.png` 与 `_perf.txt`，工具是
`scripts/_probe_splat_quality.gd`（只出图）与 `scripts/_probe_splat_perf.gd`（只出帧率）。

> ⚠️ 这只解决了「像素不够」那一半。同一批图还暴露出另一半是**后端管线**问题 ——
> Raster 后端在 Forward+ 下是在**错误的颜色空间**里合成泼溅的，那一半的差距比
> 分辨率还大（右墙海报锐度 +89%）。见 **§6.11**。

护栏本身仍然保留 —— 物理稀释是真实机制，8K 屏上照样会撞。另外这里踩过两个坑，
都是「量法/API 用错」而不是逻辑错：

1. **不能用 `get_visible_rect().size`** —— `canvas_items` 拉伸模式下它返回的是
   **画布矩形**（= 设计分辨率 1600×900），跟真实渲染尺寸无关。要用 `Viewport.size`
   （= `Window.size` = 渲染目标的像素数）。第一版用错了，于是在 2560×1440 下算出
   「不用缩放」，白改一轮。
2. **不能只在 `_ready()` 里算一次** —— 那一刻窗口还没变成全屏尺寸；回到设计分辨率时
   也必须**显式设回 1.0**，不能「提前 return 什么都不做」。所以挂在 `Viewport.size_changed` 上。

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
| `world_scale` | **4.25** → 世界约 **23.9 × 8.3 × 27.2 m**（包围盒，按源测量比例换算） |
| `yaw_degrees` | **248.6**（把房间矩形转成轴对齐，见下） |
| 摆放 | `auto_place = false` + `use_anchor = true`，把源坐标的地板中心 (0.022, −0.333, −0.121) 对到 **(0, 0.03, 4.25)** |
| 地板平面（实测） | y = **0.062** |
| 房间范围（实测） | x ∈ [−12.31, 11.59]，z ∈ [−9.57, 17.64] —— 正好**不探出** 40 × 40 平台 |
| 顶面 / 相机 | 顶面 y = 6.38，玩家相机 y = 1.79 → **头顶余量 4.59 m** |
| 碰撞 | **手摆在 `game.tscn` 里的 5 个盒**：4 面墙（厚 0.3 m），z− 那面被 **1.6 m 门洞**切成 2 段（见下「房间碰撞」） |
| 帧率 | 现在场上**只有这一份**泼溅（校园已搬走），独占那 ≈ 2.9 GiB 的显存预算 |

### 为什么采用 ×4.25

* ×6.4：房间约 36 × 41 m，桌椅相对 Arisu 显得过大
* ×1.8~2.0：接近扫描源文件的真人比例，但净高过低、相机余量不足
* **×4.25（当前）**：在保留较宽敞室内空间的同时，缩小霸王龙与 +X 墙的碰撞冲突；边界、门洞和相机净空以 `_verify_room.gd` 实测断言为准

⚠️ 缩放调整后仍需复跑以下硬约束（均由 `_verify_room.gd` 验证）：

1. **相机到天花板 > 0.6 m**，避免上半屏紧贴天花板
2. **出生点必须在房间的 xz 范围内**，保证第三人称相机位于室内

### 当前场景几何（×4.25 实测）

| 项 | 实测值 |
|---|---|
| 房间包围盒 | **23.9 × 8.3 × 27.2 m**（= 源 5.63 × 1.95 × 6.41 × 4.25） |
| 房间 xz 范围 | x ∈ [−12.31, 11.59]、z ∈ [−9.57, 17.64] |
| 顶面 / 相机 | 顶面 y = 5.43、相机 y = 1.79 → **头顶余量 3.64 m** ✅（> 0.6） |
| 出生点 | (0, 6) —— 在房间内 ✅ |
| 门洞 | z− 面，宽 1.6 m，居中 |
| 碰撞盒 | 5 个，墙厚 0.30 m（**手摆**在 `game.tscn` 里，见下） |

⚠️ 缩放从 ×5 降到 ×4.25 之后，**两位 Boss 都落到墙外了**：霸王龙在 x = 13、
飞猪在 x = −13，而房间只到 ±12.3 左右。这和 ×5 时刚好相反（那时霸王龙的碰撞盒
有 0.72 m 卡进 +X 墙里）。现在想打 Boss 得先从 **z− 的门洞走出去** ——
门正对着靶场，出生时面朝 −Z 就是朝门。

### 为什么房间要「罩着出生点」而不是摆在平台正中央

这一条是缩放改小时才暴露的：出生点在 (0, 0.05, 6)，而第三人称相机在玩家
**背后 3.5 m**（z ≈ 9.5）。如果房间只有 13 m 深却摆在平台正中央（z ∈ [−5.9, 5.6]），
出生点就正好贴在 z+ 的墙上，**相机（z ≈ 9.5）会落到房间外面**，开局看到的是
房间的**外墙** —— 而这份扫描只扫了室内，从外面看是一片糊（`73_door_from_outside.png`
就是这个观感）。

所以 `anchor_world` 用 (0, 0.03, **4.25**)，房间罩住出生点：×4.25 实测房间
z ∈ [−9.6, 17.6]，相机 z ≈ 9.5 稳稳在室内。门开在 **z−**（朝靶场那一面），
出生时面朝 −Z 就正对着门，走出去再走几米就是靶子和 Boss。

`_verify_room.gd` 把这条当成断言验：**出生点必须在房间的 xz 范围内**。

### 房间碰撞：手摆在场景里的 5 个盒（4 面墙 + 1 个门洞）

碰撞**不再由脚本生成**，而是作为普通节点摆在 `game.tscn` 里：

```
Room609
└─ RoomCollision (StaticBody3D)
   ├─ WallXNeg    ┐
   ├─ WallXPos    │ 厚 0.3 m，高 8.2994，盒中心 y = 1.2768
   ├─ WallZNegA   │ z− 那面被 1.6 m 门洞切成两段
   ├─ WallZNegB   ┘
   └─ WallZPos
```

| 墙 | 盒中心 (x, y, z) | shape.size |
|---|---|---|
| `WallXNeg` | (−12.1596, 1.2768, 4.0346) | (0.3, 8.2994, 27.2121) |
| `WallXPos` | (11.4437, 1.2768, 4.0346) | (0.3, 8.2994, 27.2121) |
| `WallZNegA` | (−6.5548, 1.2768, −9.4215) | (11.5096, 8.2994, 0.3) |
| `WallZNegB` | (6.1968, 1.2768, −9.4215) | (10.7937, 8.2994, 0.3) |
| `WallZPos` | (−0.358, 1.2768, 17.4907) | (23.9033, 8.2994, 0.3) |

门洞实测 **x ∈ [−0.8, 0.8]、宽 1.6 m、中心 0**。

**为什么从「脚本生成」改成「手摆」**：生成式碰撞在编辑器里**根本不存在** ——
`build_box_collision` 是在运行时 `_finish()` 里建的（`splat_scene.gd::_build_box_collision`），
所以编辑器树里找不到、看不见、也拖不动。改成节点之后就能直接选中拖手柄、
或在检查器里改 `shape.size`。

⚠️ **`build_box_collision` 现在必须保持 `false`**，否则脚本会再生成一个同名
`RoomCollision`，两套碰撞叠在一起（而 `_verify_room.gd` §5 要求**恰好 5 个盒**）。

⚠️ **盒的数值是静态的**，和 `world_scale` / `yaw_degrees` / `anchor_*` / `crop_*`
绑死 —— 那串数字是把生成算法的输出**抄**进来的。所以房间参数一改就要重新导出并覆盖：

```powershell
& $g --headless --path $p --script res://scripts/_probe_room_collision.gd
# 把 stdout 里「粘进 game.tscn 的文本」那段贴回去（同时也写到
# ..\_arisu_captures\_collision\room609_room_collision.txt）
```

`box_wall_thickness` / `box_door_side` / `box_door_width` / `box_door_center`
**保留为参考值**：`_verify_room.gd` §5 拿它们校验手摆的盒 —— 数量、门洞宽度与中心，
外加「冲刺撞 x+ 墙被挡住」与「从门洞走出去」两个物理跑测。只改盒不改这几个数，
或者只改这几个数不改盒，都会被它抓出来。

#### ⚠️ 手摆的碰撞是「无条件存在」的 —— 跳过加载时必须关掉

这是把碰撞从生成改成手摆后**唯一的语义变化**，而且它真的咬过人：

生成式碰撞挂在 `_finish()` 里，所以 `--splat=off`（或 `--venue=` 不匹配）时
**根本不会生成**，那 11 套带 `--splat=off` 的自检里场上是一间**没有墙的**房间，
子弹想怎么飞怎么飞。改成场景里的静态节点之后，墙**不受加载与否影响** ——
一进场景就在那儿，于是那批自检里凭空多出四面**看不见但打得中**的墙。

实测后果（一次跑出 7 套红，全指向同一件事）：

| 套件 | 红项 |
|---|---|
| `_verify_final` §6 | 靶子掉血 100 → 100（准星压着也打不掉） |
| `_verify_mag` | 靶子掉血 100 → 100 |
| `_verify_turnfire` | 连发期间弹道正确命中靶子 |
| `_verify_boss` / `_verify_boss_pig` | 子弹射线打不到本体；没挡住自检弹道 |
| `_verify_companion_attack` | 同伴开了 0 次火、靶子 5000 → 5000 |
| `_verify_companion` | 七人没跟上/没走回站位、屏幕位置互相挤在一起 |

全都因为那条自检弹道「玩家(6,−4) → Target1(6,−10)」在 z = −9.3 处撞上了
z− 墙（门洞只有 x ∈ [−0.8, 0.8]，而弹道在 x = 6）。

**修法**：`splat_scene.gd` 的两条「跳过」路径都会调 `_disable_placed_collision()`，
把自己名下**预先摆好的** `CollisionObject3D` 全部 `collision_layer = 0`
（不是 `queue_free()` —— 不改场景树、可逆、也不影响自检去数节点）。
语义回到改之前：**没加载的场地不留碰撞**。

⚠️ 以后再加手摆的碰撞节点，记得它是挂在 `SplatScene` 下、会被这条规则一起关掉；
如果你**希望**某块碰撞在 `--splat=off` 时仍然生效，它就不能挂在这个节点下面。

**为什么不用 GDGS 自带那条「从点云生成碰撞网格」的管线**：那要给 277 万点建体素索引
再 marching cubes，慢且结果不可控；这间房**已经轴对齐**、形状就是个矩形，
四面盒子又稳又快，而且哪面是门可以明确指定。

⚠️ 关于「门开在哪一面」本喵量过、量不出来，最后是**按玩法定的**：先试着在
「地板面 ~ +1.2 m」这条带里找墙上的空缺，结果发现这条带里**全是桌椅**（打出来的
XZ 占用图里能看到两排桌椅和中间的走道），墙在 1.2 m 以下几乎没有点；改用包围盒面
去找更糟 —— 包围盒两端那 0.1% 的离群点把面推到了墙外面（x− 面附近 0.35 m 内
**一个点都没有**）。所以门的位置是**设计选择**（朝靶场、正对出生点），不是量出来的，
换数据别指望生成算法能自动找到门 —— 这也是把碰撞改成手摆的一个附带好处：
门的位置现在就是场景里两个盒之间的缝，肉眼可见、随手可挪。

生成算法本身（`splat_scene.gd::_build_box_collision`）**保留着**，`build_box_collision`
默认 `false`；换新数据时先把它打开跑一遍，用 `_probe_room_collision.gd` 导出结果再手摆。

`_verify_room.gd` §5 会真跑物理验证（×4.25 下的实测值）：撞 x+ 墙被挡在墙内面
（停在 **x = 10.99** = 墙内面 11.29 − 胶囊半径 0.3），以及从门洞走出去
（z 从 4.25 跑到 **−10.65**，门在 z = −9.57）。

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
& $g --path $p --script res://scripts/_verify_room.gd      # 54 项
```

它会在**入树前**把校园那份摘掉（`_ready()` 是 `add_child` 时才跑的，此刻摘掉就不会
开始解码），然后验：场景结构 / 点数与裁剪统计 / 地板 y 与质心 / **出生点在房间里** /
**相机到天花板的余量** / 世界尺寸 / 轴对齐（含合成自检）/ floaters 是否真裁干净 /
**墙碰撞与门洞（真跑物理）** / HUD 多行是否按行号路由 / Arisu 的朝向 / 7 张渲图。

---

## 6.9 动态 3DGS：坍缩 / 布朗抖动 / 粒子上升

给泼溅加了三个随时间运动的逐高斯效果。**两条实现路线**，选哪条取决于要不要
「每个高斯各自行动」：

| 路线 | 何时用 | 原理 | 后端 |
|---|---|---|---|
| 节点缩放 | `collapse_mode = "uniform"` | 把系数乘进 `_local_basis()` | Compute + Raster |
| 着色器逐高斯 | `staggered` / 布朗 / 上升 | 在 `gaussian_raster.gdshader` 里按 `sidx` 逐高斯求值 | **仅 Raster** |

### 路线一：节点缩放（`uniform`）

白捡的一条路 —— 两套后端本来就共用了这两行：

```glsl
vec4 world_pos = MODEL_MATRIX * vec4(splat_pos, 1.0);              // 位置吃 basis
mat3 world_cov = object_linear * cov3d * transpose(object_linear);  // 尺度吃 basis²
```

`MODEL_MATRIX` 就是 `GaussianSplatNode` 的变换：后端把 MultiMeshInstance3D 作为
**INTERNAL 子节点**挂上去（`raster_render_backend.gd` 原注释写着 *"inherits the
node's transform"*）。所以把系数乘进 `_local_basis()`，所有高斯会**同步**等比变小
并向 `offset` 收敛，**插件一行都不用改**。

`use_anchor` 时 `offset = anchor_world − basis·anchor_source`，basis→0 时
`offset→anchor_world` —— 于是**坍缩点精确可控**。测试场景钉在原点，实测
`坍缩点 = (0.000, 0.000, 0.000)`。

判据：包围盒尺寸必须**精确**等于 `k × 原尺寸`。

| t | 系数 k | 实测尺寸 | 判定 |
|---|---|---|---|
| 0.000 | 1.00000 | 16.89 | OK |
| 0.500 | 0.87500 | 14.78 | OK |
| 0.850 | 0.38587 | 6.52 | OK |
| 1.000 | 0.00040 | 0.01 | OK |

9 档 0 档不符，小数点后 4 位吻合。**不取 0**：全 0 的基矩阵是奇异的，Godot 会报错。

### 路线二：着色器逐高斯（错峰 + 布朗 + 上升）

节点缩放做不到「每个高斯各自行动」，所以另开一条：

| 文件 | 职责 |
|---|---|
| `addons/gdgs/.../materials/gaussian_raster.gdshader` | 按 `sidx` 逐高斯求值 |
| `addons/gdgs/.../raster/raster_render_backend.gd` | `_drive_collapse()` 每帧轮询节点属性 → 推入材质 |
| `addons/gdgs/runtime/nodes/gaussian_splat_node.gd` | `Dynamic` 组导出，**只是数据，不含逻辑** |
| `scripts/splat_scene.gd` | 对外参数 + 每帧刷新 |

**每个高斯的随机数不占一点显存。** 光栅路径里 `sidx` 在 `use_order` 打开后就是
**源索引**，直接拿它做哈希当种子：

```glsl
float r = anim_hash01(float(sidx) + float(anim_seed));
```

277 万点若各存一个随机数要十几 MB，哈希是零成本；而且**种子稳定** ⇒ 每个高斯的
错峰时刻与漂移方向在整个动画里不会逐帧乱跳。

#### 三个效果

| 效果 | 主要参数 | 数学 |
|---|---|---|
| 错峰坍缩 | `collapse_stagger` | `lt = clamp((t − r·stagger)/(1−stagger), 0, 1)`；位置 `mix` 向 `anim_center`，协方差乘 `(1−e)²` |
| 布朗抖动 | `brownian_amp` / `brownian_freq` | 两段八度正弦叠加，以**原位置为中心**，硬上界 `1.5 × amp` |
| 粒子上升 | `rise_speed` / `rise_jitter` / `rise_span` / `rise_side` / `rise_loop` | 每高斯随机速度倍率 `[1−j, 1+j]`，`splat_pos.y += speed·sp·t` |

⚠️ **错峰公式里的 `/(1−stagger)` 是必需的** —— 它同时做归一化，保证所有高斯仍在
`t = 1` 处收齐，否则错峰越大尾巴拖越长。

⚠️ **`rise_fade` 必须 > 0。** 循环模式靠 `fract(risen/span)` 把粒子送回底部，各高斯
速度不同 ⇒ 回绕时刻也不同（所以不会整场同时跳一下）；但**单个**粒子的回绕仍会
瞬移，必须靠两端淡出遮住。侧向偏移乘 `ph` 是同一个道理：从底部出发时偏移恰为 0，
而那一刻正被淡出遮住。

⚠️ **`min_pixel_size` 后端没设**（保持 shader 默认 `0.0`），所以次像素剔除是关的。
收缩过程中高斯不会突然消失，会一路平滑缩到重叠、中心越来越亮 —— 这是「坍缩成
奇点」该有的观感，不是 bug。

#### 验证：三种判据，各有各的适用范围

| 效果 | 判据 | 为什么必须换 |
|---|---|---|
| `uniform` | 包围盒 = `k × 原尺寸` | 节点缩放确实改变包围盒 |
| `staggered` | **画面覆盖率** | 逐高斯坍缩**不缩放节点**，包围盒纹丝不动，原判据失效 |
| 上升 | **亮度重心上移** | 对整体缩放免疫（等比放大会把所有像素一起放大，重心不动）⇒ 重心上移只可能来自粒子真的位移 |
| 布朗 | **同一 t 连拍两帧做像素差** | 单帧看不出抖动；两帧的 `collapse_t` 与节点变换完全相同，**唯一变量是时间** |

实测（`--mode=staggered --stagger=0.6 --brown=0.02 --rise=0.6`）：

- 覆盖率 `0.2169 → 0.0000`
- 同 t 两帧像素差：均值 `1.309` / 峰值 `164` / **4.88%** 像素明显变化
- 上升：亮度重心 `0.5943 → 0.5523`（上移 **4.20%** 屏高）
  手算校验：`0.6 源单位/秒 × 0.9 s × 2.5 = 1.35 m`，相机距原点 27.8 m、
  fov 60° ⇒ 屏高 32.1 m ⇒ `1.35 / 32.1 = 4.2%` —— **实测与预测吻合到小数点后一位**

⚠️ **上升与世界无关的判据要用「手动时钟」跑**（`dynamic_auto_time = false`），
否则两次拍摄之间到底过了多少真实时间取决于渲染帧率，位移量会飘。本工程在帧率上
栽过两轮（headless 约 6 fps / 真窗口实测约 2000 fps，见 §1.11）。

⚠️ **改着色器时最容易犯的错是「声明了 uniform 却没在 `vertex()` 里用」。**
本喵就这么栽过：uniform 与噪声函数都加好了，`vertex()` 里忘了调用，覆盖率五档
纹丝不动（`0.2167`）才暴露出来 —— 着色器**不报错**，只是什么都不做。所以判据
必须能测出「有没有真的生效」，不能只看有没有编译错误。

### 探针

```powershell
# 逐高斯错峰 + 布朗：覆盖率 + 同 t 像素差
& $g --path $p --script res://scripts/_probe_collapse.gd -- `
      --sog=res://splatdata/collapse_test.sogdata --scale=2.5 `
      --mode=staggered --stagger=0.6 --brown=0.02 --brownfreq=1.5 `
      --t=0,0,0.4,0.7,0.9,1.0

# 粒子上升：亮度重心上移（手动时钟，每档 +0.3 s）
& $g --path $p --script res://scripts/_probe_collapse.gd -- `
      --rise=0.6 --risejitter=0.8 --risespan=1.5 --riseloop=0 --risestep=0.3 `
      --t=0,0,0,0
```

输出到 `..\_arisu_captures\_collapse\`（帧名带全局拍摄序号 `_iN`）。
拼图与像素差用同目录的 `check.py`，**必须用自带的 Python** —— 系统那个没有 Pillow：

```powershell
& "C:\Users\WY157\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe" `
      check.py C:\Users\WY157\Desktop\GODOT\_arisu_captures\_collapse
```

### 对外接口

```gdscript
$Room609.collapse_enabled = true
$Room609.collapse_mode = "staggered"   # uniform = 节点缩放，两后端通用
$Room609.collapse_stagger = 0.6
$Room609.collapse_shader_fade = 1.0
$Room609.brownian_amp = 0.02           # 源坐标单位；这份扫描 6.8 单位宽
$Room609.brownian_freq = 1.5
$Room609.rise_speed = 0.6              # 源坐标/秒
$Room609.rise_loop = true
$Room609.rise_span = 1.5
$Room609.play_collapse()               # 或 set_collapse(0.5) 手动驱动
```

⚠️ **这三个效果只有 Raster 后端实现了**。Compute 侧的 `gsplat_projection.glsl`
有它自己的一套 `time_factor` 入场动画，但**没有**错峰坍缩、布朗漂移与上升，所以
本项**不保持两后端 parity** —— 这与那两个文件顶部声明的「协方差 / 重光照 parity」
是两码事，后者没动。

⚠️ 三个效果**可以叠加**：它们是相互独立的偏移量。`_advance_dynamic` 只在
「错峰模式 **或** 布朗 **或** 上升」任一开启时才每帧推参数，三者全关时零开销。

⚠️⚠️ **而本工程现在的默认后端是 Compute（§6.11）**，因为 Raster 在 Forward+ 下
的颜色合成空间是错的（会把画面拖灰拖糊）。要看这三个效果就得**
临时把 `gdgs/rendering/backend` 改回 `"Raster"` 重启**——`_probe_collapse.gd`
那套演示只在 Raster 下有效。

---

## 6.11 ⚠️ 必须用 Compute 后端：Raster 在 Forward+ 下会在错误的颜色空间合成

### 现象

画室609 在游戏里**发灰、发糊、对比度低**，同一份数据在网页查看器（SuperSplat /
知天下）里却通透锐利。**在同样的分辨率、同样的 MSAA、同样的色调映射下**都差一截 ——
所以这不是分辨率问题。

### 根因：两套后端在**不同的颜色空间**里累加泼溅

| | Raster | Compute |
|---|---|---|
| 合成空间 | **线性** —— `fragment()` 里**逐高斯**先 `srgb_to_linear(albedo)`，再走 Godot 标准透明混合 | **sRGB(γ)** —— 在离屏 `rgba32f` 缓冲里按 γ 空间累加，**最后一次性**转线性再叠回场景 |
| 排序 | CPU 计数排序 + **组宽 32 近似**（§6.10） | **GPU 基数排序，逐高斯精确** |
| 光栅化 | 每高斯一个 instanced quad，走硬件透明通道 | 16×16 瓦片 → 独立缓冲 → Compositor 合成 |
| 与场景网格的遮挡 | 硬件深度测试，**几何精确** | 深度剔除 + `depth_bias`，**要调**（见下） |

Compute 侧的 `runtime/compositor/shaders/gaussian_composite.glsl`：

```glsl
vec3 gsplat_straight = unpremultiply_color(gsplat_color.rgb, gsplat_alpha);
vec3 gsplat_linear   = srgb_to_linear(gsplat_straight) * gsplat_alpha;  // ← 先累加，后转
vec3 composited_color = gsplat_linear + scene_color.rgb * (1.0 - gsplat_alpha);
```

3DGS 的 SH 与 alpha 是在 **γ 空间**训练的，参考实现也在 γ 空间累加。γ→线性是凸函数，
`mean(linear(c)) ≥ linear(mean(c))`，所以线性空间累加会**抬亮暗部、压平对比**。
一个像素上叠 10~50 层高斯时这个偏差会累积成肉眼可见的"灰雾"。

插件作者自己知道这件事，`raster/materials/gaussian_raster.gdshader` 第 143-152 行的
原注释就写着 *"the **blend-space difference is inherent to the standard pipeline**"*。
而且 `OUTPUT_IS_SRGB` 只在 **Compatibility** 渲染器下为真 —— 也就是说
**Raster 后端只有在 Compatibility 上才是对的**，Forward+ 上必然走错空间。

> 这条对别的引擎同样成立：任何"线性 HDR 管线 + 不做特殊处理的泼溅材质"都会踩，
> UE 的延迟管线就是典型。

### 实测（同一相机、2560×1334、同 ACES、同关 MSAA，**只换后端**）

| 取景区域 | 指标 | Raster | Compute | 变化 |
|---|---|---|---|---|
| 右墙海报 | 锐度（拉普拉斯方差） | 49.2 | **92.8** | **+89%** |
| | 平均饱和度 | 0.052 | **0.070** | +35% |
| | 对比度（亮度 σ） | 0.121 | **0.157** | +30% |
| 黑板 | 锐度 | 404.8 | **439.7** | +9% |
| | 饱和度 | 0.158 | **0.200** | +27% |
| 地板斑驳 | 锐度 | 920.4 | **1050.6** | +14% |

### 帧率：Compute 更快，**但和 MSAA 4× / 降分辨率放在一起会崩**

用 `scripts/_probe_splat_perf.gd`（关垂直同步、每档预热 15 帧再连测 40 帧、
三档**交错重复 3 轮**，所以同一行里的三个数才可比）分别强制两个后端各跑一遍：

| 配置 | Raster 三轮 / 中位 | Compute 三轮 / 中位 |
|---|---|---|
| C1 `scale 0.649` + **MSAA 4×** + 全套后处理 | 52.1 / 52.1 / 52.2 → **52.1** | 11.3 / 12.2 / 12.1 → **12.1** ⚠️ |
| C2 `scale 1.000` + **无 MSAA** + 全套后处理 | 37.7 / 38.0 / 37.4 → **37.7** | 44.0 / 61.8 / 61.6 → **61.6** |
| C3 `scale 1.000` + **无 MSAA** + 只留 ACES | 39.3 / 38.9 / 38.9 → **38.9** | 48.6 / 65.3 / 65.3 → **65.3** |

两条结论：

1. **本工程实际用的那一档（C2/C3）Compute 快约 1.6 倍**（61.6~65.3 vs 37.7~38.9）。
2. ⚠️ **Compute 千万不要和「MSAA 4× + 降分辨率」一起用** —— 那一档只有 **12 fps**，
   比 Raster 的 52 还慢 4 倍。Compute 把泼溅渲进离屏缓冲，分辨率与 MSAA 会同时
   乘到那个缓冲上，而它不像标准网格管线那样能省。好在 §6.6 已经把 MSAA 关掉、
   分辨率放开到原生，正好避开了这颗雷 —— **但切回 Raster 时别忘了这条**。

> ⚠️ 跨进程的绝对帧率在这台笔记本上抖得很厉害（同一档三次跑差过 2~30 倍，见 §6.6），
> 所以只有**同一进程内交错重复出来的中位**才可信。单跑一次得到的 37~38 fps
> 就是这种噪声，别当结论。

对照图与逐项读数：`_arisu_captures/_backend_ab/_compare_backend.png`。
工具：`scripts/_probe_splat_backend.gd`（`--backend=` / `--bias=` / `--tag=` / `--hide-floor`）
+ `_arisu_captures/_backend_ab/_compare_backend.py`。

### 接线：为什么用 autoload 而不是改场景

Compute 后端不在标准网格管线里画泼溅，它渲染到离屏缓冲、再由
`GaussianCompositorEffect`（一个 `CompositorEffect`）合成回场景缓冲。而 `Compositor`
在 Godot 4 里**只能挂在 `Camera3D` 上** —— 没有它就一张泼溅都看不到，而且失败得很安静。

自检与探针会**自己 `new` 一台相机再 `make_current()`**（例如 `_verify_room.gd`），
那种相机上不会有 Compositor。所以做成 autoload `scripts/splat_compositor.gd`：
逐帧盯着根视口的「当前相机」，没挂就挂上（按实例 id 缓存，不重复重建）。
正常会话只会看到 1~2 行 `[SplatCompositor] 已为相机…`，刷屏就说明缓存判据失效了。

### ⚠️ 共面地板：Compute 的深度剔除会和场景方盒地板打架

`depth_rejected = gsplat_depth > scene_depth + depth_bias`。而 `game.tscn` 那块
兜底方盒地板 `Floor/Mesh` 的顶面**正好在 y = 0**，扫描出来的地面在 **y ≈ 0.03**
—— 两者共面，于是扫描地面被判成"在场景几何后面"而**整片剔掉**，露出深色方盒：
地板上是一片黑洞。五条路都试过：

| 做法 | 地板 | 角色 / 房间外 | 结论 |
|---|---|---|---|
| `depth_bias` 0.05（默认） | ❌ 成片黑洞 | ✅ 完好 | |
| `depth_bias` 0.5 | ✅ 干净 | ⚠️ 0.5 m 内的泼溅盖住腿脚 | ✗ 偏置是**全局一个数**，地板和角色差一个数量级，调不拢 |
| 关掉深度剔除 | ✅ 干净 | ❌ 角色被泼溅整个盖住 | ✗ |
| `Floor/Mesh` 改 `DEPTH_DRAW_DISABLED` | ❌ **更糟** | — | ✗ Godot 的不透明深度**预通道**照样把它写进深度缓冲，`scene_depth` 里仍有它；彩色通道还糊住下半屏 |
| 方盒地板整体下压 | — | — | ✗ 要让 20 m 外的掠射角也不冲突得压到接近 1 m，走出门就是悬空平台 |
| 整块**藏掉** `Floor/Mesh` | ✅ 干净 | ❌ **房间外没地面** | ✗ 见「坑一」 |
| 按世界包围盒挖 4 块轴对齐盒子 | ✅ 干净 | ❌ **四角真空** | ✗ 见「坑二」（房间是斜的） |
| **用 CSG 挖掉房间那一块** | ✅ **干净** | ✅ **完好** | ✅ **采用** |

#### ✅ 采用：用 CSG 把方盒地板挖掉房间那一块

保留整块方盒地板，只把房间占位的那一块切掉 —— 房间里靠扫描地面，房间外照旧是
方盒平台。位置、碰撞体、`--splat=off` 行为**全都不动**。

实现：`game.gd::_on_splat_loaded` → `_carve_fallback_floor()`。用
`CSGCombiner3D` + `CSGBox3D`（`OPERATION_SUBTRACTION`）做布尔减法，洞的变换
取 `Room609.global_transform * splat_node.transform`，尺寸取房间的
`content_min/content_max` —— 所以**洞就是房间自己那个旋转矩形**，和扫描地面严丝合缝。
生成节点名 `FloorCarved`（`Slab` = 板子，`RoomHole` = 挖掉那块），原来那块
`Floor/Mesh` 藏掉。`Floor/Collision` 始终是完整的 40 × 40 m，玩家站在 y = 0。

`FLOOR_HOLE_MARGIN`（默认 **−0.15 m**）是洞相对房间 footprint 的外扩量。
**故意取负数**：让平台和扫描地面重叠一条 15 cm 的窄边（在墙根，基本看不见），
而不是留一条头发丝宽的缝 —— 缝下面就是几百米高的天空。

想回到一整块方盒地板（排查别的问题时）：`-- --solid-floor`，或把
`CARVE_FALLBACK_FLOOR` 改成 `false`。

#### ⚠️ 坑一：不要「整块藏掉」

第二版是整块藏掉 —— 房间里确实完美，**但房间外那片平台没影了**。
`Floor/Collision` 还在，于是玩家走出那扇 3.88 m 的门之后：

- **站在看不见的地板上**（症状："地板不见了"）
- 人已经钻进扫描墙壁的**背面**。扫描只拍了房间**内部**，从外面看整间房就是
  一团糊 —— 于是画面变成「背景一坨糊 + 网格角色很清楚」的诡异状态
  （复现图：`_arisu_captures/_gameplay/carved_outside.png`）

**这是本工程最像"渲染坏了"的一个假象**，实际只是"走到了一堵单向墙的外面"。

#### ⚠️ 坑二：洞不能按「世界轴对齐包围盒」挖

第三版用房间的**世界包围盒**切四块轴对齐的盒子，结果**平台中间破出一大片真空**
（症状："中间这段怎么空了"）。原因是房间是**斜的**：

| | 尺寸 |
|---|---|
| 房间世界**包围盒**（`content_world_aabb()`） | 23.9 × 27.2 m |
| 房间**实际** footprint（`yaw_degrees = 248.6`） | 22.6 × 16.8 m |

包围盒比房间大了 **270 m²**，那四个角落在房间外面 —— 既没有扫描地面、也没有
方盒地板。所以必须让洞跟着房间的**真实朝向**走，这也是这里改用 CSG 的原因
（手摆的盒子只能轴对齐）。

诊断手段：`scripts/_probe_gameplay_shot.gd -- --outside`（把相机架到平台上看房间）
和 `-- --tag=` 出图。

> 顺带确认：这两个坑**和 Compute 后端无关**，Raster 下叠加同一套地形也会一样 ——
> 差别只是共面黑洞只在 Compute 上出现。

`--splat=off`、或房间泼溅加载失败时**挖洞不执行**，方盒地板保持整块，
所以 11 套玩法自检完全不受影响。

### 切回 Raster
```powershell
# 只有为了看 §6.9 那三个逐高斯动态效果才需要
# 把 project.godot 的 [gdgs] rendering/backend 改成 "Raster" 再重启
```

Raster 的排序延迟问题（§6.10）在 Compute 上**不存在** —— Compute 走 GPU 基数排序。

---

## 6.10 ⚠️ 快速转身时画面糊掉 0.8 秒（Raster 排序延迟，已修）

**现象**：猛地回头，转身方向那一整片高斯**不是缺一块，而是糊成一团白**，
大约一秒后「浮现」出完整画面。

**这不是「没加载」**，是 Raster 后端的排序表比相机落后了整整一次排序的时间。

### 成因（三处源码合起来）

| 文件 | 干了什么 |
|---|---|
| `raster_sorter.gd` | 16 位计数排序，**逐高斯**排序。2,774,116 点实测 **812 ms**（`_probe_sort_cost.gd`） |
| `raster_sort_job.gd` | 双缓冲：排序在工作线程跑，主线程继续用**上一张**排序表渲染 |
| `raster_render_backend.gd` | `_drive_entry` 里 `not entry.job.is_running()` 挡住重踢 —— 飞行中的 812 ms 内不会再排，落地才 `_upload_order` |

排序表的含义是「离相机由远到近的绘制顺序」。方向反 180° 就变成**由近到远**：
远端几何最后画、把近端整个盖住。所以看到的是「远处的东西糊了一大片」，
而不是「空的」。812 ms 后新表落地，画面才「浮现完整」。

### 量出来的

`--splat=off` 的那 11 套自检碰不到这条路径，所以专门写了两个探针
（`_probe_sort_cost.gd` 纯 CPU；`_probe_stale_order.gd` 真渲染、盯排序表内容摘要）。
实测（RTX 4060 Laptop，room609 ×4.25，2,769,851 点，960×540）：

| 量 | 修前 | 修后 |
|---|---|---|
| 逐高斯排序单次 | **812 ms** | —— |
| **转身 → 新排序表落地** | **789 / 810 ms** | **49 ms** |
| 首次排序表落地 | 1,213 ms | 1,253 ms（多出的是一次性建质心） |
| 排序表尺寸 | 1665 × 1664（逐高斯） | **295 × 294（逐组）** |

### 修法：只排「每 32 个高斯一组」的质心

关键发现：**这份数据的源顺序本身就有很强的空间局部性** ——

```
相邻点平均距离    0.022071
随机点对平均距离  2.162575
相邻 / 随机 = 0.01021          ← 比随机近 100 倍
```

（`splat-transform` 之类的导出器会按空间曲线重排点。）既然相邻的高斯本来就挨着，
就没必要逐高斯排序：**每组求一个质心、只排组**，组内直接按源顺序连排。
排序量少 group 倍，着色器侧只多一次除法与取模（`gaussian_raster.gdshader`）：

```glsl
int og = sorted_pos / order_group;
sidx = order_tex[og] * order_group + (sorted_pos % order_group);
```

| 组宽 | 组数 | 建质心（一次性） | 排序（每次重排） | 相对逐高斯 |
|---|---|---|---|---|
| 1（修前） | 2,774,116 | —— | 748 ms | 1× |
| **32（现在）** | **86,692** | 81 ms | **25.6 ms** | **29×** |
| 128 | 21,673 | 71 ms | 8.1 ms | 93× |

建质心那 81 ms 是 O(n) 的 GDScript 累加，**放在工作线程里做且只做一次**
（`raster_sort_job.gd::_run`）—— 放主线程就是加载完成那一帧的卡顿。

### 为什么组宽取 32 而不是 128

组内是源顺序连排，所以**组内深度乱序的量级 = 组内空间离散度**，实测随组宽按 √group 增长：

| 组宽 | 组内平均离散度（源单位） |
|---|---|
| 128 | 0.0468（≈ 两个高斯间距） |
| **32** | **约 0.023 ≈ 相邻高斯平均间距 0.0221** |

取 32 时「组内乱序不到一个高斯间距」，而它的 25.6 ms 已经只相当于一帧半（60 fps），
128 省下的 17 ms 换不到什么。要更快就调 `raster_render_backend.gd` 的 `ORDER_GROUP`。

**质检办法是拿逐高斯精确排序当参照物**：探针自己硬算一份精确排序（708 ms，
只在探针里付这个代价）替换材质的排序表再拍一张，两张图对比 ——

```
组顺序（线上走的那条路） vs 逐高斯精确排序   平均差 0.0315
```

参照物：资源顺序 vs 正确 = 0.0757，陈旧排序表 vs 正确 = 0.1090，
**完全另一个朝向** vs 正确 = 0.19。所以 0.0315 只是逐像素 alpha 混合的细微抖动，
并排看分不出来（`..\_arisu_captures\_stale_order\montage.png` 第 3、4 格）。
另外「转一圈转回来」重拍的图与基准差 **0.0000** —— 排序结果是确定的，不抖。

### ⚠️ 两个量法上的坑（本喵都栽过）

1. **判据不能看「相邻帧是否变化」。** 陈旧排序表期间画面本来就是**冻结**的，
   「不变」恰好是最不可靠的信号 —— 第一版探针因此把一个假的「收敛」当成落地了。
   要盯**排序表字节摘要**（`ImageTexture.get_image()` + `HashingContext`）。
2. **量延迟时不能回读画面。** `root.get_texture().get_image()` 在 960×540 上要
   **~190 ms**，会把主线程整个卡住，而主线程的 `_drive_entry` 才是 `poll()` +
   上传排序表的地方。一抓图，量到的就不是「排序多久」而是「回读多久」
   —— 本喵因此先量出个假的 215 ms。排序表的 `get_image()` 只有 347 KB
   （表项是组不是点），几乎不要钱，可以放心轮询。

### 还会退化的情形

`_choose_order_group()` 在装配时验一次局部性（固定种子、采样 3000 对、主线程 1~3 ms）：
比值 > 0.25 就退回逐高斯排序并打一条提示。**源顺序没有局部性时，组内连排会退化成
全随机**，那比逐高斯排序还差，所以这道闸不能省。种子固定是为了让同一个资源每次
判出来的组宽一致 —— 否则会出现「这次启动用了分组、下次没用」的随机画面差异。

### 探针

```powershell
# 排序成本 + 源顺序局部性（纯 CPU，几秒）
& $g --headless --path $p --script res://scripts/_probe_sort_cost.gd

# 转身延迟（真渲染，盯排序表，**不回读画面**）
& $g --path $p --script res://scripts/_probe_stale_order.gd
# 出图 → ..\_arisu_captures\_stale_order\，拼图用同目录 montage.py（必须自带 Python）
```

### 已知取舍

- 这是**近似**排序（组内按源顺序），不是精确排序。旋钮见上表。
- 只改了 Raster 后端；Compute 后端走 GPU 基数排序，没有这个问题。

---

# 七、Boss：霸王龙优香 + 飞猪优香

两位 Boss **现在都会主动攻击玩家了**（§7.5）：站在平台上、吃得下子弹、受击闪白、
打光后扑倒并在数秒后站起来，同时会在地面画预警圈打人 ——
霸王龙是「**重击型**」（圈大、伤害高、击退远），飞猪是「**骚扰型**」（圈小、冷却短）。
两者在「怎么量尺寸」上是两条路（见 §7.6），但在「怎么攻击」上**共用
`scripts/boss_attacker.gd`**，各自只配一套参数。

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

## 7.5 Boss 的攻击（**两只都会打人了**）

这一节原来写的是「下一步想做行为」。现在两只 Boss 都会主动攻击：

- **霸王龙优香**（`trex_boss.gd`）—— **重击型**：圈大、伤害高、击退远
- **飞猪优香**（`pig_boss.gd`）—— **骚扰型**：圈小、冷却短、伤害低，但逼你一直挪位置

机制**完全共用** `boss_attacker.gd`（`class_name BossAttacker extends Boss`）：
两个子类只改参数 + 两个钩子（`_on_windup_start` / `_on_resolved`，用来做模型表现 ——
霸王龙蓄力时低头、飞猪整只向上一蹦）。想再加一位会攻击的 Boss，就
`extends BossAttacker` 然后配一套参数，不用碰机制。

| 参数 | 霸王龙（重击） | 飞猪（骚扰） | 说明 |
|---|---|---|---|
| `attack_interval` | 4.5 s | **3.0 s** | 两次攻击的间隔 |
| `attack_start_delay` | 2.0 s | 3.5 s | 进场后多久开始 |
| `windup_time` | 0.9 s | 0.7 s | 预警圈从 55% 涨到 100% 的蓄力时间 |
| `attack_range` | 18 m | 14 m | **发现**玩家的距离（⚠️ 不是伤害半径） |
| `attack_half_angle_degrees` | 32° | **45°** | 只在正面这个半角内起手 |
| `attack_reach` | 5.0 m | 3.6 m | 预警圈圆心离本体的水平距离 |
| `attack_radius` | **4.8 m** | **3.4 m** | 预警圈半径，**同时就是伤害半径** |
| `attack_damage` | 24 | 14 | 玩家满血 100 |
| `knockback_force` | 8.0 | 5.0 | 命中时的水平击退 |
| `telegraph_color` | 红 | **紫** | 场上有两只时，一眼看出是谁要打你 |

⚠️ **`attack_radius` 必须同时是「预警圈半径」和「伤害半径」** —— 这是写这一版时踩的坑：
第一版判定沿用了 `attack_range`（18 m），于是玩家站在**看得见的圈外面**照样被扣血，
预警圈等于在骗人。现在判定就是「玩家到圈心的水平距离 ≤ `attack_radius`」，
和画出来的那个圈一一对应，站在圈外一定安全。

流程：`_process` 里冷却到点 → 检查玩家在 `attack_range` 内**且在正面半角内** →
起手 → 地面画出预警圈并涨大 → `windup_time` 后结算 → 圈内扣血 + 击退 → 收圈。

玩家侧配套（`player.gd`）：`max_health = 100`、`take_damage()` / `heal()`，
HUD 状态行显示 `HP xx/100`；血被打空不做死亡画面，1 秒后原地回满（教学沙盒）。
Player 加入了 `"player"` 组，Boss 靠它找人。

自检：
- `_verify_trex_attack.gd`（9 项）—— 预警圈可见 / 圈内必中 / 有击退 / 收圈 /
  **圈外（但在 18 m 内）不掉血** / 背后不掉血
- `_verify_boss_pig.gd` §6（8 项）—— 飞猪确实挂了攻击脚本、**三组参数都与霸王龙不同**
  （专门防止「两只被做成一模一样」）、圈内扣血 + 击退 + 收圈

### 还没做的

- **骨骼动作**：霸王龙那 73 根骨还在，「张嘴 + 摆尾」是有戏的 ——
  现在蓄力只有「低头」这一点点程序化动作，还没有真正的骨骼动画
- **飞猪的冲撞 / 滚动**：它没有骨，只能在节点层级上做（现在是「向上一蹦」）

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

**七名同伴会跟着玩家走位，并自己选目标开火帮忙**（打靶子 / Boss，见 §8.7）。
不需要玩家下指令，也不会误伤玩家和自己人。模型用 `tools\Find-BlueArchiveModel.cmd`
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
| 凯伊 Kei | `Kei_ext.glb` | 166 骨 | 32 | `(−5.2, 0, −1.4)` 最左 |

七只都自带 `Normal_Idle` / `Cafe_Walk` / `Move_Ing`，所以直接复用了主角那套 `AnimDriver`。
（`Move_Jump` 只有前四只有，但跟随逻辑没用到它。）

> 这批 GLB 的**贴图是内嵌的**（`glb_info.py` 实测：Momoi 13 张、Kei 22 张 image 全部走
> bufferView），所以只要拷 `.glb`，不用像早期那样连 PNG 一起搬。

`Find-BlueArchiveModel.cmd` 的匹配规则是 `^Mika(?:\s|$)` 这种前缀，
所以 `未花` 会同时命中 `Mika.glb`、`Mika (Swimsuit).glb`、`Mika (Cut-in).glb` ——
`-CopyTo` 会把三个都复制过去，只要初始形态的话得自己挑（两次都是这么挑的：
`Mika.glb` / `Momoi.glb` / `Midori.glb` / `Yuzu.glb` / `Kei.glb`）。

> 七只里只有凯伊实际用的是 `Kei_ext.glb`（重导过的版本，见 §8.8），其余六只直接用原始 glb。
>
> 凯伊的 `Kei.glb` 有 **4 个 skin / 2 个 Skeleton3D**（166 + 21 + 6 + 1 骨）；
> 重导的 `Kei_ext.glb` 合并成 **2 个 skin**（166 + 6 骨）。
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
  - 两者**播同一条 `Move_Ing`**，只靠 `speed_scale` 区分（0.42 倍 vs 1.23 倍）——
    以前这里写的是「`walk_speed` 要压在走路动画阈值以下」，那套阈值已经删了
    （`Cafe_Walk` 不拿武器，§1.17）
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

> 「身高在合理区间」那一项的度量口径，以及凯伊圆整导出后为什么会误报，见 §8.8.6。

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

## 8.7 同伴会开火（`scripts/companion_gun.gd`）

同伴原来是「只跟随、不开火」。现在**自己选目标开火帮玩家打**（靶子 / Boss），
不需要玩家下指令。它挂在 `companion.tscn` 的 `Gun` 节点上，所以 7 名同伴**各有一把**。

三条硬约束（都写在脚本文件头）：

1. **不打自己人。** 射线 mask 去掉朋友层（`Companion.LAYER` = 2），再把玩家 RID
   加进 `exclude` —— ⚠️ 玩家在**层 1**，光靠 mask 屏蔽不掉。§8.1 解决的是
   「同伴**挨打**」，这里是反过来的那一侧，要单独处理。
2. **不隔墙打。** 扣血以**射线真正命中的那个目标**为准，不是「预测命中」：
   预测和开火之间隔了一帧、目标还会动，靠预测就会出现「隔着墙掉血」。
3. **不为开火而乱转身。** 只有目标已经在同伴**正前方 ±25°** 内才开火。
   否则同伴会为了瞄准而东倒西歪，把 §8.3 那套「一队人朝同一个方向」的观感毁掉。

| 参数 | 默认 | 说明 |
|---|---|---|
| `attack_interval` | 1.8 s | 每名同伴的射击间隔（7 把枪各自独立） |
| `attack_range` | 24 m | 超过就不打 |
| `attack_damage` | 12 | 7 人齐射约 47 dps |
| `aim_half_angle_degrees` | 25° | 见约束 3 |
| `enabled` | `true` | 关掉就完全不开火（自检里用得到） |

目标来源：靶子看 `targets` 组，Boss 看 `bosses` 组。

⚠️ 为此修了一个**一直存在、但谁都没发现**的问题：`targets` 组**以前根本是空的** ——
`game.tscn` 里 5 个 `Target` 节点都没写 `groups=`，代码里也没有 `add_to_group`。
于是 `game.gd` 那句「按 `targets` 组连 `died`」一直在空转，全靠它下面那段
「没进组也接一下」的兜底在干活 —— **计分一直是对的，所以没人察觉**。
现在由 `target.gd` 的 `_ready()` 自己 `add_to_group("targets")`，以后新加的靶子
不用再手动配组。Boss 那边特意用**另一个**组名（`bosses`）：`game.gd` 对 `targets` 组
和 Boss 是**分别**连 `died` 的，Boss 若也进 `targets` 会被连两次、一次击杀加两分。

自检 `_verify_companion_attack.gd`（10 项）：

```powershell
& $g --path $p --script res://scripts/_verify_companion_attack.gd -- --splat=off
```

⚠️ 这个套件每条都会**先把同伴排队 + 冻住跟随**（`set_physics_process(false)`）再测：
同伴平时一直在走位和转身，不冻住的话「有没有开火」就混进了「有没有走到位 /
转过身」，断言会变成看运气。它覆盖：挂了枪 / 默认开启 / 面朝靶子会开火且打掉血 /
**玩家不被误伤** / **背后停火** / **隔墙停火** / 会打霸王龙 / 关掉 `enabled` 停火。

---

## 8.8 修正凯伊（Kei）跑动的整体前折

凯伊的 `Move_Ing` 比爱丽丝夸张得多：不是「胸腔多趴一点」，而是**整个人绕髋部前折约 45°**，
跑起来像一直弓着身子冲刺。已用 [`..\_blender_kei\fix_lean_kei.py`](../_blender_kei/fix_lean_kei.py)
修正并导出 `models/companions/Kei_ext.glb`（`game.tscn` 的 `CompanionKei.model_path` 已切过去，
`Kei.glb` 原文件未改动）。

### 8.8.1 先看清楚「前折」写在哪根骨上

逐骨量「rest 时最接近角色上方的局部轴」被摆到哪，相邻两骨之差就是该骨的局部贡献：

| `Move_Ing` 帧 0 | 世界绝对倾角 |
|---|---|
| `Bip001`（根骨） | **+45.0°** |
| `Bip001 Pelvis` | +45.0°（相对根骨 0°） |
| `Bip001 Spine` | +50.3°（+5.3°） |
| `Bip001 Spine1` | +36.3°（−14.0°） |
| `Bip001 Neck` | +44.0°（+7.7°） |
| `Bip001 Head` | +31.5°（−12.5°） |

**45° 全部写在根骨 `Bip001` 上**，脊柱各段自己的贡献都在 ±15° 以内 —— 这是**整体刚性前折**，
不是脊柱弯。所以只拧脊柱是没用的，必须动根骨。

> ⚠️ **量这套模型的朝向时别信「rest 前向」。** rest 姿态下角色朝 −Z（脚趾指向 −Z），
> 但动画里 **`Normal_*` / `Move_*` 朝 −X，`Cafe_*` 朝 −Z**，同一个文件里就差 90°。
> 第一次量的时候就是踩了这个坑，把「前后」搞反了。判断办法：直接渲
> 「按 `Spine1` 骨局部 Y 轴取景」的正视/侧视图（`..\_blender_kei\shots_body_kei.py`）。

### 8.8.2 为什么可以「转根骨但腿一动不动」

这套 Biped 里有两个巧合，正好让修改变成纯解析操作：

- 根骨 `Bip001` 的 **bone head 与 `Bip001 Pelvis` 的 head 重合**（都在髋点），
  姿态旋转绕骨头发生 → 转根骨**不会移动髋点**；
- 两根大腿骨的 head 相对髋点只差一个 **X 方向偏移**（`(±0.073, 0, 0)`），
  正好落在旋转轴上。

于是给根骨叠一个「向后 θ」的旋转后：**骨盆及以上整体立起来 θ**，髋点纹丝不动；
再给两根大腿骨各叠一个反向旋转、使其**世界朝向完全不变**，腿（含膝/踝/脚/脚趾）就一个像素都不动。
反向旋转不能取常数——大腿骨的世界朝向还受骨盆摆姿影响，所以按每个关键帧解
`u = B⁻¹ · Δ⁻¹ · B`（`B` = 该骨世界朝向中不含自身 basis 的部分）。

### 8.8.3 接地：髋点在偏航的骨盆里还是会被带跑

骨盆在 `Move_Ing` 里带着明显偏航（髋线偏离左右轴 23°~48°），所以绕全局左右轴转时，
左右髋会**反向**跑掉最多 ~2 cm（左髋上移+后移，右髋下移+前移）。腿跟着刚性平移，
脚就会浮起/陷入地面。

补偿办法：给根骨的**位置通道**加一条逐帧纯竖直修正，把角色最低点拉回原高度
（0.5 帧一格、重建为 33 个关键帧）。落地脚因此完全复原，腾空脚本来就在空中，
**腾空/落地的节奏一点没变**。

### 8.8.4 结果

Blender 侧（`Move_Ing` 帧 0..16）：

| 指标 | 修正前 | 修正后 |
|---|---|---|
| 根骨前倾（均值） | +44.9° | **+14.9°** |
| 躯干前倾 骨盆→颈（均值） | +43.1° | **+13.1°** |
| 角色本体最低点（相对原版） | — | 逐帧偏差 **0.00000** |

Godot 侧复测（`scripts/_probe_kei_lean.gd`，`--headless` 可跑，直接量
「骨盆→颈」与世界上方向 `+Y` 的夹角，不依赖任何朝向约定）：

| 指标（9 个相位采样） | `Kei.glb` | `Kei_ext.glb` |
|---|---|---|
| 躯干倾角 平均 / 最大 | +43.6° / +46.5° | **+15.0° / +18.1°** |
| 踝点高度范围 | 0.0419 ~ 0.0881 | 0.0389 ~ 0.0889（接地节奏不变 ✓） |

`scripts/_probe_kei_godot.gd` 逐轨道比对确认：`Bip001 Spine` / `Spine1` / `Neck` / `L Calf`
的关键帧值**一字未变**，只有根骨与两根大腿骨变了 —— 正是设计意图。

侧视/正面对照图（固定机位、原版 vs 修正版）：`..\_blender_kei\凯伊跑姿对照.png`。

### 8.8.5 这两个导出参数必须改

`..\_blender_kei\export_kei.py` 里有两个参数和爱丽丝那次不同，踩过才知道：

- **`export_anim_single_armature = False`** —— 凯伊有**两套骨架**（`bone_root` 166 骨 +
  `bone_prop_root` 6 骨）共用同一批动作，开着的话只会导出其中一套。
- **`export_optimize_animation_size = True`** —— 关着的话 Blender 会把动画**逐帧全量烘焙**，
  通道数从 6132 涨到 17172、文件 9.18 MB → 20.91 MB。打开后是 **7.63 MB**，
  通道数 6165 ≈ 原版，`Move_Ing` 轨道数与原版一致（138）。

> 脚本同样是**幂等**的：原始四元数关键帧存在 `move_ing_lean_backup.json`、
> 根骨位置关键帧存在 `move_ing_lean_loc_backup.json`，每次运行先还原再施加。
> 想改幅度就改脚本顶部的 `THETA_DEG`（当前 30.0°）重跑。

> Blender 侧工具在 `..\_blender_kei\`：`keirig.py`（坐标系断言 + 轴向标定 + 关键帧读写）、
> `probe_rig_kei.py` / `probe_lean_kei.py` / `probe_chain_kei.py` / `probe_root_all_kei.py`
> / `probe_yaw_kei.py` / `probe_facing_kei.py`（诊断）、`fix_lean_kei.py`（修正）、
> `export_kei.py`（导出）、`shots_*.py` / `compare_kei.py` / `make_sheet_*.py`（出图）。

> 顺带一个数据事实：`Move_End_Normal`（停下过渡）根骨前倾是从 +19.8° 收到 −2.3°。
> 改之前 `Move_Ing` 是 45°、切过去会跳 25°；改完是 15°，**跳变反而从 25° 缩到 5°**。

### 8.8.6 重导带来的结构变化（和 §8.4 的「身高」检查）

圆整导出会把节点层级规整一遍，`Kei_ext.glb` 与 `Kei.glb` 的结构差异：

| | `Kei.glb` | `Kei_ext.glb` |
|---|---|---|
| 节点数 | 205 | 219 |
| skin 数 | 4（123 / 21 / 6 / 1 骨） | 2（166 / 6 骨） |
| 动画数 | 32 | 32 |
| 动画通道总数 | 6132 | 6165 |
| 文件大小 | 9.18 MB | 7.63 MB |

⚠️ 副作用：`MeshInstance3D.get_aabb()` 是**未蒙皮**的原始包围盒，节点朝向被规整后这一项
从 1.71 m 变成 0.58 m —— 但屏幕上像素高度只从 185 变 179，**外观没有回归**。
`_verify_companion.gd` 原来的「身高在合理区间」就是拿这一项判的，于是误报 FAIL。

已把 `_local_height()` 改成对三个口径**取最大值**：网格原始盒 / 骨架 rest 在骨架局部空间的
Y 跨度 / 骨架当前姿态在世界空间的 Y 跨度。单用任何一个都会误报 ——

| 模型 | 网格原始盒 | 骨架rest局部 | 骨架世界 | 实际 |
|---|---|---|---|---|
| `Kei.glb` | 1.705 | 0.682 | 1.147 | ~1.4 |
| `Kei_ext.glb` | **0.578** | 1.089 | 1.204 | ~1.4 |
| `Mika.glb` | 1.380 | 0.842 | 0.926 | 1.39 |
| `Momoi.glb` | 1.245 | 0.794 | 0.833 | 1.28 |

真实尺寸不会小于其中任何一个，而「哪个口径在哪个文件上失灵」不可预知（米卡的骨架跨度
只有 0.83~0.93 m，实际身高却是 1.39 m），所以取最大。三条口径的来历都写在函数注释里。
改完重跑 `_verify_companion.gd`：**100 PASS / 0 FAIL**（凯伊 1.20 m ✓）。

---

# 九、剧情系统（纯文本剧本 + 对话框）

## 9.1 一句话：**剧本是数据，代码只是播放器**

剧情**不写在 `.gd` 里**。加一句台词 = 往 `story/开场.txt` 里加一行，代码零改动。
代码那边只有两件事：把文本读成一串「步骤」，再把步骤画到屏幕上。

```
story/开场.txt          ← 你写的东西（UTF-8 纯文本）
story/设定.md           ← 角色表 / 场景表（人看着写剧本，代码拿去校验说话人）
        │
        ├─ scripts/story_script.gd   解析 + 校验（**纯静态类**，不碰节点、不读场景）
        └─ scripts/dialogue_box.gd   屏幕下方的对话框：打字机、翻页、暂停世界
                │
                └─ scripts/game.gd `_play_opening()`   进关卡时自动开播
```

| 文件 | 干什么 | 什么时候要动它 |
|---|---|---|
| `story/开场.txt` | **剧本正文** | 每次写剧情 |
| `story/设定.md` | **角色表 / 场景表**（人看 + 机器校验） | 加角色、加场地、改场地接线时 |
| `scripts/story_script.gd` | 解析 / 报错 / 校验 | 想加新指令时 |
| `scripts/dialogue_box.gd` | 对话框外观与播放 | 想改样式 / 版式时 |
| `scripts/_verify_story.gd` | 自检（含**排版检查**与**设定表校验**） | 改完剧本跑一次 |

## 9.2 剧本格式

文件放 `res://story/`，后缀 `.txt`，**必须是 UTF-8**。只认五种写法：

| 写法 | 意思 |
|---|---|
| `# 任意文字` | 注释（**整行**以 `#` 开头才算） |
| `名字: 台词` | 有名字的对话（半角 `:` 和全角 `：` 都行） |
| `* 任意文字` | 没有名字的旁白（`*` 后面要有内容） |
| `@wait 1.2` | 停一拍（秒，> 0） |
| `@clear` | 清空对话框，停 `StoryScript.CLEAR_SECONDS`（0.6 s） |
| `@speed 45` | 之后每句的打字速度（字/秒，> 0） |
| `@end` | 到此为止，后面的不播 |

认不出来的行**不会静默跳过**——启动时在控制台报错，并给出**第几行 + 原行原文 +
怎么改**。剧本有任何一处错误就**整段不播**（宁可不出，也别演半截）：

```
第 2 行：不认识的指令 `@bgm`。现在只有这四个：
        @wait <秒>        停一拍，例如 @wait 1.2
        @clear            清空对话框，停一个空档（CLEAR_SECONDS）
        @speed <字/秒>    改打字速度，例如 @speed 45
        @end              到此为止，后面的内容不播 ｜ 原行「@bgm 天台」
```

四个刻意的取舍（都是「写剧本的人不该操心的事」）：

1. **一行 = 一句**，不做 `\n` 转义 —— 要换行就多写一行。
2. **不支持行尾注释**：`优香: 你好 # 备注` 里的 `#` 是正文。否则正文里的 `#`
   会被悄悄吃掉，那种 bug 最难查。
3. **台词只在第一个冒号处切**：`优香: 他说：好` → 说话人「优香」、正文「他说：好」。
4. 正文不能以 `*` 或 `@` 开头（那是语法）。真要用就前面加个全角空格。

## 9.3 播放时的行为

| 键 | 效果 |
|---|---|
| 空格 / 回车 / 小键盘回车 / 鼠标左键 | 第一次把**当前这句打完**，第二次翻到下一句 |
| `@wait` | 画面**保持不动**等 N 秒，自己往下走（按键可以跳过） |
| `@clear` | 清空 + 停 0.6 秒 |
| `Esc` | 照常开设置界面；设置界面**优先**，剧情会等着 |

**播放期间整个世界是暂停的**（`get_tree().paused = true`）。这样做有两个好处：
开场剧情不会被同伴的枪声和 Boss 的预警圈打断；而且**顺带关掉了开火**（见 9.5 坑 4）。
播完自动恢复。

想「进关卡直接开打、不看剧情」，或者想直接跳到某一段剧情：

```powershell
& <godot> --path . -- --story=off                     # 不播开场
& <godot> --path . -- --story=res://story/开场.txt     # 改播指定的那一份
```

## 9.4 改完剧本怎么知道改对了

```powershell
# 只跑剧情这一套（几秒）
& <godot> --path . --script res://scripts/_verify_story.gd -- --splat=off
```

它会做五件你最关心的事：

1. **解析真剧本**，把每一条错误、每一条提醒打出来（带行号）；
2. **排版检查**：按**真实字体**量每一句在对话框里占几行，太长就点名
   （`[太长] 第 12 行要 3 行 →「…」`）。对话框只放得下 **2 行**，
   一行约 **44 个汉字**（正文区 1060 逻辑 px ÷ 24 px 字宽）；
3. 解析器 / 报错 / 编码的边界用例；
4. 播放：打字机、翻页、`@wait` 自己走、`@end` 收尾并恢复运行；
5. **设定表**（第 7 节）：角色表 / 场景表能不能解析、剧本里的说话人在不在表里
   （故意打错一个字，验证它会不会给出正确建议）、表里写的节点在不在
   `game.tscn` 里 —— 见 §9.8。

## 9.5 ⚠️ 七个坑（都踩过）

### 坑 1：皮肤字体**没有汉字**，中文必须另找一套（现在整套 UI 都换了）

两套皮肤的 `font.ttf` 都不够用。把「游戏里**实际会显示**的 189 个字」对着
`cmap` 表逐个查过（`tools\font\font_needed.py`，按界面分组报缺字；
剧情那一组直接读 `story/*.txt`，且按解析器语法剥掉了注释与 `@指令`）：

| 字体 | 大小 | 剧情 97 字 | 名字 18 字 | HUD 30 字 | 设置 96 字 | 结论 |
|---|---|---|---|---|---|---|
| `assets/ui_font/Aa暗夜深渊.ttf` | 3.86 MB | ✅ | ✅ | ✅ | ✅ | 整套可用（**不在仓库里**） |
| `assets/ui/font.ttf`（Fusion Pixel 12px，OFL） | 6.68 MB | ✅ | ✅ | ✅ | ✅ | 整套可用（兜底） |
| `assets/ui_sprout/font.ttf` | 0.11 MB | ❌ | ❌ | ❌ | ❌ | 缺 **213** 个字，只够画数字 |

Sprout 那套只有 80 个拉丁字形（设置界面全是数字/拉丁，所以一直没暴露）。

**现在是整套 UI 一套字**，走 `UiSkin.ui_font()`：

```
assets/ui_font/Aa暗夜深渊.ttf      ← 本地放进去就自动启用（不在版本库里）
        ↓ 没有它时回退
assets/ui/font.ttf                 ← Fusion Pixel 12px，OFL，随仓库分发
        ↓ 连它也没有时
皮肤自带的 font.ttf                ← 只够画数字，中文交给系统字体回退
```

`UI_FONT_CANDIDATES` 就是这张优先级表。**丢新字体进去要导入一次**
（`--headless --path . --import`），否则 `ResourceLoader.exists()` 认不出来。
挑字体前先跑 `font_needed.py` 查缺字 —— 显示字体经常只有 GB2312 那 6763 字。

> ⚠️ 换字体**不需要动版式**：实测两套字体的字宽几乎完全一致
> （16 px 下「鼠标灵敏度」都是 80 px；24 px 下 28 个汉字是 611 / 612 px），
> 所以对话框的「一行 44 个汉字」、行高 32.0 px、设置面板 620 宽全都照旧。
>
> ⚠️ **Aa暗夜深渊商用需授权**，所以它被 `.gitignore` 排除、不随仓库分发，
> 克隆者会自动回退到 OFL 的 Fusion Pixel。见 §11.1 与 `THIRD_PARTY.md`。
>
> HUD 上的数字（HP / 弹药）原来走像素字体是为了「醒目」（HUD 那一轮的明确要求）。
> 现在跟整套 UI 统一了；想改回「HUD 数字保持像素字体」就把
> `ui_skin.gd` 的 `HUD_FOLLOWS_UI_FONT` 改成 `false`。
> 想反过来「用这套字但加粗」可以用 `FontVariation.variation_embolden`。

### 坑 2：两个节点都会 `paused = true`，必须定交接规则

`SettingsMenu` 和 `DialogueBox` 都会暂停世界。不定规则就有两个真 bug：

- 剧情播完时**无条件** `paused = false` → 会把用户正在看的设置界面解除暂停；
- `DialogueBox` 的 `_input` 在设置界面开着时吞鼠标 → 设置界面的**按钮点不动**。

现在的规则写在 `dialogue_box.gd` 的 `_menu_open()` 里：设置界面开着时
**什么都不吞**，剧情结束时**也不解除暂停**（把恢复交给菜单）。
`_verify_story` 第 6 节专门验这两条。

### 坑 3：`_input` 比 GUI 事件**先跑**

Godot 的顺序是 `_input` → `_gui_input` → `_unhandled_input`。
所以在 `_input` 里无脑吞鼠标 = 全屏所有按钮失灵。见坑 2 的规则。

### 坑 4：开火是**轮询**的，`set_input_as_handled()` 拦不住

`player.gd` 用 `Input.is_mouse_button_pressed()` 在 `_process` 里判开火
（不是收事件）。吞事件只能拦住事件那一路，**拦不住 poll**。
真正让「过场里点鼠标不会开枪」的是**暂停**——`_process` 不跑了。
这也是为什么对话框必须是 `PROCESS_MODE_ALWAYS`（否则自己也停了，打字机和
翻页全死，和 `settings_menu.gd` 遇到的是同一个问题）。

### 坑 5：暂停会**卡住泼溅的收尾**，舞台要等剧情完才出现

`splat_scene.gd` 的 `_process()` 干两件性质不同的事：**后台解码线程的 join**
（`_finish()`）和两个纯观赏用的动态效果（坍缩 / 粒子上升）。默认的
`process_mode` 是「跟着暂停走」，于是剧情一播：

- 后台线程照常把点数解码完（`Thread` 不受暂停影响）；
- 但 `_process()` 不跑 ⇒ **join 不执行 ⇒ `_finish()` 不执行** ⇒ 泼溅**不出现**。

实测（正常启动、停在开场第一句、跑 70 秒）：日志里只有画室609 的
`[SplatScene] 裁剪：留 2769851 点…`，**没有**任何 `[SplatScene] 完成：…`
（那句在 `_finish()` 里）——舞台会等剧情读完才**突然**冒出来，
而开场旁白第一句就在讲「脚下的校园」。

修法：`splat_scene.gd` 的 `_ready()` 里 `process_mode = PROCESS_MODE_ALWAYS`。
**资源加载不该被游戏暂停卡住。** 代价是 `play_collapse()` / 粒子上升这类效果
在暂停期间也会继续走 —— 目前只有 `_probe_collapse.gd` 用它们，而它不暂停。

改完复测（同一次正常运行）：剧情**还停在第一句**（`paused=true`）的时候，
`[SplatScene] 完成：2769851 点，耗时 1.6 s（缓存 true）` 已经打出来了。

### 坑 6：`--script` 下**不能**自动播开场

13 套自检各自 instantiate `game.tscn`。`_play_opening()` 里第一件事就是
「`--script` 在命令行里吗」，是就退。不这么写，一进场景整棵树就被暂停，
`_verify_settings` 的「初始没有暂停」当场就红。

### 坑 7：编码 —— **GBK** 与 **BOM**

两个都栽在「中文 Windows 的编辑器」上，都已在解析器里堵上：

- **GBK**：记事本「另存为」的默认编码是 ANSI = GBK。Godot 的
  `get_file_as_string()` **假定 UTF-8**、不认 GBK，中文会变成一串 `�`。
  解析器检测到 `U+FFFD` 就报「文件不是 UTF-8」，并给出记事本/VS Code 的救法。
  `_verify_story` 第 3 节是**真写两个 GBK 字节**（`0xBA 0xC3` =「好」）验的，
  不是模拟。
- **BOM**：某些编辑器存 UTF-8 会带 `\uFEFF`，不去掉的话**第一行头一个字符
  就是 BOM**，注释和台词都认不出来，而那行**看着完全正常**。解析器会剥掉它。

## 9.6 ⚠️ 导出成 exe 之后要放行 `.txt` **和 `.md`**

Godot 只把「导入过的资源」和 `export_presets.cfg` 里 `include_filter` 列出的
后缀打进包，`.txt` 与 `.md` 两者都不是 —— 不写的话，编辑器里跑得好好的，
导出后：

- 剧本**读不到**（`FileAccess.file_exists()` 返回 false）→ 开场剧情**静默**变成
  「没有剧情」；
- 设定表也读不到 → 说话人校验**静默**失效（剧情照演，只是不再提示打错的名字）。

两种都「不崩、只是少了个功能」，所以特别容易到发布之后才发现。

本仓库现在还没有 `export_presets.cfg`（只能编辑器 / 源码跑），所以这条先记在
§11.3 的发布检查表里。

## 9.7 想加新指令要动哪两处

1. `story_script.gd` 的 `COMMANDS`（**报错时列给用户看的就是这张表**，
   也是「剧本语义」的唯一真相来源）；
2. 同一个文件的 `_parse_command()` 里的 `match`。

播放侧再按需要在 `dialogue_box.gd` 的 `_run_current()` 里加一个 `match` 分支。

**想往「过场动画」走的时候**：现在这一版刻意不碰相机、不摆人物走位
（用户选的是「原地式」）。加一个 `@camera` / `@cast` 指令即可 ——
播放器的结构不用改，只是多一个步骤分支，这就是当初先做「原地式」的原因。

## 9.8 角色表 / 场景表（`story/设定.md`）

写剧情真正缺的不是语法，是**「谁在场、站在哪、名字怎么写」**。这些事实原本散在
`game.tscn` 的节点、`companion.gd` 的导出、README 第七/八节里 —— 写台词时要翻三处，
而且**翻错了不会报错**（写 `凯依` 也能播，只是名字牌上多一个不存在的人）。

所以有了 `story/设定.md`：**一份文件，人看着写、代码拿去校验**。

### 格式：Markdown 表格 + 两个标记

```markdown
<!-- CAST:BEGIN -->
| 名字 | 身份 | 节点 | 模型 | 备注 |
|---|---|---|---|---|
| 优香 | 同伴 | `CompanionYuuka` | `models/companions/Yuuka.glb` | 站位：右后 |
<!-- CAST:END -->
```

- 两张表（`CAST` / `SCENES`），各由一对 HTML 注释标记夹住；标记只认前缀，
  所以 `<!-- CAST:BEGIN -->` 和 `<!-- CAST:BEGIN 说明 -->` 都行。
- **第一列就是剧本里能写的名字**，逐字照抄。角色表第一列的列名必须是 `名字`、
  场景表必须是 `代号`，否则报错。
- 数据行的每一格按**列名**存成字典（`read_bible()`），所以**加一列不用改代码**。
- 整格被反引号包起来时反引号会被剥掉（`` `Player` `` → `Player`）：表格是给人看的，
  代码要的是原值。

### 机器读它来干什么

| 在哪 | 干什么 |
|---|---|
| 进游戏时（`dialogue_box.gd::play_file`） | 剧本里的说话人不在角色表里 → 控制台 warning + **猜你想写谁** |
| `_verify_story.gd` 第 7 节 | 表能不能解析 / 说话人全不全 / 表里的节点在不在 `game.tscn` 里 |

进游戏时的样子（**只是提醒，不拦播放**）：

```text
[Dialogue] 第 12 行：说话人「凯依」不在角色表里 —— 是不是想写「凯伊」？（表在 res://story/设定.md）
```

「猜你想写谁」是**编辑距离 ≤ 2** 才会给的（`凯依 → 凯伊` 距离 1）。差太远就闭嘴 ——
随便猜一个比不猜更烦人。

### ⚠️ 为什么让一份「给人看的文档」同时能被解析

这是这一节唯一的设计取舍，值得写下来：角色表要是拆成「文档一份 + 代码里再列一遍」，
**两边迟早对不上**；而对不上的时候，校验会走向两种最糟的结局 —— 要么静默失效
（表改了、校验还在查旧的），要么开始**冤枉人**（表是对的，代码里的旧名单说不认识）。
**只有一处真相**就没有这个缝。同理，README 这一节只讲**怎么用**，不再抄一份名单。

### ⚠️ 设定表最容易「写了但早就过期」

文档类的坑不是写错，是**过期**。所以第 7 节把两件最会漂移的事钉成了断言：

1. **表里写的节点必须真的在 `game.tscn` 里** —— 有人改了节点名，表就红。
2. **「校园在不在场景里」表里怎么写、场景就得怎么是。** 校园那份泼溅是按用户要求
   从 `game.tscn` 搬去 `scenes/campus_venue.tscn` 的（`_verify_room` 也有常驻断言），
   而**开场旁白第一句就在讲「脚下的校园」** —— 这就是「文案里有的东西、画面里没有」
   最容易复发的地方。表里那一行写着「不在」，真把校园加回来时这条会红，
   提醒你去改表（而不是让一句过期的台词一直演下去）。

---

# 十、下一步

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
7. **换原创素材** —— 换掉模型与泼溅数据后本工程才能真正对外发布（见第十一节）
8. **剧情的下一步**（第一版已能跑，见第九节）——
   现在的形态是「原地式 + 纯线性 + 进关卡自动播」。按价值排，接下来可以加：
   - **触发方式**：走到某个区域自动播（推门进画室609 就演一段）、打完 Boss 播、
     按 `E` 和同伴搭话。**都不需要动播放器**，只要在 `game.gd` 里再调一次
     `play_file()`，配一个「播过没有」的标记。场地代号已经在
     `story/设定.md` 的场景表里（§9.8），可以直接拿它当剧本的挂载点
   - **进度存档**：现在同一段剧情每次进关卡都会重播；要「看过就不再播」得写
     `user://story.cfg`（照 `game_settings.gd` 的 `_load/_save` 抄一份即可）
   - **选项分支**：解析器加 `@choice` + `@label`（`story_script.gd` 的 `steps`
     已经是「带行号的步骤表」，加跳转不影响现有结构）
   - **运镜 / 人物走位**：加 `@camera` / `@cast`。这是当初先做「原地式」的原因 ——
     它是加运镜的**地基**，不是要被替换掉的临时方案
9. **手工场地（`MeshHut`）的下一步**（§1.13）——
   - **补室内地板的正解**：现在那块混凝土地面是「没碰撞的薄板」（坑 ① 的取舍）。
     正经做法是把小屋 footprint 里的平台地板也挖掉（照 `game.gd` 给画室609 那份
     挖洞的写法），然后地板就能带碰撞、顶面正好在 y = 0
   - **扩成一条走廊 / 一间二楼**：整份场景只有一个 `BoxMesh` + CSG，加体量就是复制
     节点改 `scale`/`position`，只要守住 0.05 m 网格（自检会核对）
   - **让它参与玩法**：现在它纯粹是块布景（`game.gd` 按类型收 `SplatScene` /
     `Boss` / `Companion`，`MeshHut` 是普通 `Node3D`，谁也看不见它）。想让它当
     掩体 / 触发剧情的区域，就照 §9.8 场景表里那个 `hut` 代号接线

---

# 十一、开源与许可

## 11.1 结论

**除模型与美术素材外，本仓库全部以 [MIT](LICENSE) 授权。**
逐项清单见 [THIRD_PARTY.md](THIRD_PARTY.md)。

| 内容 | 许可 | 在仓库里？ |
|---|---|---|
| 本项目作者编写的全部代码与文档（`scripts/`、`scenes/`、`project.godot`、README…） | **MIT** | ✅ |
| `addons/gdgs/`（GDGS 3.3.0，ReconWorldLab） | MIT（作者原许可保留在 `addons/gdgs/LICENSE`） | ✅ |
| `assets/ui_sprout/` | Sprout Lands 皮肤 | 专有（禁止再分发） | ❌ 被 `.gitignore` 排除 |
| `assets/sfx/*.ogg`（13 个，Kenney Interface/Sci-fi/RPG Audio） | **CC0** | ✅ **随仓库分发**（§1.14） |
| `models/Arisu*.glb` + 解包贴图 | © NEXON Games / Yostar，**专有** | ❌ 被 `.gitignore` 排除 |
| `models/companions/*.glb`（未花 / 优香 / 诺亚 / 小桃 / 小绿 / 柚子 / 凯伊） | 同上，**专有** | ❌ 被 `.gitignore` 排除 |
| `models/boss/优香霸王龙.fbx` + 贴图 | 派生自 Blue Archive，**专有** | ❌ 被 `.gitignore` 排除 |
| `models/boss_pig/`（飞猪优香 FBX + 贴图，作者：一个睿智） | 派生自 Blue Archive，**专有** | ❌ 被 `.gitignore` 排除 |
| `splatdata/*.sogdata`、`models/school.collision.glb` | 权利状态未核实 | ❌ 被 `.gitignore` 排除 |
| `icon.png` | 待仓库作者确认 | ✅（如非原创请替换） |

## 11.2 克隆者怎么跑起来

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

## 11.3 发布自己的版本前的检查表

- [ ] `models/` 换成**你有权分发**的模型（或明确许可允许再分发的模型），
      含 `models/companions/` 与 `models/boss_pig/` 这两处新加进来的
- [ ] `splatdata/` 换成你有权分发的场景数据，或删掉该目录并只用 `--splat=off`
- [ ] 确认 `models/README.md` 里那三个换模型注意点（骨名 / 动作名 / 朝向约定）都过了
- [ ] `LICENSE` 里的版权行改成你的名字与年份
- [ ] `THIRD_PARTY.md` 删掉已不适用的条目，补上你新引入的第三方资源
- [ ] `icon.png` 换成你自己的图标
- [ ] 检查 `.gitignore`：`git status` 里**不该**出现任何 `.glb` / `.sogdata` / 大体积贴图
- [ ] 顺手确认没把 `..\_blender_arisu\`（专有模型的派生数据）一起推上去
- [ ] **建 `export_presets.cfg` 时，把 `*.txt` 和 `*.md` 都加进 `include_filter`** ——
      否则导出后 `story/` 里的剧本读不到（静默变成「没有剧情」）、设定表也读不到
      （说话人校验静默失效），见 §9.6

## 11.4 关于截图

`_arisu_captures/` 里的截图是在本机渲染的、含专有角色形象，
**不建议**放进公开仓库的 README（截图是模型形象的派生作品）。
想放演示图，请先用**你有权分发的素材**重新渲一遍。
