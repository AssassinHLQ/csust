# 第三方组件、素材来源与许可记录

完整逐项清单见 [CREDITS.md](CREDITS.md)，游戏内由 `scripts/credits.gd` 提供。每条记录作者、来源平台、资源位置与已有许可；本页说明来源核对方式与保留的许可原文。更新日期：2026-11-14。

## 优先致谢

1. **Kenney — Kenney.nl**：Pixel Adventure UI、Interface Sounds、Sci-fi Sounds、RPG Audio，CC0 1.0。原文分别保留在 `assets/ui/LICENSE_Kenney_UI-Pack_CC0.md`、`assets/sfx/LICENSE_Kenney_CC0.md`。
2. **Cup Nooble — itch.io**：Sprout Lands UI Pack，原包条款限非商业项目，并限制素材再分发与转售。来源：<https://cupnooble.itch.io/sprout-lands-ui-pack>；原文 `assets/ui_sprout/LICENSE_SproutLands.txt`。

## 代码、插件与算法

| 组件 | 作者与平台 | 来源与许可记录 |
|---|---|---|
| 本项目自有代码、场景与文档 | AssassinHLQ；本地创作 / GitHub | MIT，见根目录 `LICENSE`；第三方素材另按原始条款 |
| Godot Engine | Godot Engine contributors；Godot 官网 / GitHub | MIT；本工程使用支持 C# / .NET 的 Godot Mono 发行版，工程主要代码为 GDScript；这里的 Mono 与 JetBrains Mono 字体不同 |
| GDGS | ReconWorldLab、4321ba、beiller（William / Bill）、sodih3iw（Wu Xinyue）；AssassinHLQ（本项目分支）；GitHub | 四位上游提交者加一位本项目分支作者分别列出，原 MIT 许可在 `addons/gdgs/LICENSE`。上游：<https://github.com/ReconWorldLab/godot-gaussian-splatting>；本项目分支：<https://github.com/AssassinHLQ/godot-gaussian-splatting> |
| 高斯渲染 / 排序算法参考 | 2Retr0；GitHub | GDGS 上游 README 的 Acknowledgements 指向 <https://github.com/2Retr0/GodotGaussianSplatting>。校园 GGS 移植另参考 GodotGSplat，原始 MIT 许可保留在 `addons/ggs_campus/NOTICE.md` |
| 碰撞体素化与网格算法参考 | PlayCanvas Ltd. / PlayCanvas 团队；GitHub | <https://github.com/playcanvas/splat-transform>；GDGS 上游记录为其 GDScript 移植；保留上游 MIT 及代码署名 |
| Blue Archive 界面规格参考 | ywhdzrb；GitHub | <https://github.com/ywhdzrb/BlueArchiveUI>，来源说明保留于 `scripts/ui_skin.gd`；不把界面参考项目的许可扩展到角色与原作美术 |
| 坦克动荡小游戏 | AssassinHLQ；原作恢复自百度网盘，内部素材授权参考用户同名 GitHub 项目 | 用户先前制作的独立小游戏，恢复后接入本作；自有代码原工程附 CC0 1.0，原文保留在 `assets/tank_turmoil/LICENSE`。内部第三方素材分别适用原许可。用户同名仓库的准确链接待补，当前公开列表未找到 |
| 坦克小游戏算法参考 | JustDoIt0910 / Zhao Ran；GitHub | <https://github.com/JustDoIt0910/TankTrouble>；保留 Copyright (c) 2023 Zhao Ran 与完整 MIT 原文：`assets/tank_turmoil/THIRD_PARTY_NOTICES.txt`。该作者是算法参考作者，不是整个小游戏的作者 |

GDGS 的人数按实际角色核对：2026-11-14 上游 contributors API 为四位，本项目分支为 AssassinHLQ。算法上游作者另列，不混作该仓库的直接提交者。核对接口见 `CREDITS.md`。

## 参考软件与社区资料致谢

| 参考项目 | 作者 / 贡献者 | 平台与来源 | 用途 |
|---|---|---|---|
| 同花顺等交易软件 | 同花顺产品、设计与开发团队 | 同花顺交易软件 / 官网，<https://www.10jqka.com.cn/> | 行情、K 线、涨跌表达及界面交互参考 |
| 币安等交易软件 | Binance（币安）产品、设计与开发团队 | Binance 交易软件 / 官网，<https://www.binance.com/> | 交易界面、行情与交互表达参考 |
| Linux | Linus Torvalds 与 Linux 内核及开源社区贡献者 | kernel.org / Linux 开源社区，<https://www.kernel.org/> | 系统、终端文化与技术资料参考 |
| Arch Linux | Arch Linux 开发团队与社区贡献者 | Arch Linux 官网 / 开源社区，<https://archlinux.org/> | 发行版、终端、仿官网与社区文化参考 |
| ArchWiki | ArchWiki 条目作者、编辑者与维护社区 | ArchWiki / Arch Linux，<https://wiki.archlinux.org/> | 安装、配置、系统与软件使用资料 |
| 蔚蓝档案 Wiki | 蔚蓝档案 Wiki 社区维护者与条目贡献者 | 蔚蓝档案 Wiki 社区资料站；现有源码资料链接 <https://bluearchive.wiki/wiki/Cost> | 游戏角色、技能与机制资料参考；具体中文站点未注明，不推断每个数值都已由 Wiki 查证 |

以上是参考与社区贡献致谢；产品名称、标识及原站内容保留相应权利与条款，不表示本项目获得其合作、授权或背书。

## 模型、扫描与图像

| 素材 | 作者与平台 | 记录 |
|---|---|---|
| 老师模型 | 张伟事务所；模之屋 | 当前模型按用户确认署名；保留在本地的旧版 sensei 包另署食小派蒙辣 |
| 七个 Boss，包括霸王龙优香与飞猪优香 | 一个睿智；模之屋 | 霸王龙、飞猪、倭瓜、霍德、佩洛洛斯拉、比纳、哥利亚统一登记；原作角色权利仍属于相应版权方 |
| 游戏开发部部室 | 起航扬帆了；模之屋 | 更正旧记录中的 Sketchfab；导入、围合与碰撞处理不改变源模型署名 |
| 商店 Shop | Nikitos & 3130 / vrcityphoto；Sketchfab | CC BY 4.0；作者、模型链接与缩放 / 材质 / 烘焙改动保留在完整清单 |
| Falcon 9 火箭 | Forest Katsch / ForestKatsch；Sketchfab | CC BY-NC 4.0；保留作者、来源及模型处理说明 |
| DDR4 内存条 | suuugar_mommy；Sketchfab | CC BY-NC 4.0；原 GLB 元数据有来源与许可记录 |
| 天空盒 | 原作者未查明；爱给网整理 | 用户确认下载整理平台为爱给网。旧记录中 AllSky Free / Richard Whitelock 与当前文件缺少对应证据，作为待核实线索保留，不再据此将整包标为 MIT。原作者未查明，侵权必删。程序生成的 `sky_doom.jpg` 另署本项目作者 |
| 电竞房、硬件与保留的处理中间模型 | 原作者未查明；爱给网整理；本项目处理与导入 | 原始作者与具体资源页未找到；原作者未查明，侵权必删。完整清单逐目录登记 RTX 5090、CPU、显示器、机箱、970 EVO 与电竞房等 |
| 蒙德里安建筑 | AssassinHLQ；DeepSeek Harness（使用 1017） | 用户确认系自行使用该工具制作；保留“1017”原始标识，不推测模型全名 |
| Arisu、同伴与芹香模型 | NEXON Games / Yostar；模型整理 lihaohong6 / Peterli；GitHub（BlueArchiveModels） | 模型包来源 <https://github.com/lihaohong6/BlueArchiveModels>；整理与解包不改变原作版权。校园扫描不是 Blue Archive 角色素材 |
| 校园 / 画室609 扫描及派生碰撞 | 用户提供；知天下 AI；碰撞工具参考 GitHub 项目 | 具体数据的原始权利与工具代码的 MIT 许可分别记录，不混为同一许可 |
| 当前开场 PNG | AssassinHLQ（本作截图）；本地提供 | `_arisu_captures/_shots` 下当前 5 张 PNG 已纳入导出。截图内的模型、美术等第三方素材保留各自署名与权利；历史 PV 图片另列 |

“侵权必删”是使用者指定的联系与移除说明，不代替原始作者，也不作为授权证明。

## 字体

| 文件 | 作者与来源平台 | 已核实信息 |
|---|---|---|
| `assets/ui/font.ttf` 及招牌子集 | TakWolf；GitHub | Fusion Pixel Font，<https://github.com/TakWolf/fusion-pixel-font>；SIL OFL 1.1，原文 `assets/ui/LICENSE_FusionPixel_OFL.txt` |
| `assets/ui/mono.ttf` | The JetBrains Mono Project Authors；设计 Philipp Nurullin、Konstantin Bulenkov；JetBrains 官网 / GitHub | JetBrains Mono 等宽字体；内嵌元数据与 `assets/ui/LICENSE_JetBrainsMono_OFL.txt` 均确认 SIL OFL 1.1；<https://github.com/JetBrains/JetBrainsMono> |
| `assets/ui_sprout/font.ttf` | Cup Nooble；itch.io | 内嵌家族名 pixelFont-7-8x14-sproutLands、设计者 Cup Nooble；随 Sprout Lands UI Pack，按原包条款记录，不标为 OFL；主要用于数字与拉丁字形 |
| `assets/ui_font/Aa暗夜深渊.ttf` | Aa / 翰美互通（厦门）科技有限公司；字体管家内嵌官网，实际下载站待查 | TTF name 表标 ©2020 HanMeiHutong (XiaMen) Technology Co.Ltd.、设计者 Aa、`http://www.zitiguanjia.com`，字体家族名为“Aa暗夜深渊 (非商业使用)”。当前缺原始下载页面与完整发行条款，不从官网地址推断实际下载渠道 |

## 视频、语音与音乐

- 绿幕视频逐位标作者与 **哔哩哔哩**：香草BA、忧郁的优_、沉迷爱丽丝（阿洛娜）；瞿黧、星冻qwq、优香体重100kg（普拉娜）。具体保留的视频名与链接见 `CREDITS.md`；未找到的具体链接明确待补。
- 配音：**SLNeil — 哔哩哔哩**，<https://space.bilibili.com/523537077>。按使用者确认，音色模型均来自 SLNeil，语音由 **GPT-SoVITS** 合成，覆盖终端、商店、凯伊与开场剧情。项目台词、音色模型、合成工具与原作角色声音分别记录；工具来源为 GitHub 的 `RVC-Boss/GPT-SoVITS`。
- 商店 Tem Shop：**Toby Fox / Materia Collective**，按使用者要求省略来源平台。
- 蔚蓝档案音乐合集收集整理：**雷月夜 — 哔哩哔哩（UID 76847448）**，<https://space.bilibili.com/76847448>。用户补充此音乐整理来源，账号昵称已于 2026-11-14 通过哔哩哔哩账号接口核对；具体合集视频链接待补。整理者与作曲者、录音权利人分别署名。
- 其他音乐按具体曲目列入完整清单，包括 Constant Moderato、Pixel Time、Colorful Mess、Lemonade Diary、Daily Routine 247、Midsummer Cat、Encroached Sky；本地合集来源记录为哔哩哔哩，具体作曲署名仍待补。`doom_theme.ogg` 实际为 Encroached Sky，不能按文件名署成 DOOM 音乐。

## 版本管理与导出

`.gitignore` 管理 Git 跟踪，`export_presets.cfg` 管理游戏导出；两者分开。本次署名更新不添加素材导出排除，不把未入 Git 的本地素材说成磁盘缺失，也不由“已归位”推断已取得额外授权。未知作者、失落链接与许可待核项保留在清单，已有第三方许可原文不删除、不改写权利人。

## 免责声明

本项目仅供学习交流，无意分发。第三方名称、商标、角色、模型、图像、音乐及语音等权利归原作者或相应权利人所有。署名、致谢及本声明不替代原始授权，也不变更既有开源许可。如有侵权或署名遗漏，请联系项目作者核实、补正或删除。
