# PLAN.md —— 用户手写计划（逐条转录 + 状态）

> 来源：用户 2026-10-22 手写在本子上的 8 条计划，拍照给本喵逐条转录。
> **转录是原文，不修饰**；状态和「卡在哪」是本喵补的。
> ⚠️ 第 5 条是**剧情灵感**，用户明确说「先记下来，不要改动游戏」。

## 1. 把代码建物块换成编辑器物块

> 「1. 将所有开始游戏前构建的物块替换为真正进入 godot 编辑器的物块，
> 因为积少成多，过多的代码构建物块会拖慢启动速度」

**状态：暂缓（用户后来改口「算了，先改第二个」）。**

实测数据（`_probe_block_cost.gd` / `_probe_boot_cost.gd` / `_probe_clerk_cost.gd`）：

| 做法 | 每块耗时 |
|---|---|
| 代码建（独立网格 + 独立材质） | 0.0230 ms |
| 代码建（共享网格 + 共享材质） | 0.0098 ms |
| 代码建 + MultiMesh | 0.0006 ms |
| 先建好 → `pack()` → `instantiate()` | 0.0001 ms |

- 整局开机 ≈ 7.3 s：读场景 708 ms + `_ready` 2.5~3.3 s + 等泼溅 4.0 s。
- 商店 `shop.build()` 全程 **107 ms**，其中 155 个盒子只占 **4.63 ms**（4%），
  大头是小空模型（6~38 ms）和材质克隆。
- 结论：**启动时间不是瓶颈**（堆到 2 万块才 +0.46 s）；真正会被拖垮的是
  **draw call** —— 每块一个 `MeshInstance3D` + 独立材质就是一次独立 draw call，
  搬进编辑器**一个都不会少**。要治只能共享材质 + MultiMesh / 合并网格。

## 2. 渲染距离（参考 Minecraft）

> 「2. 设置渲染距离，参考 Minecraft。渲染距离以外的物体、生物不加载
> （假如该物体或生物一部分包含在渲染距离内也需加载）。
> 在设置中，渲染距离是伪无极调节，即：玩家可以滑动滑块到线段上任意一处；
> 后方数字是 100m ~ 1000m 的无极调节，但实际上是分段的：100m, 200m, 300m, 以此类推」

**状态：✅ 已完成（commit `62a371d`）。**

- 设置项 `render_distance`：滑块 100~1000 m、步长 1 m（连续），
  生效值 `GameSettings.render_distance()` 按 100 m 分段。
- `scripts/render_distance.gd`：递归切成「包围盒对角 ≤ 60 m」的簇（144 个，
  覆盖 586 个网格），按「包围球的最近点 > 渲染距离」裁掉；摄像机 `far` 同步。
- 实测（机位 (-8, 3.2, 9) 朝 -X，每档 40 帧）：

| 渲染距离 | draw call | 图元 | 可见网格 |
|---|---|---|---|
| 1000 m | 510 | 38,050 | 586/586 |
| 300 m | 248 | 6,150 | 470/586 |
| 100 m | 110 | 2,036 | 361/586 |

⚠️ 这一版是「不渲染」，不是「不加载内存」。真·不加载要把 `Parkour`
（本来就是 `scenes/parkour.tscn` 的实例）运行时 `queue_free` 再按需实例化，
但会重置跑酷进度，需要用户点头。

## 3. 内置 Arch Linux 终端 + 整机模型 + LOD

> 「3. 后续剧情发展：购买 5090 整机。godot 中实现 内置 Arch Linux。
> 制作整机模型，显示器外设等。制作 godot Lod 降低压力」

**状态：终端已做（假终端）；整机模型待做；LOD 结论 = 不需要。**

- 用户后来明确：「假终端，这样看还是不下插件了，自己做一个 ARCH LINUX 的界面，
  虚拟的不需要有真实功能」。**已经做完**（commit `d3d281f`）：
  小屋桌子上有显示器 + 键盘，按 F 打开/关闭「假 Arch Linux 终端」
  （`scripts/arch_terminal.gd` + `scripts/hut_computer.gd`）。
- 为什么没用 [godot-xterm](https://github.com/lihop/godot-xterm)：本机连不上
  github.com / objects.githubusercontent.com，11 MB 的 release 包下不下来；
  而且真 PTY 会 fork 宿主机 shell（这台机器 `wsl -l -v` 显示**没有安装任何
  Linux 发行版**，「Arch」无从谈起）。
- **LOD 结论（引擎实测 `_probe_lod_caps.gd`，Godot 4.7.1）**：
  自带「导入时生成 LOD」+ `Viewport.mesh_lod_threshold` +
  `GeometryInstance3D.lod_bias` + `visibility_range_*` 距离剔除。
  但本工程 **整场景图元只有 3.8 万**（1000 m 全显示时），而最大的三角形来源是
  **高斯泼溅（点云，不吃网格 LOD）**。所以 LOD 收益 ≈ 0，**现在不加**。

## 4. 场景拆分（学校高斯场景独立）

> 「4. 场景：开启新的场景。（不）能全部都在 game.tscn。可以……换小空为芹香」

**状态：校园已经独立（`scenes/campus_venue.tscn`，尚未实例化进主场景）。**

- 校园泼溅 615 万点 ≈ **2.9 GiB 显存**，和画室609（277 万点）一起 ≈ 4 GiB。
  用户判断「不然显存炸」是对的。
- 现在 `game.tscn` 里只有画室609 一份泼溅（2,769,851 点，解码 3.6 s）。
- 「换小空为芹香」见下一条的素材状态。

## 5. 剧情：PICO 4 Ultra → GitHub → 知天下查看器 → CSUST

> 「5. 小桃小绿获得 pico4 Ultra。爱丽丝寻找 github（番羽墙）。
> 找到知天下开源查看器。利用头显进入 CSUST」

用户口述的完整版本（**灵感，暂不实现，不改游戏**）：

1. 爱玩游戏的小桃联手小绿赢得比赛，奖品是一台 **PICO 4 Ultra** 头显。
2. 两人研究怎么用；爱丽丝告诉她们可以用「**知天下**」的开源查看器来玩。
3. 于是爱丽丝**翻越围墙与高山**，到达 **GitHub 领地**，在神秘 **VPN** 的帮助下
   拿到了知天下的源代码。
4. 爱丽丝立刻吸收知识、自己动手编译，最后成功编译出**看高斯泼溅的头显软件**。
5. 爱丽丝戴上小桃小绿的 PICO 4 Ultra 做测试 —— 没想到**来到了长沙理工大学**。

**状态：📝 仅记录，用户明确「不要改动游戏」。**

实现时可能用到的东西（先记着）：
- 头显里看到的东西就是现成的**高斯泼溅**（`SplatScene` / gdgs），
  正好可以复用校园那份泼溅（见第 4 条）。
- 「进入 CSUST」= 切到独立场景而不是在 `game.tscn` 里加载 2.9 GiB 的泼溅，
  和第 4 条是同一件事。
- 头显 UI 可以复用 `arch_terminal.gd` 那套「逐字符格 + `SubViewport` 贴到 3D
  物体上」的做法（`hut_computer.gd` 里的显示器就是样板）。

## 6. README 与 GitHub 文件分发

> 「6. Readme 更新，放取 github 文件，去 QQ 群（文件太大或授权）」

**状态：待做。**

- 被 `.gitignore` 排除的素材已经**另存一份**供审核：
  `C:\Users\WY157\Desktop\GODOT\_gitignore_审核\`
  （541 个文件 / 389.4 MB，含 `_MANIFEST.md` 分类清单 + `_FILES.csv` 逐文件表，
  生成脚本 `_tools/copy_gitignored.py`）。
- 用户的打算：大文件/受授权限制的文件走 QQ 群，GitHub 上只放能放的。
  需要 README 里写清楚「哪些文件要自己补、放哪个目录」。

## 7. 换窝 / 换系统

> 「7. 换窝 或者更换系统」

**状态：待确认含义。**（字迹是「换窝」还是「探窝」本喵吃不准，
「更换系统」可能指 Godot 版本 / 渲染后端 / 操作系统。）

## 8. 未来：网络 + 买显卡

> 「8. 未来 网络 买显卡」

**状态：硬件计划，与本仓库无关。**

---

# 附：芹香（Serika）素材状态

用户 2026-10-22 指路："找模型是在 `C:\Users\WY157\Downloads\BlueArchiveModels-main` 这里找"。

已找到并拷进工程（本地产物，`/models/npc/**` 在 `.gitignore` 里，不随仓库分发）：

| 文件 | 大小 |
|---|---|
| `Serika.glb`（默认/校服） | 4.0 MB |
| `Serika (New Year).glb` | 3.1 MB |
| `Serika (Swimsuit).glb` | 3.5 MB |

`_probe_model_info.gd` 实测 `models/npc/serika/serika.glb`：

```
网格 13 个，包围盒 (0.67, 1.39, 0.50) m，底 y = -0.27，顶 y = 1.11
骨架 93 骨；光环网格 Serika_Halo ✓
手骨 Bip001 L Hand / Bip001 R Hand（世界 y = 0.45）
头骨 Bip001 Head（y = 0.67）；眼骨 Bip001 eye_L / eye_R（y = 0.77）
动画 40 条：Normal_Idle / Cafe_Idle / Stand_Idle / Cafe_Walk / Move_Ing …
```

⚠️ 和小空（`sora.glb`，338 骨，手骨名 `hand.l`/`hand.r`，手骨高 0.89/0.69 m）
**不是同一套 rig**，所以 `scripts/shop_clerk.gd` 换人时要改四处：
手骨名、动画名、落脚偏移（−0.27 m 要抬起来）、身高缩放（1.39 m 偏矮）。

**✅ 2026-10-22 已换完（校服版）**，改动：
- `shop_clerk.gd`：`MODEL` → `serika.glb`；手骨名走 `Bip001 L/R Hand`；
  待机播 `Normal_Idle`；`HaloFix.polish()` 抛光 `Serika_Halo`；
- 缩放 `MODEL_SCALE = 1.55`、抬高 `CLERK_LIFT = 0.45 m`（**不是**按包围盒算 ——
  这套 rig 的骨骼在压缩空间里，改 scale 几乎不改变世界高度，实测三次）；
- 节点 `ClerkSora` → `ClerkSerika`；`CREDITS.md` / `credits.gd` 把小空标成「已停用」。
- 小空的文件仍留在 `models/npc/sora/`，只是不再上场。
