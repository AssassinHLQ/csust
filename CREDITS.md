# 素材署名与许可（CREDITS）

> **这份文件是 `scripts/credits.gd` 的人读版。** 游戏里 Esc → 设置 →「致谢与素材署名」
> 显示的是同一份数据；`scripts/_verify_credits.gd` 会断言 `models/`、`assets/`、
> `addons/`、`splatdata/` 下的**每一个目录**都在这张表里登记过 ——
> 也就是说：**新加一套素材却没署名，自检直接红。**

本项目自己的代码、场景、着色器、文档以 **MIT** 授权，见 [LICENSE](LICENSE)。
许可分两类：能随仓库分发的（✅）与**只能本地使用、不可再分发**的（❌，已被
`.gitignore` 排除，克隆者需自己合法取得才能运行对应部分）。

## 画面上最重要的三件事

1. **主角、七名同伴、两位 Blue Archive 角色的 Boss、泼溅扫描** —— 版权不属于本项目，
   只用于本地学习研究，**不得再分发、不得商用、不得用于任何发布产物**。
   这些模型取自 [BlueArchiveModels](https://github.com/lihaohong6/BlueArchiveModels)
   （Blue Archive 官方素材的解包整理版，整理者 **lihaohong6 / Peterli**）——
   **解包不改变版权**，它们仍然是 NEXON Games / Yostar 的专有素材。
2. **四位玩家二创的 Boss（飞猪 / 倭瓜 / 霍德 / 佩洛洛斯拉）出自「一个睿智」**，
   派生自 Blue Archive，同样是专有版权。署名照下面表格写。
3. **界面字体 `assets/ui_font/Aa暗夜深渊.ttf` 商用需授权**。发布前要么取得授权，
   要么删掉它（会自动回退到 OFL 授权的 Fusion Pixel）。

## 一、代码与插件

| 素材 | 作者 / 版权方 | 许可 | 分发 | 位置 / 来源 | 说明 |
|---|---|---|---|---|---|
| 全部 GDScript 代码、场景、着色器 | 本项目作者 | MIT | ✅ | `scripts/`、`scenes/`、`project.godot` | 见 [LICENSE](LICENSE) |
| 全景天空盒（粉/日/夜/黄昏） | AllSky Free（Richard Whitelock） | MIT | ✅ | `assets/sky/`，[AllSkyFree_Godot](https://github.com/rpgwhitelock/AllSkyFree_Godot) | 原图 8192~16384 缩到 4096×2048 JPEG |
| 空地地砖贴图 + 法线图 | 本项目作者（程序生成） | MIT | ✅ | `assets/tex/`，`tools/make_lot_paver.py` | 完全可平铺 |
| [GDGS](https://github.com/ReconWorldLab/godot-gaussian-splatting) 3.3.0 | ReconWorldLab | MIT | ✅ | `addons/gdgs/` | 高斯泼溅渲染插件；原许可保留在 `addons/gdgs/LICENSE` |

## 二、角色与 Boss 模型（**全部不随仓库分发**）

> 场上默认**只有飞猪优香**一位（不挤）；其余六位在 `scenes/bosses_standby.tscn`
> 里待命，`-- --bosses=all` 才上场。

| 素材 | 作者 / 版权方 | 许可 | 分发 | 位置 / 来源 | 说明 |
|---|---|---|---|---|---|
| 比纳（第六位 Boss，备用） | **一个睿智** | 专有（Blue Archive 二创） | ❌ | `models/boss_binah/`，来源 `比纳_by_一个睿智.zip` | `Binah_Original.fbx`，44 骨；3 个材质（本体/环、武器面、光环）；`*_Mask.png` 同上 |
| 哥利亚（第七位 Boss，备用） | **一个睿智** | 专有（Blue Archive 二创） | ❌ | `models/boss_goliath/`，来源 `哥利亚_by_一个睿智.zip` | `Goliath_Decagram_Vulcan.fbx`，34 骨、单网格单材质 |
| 霍德（第四位 Boss） | **一个睿智** | 专有（Blue Archive 二创） | ❌ | `models/boss_hod/`，来源 `霍德_by_一个睿智.zip` | `HOD_Original.fbx`，164 骨、无动画；3 个材质；`*_Mask.png` 是原作者渲染遮罩，游戏里不绑 |
| 佩洛洛斯拉（第五位 Boss） | **一个睿智** | 专有（Blue Archive 二创） | ❌ | `models/boss_perorozilla/`，来源 `佩洛洛斯拉_by_一个睿智.zip` | `Perorozilla_Original.fbx`，47 骨、无动画；6 网格共用 1 材质；5 张表情变体只留 1 张 |
| 倭瓜优香（第三位 Boss） | **一个睿智** | 专有（Blue Archive 二创） | ❌ | `models/boss_squash/`，来源 `倭瓜优香压缩文件_by_一个睿智.zip` | `倭瓜优香.obj`，纯静态网格、无骨架；4 个材质 |
| 飞猪优香（第二位 Boss） | **一个睿智** | 专有（Blue Archive 二创） | ❌ | `models/boss_pig/`，来源 `飞猪优香 (2)_by_一个睿智.zip` | `猪猪优香.fbx`；`uv/` 里两张是作者的成品渲染图，已挪到 `ref/` 当贴图基准 |
| 霸王龙优香（第一位 Boss） | Blue Archive 玩家二创（原作者未标注） | 专有 | ❌ | `models/boss/` | `优香霸王龙.fbx`，73 骨、无动画 |
| 七名同伴（小雪 / 优香 / 诺亚 / 小桃 / 小绿 / 柚子 / 凯伊） | NEXON Games / Yostar（Blue Archive） | 专有 | ❌ | `models/companions/`，来源 [BlueArchiveModels](https://github.com/lihaohong6/BlueArchiveModels)（官方素材解包，整理者 lihaohong6 / Peterli） | 均取初始形态；凯伊用 `Kei_ext.glb` |
| RTX 5090 显卡模型（最后平台房顶的资产） | 爱给网（aigei.com）用户上传，作者未署名 | 专有（仅限学习交流，不可商用） | ❌ | `models/rtx5090/`，来源：爱给网下载的 `RTX5090.obj`（4.5 MB，29,480 面） | 2026-10-20 用户提供并当天换成高模（同目录还留着 945 KB 的 `RTX5090simplified.obj`）；`.gitignore` 排除了整个目录，缺它时屋顶用程序化占位卡 |
| BANK 招牌模型（最后平台小屋屋顶） | **使用者自制**（Rhino 导出 OBJ） | 归使用者所有 | ✅ `models/bank/BANK.obj` | `models/bank/`，2026-10-20 桌面提供 | 1765 面；文件自带一圈 `Default` 包围盒，`bank_sign.gd` 按材质名剔掉；原 `mtllib` 缺失，仓库补了一份最小 `BANK.mtl` |
| 主角 Arisu 模型与贴图、校园碰撞网格 | NEXON Games / Yostar（Blue Archive） | 专有 | ❌ | `models/Arisu*.glb`、`Arisu*.png`、`school.collision.glb`，来源同上 | 贴图由 Godot 导入 glb 时自动解包 |
| 校园 / 画室609 高斯泼溅扫描 | 由使用者提供，**权利状态未核实** | 未核实 | ❌ | `splatdata/*.sogdata` | 拍摄权、场地权、肖像权、再分发权均未确认；缺失时用 `-- --splat=off` |
| 老师（sensei）NPC 模型 | **张伟事务所** | 专有（Blue Archive 二创） | ❌ | `models/npc/`，来源 `Sensei_by_张伟事务所.zip` | **卡通版**：Rigify 骨架 338 骨、**0 条动作**、**0 张贴图**（颜色全在顶点色里）。带 55 个 `cs_*` 控制器网格，载入即删；网格几乎整块绑在 `head.x` 上，手臂只能掰顶点。见 `scripts/sensei_npc.gd` 与 README §8.9 |
| 老师（sensei）旧版模型与贴图 | **食小派蒙辣** | 专有（Blue Archive 二创） | ❌ | 已换成上面的卡通版；旧文件留在 `_sensei_out/sensei_tex.glb` | MMD/PMX 导出，313 骨、0 动作；本工程曾重导出为 `sensei.glb`（删 307 个刚体、贴图降到 1024、材质重建 —— MMD 材质树 glTF 导出器认不出，会静默丢贴图） |
| **天使24 店员「黑见芹香」（Serika，校服版）** | 原作 © **NEXON Games / Yostar**（Blue Archive），模型包整理者未署名 | 专有（Blue Archive） | ❌ | `models/npc/serika/serika.glb`，来源：BlueArchiveModels 模型包（2026-10-22 用户指路 `Downloads/BlueArchiveModels-main`） | 93 骨 `Bip001` 骨架、40 条动画，待机播 `Normal_Idle`；包围盒 0.67×1.39×0.50 m、原点在脚上方 0.27 m（`shop_clerk.gd` 自动抬到踩地）。手骨 `Bip001 L/R Hand` 高 0.72 m 低于台面 1.04 m，藏在柜台后；光环 `Serika_Halo` 走 `HaloFix` 抛光。见 `scripts/shop_clerk.gd` |
| （已停用）天使24 店员「小空」（Sora） | 薛定谔的小问号 | 专有（Blue Archive 二创） | ❌ | `models/npc/sora/`（文件仍在，不再上场） | 2026-10-22 起停用：用户要求「小空出差」，且 338 骨 MMD 精细模型与卡通大头小人的同伴画风不统一 |

## 三、界面与字体

| 素材 | 作者 | 许可 | 分发 | 位置 / 来源 | 说明 |
|---|---|---|---|---|---|
| [UI Pack: Pixel Adventure](https://kenney.nl/assets/ui-pack-pixel-adventure) 2.0 | Kenney | **CC0 1.0** | ✅ | `assets/ui/`，许可原文 `assets/ui/LICENSE_Kenney_UI-Pack_CC0.md` | 九宫格面板 / 按钮切片；`tile_panel.png`、`tile_button_hover.png` 的中心被填成白色（原图中空），CC0 允许修改 |
| [Fusion Pixel Font](https://github.com/TakWolf/fusion-pixel-font) 12px | TakWolf | **SIL OFL 1.1** | ✅ | `assets/ui/font.ttf`，许可原文 `assets/ui/LICENSE_FusionPixel_OFL.txt` | 中文像素字体，覆盖 19214/20992 个 CJK 汉字；整套 UI 的兜底字 |
| Aa 字库「Aa暗夜深渊」 | Aa 字库 | **商用需授权**（个人学习 / 非商业可用） | ❌ | `assets/ui_font/` | 现在实际使用的界面字体；不可再分发，故被 `.gitignore` 排除 |
| [Sprout Lands UI Pack](https://cupnooble.itch.io/sprout-lands-ui-pack) | Cup Nooble | 免费但**限非商业、禁再分发** | ❌ | `assets/ui_sprout/`，许可原文 `assets/ui_sprout/LICENSE_SproutLands.txt` | 没有它时自动回退到上面的 Kenney 皮肤 |

## 四、音效

| 素材 | 作者 | 许可 | 分发 | 位置 / 来源 | 说明 |
|---|---|---|---|---|---|
| [Interface Sounds](https://kenney.nl/assets/interface-sounds) / [Sci-fi Sounds](https://kenney.nl/assets/sci-fi-sounds) / [RPG Audio](https://kenney.nl/assets/rpg-audio) | Kenney | **CC0 1.0** | ✅ | `assets/sfx/`，许可原文 `assets/sfx/LICENSE_Kenney_CC0.md` | `click_*`、`toggle_*`、`tick_*`、`open_*`、`close_*`、`laserSmall_000..004`、`metalLatch`、`metalClick` |
| 枪声 | 本项目作者（Python 合成） | MIT | ✅ | `assets/sfx/gunshot_000.wav` ~ `gunshot_004.wav` | 不是采样，是算出来的：噪声 + 包络 + 带通，见 README §1.19 |

## 五、剧情与图标

| 素材 | 作者 | 许可 | 分发 | 位置 | 说明 |
|---|---|---|---|---|---|
| 剧情文本（开场 / 设定） | 本项目作者 | MIT | ✅ | `story/` | 角色名来自 Blue Archive，属同人创作 |
| 项目图标 `icon.png` | **待确认** | 待确认 | ✅ | `icon.png` | 若不是原创请替换为自有图标 |

## 怎么改

1. 加一套素材 → 在 `scripts/credits.gd` 的 `ENTRIES` 里加一条（`path` 写目录即可覆盖其下全部文件）。
2. 同步这张表与 `THIRD_PARTY.md`（前者面向「谁做了什么」，后者面向「许可合规」）。
3. 跑 `--script res://scripts/_verify_credits.gd`：漏登记、缺许可原文、把私有素材漏进仓库，都会红。
