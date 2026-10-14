# Arisu 学习沙盒（Godot 4.7）

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

**场地是「悬浮记忆平台」**：40 × 40 m 的竞技场悬在空中，四面有隐形护栏；
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
scenes/game.tscn          竞技场：地面 + 3 根石柱 + 5 个靶子 + 灯光 + HUD
scenes/player.tscn        Player(CharacterBody3D)
                          ├─ Collision   胶囊
                          ├─ Arisu       模型节点（绕 Y 转 180°，见 §1.4）
                          │  └─ Model    Arisu.glb 实例
                          │     └─ AnimDriver   动画驱动
                          ├─ Weapon      武器逻辑 + Muzzle 挂点
                          └─ CameraRig → SpringArm3D → Camera3D
scripts/player.gd         移动积分、相机、朝向、开火转身门控
scripts/anim_driver.gd    动画驱动（直接用 AnimationPlayer）
scripts/weapon.gd         射线命中、弹药、换弹、弹丸、开火门控、特效
scripts/target.gd         可击毁靶子（掉血 → 闪白 → 塌下 → 4 秒重生）
scripts/hud.gd            准星、弹药、状态、速度、换弹条
scripts/game.gd           玩法总控
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
& $g --path $p --script res://scripts/_verify_splat.gd      # 15 项：泼溅摆放 / 悬浮平台 / 隐形护栏（第六节）
& $g --path $p --script res://scripts/_probe_view.gd         # 诊断：打印视线/朝向数值，并从四方位渲图
```

前五条建议加 `-- --splat=off`：615 万点的逐帧光栅化会让这些渲染相关用例慢很多
（第六节实测，`_verify_final` 第 5 节甚至会卡住）。`_verify_splat` 要开着泼溅跑。

> ⚠️ headless 帧率极低（约 6 fps，每帧只推进 0.006 s），按时间推进的项
> （换弹、连发）**必须按状态等**（等 `is_reloading()`、等弹药归零），
> 不能按帧数算。也别拿 60 帧/秒去估算。

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
│  └─ Arisu*_*.png          自动解包的贴图 ※不随仓库分发
├─ splatdata/
│  ├─ README.md             说明：泼溅数据要求与摆放参数
│  ├─ school_playable.sogdata  **实际加载**的校园泼溅（清理版，86.6 MB）※不随仓库分发
│  └─ school_raw.sogdata       原始未清理扫描（仅存档）※不随仓库分发
├─ scenes/
│  ├─ game.tscn             玩法场景（40×40 悬浮平台 + 四面隐形护栏 + 下沉校园）
│  ├─ player.tscn           玩家（模型 + 动画 + 武器 + 相机）
│  └─ main.tscn             动画查看器
├─ scripts/
│  ├─ player.gd             移动 / 相机 / 朝向 / 开火转身门控
│  ├─ anim_driver.gd        动画驱动（直接 AnimationPlayer）
│  ├─ weapon.gd             开火 / 弹药 / 换弹 / 弹丸 / 特效
│  ├─ splat_scene.gd        高斯泼溅接入器：后台线程解码 + 自动摆放（第六节）
│  ├─ sog_runtime.gd        运行时 SOG 解码器（绕开编辑器导入器，第六节）
│  ├─ target.gd / hud.gd / game.gd / main.gd
│  ├─ _verify_*.gd          [工具] 自检（见 §1.11）
│  ├─ _capture.gd           [工具] 24 条动作取样帧
│  ├─ _pose_shots.gd        [工具] 多机位姿势检查
│  ├─ _play_shots.gd        [工具] 玩法全流程截图
│  ├─ _probe_ext_glb.gd     [工具] 两个 glb 的动作/时长/前倾对比
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

本喵在这上面栽了**四次**。`Get-Content`（含 `-Raw`）会把 UTF-8 中文按 ANSI 解码，
再用 `Set-Content` 写回去就全是乱码：

- GDScript 文件 → Godot 报 `invalid unicode (UTF-8)` 拒绝加载，整个类都解析不了
- Markdown 文档 → 163 行注释变乱码，只能整份重写

**改脚本/文档一律用编辑器工具**（读全文 → 写全文），不要用 PowerShell 的
文本替换或 `Set-Content`。

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
        竞技场 40×40 悬浮平台（y = 0，四面隐形护栏）
   ──────────────────────────────────────────
                    ↓ 12 m
        校园泼溅 ×25（211 × 160 m，水平居中）
```

- `game.tscn` 的 `Floor` 从 80×80 缩到 40×40 —— 靶子/柱子坐标全在 ±20 内，**一个都没动**
- 新增 `WallPX / WallNX / WallPZ / WallNZ`：只有 CollisionShape3D、没有网格的 StaticBody3D（隐形护栏，高 4 m）
- 新增 `SplatScene` 节点：`world_scale = 25`、`auto_place = true`、`top_gap = 12`、`cache_mode = "auto"`
- 相机与跑打手感**一点没改**
- `game.gd` 加了保险：掉到 y < −60 就送回出生点
- HUD 左上角状态行显示解码进度；底部提示加了「走到平台边缘低头看脚下的校园」

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

`SplatScene` 支持两个命令行覆盖：`-- --splat=off`（完全不加载）与
`-- --splat-cache=auto|off|refresh`（展开缓存策略）。

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

---

# 七、下一步

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
7. **换原创素材** —— 换掉模型与泼溅数据后本工程才能真正对外发布（见第八节）

---

# 八、开源与许可

## 8.1 结论

**除模型与美术素材外，本仓库全部以 [MIT](LICENSE) 授权。**
逐项清单见 [THIRD_PARTY.md](THIRD_PARTY.md)。

| 内容 | 许可 | 在仓库里？ |
|---|---|---|
| 本项目作者编写的全部代码与文档（`scripts/`、`scenes/`、`project.godot`、README…） | **MIT** | ✅ |
| `addons/gdgs/`（GDGS 3.3.0，ReconWorldLab） | MIT（作者原许可保留在 `addons/gdgs/LICENSE`） | ✅ |
| `models/Arisu*.glb` + 解包贴图 | © NEXON Games / Yostar，**专有** | ❌ 被 `.gitignore` 排除 |
| `splatdata/*.sogdata`、`models/school.collision.glb` | 权利状态未核实 | ❌ 被 `.gitignore` 排除 |
| `icon.png` | 待仓库作者确认 | ✅（如非原创请替换） |

## 8.2 克隆者怎么跑起来

```powershell
git clone <你的仓库>
cd <仓库目录>
# ① 放入你自己合法获得的角色模型（必需）
#    models/Arisu_ext.glb     见 models/README.md
# ② 可选：放入校园泼溅（没有就用 --splat=off）
#    splatdata/school_playable.sogdata   见 splatdata/README.md

& <godot 4.7 mono 版> --path .              # 有泼溅数据
& <godot 4.7 mono 版> --path . -- --splat=off   # 没有泼溅数据
```

第一次打开时 Godot 会自动导入 glb 并解包贴图，然后就能 F5。

## 8.3 发布自己的版本前的检查表

- [ ] `models/` 换成**你有权分发**的模型（或明确许可允许再分发的模型）
- [ ] `splatdata/` 换成你有权分发的场景数据，或删掉该目录并只用 `--splat=off`
- [ ] 确认 `models/README.md` 里那三个换模型注意点（骨名 / 动作名 / 朝向约定）都过了
- [ ] `LICENSE` 里的版权行改成你的名字与年份
- [ ] `THIRD_PARTY.md` 删掉已不适用的条目，补上你新引入的第三方资源
- [ ] `icon.png` 换成你自己的图标
- [ ] 检查 `.gitignore`：`git status` 里**不该**出现任何 `.glb` / `.sogdata` / 大体积贴图
- [ ] 顺手确认没把 `..\_blender_arisu\`（专有模型的派生数据）一起推上去

## 8.4 关于截图

`_arisu_captures/` 里的截图是在本机渲染的、含专有角色形象，
**不建议**放进公开仓库的 README（截图是模型形象的派生作品）。
想放演示图，请先用**你有权分发的素材**重新渲一遍。
