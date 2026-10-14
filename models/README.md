# models/ —— 角色模型（不随仓库分发）

这个目录在本仓库里**只有说明文件**。要运行工程，请放入你自己合法获得的模型：

| 文件名 | 必需 | 说明 |
|---|---|---|
| `Arisu_ext.glb` | ✅ 必需 | `scenes/player.tscn` 引用的模型。27 条动作、170 骨（含 `Jump_Start` / `Jump_Land` / `Dodge_Roll`，见 README 第五节） |
| `Arisu.glb` | 可选 | 原始版（24 条动作）。切换它只需把 `player.tscn` 第 4 行的 `Arisu_ext.glb` 改回 `Arisu.glb` |
| `school.collision.glb` | 可选 | 校园碰撞网格。默认不挂载（`SplatScene.build_collision = false`） |
| `Arisu*_*.png` | 自动生成 | 贴图会由 Godot 在首次导入 glb 时自动解包，不用手动放 |
| `companions/Mika.glb` | 可选 | 同伴「未花」。145 骨、33 动作（README 第八节） |
| `companions/Yuuka.glb` | 可选 | 同伴「优香」。108 骨、38 动作 |
| `companions/Noa.glb` | 可选 | 同伴「诺亚」。135 骨、31 动作 |
| `companions/Momoi.glb` | 可选 | 同伴「小桃」。105 骨、37 动作 |
| `companions/Midori.glb` | 可选 | 同伴「小绿」。105 骨、31 动作 |
| `companions/Yuzu.glb` | 可选 | 同伴「柚子」。122 骨、30 动作 |
| `companions/Kei.glb` | 可选 | 同伴「凯伊」。主骨架 166 骨、32 动作（另有 21/6/1 骨的附属 skin） |
| `boss/优香霸王龙.fbx` | 可选 | 第一位 Boss（README 第七节）。73 骨、无动画、约 31 万三角形 |
| `boss_pig/猪猪优香.fbx` | 可选 | 第二位 Boss（README §7.6）。**纯静态网格**，4 网格 / 1.27 万三角形、无骨无动画 |

同伴与 Boss 都是**可选**的：没有就把 `scenes/game.tscn` 里对应的
`CompanionMika` / `CompanionYuuka` / `CompanionNoa` / `CompanionMomoi` /
`CompanionMidori` / `CompanionYuzu` / `CompanionKei` / `Boss` / `BossPig` 节点删掉。

同伴这七份 GLB 的**贴图是内嵌的**（image 走 bufferView），所以只要拷 `.glb` 本体。

`companions/` 与 `boss*/` 内部的文件名（ASCII 化后的 `tex/*.png`、`ref/*.png`）见 README 第七、八节。
`models/companions/**`、`models/boss/**`、`models/boss_pig/**` 都已被 `.gitignore` 排除。

## ⚠️ 版权

本工程验证时用的是 **Blue Archive 的 Arisu** 模型，版权属于
**NEXON Games / Yostar**。该项目**仅供本地学习研究**：

- 不得再分发（所以它被 `.gitignore` 排除，不在仓库里）
- 不得用于任何发布产物或商业用途

换成你自己的原创模型（或明确允许再分发的模型）之后，本工程才可以对外发布。
换模型时注意三件事：

1. **骨骼名**：`anim_driver.gd` 与 `weapon.gd` 靠 `Bip001*` 骨名找骨骼
   （`Bip001 Pelvis` / `Bip001 Spine1` / `Bip001 Neck` / `Bip001 Head` /
   `Bip001 eye_L` / `Bip001 eye_R` / `Bip001 R Hand` / `bone_Railgun_Muzzle_03`）。
   换骨架就要同步改这两个脚本的 `@export` NodePath 与骨名常量。
2. **动作名**：驱动器引用 `Normal_Idle` / `Cafe_Walk` / `Move_Ing` /
   `Normal_Attack_Ing` / `Normal_Reload`（都有 `has_animation()` 兜底）。
3. **朝向约定**：这套模型 `rotation.y = 0` 时脸朝世界 **+Z**（README §1.4）。
   换了模型要用四方位渲图重新确认，`scripts/_probe_view.gd` 就是干这个的。
