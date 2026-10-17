# 第三方组件与素材许可说明

本仓库**自己的代码**（GDScript、场景、着色器、项目配置、文档）以 **MIT** 授权，见 [LICENSE](LICENSE)。

下面这些**不属于** MIT 覆盖范围。其中私有素材**不在本仓库中分发**，
`.gitignore` 已强制排除 —— 克隆本仓库后需要你自己补齐才能运行（见各目录下的 README）。

## 一览

| 组件 | 许可 | 是否随仓库分发 | 说明 |
|---|---|---|---|
| [Godot Engine](https://godotengine.org) 4.7.1 | MIT | ❌ 不包含 | 需要自行安装（本工程用 mono 版验证，不含 C# 代码） |
| [GDGS](https://github.com/ReconWorldLab/godot-gaussian-splatting) 3.3.0 | MIT | ✅ 包含于 `addons/gdgs/` | 高斯泼溅渲染插件，作者 ReconWorldLab；原许可文件保留在 `addons/gdgs/LICENSE` |
| [UI Pack - Pixel Adventure](https://kenney.nl/assets/ui-pack-pixel-adventure) 2.0 | **CC0 1.0**（公有领域，可商用、无需署名） | ✅ 包含于 `assets/ui/` | 设置界面的九宫格面板 / 按钮切片（`tile_*.png`），作者 Kenney。原许可保留在 `assets/ui/LICENSE_Kenney_UI-Pack_CC0.md`。⚠️ 其中 `tile_panel.png` / `tile_button_hover.png` 的**中心被填成了白色**（原图是中空边框，直接当面板用会透出背后的游戏画面）—— CC0 允许修改 |
| [Fusion Pixel Font](https://github.com/TakWolf/fusion-pixel-font) 12px | **SIL OFL 1.1** | ✅ 包含于 `assets/ui/` | **中文像素字体**（`assets/ui/font.ttf`），作者 TakWolf。实测覆盖 19214/20992 个 CJK 统一汉字、100% 中文标点、100% 假名与谚文。它是现在整套 UI 字体（`ui_skin.gd` 的 `UI_FONT_CANDIDATES`）的**兜底**：本地没放 `assets/ui_font/` 时就用它，所以克隆仓库的人一定有一套能显示中文的字。OFL 允许随软件分发，许可原文在 `assets/ui/LICENSE_FusionPixel_OFL.txt` |
| Aa 字库「Aa暗夜深渊」 | **商用需授权**（字体压缩包内附 `获取商用授权.url`）；个人学习 / 非商业使用 | ❌ **不包含** | `assets/ui_font/Aa暗夜深渊.ttf`（3.86 MB）。现在整套 UI 用的显示字体。实测覆盖游戏里**实际会显示的 189 个字一个不缺**（含全部中文标点、同伴与 Boss 名字；`tools/font/font_needed.py` 可复现）。和 Sprout Lands 皮肤同一类处理：**可本地使用、不可再分发** —— `.gitignore` 排除该目录（只保留一份 README 说明），克隆者会自动回退到上面的 Fusion Pixel。**发布任何产物前请自行取得商用授权，或换一套允许分发的字体（如思源黑体 / 霞鹜文楷等 OFL 字体）** |
| Sprout Lands UI Pack（美术：Cup Nooble） | **免费但限非商业**：可修改，但**不可再分发或转售（即使修改过）**，且只能用于非商业项目 | ❌ **不包含** | `assets/ui_sprout/`（设置界面的 Sprout Lands 皮肤）。授权原文抄在该目录的 `LICENSE_SproutLands.txt`。**因为禁止再分发**，这一套被 `.gitignore` 排除 —— 克隆后需自行从 [itch](https://cupnooble.itch.io/sprout-lands-ui-pack) 取得；没有它时设置界面会**自动回退**到上面的 Kenney 皮肤，不会报错 |
| [Interface Sounds](https://kenney.nl/assets/interface-sounds) 1.0 | **CC0 1.0**（公有领域，可商用、无需署名） | ✅ 包含于 `assets/sfx/` | 界面音效，作者 Kenney：`click_001.ogg`（空仓干响）/ `click_002.ogg`（按钮）/ `toggle_001.ogg`（开关）/ `tick_002.ogg`（滑条）/ `open_001.ogg`、`close_001.ogg`（菜单开 / 关）。原许可保留在 `assets/sfx/LICENSE_Kenney_CC0.md` |
| [Sci-fi Sounds](https://kenney.nl/assets/sci-fi-sounds) | 同上 | ✅ 包含于 `assets/sfx/` | 枪声：`laserSmall_000` ~ `laserSmall_004`（**5 条候选随机播 + 音高抖动**，免得连发听起来像复读机）。挑它是因为武器打的是可见的光弹（§1.6），能量枪声比写实枪声更贴 |
| [RPG Audio](https://kenney.nl/assets/rpg-audio) | 同上 | ✅ 包含于 `assets/sfx/` | 换弹两声：`metalLatch.ogg`（拔弹匣 / 松卡榫）、`metalClick.ogg`（推上弹匣） |
| Blue Archive 「Arisu」角色模型与贴图 | **专有版权**（© NEXON Games / Yostar） | ❌ 不包含 | `models/Arisu.glb`、`models/Arisu_ext.glb` 与自动解包的 `Arisu*.png`。取自 [BlueArchiveModels](https://github.com/lihaohong6/BlueArchiveModels)（官方素材解包整理版，整理者 **lihaohong6 / Peterli**）—— **解包不改变版权**，仍然只能本地学习。**仅用于本地学习研究，不得再分发、不得商用、不得用于任何发布产物** |
| Blue Archive 同伴模型「未花 / 优香 / 诺亚 / 小桃 / 小绿 / 柚子 / 凯伊」 | **专有版权**（同上） | ❌ 不包含 | `models/companions/**`（`Mika.glb` / `Yuuka.glb` / `Noa.glb` / `Momoi.glb` / `Midori.glb` / `Yuzu.glb` / `Kei.glb` / `Kei_ext.glb`（凯伊的重导版，见 README §8.8），均取**初始形态**）。来源同上（BlueArchiveModels）。同样仅供本地学习 |
| 「霸王龙优香」Boss 模型（FBX） | **专有版权**（同上，玩家二创） | ❌ 不包含 | `models/boss/**`（`优香霸王龙.fbx` + 贴图 + ASCII 副本）。同样仅供本地学习 |
| 「飞猪优香」Boss 模型（FBX，作者：**一个睿智**） | **专有版权**（派生自 Blue Archive，玩家二创） | ❌ 不包含 | `models/boss_pig/**`（`猪猪优香.fbx` + `uv/` + `tex/` + `ref/` 作者的对照渲染图）。同样仅供本地学习 |
| 「倭瓜优香」Boss 模型（OBJ，作者：**一个睿智**） | **专有版权**（派生自 Blue Archive，玩家二创） | ❌ 不包含 | `models/boss_squash/**`（`倭瓜优香.obj` + `textures/` 4 张贴图）。同样仅供本地学习 |
| 「霍德」Boss 模型（FBX，作者：**一个睿智**） | **专有版权**（派生自 Blue Archive，玩家二创） | ❌ 不包含 | `models/boss_hod/**`（`HOD_Original.fbx` + 3 张贴图 + 2 张作者渲染遮罩） |
| 「佩洛洛斯拉」Boss 模型（FBX，作者：**一个睿智**） | **专有版权**（派生自 Blue Archive，玩家二创） | ❌ 不包含 | `models/boss_perorozilla/**`（`Perorozilla_Original.fbx` + 贴图 + 表情遮罩） |
| 高斯泼溅扫描数据（校园 / 画室 609） | **权利状态未核实** | ❌ 不包含 | `splatdata/*.sogdata`（含 `room609.sogdata`）。由使用者提供，其拍摄权、场地权、肖像权与再分发权均未由本项目核实 |
| 校园碰撞网格 | 派生自上一项 | ❌ 不包含 | `models/school.collision.glb` |
| 项目图标 `icon.png` | 待确认 | ✅ 包含 | 来源需仓库作者确认；若不是原创请替换为自有图标 |

## 克隆后怎么补齐

```text
_arisu_learn/
├─ models/              ← 放入你自己合法获得的角色模型（见 models/README.md）
│  ├─ companions/       ← 可选：七名同伴的 glb（来源：BlueArchiveModels）
│  ├─ boss/             ← 可选：霸王龙优香 FBX + 贴图
│  ├─ boss_pig/         ← 可选：飞猪优香 FBX + 贴图
│  ├─ boss_squash/      ← 可选：倭瓜优香 OBJ + 贴图
│  ├─ boss_hod/         ← 可选：霍德 FBX + 贴图
│  └─ boss_perorozilla/ ← 可选：佩洛洛斯拉 FBX + 贴图
├─ assets/
│  ├─ ui_font/          ← 可选：界面显示字体（现在是「Aa暗夜深渊.ttf」，商用需授权）
│  │                       丢进来就整套 UI 换字；没有它会**自动回退**到下面的
│  │                       Fusion Pixel，不会报错。放进去后要导入一次：
│  │                       `--headless --path . --import`。见 assets/ui_font/README.md
│  ├─ ui_sprout/        ← 可选：Sprout Lands 皮肤（panel.png / button*.png / font.ttf）
│  │                          没有它会**自动回退**到仓库自带的 Kenney 皮肤，不会报错
│  └─ sfx/              ← **不用补**：13 个 Kenney 音效（CC0）已经在仓库里，
│                            克隆下来就有声音；没有文件时也只是静默、不报错（§1.14）
└─ splatdata/           ← 可选：放入校园 / 画室609 的 .sogdata（见 splatdata/README.md）
                          两份都没有也能跑：`-- --splat=off`
```

角色模型与泼溅数据**都是可选的第二块**：没有泼溅数据时，用
`-- --splat=off` 运行即可只玩射击部分（只想留一份泼溅用 `-- --venue=room|campus`，
两份同时在 8 GB 显卡上显存偏紧，见 README §6.8）；没有同伴 / Boss 素材时，
把 `game.tscn` 里对应的 `Companion*` / `Boss` / `BossPig` / `BossSquash` / `BossHod` /
`BossPeroro` 节点删掉即可；没有主角模型时工程无法运行（`scenes/player.tscn` 直接引用该模型）。

> **逐项署名**（谁做了什么、能不能分发）见 [CREDITS.md](CREDITS.md)，
> 游戏里 Esc → 设置 →「致谢与素材署名」显示的是同一份数据。

## 关于 `..\_blender_arisu\`

Blender 动作生成管线**不在本仓库内**，而且它的产物是上述专有模型的派生数据，
同样**不可分发**。本仓库只保留了「怎么改动作」的文档（README 第五节）。

## 你自己也要注意

- 若你把本工程改成自己的角色与场景，请把 `LICENSE` 里的版权行换成你的名字，
  并删掉本文件中不再适用的条目。
- MIT 是宽松许可，但它**不覆盖**你放进 `models/`、`splatdata/` 的素材 ——
  别把它们一起推上去。
