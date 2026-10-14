# 第三方组件与素材许可说明

本仓库**自己的代码**（GDScript、场景、着色器、项目配置、文档）以 **MIT** 授权，见 [LICENSE](LICENSE)。

下面这些**不属于** MIT 覆盖范围。其中私有素材**不在本仓库中分发**，
`.gitignore` 已强制排除 —— 克隆本仓库后需要你自己补齐才能运行（见各目录下的 README）。

## 一览

| 组件 | 许可 | 是否随仓库分发 | 说明 |
|---|---|---|---|
| [Godot Engine](https://godotengine.org) 4.7.1 | MIT | ❌ 不包含 | 需要自行安装（本工程用 mono 版验证，不含 C# 代码） |
| [GDGS](https://github.com/ReconWorldLab/godot-gaussian-splatting) 3.3.0 | MIT | ✅ 包含于 `addons/gdgs/` | 高斯泼溅渲染插件，作者 ReconWorldLab；原许可文件保留在 `addons/gdgs/LICENSE` |
| Blue Archive 「Arisu」角色模型与贴图 | **专有版权**（© NEXON Games / Yostar） | ❌ 不包含 | `models/Arisu.glb`、`models/Arisu_ext.glb` 与自动解包的 `Arisu*.png`。**仅用于本地学习研究，不得再分发、不得商用、不得用于任何发布产物** |
| Blue Archive 同伴模型「未花 / 优香 / 诺亚 / 小桃 / 小绿 / 柚子 / 凯伊」 | **专有版权**（同上） | ❌ 不包含 | `models/companions/**`（`Mika.glb` / `Yuuka.glb` / `Noa.glb` / `Momoi.glb` / `Midori.glb` / `Yuzu.glb` / `Kei.glb`，均取**初始形态**）。同样仅供本地学习 |
| 「霸王龙优香」Boss 模型（FBX） | **专有版权**（同上，玩家二创） | ❌ 不包含 | `models/boss/**`（`优香霸王龙.fbx` + 贴图 + ASCII 副本）。同样仅供本地学习 |
| 「飞猪优香」Boss 模型（FBX，作者：一个睿智） | **专有版权**（派生自 Blue Archive，玩家二创） | ❌ 不包含 | `models/boss_pig/**`（`猪猪优香.fbx` + `uv/` + `tex/` + `ref/` 作者的对照渲染图）。同样仅供本地学习 |
| 高斯泼溅扫描数据（校园 / 画室 609） | **权利状态未核实** | ❌ 不包含 | `splatdata/*.sogdata`（含 `room609.sogdata`）。由使用者提供，其拍摄权、场地权、肖像权与再分发权均未由本项目核实 |
| 校园碰撞网格 | 派生自上一项 | ❌ 不包含 | `models/school.collision.glb` |
| 项目图标 `icon.png` | 待确认 | ✅ 包含 | 来源需仓库作者确认；若不是原创请替换为自有图标 |

## 克隆后怎么补齐

```text
_arisu_learn/
├─ models/              ← 放入你自己合法获得的角色模型（见 models/README.md）
│  ├─ companions/       ← 可选：七名同伴的 glb
│  ├─ boss/             ← 可选：霸王龙优香 FBX + 贴图
│  └─ boss_pig/         ← 可选：飞猪优香 FBX + 贴图
└─ splatdata/           ← 可选：放入校园 / 画室609 的 .sogdata（见 splatdata/README.md）
                          两份都没有也能跑：`-- --splat=off`
```

角色模型与泼溅数据**都是可选的第二块**：没有泼溅数据时，用
`-- --splat=off` 运行即可只玩射击部分（只想留一份泼溅用 `-- --venue=room|campus`，
两份同时在 8 GB 显卡上显存偏紧，见 README §6.8）；没有同伴 / Boss 素材时，
把 `game.tscn` 里对应的 `Companion*` / `Boss` / `BossPig` 节点删掉即可；
没有主角模型时工程无法运行（`scenes/player.tscn` 直接引用该模型）。

## 关于 `..\_blender_arisu\`

Blender 动作生成管线**不在本仓库内**，而且它的产物是上述专有模型的派生数据，
同样**不可分发**。本仓库只保留了「怎么改动作」的文档（README 第五节）。

## 你自己也要注意

- 若你把本工程改成自己的角色与场景，请把 `LICENSE` 里的版权行换成你的名字，
  并删掉本文件中不再适用的条目。
- MIT 是宽松许可，但它**不覆盖**你放进 `models/`、`splatdata/` 的素材 ——
  别把它们一起推上去。
