# 素材署名与致谢

本清单与 `scripts/credits.gd` 同步，游戏内入口：Esc → 设置 → 致谢与素材署名。更新日期：2026-11-14。

致谢顺序按使用者要求：**第一位 Kenney，第二位 Cup Nooble**。每条列出作者与平台；Toby Fox 按使用者要求省略平台。

作者、下载整理平台与工具作者分别记录。未查明的作者或原始页面保持待查，不将下载站当作原作者。Git 忽略状态仅指源码版本管理，不决定游戏打包是否包含素材，也不代表授权结论。当前开场的 PNG 已纳入导出。

本项目自有代码使用 MIT（见 `LICENSE`）；坦克小游戏原工程自有代码附 CC0；第三方美术、模型、声音、字体与音乐分别适用其原始条款。

## 特别致谢

| 素材 / 位置 | 作者 | 平台 | 来源 | 许可与原文 | 备注 |
|---|---|---|---|---|---|
| UI Pack: Pixel Adventure 2.0（九宫格面板 / 按钮切片）<br>`assets/ui` | Kenney | Kenney.nl | https://kenney.nl/assets/ui-pack-pixel-adventure | CC0 1.0（公有领域，可商用、无需署名）；原文 `assets/ui/LICENSE_Kenney_UI-Pack_CC0.md` | 优先致谢第一位。提供像素界面素材；面板中心填白等适配由本项目完成。 |
| Sprout Lands UI Pack（设置界面皮肤）<br>`assets/ui_sprout` | Cup Nooble | itch.io | https://cupnooble.itch.io/sprout-lands-ui-pack | 免费但限非商业，禁止再分发或转售（即使修改过）；原文 `assets/ui_sprout/LICENSE_SproutLands.txt` | 优先致谢第二位。作者 Cup Nooble，Sprout Lands UI Pack；原始条款保留在 LICENSE_SproutLands.txt。 |

特别致谢 **知天下 AI 团队／知天下 AI**，提供校园与画室609扫描、高斯泼溅生成支持（`splatdata`）。具体官网与团队成员署名待补，源数据许可仍按已有记录保留。Kenney 第一、Cup Nooble 第二的顺序保持不变。

## 代码与插件

独立致谢 **splat-transform**：作者 **PlayCanvas Ltd. / PlayCanvas 团队**，平台 **GitHub**，来源 https://github.com/playcanvas/splat-transform，MIT。项目接入记录位于 `scripts/_import_splattransform_collision.gd`；GDGS 的算法移植另列。

| 素材 / 位置 | 作者 | 平台 | 来源 | 许可与原文 | 备注 |
|---|---|---|---|---|---|
| 校园 GGS 泼溅光栅器（Godot 4.7 移植版）<br>`addons/ggs_campus` | 2Retr0（GodotGSplat 原作者）；本项目移植到 4.7，并加了校园专用 bin 加载与全屏合成 | GitHub | https://github.com/2Retr0/GodotGSplat | MIT（可分发、可商用）；许可原文见 addons/ggs_campus/NOTICE.md；原文 `addons/ggs_campus/NOTICE.md` | 6.14M 高斯校园 72–83 fps、约 5 GB 显存；不走 Compositor，用全屏 quad 画在场景背后 |
| 全部 GDScript 代码、场景与着色器<br>`scripts` | 本项目作者 | 本项目（本地制作） | 本地来源，尚无外部链接 | MIT；原文 `LICENSE` | 含 scripts/、scenes/、addons 之外的着色器与 project.godot |
| GDGS 高斯泼溅渲染插件 3.3.0<br>`addons/gdgs` | ReconWorldLab、4321ba、beiller（William / Bill）、sodih3iw（Wu Xinyue）；AssassinHLQ（本项目分支） | GitHub | https://github.com/ReconWorldLab/godot-gaussian-splatting | MIT；原文 `addons/gdgs/LICENSE` | 五位按角色列出：上游仓库四位提交者 ReconWorldLab / 4321ba / beiller / sodih3iw，本项目分支开发 AssassinHLQ。核对日期 2026-11-14；上游 MIT 原文保留。算法上游 2Retr0 与 PlayCanvas 另列，不将其误写为该仓库直接提交者。 |
| GDGS 高斯渲染与排序算法参考<br>`addons/gdgs/runtime/render` | 2Retr0（上游实现）；GDGS 开发者（移植） | GitHub | https://github.com/2Retr0/GodotGaussianSplatting；https://github.com/ReconWorldLab/godot-gaussian-splatting | MIT；各源码文件的原始署名保留 | 按 GDGS 上游 README Acknowledgements 记录算法与着色器来源。 |
| GDGS 碰撞管线 / splat-transform 算法参考<br>`addons/gdgs/collision` | PlayCanvas Ltd. / PlayCanvas 团队；GDGS 开发者（GDScript 移植） | GitHub | https://github.com/playcanvas/splat-transform；https://github.com/ReconWorldLab/godot-gaussian-splatting | MIT；上游原始许可与代码署名保留 | 包含体素化、封闭与网格生成算法参考；算法署名与本项目生成的碰撞数据来源分别记录。 |
| Blue Archive UI 布局与配色参考<br>`scripts/ui_skin.gd` | ywhdzrb（BlueArchiveUI） | GitHub | https://github.com/ywhdzrb/BlueArchiveUI | 按原项目 MIT 许可保留来源；本项目代码见 LICENSE | 来源记录见 ui_skin.gd 的代码注释；参考界面规格，不表示第三方角色、美术一并适用 MIT。 |
| 坦克动荡小游戏与内置素材<br>`assets/tank_turmoil` | AssassinHLQ（小游戏作者）；内部第三方素材作者见原项目记录 | 本项目原作；百度网盘（旧工程恢复）；GitHub（同名项目及内部素材授权参考） | 本地恢复工程 D:/BaiduNetdiskDownload/tank-turmoil；用户的同名 GitHub 仓库（准确链接待补，当前公开仓库列表未找到） | 原工程自有代码附 CC0 1.0；内部素材各自适用原作者授权，不能将整包素材视为 CC0；原文 `assets/tank_turmoil/LICENSE` | 用户之前制作的小游戏，原本地工程删除后从百度网盘恢复，再接入本作。内部素材对应授权按用户同名 GitHub 项目记录，尚未逐项复核。算法参考另外署名，不能将整个小游戏归为算法参考作者制作。 |
| 坦克动荡算法参考<br>`scripts/tank_turmoil` | JustDoIt0910 / Zhao Ran（TankTrouble）；AssassinHLQ（小游戏实现与接入） | GitHub | https://github.com/JustDoIt0910/TankTrouble | MIT（算法参考项目）；原工程 CC0 及内部素材许可分别记录；原文 `assets/tank_turmoil/THIRD_PARTY_NOTICES.txt` | 保留 Copyright (c) 2023 Zhao Ran 及完整 MIT 许可原文。 |

## 角色与 Boss 模型

| 素材 / 位置 | 作者 | 平台 | 来源 | 许可与原文 | 备注 |
|---|---|---|---|---|---|
| RTX 5090 显卡模型（最后平台房顶那件资产）<br>`models/rtx5090` | 原作者未查明；爱给网整理；AssassinHLQ（导入与处理） | 爱给网（下载整理平台）；本地处理 | https://www.aigei.com/（用户本地下载的 RTX5090.obj，4.5 MB / 29,480 面） | 原始模型许可待核实；处理与署名不代表已取得再分发授权 | 原作者未查明，侵权必删。模型减面、材质与导入适配由本项目完成。 |
| AMD Ryzen 9 9950X3D 处理器模型（609 屋顶的 149 颗，Rhino 源）<br>`models/cpu_9950x3d` | 原作者未查明；爱给网整理；AssassinHLQ（导入与处理） | 爱给网（下载整理平台）；本地处理 | 用户提供的爱给网（aigei.com）`AMD Ryzen9 9950 X3D.SLDPRT`（SolidWorks，Godot/Blender 读不了，仅作外观参考）+ 同包 P1.PNG | 原始模型许可待核实；处理与署名不代表已取得再分发授权 | 原作者未查明，侵权必删。模型减面、材质与导入适配由本项目完成。 |
| 游戏开发部部室（商店东侧新地块）<br>`models/gamedev_room` | 起航扬帆了（模型）；AssassinHLQ（围合与导入处理） | 模之屋 | 模之屋创作者「起航扬帆了」；用户下载包《游戏开发部部室_by_起航扬帆了_ebd4291471b4ef51514e232113d2c349》 | 原模型授权资料未留存，许可待核实 | 作者与平台由用户确认；旧版误写 Sketchfab，现更正。围合、去重、材质处理与 Godot 导入由本项目完成。 |
| 游戏开发部部室碰撞网格<br>`assets/collision` | 起航扬帆了（源模型）；AssassinHLQ（碰撞处理） | 模之屋；本地处理 | 由 models/gamedev_room 的 GLB 烘焙，脚本 scripts/_bake_gamedev_trimesh.gd | 源模型许可待核实；碰撞为其派生数据 | 由 models/gamedev_room 烘焙，原模型作者与来源平台一并保留。 |
| 普拉娜（电脑里第二个虚拟助手，终端敲 `plana` 出现）<br>`assets/plana_frames` | 哔哩哔哩 UP 瞿黧（《依旧送送送，普拉娜绿幕素材，想用的可以自己拿》，BV1jsN26uEF3）；角色版权属于 NEXON Games / Yostar（Blue Archive） | 哔哩哔哩 | 用户本地的 `依旧送送送，普拉娜绿幕素材，想用的可以自己拿_视频.mp4`（1080×1180 / 30 fps / 29.53 s，绿幕底色 #46E200） | 视频二创素材；具体授权以原作者说明为准，现有记录未附完整许可 | 原视频经抠像转换为 PNG 帧序列；原作角色版权属于 NEXON Games / Yostar。 |
| 阿洛娜（终端右半屏那个虚拟助手，敲 `arona` 出现）— 绿幕帧序列<br>`assets/arona_frames` | 哔哩哔哩 UP 香草BA（空间 space.bilibili.com/3546885205789214，原画面水印「浅羽香草 bilibili」）；角色版权属于 NEXON Games / Yostar（Blue Archive） | 哔哩哔哩 | 用户 2026-11-12 下载的绿幕视频（bilibili 空间 3546885205789214，源 1080×1848）；ffmpeg 先按比例裁掉顶部 4.87% 的水印带、把右上角刷成纯绿让 chromakey 一起抠掉，再 chromakey=0x2EDC01 + despill | 视频二创素材；具体授权以原作者说明为准，现有记录未附完整许可 | 原视频经抠像转换为 PNG 帧序列；原作角色版权属于 NEXON Games / Yostar。 |
| 阿洛娜 / 普拉娜 的中文配音（电脑右半屏的台词）<br>`assets/companion_voice` | SLNeil（音色模型）；AssassinHLQ（台词与 GPT-SoVITS 合成）；NEXON Games / Yostar（原作角色） | 哔哩哔哩（SLNeil）；GitHub（GPT-SoVITS） | https://space.bilibili.com/523537077；GPT-SoVITS：https://github.com/RVC-Boss/GPT-SoVITS | 音色模型与角色声音按其原始条款；未核实额外再分发许可 | 用户确认：语音用 GPT-SoVITS 合成，音色模型均来自 SLNeil。保留角色、模型作者与合成工具三者的区别。 |
| 阿洛娜 第 2 版素材（木偶半身，《阿罗娜木偶》）<br>`assets/arona_frames_b` | 哔哩哔哩 UP 忧郁的优_（《阿罗娜木偶，可直接用，也可艾特》）；角色版权属于 NEXON Games / Yostar（Blue Archive） | 哔哩哔哩 | 用户 2026-11-13 下载的 `阿罗娜木偶，可直接用，也可艾特_视频.mp4`（1290×1078 / 30 fps / 15.0 s，绿幕底色 #05D504） | 视频二创素材；具体授权以原作者说明为准，现有记录未附完整许可 | 原视频经抠像转换为 PNG 帧序列；原作角色版权属于 NEXON Games / Yostar。 |
| 普拉娜 第 2 版素材（近景头肩，《普拉娜自己取》）<br>`assets/plana_frames_b` | 哔哩哔哩 UP 星冻qwq（《普拉娜自己取》）；角色版权属于 NEXON Games / Yostar（Blue Archive） | 哔哩哔哩 | 用户 2026-11-13 下载的 `普拉娜自己取_视频.mp4`（1280×720 / 30 fps / 20.0 s，绿幕底色 #00DC22） | 视频二创素材；具体授权以原作者说明为准，现有记录未附完整许可 | 原视频经抠像转换为 PNG 帧序列；原作角色版权属于 NEXON Games / Yostar。 |
| 阿洛娜 3D 模型（已停用，改用上面的绿幕帧序列）<br>`models/arona` | 原作者未查明；爱给网整理；AssassinHLQ（导入与处理） | 爱给网（下载整理平台）；本地处理 | 用户本地下载的 `[BlueArchive] - Arona.blend`（1.3 MB，205 骨骼绑定）+ 6 张贴图（Body / Eye / Eyebrow / Face / Hair / Halo） | 原始模型许可待核实；处理与署名不代表已取得再分发授权 | 原作者未查明，侵权必删。阿洛娜 3D 模型已停用，保留在本地。 |
| 壁挂 8×5090 机箱外壳（游戏开发部活动室）<br>`models/pc_case` | 原作者未查明；爱给网整理；AssassinHLQ（导入与处理） | 爱给网（下载整理平台）；本地处理 | 用户 2026-11-02 下载的 `游戏电脑机箱主机，白色 i7 RTX3090 内存条风扇散热_爱给网_aigei_com.zip` 中的 `CUSTOM GAMING PC.blend`（94 MB / 1,035,668 面） | 原始模型许可待核实；处理与署名不代表已取得再分发授权 | 原作者未查明，侵权必删。模型减面、材质与导入适配由本项目完成。 |
| RTX 5090 低模副本（壁挂机箱里的 8 张）<br>`models/rtx5090_card` | 原作者未查明；爱给网整理；AssassinHLQ（导入与处理） | 爱给网（下载整理平台）；本地处理 | 用户 2026-10-20 下载的 `models/rtx5090/RTX5090simplified.obj`（945 KB，同目录高模不入库） | 原始模型许可待核实；处理与署名不代表已取得再分发授权 | 原作者未查明，侵权必删。模型减面、材质与导入适配由本项目完成。 |
| AM261_029 超宽显示器（壁挂机箱旁）<br>`models/monitor` | 原作者未查明；爱给网整理；AssassinHLQ（导入与处理） | 爱给网（下载整理平台）；本地处理 | 用户 2026-11-03 下载的 `29 显示器 屏幕_爱给网_aigei_com/AM261_029.fbx`（30,077 面，含第三方屏摄图） | 原始模型许可待核实；处理与署名不代表已取得再分发授权 | 原作者未查明，侵权必删。模型减面、材质与导入适配由本项目完成。 |
| BANK 招牌（最后平台小屋屋顶）<br>`models/bank` | 使用者自制（Rhino 导出 OBJ） | 本项目（本地制作） | 用户 2026-10-20 提供的桌面文件 BANK.obj | 归使用者所有，可随仓库分发 | 1765 面；文件自带一圈 `Default` 包围盒，`bank_sign.gd` 按材质名剔掉；原 `mtllib` 没给出来，仓库补了一份最小 `BANK.mtl` |
| DDR4 内存条（跑酷第 9~10 段「内存条市场」，121 根）<br>`models/ram` | suuugar_mommy（Sketchfab） | Sketchfab | https://sketchfab.com/3d-models/random-access-memory-ram-ddr4-6f37195ac2b84b21a901471485351b37 | **CC BY-NC 4.0** —— 必须署名、**不可商用**；GLB 的 `asset.extras` 自带这条声明，用 `tools/glb_meta.py` 可复核 | ⚠️ NC 条款：要放进商业版本，这个文件必须换成程序化盒子模型。2026-11-03 补登记 —— 之前只在 README §1.16.4 提过，`credits.gd` / `CREDITS.md` 里一直没有，而 `models` 那条整体条目（讲的是 Arisu）把 `models/ram` 前缀盖住了，自检没报 |
| SpaceX Falcon 9（跑酷去程 / 回程的载具，两枚）<br>`models/rocket_falcon9` | Forest Katsch（Sketchfab，`ForestKatsch`） | Sketchfab | https://sketchfab.com/3d-models/spacex-falcon-9-block-45-12285ccc02de4d5c91b00632f0722c92 | CC BY-NC 4.0（署名、非商业、注明改动） | ⚠️ 带 **NC（非商用）** 条款：一旦要商业发布，这套必须换掉或取得另行授权。下载当时的许可凭证存工作区 `_模型授权存档/12285ccc02de4d5c91b00632f0722c92_授权凭证.txt`（不在仓库内 —— 和 DDR4 内存条同口径，`license_file` 留空）。下载包只有 `source/f9-block-5.blend`（8.7 MB）+ 11 张 PNG，没有 glTF；本工程的 GLB 由 `_tools/_blender_export_f9_v4.py` 转出：剔掉 47 个特效占位（火焰/排气/体积）、把作者的自定义节点组材质**重建为标准 Principled BSDF**（glTF 导出器只认这个，否则贴图全丢）、贴图 4096 降到 1024（12.4 MB → 0.86 MB，显存约 1.3 GB → 36 MB）、缩放到真实 70 m 高、原点挪到箭体底面中心。最终 116,575 面 / 3 材质 / 4.81 MB。**改动已按 CC BY 4.0 惯例声明**（NC 条款同样要求标明改动）。缺文件时 `rocket_ride.gd` 用程序化占位火箭顶上。 |
| 柴关电脑城的新屋壳（Sketchfab「Shop」）<br>`models/shop_building` | Nikitos & 3130（Sketchfab，`vrcityphoto`） | Sketchfab | https://sketchfab.com/3d-models/42510bda855c4e60bf5cf7ecb9a2a57c | CC BY 4.0（署名、保留来源并注明改动） | 极简白色店铺：白墙 + 玻璃隔断 + 吊顶灯带 + 两组玻璃展柜。原生 6.357 × 2.884 × 5.201 m / 1,158 面 / **无贴图**（纯材质色）。按用户 2026-11-07 选的「长度对齐」缩放 2.0764 → 13.20 × 10.80 × 5.99 m，正面 z 对齐老壳的 shop_depth/2，多出来的进深往 −Z 长，所以柜台/芹香位置不用动。**只保留招牌**：原来的屋顶/三面墙/门柱/幕墙/货架全部不再程序化生成，换成本 GLB + 5 块不可见碰撞盒（后墙 / 东西墙 / 正面门洞左右两段）。GLB 原点离网格很远（中心 (212.2, −242.0, 1.1)），`shop.gd::_build_shell_from_glb()` 会现量包围盒再居中。烘焙进 `scenes/shop_baked.tscn` 时保持 instance 引用（`_bake_buildings.gd::_own()` 对 `scene_file_path` 非空的节点只设 owner、不下钻）。 |
| 蒙德里安大楼外壳（第二关）<br>`models/mondrian` | AssassinHLQ（本项目作者） | DeepSeek Harness（使用 1017 制作） | 用户确认：使用 DeepSeek Harness 的 1017 制作；原工程为蒙德里安建筑/mondrian_building.blend | 本项目原创（MIT）；原文 `LICENSE` | 保留用户给出的工具标识“1017”，不推断具体模型全名。模型导出、开门洞与场景适配由本项目完成。 |
| 比纳（第六位 Boss，备用）FBX + 贴图<br>`models/boss_binah` | 一个睿智（模型二创）；NEXON Games / Yostar（原作角色） | 模之屋 | 比纳_by_一个睿智.zip | 专有版权（派生自 Blue Archive，玩家二创） | Binah_Original.fbx，44 骨、无动画；3 个材质（本体/环、武器面、光环）；*_Mask.png 是作者渲染遮罩，游戏里不绑 |
| 哥利亚（第七位 Boss，备用）FBX + 贴图<br>`models/boss_goliath` | 一个睿智（模型二创）；NEXON Games / Yostar（原作角色） | 模之屋 | 哥利亚_by_一个睿智.zip | 专有版权（派生自 Blue Archive，玩家二创） | Goliath_Decagram_Vulcan.fbx，34 骨、单网格单材质；*_Mask.png 同上 |
| 霍德（第四位 Boss）FBX + 贴图<br>`models/boss_hod` | 一个睿智（模型二创）；NEXON Games / Yostar（原作角色） | 模之屋 | 霍德_by_一个睿智.zip | 专有版权（派生自 Blue Archive，玩家二创） | HOD_Original.fbx，164 骨、无动画；3 个材质，2 张 *_Mask.png 是原作者渲染用的遮罩，游戏里不绑 |
| 佩洛洛斯拉（第五位 Boss）FBX + 贴图<br>`models/boss_perorozilla` | 一个睿智（模型二创）；NEXON Games / Yostar（原作角色） | 模之屋 | 佩洛洛斯拉_by_一个睿智.zip | 专有版权（派生自 Blue Archive，玩家二创） | Perorozilla_Original.fbx，47 骨、无动画；6 网格共用 1 个材质；5 张表情变体只留一张（见 peroro_boss.gd） |
| 倭瓜优香（第三位 Boss）OBJ + 贴图<br>`models/boss_squash` | 一个睿智（模型二创）；NEXON Games / Yostar（原作角色） | 模之屋 | 倭瓜优香压缩文件_by_一个睿智.zip | 专有版权（派生自 Blue Archive，玩家二创） | 倭瓜优香.obj，纯静态网格、无骨架；4 个材质 |
| 飞猪优香（第二位 Boss）FBX + 贴图<br>`models/boss_pig` | 一个睿智（模型二创）；NEXON Games / Yostar（原作角色） | 模之屋 | 飞猪优香 (2)_by_一个睿智.zip | 专有版权（派生自 Blue Archive，玩家二创） | 猪猪优香.fbx，纯静态网格；uv/ 里两张是**作者的成品渲染图**，挪到 ref/ 当贴图分配基准 |
| 霸王龙优香（第一位 Boss）FBX + 贴图<br>`models/boss` | 一个睿智（模型二创）；NEXON Games / Yostar（原作角色） | 模之屋 | 模之屋创作者「一个睿智」的霸王龙优香；作者由用户确认，与飞猪优香同一作者 | 专有版权（派生自 Blue Archive） | 优香霸王龙.fbx，73 骨、无动画；贴图要按材质名手工绑（见 boss.gd 的 TEXTURES） |
| 七名同伴模型（小雪 / 优香 / 诺亚 / 小桃 / 小绿 / 柚子 / 凯伊）<br>`models/companions` | NEXON Games / Yostar（原作）；lihaohong6 / Peterli（模型整理） | GitHub（BlueArchiveModels） | https://github.com/lihaohong6/BlueArchiveModels | 专有版权 | 官方素材解包（整理者 lihaohong6 / Peterli），均取初始形态；凯伊用 Kei_ext.glb（跑动前折已修） |
| 主角 Arisu 模型与贴图<br>`models` | NEXON Games / Yostar（原作）；lihaohong6 / Peterli（模型整理） | GitHub（BlueArchiveModels） | https://github.com/lihaohong6/BlueArchiveModels | 原作角色素材专有版权；模型整理不改变原作权利 | Arisu.glb / Arisu_ext.glb / Arisu*.png；校园扫描及碰撞不属于 Blue Archive，另列来源。 |
| 老师（sensei）NPC 模型与贴图<br>`models/npc` | 张伟事务所（当前老师模型）；食小派蒙辣（旧版备用模型） | 模之屋 | 用户确认当前老师模型作者为张伟事务所；旧版包 sensei_by_食小派蒙辣.zip 仍保留原署名 | 专有版权（派生自 Blue Archive，玩家二创） | 当前游戏使用的老师模型与旧包分别保留作者，避免以旧模型作者代替现用模型作者。 |
| 柴关电脑城店员「黑见芹香」（Serika，校服版）<br>`models/npc/serika` | NEXON Games / Yostar（原作）；lihaohong6 / Peterli（模型整理） | GitHub（BlueArchiveModels） | https://github.com/lihaohong6/BlueArchiveModels；Serika.glb | 专有版权（Blue Archive），仅本地学习用，不随仓库分发 | 93 骨 Bip001 骨架、40 条动画，待机播 Normal_Idle；包围盒 0.67×1.39×0.50 m、原点在脚上方 0.27 m，shop_clerk.gd 会自动抬到踩地。手骨 Bip001 L/R Hand 高 0.72 m，低于台面 0.88 m，藏在柜台后；头顶光环 Serika_Halo 走 HaloFix 抛光 |
| （已停用）天使24 店员「小空」（Sora）<br>`models/npc/sora` | 薛定谔的小问号 | 待查（仅保留本地模型包来源） | kong_by_薛定谔的小问号（小空1donzuo.blend，2023-12） | 专有版权（派生自 Blue Archive，玩家二创） | 2026-10-22 起不再上场：用户要求「小空出差」，且她的画风（338 骨 MMD 精细模型）与卡通大头小人的同伴不统一。文件仍留在 models/npc/sora/ 备用 |
| 校园 / 画室609 高斯泼溅数据（知天下 AI 生成）<br>`splatdata` | 知天下 AI 生成（由使用者提供） | 知天下 AI | 知天下 AI | 权利状态未核实 —— AI 生成，再分发权由使用者确认 | 使用者提供校园 / 画室609 扫描与高斯数据；具体数据的权利与上游模型版权分开记录。 |
| 校园扫描碰撞网格（保留的历史资产）<br>`models/school.collision.glb` | AssassinHLQ（碰撞生成）；知天下 AI（源扫描数据平台） | 知天下 AI；GitHub（碰撞工具参考） | 由使用者提供的校园扫描派生；工具来源见 GDGS / PlayCanvas splat-transform 条目 | 派生数据按源扫描的权利状态记录，未核实统一再分发许可 | 不将校园碰撞错误归入 NEXON 角色模型。 |
| 阿洛娜第 3 版绿幕帧序列<br>`assets/arona_frames_c` | 沉迷爱丽丝（视频作者）；NEXON Games / Yostar（原作角色） | 哔哩哔哩 | 哔哩哔哩 UP 沉迷爱丽丝《绿幕素材分享（阿洛娜木偶）》；来源记录见 scripts/arch_terminal.gd 的 COMPANIONS 注释 | 视频二创素材，完整授权资料未留存 | 转换为透明 PNG 帧序列供终端播放；原视频具体链接待补。 |
| 普拉娜第 3 版绿幕帧序列<br>`assets/plana_frames_c` | 优香体重100kg（视频作者）；NEXON Games / Yostar（原作角色） | 哔哩哔哩 | 哔哩哔哩 UP 优香体重100kg《普拉娜木偶绿幕素材》；来源记录见 scripts/arch_terminal.gd 的 COMPANIONS 注释 | 视频二创素材，完整授权资料未留存 | 转换为透明 PNG 帧序列供终端播放；原视频具体链接待补。 |
| 电竞房（现代网咖 / 电竞酒店套房）<br>`models/esports_room` | 原作者未查明；爱给网整理；AssassinHLQ（处理与导入） | 爱给网（下载整理平台） | 用户提供的爱给网模型包；https://www.aigei.com/；具体原始作者页未找到 | 授权资料未齐，许可待核实 | 原作者未查明，侵权必删。保留原模型的来源与权利；中间导出文件不是新的独立原创模型。 |
| 三星 970 EVO SSD 硬件模型<br>`models/ssd_970evo` | 原作者未查明；爱给网整理；AssassinHLQ（处理与导入） | 爱给网（下载整理平台） | 用户提供的爱给网模型包；https://www.aigei.com/；具体原始作者页未找到 | 授权资料未齐，许可待核实 | 原作者未查明，侵权必删。保留原模型的来源与权利；中间导出文件不是新的独立原创模型。 |
| 电竞酒店模型处理中间资产<br>`models/_wip_esports_hotel` | 原作者未查明；爱给网整理；AssassinHLQ（处理与导入） | 爱给网（下载整理平台） | 用户提供的爱给网模型包；https://www.aigei.com/；具体原始作者页未找到 | 授权资料未齐，许可待核实 | 原作者未查明，侵权必删。保留原模型的来源与权利；中间导出文件不是新的独立原创模型。 |
| 酒店模型处理中间资产<br>`models/_wip_hotel` | 原作者未查明；爱给网整理；AssassinHLQ（处理与导入） | 爱给网（下载整理平台） | 用户提供的爱给网模型包；https://www.aigei.com/；具体原始作者页未找到 | 授权资料未齐，许可待核实 | 原作者未查明，侵权必删。保留原模型的来源与权利；中间导出文件不是新的独立原创模型。 |
| 游戏开发部模型处理中间资产<br>`models/_wip_room` | 起航扬帆了（源模型）；AssassinHLQ（导入处理） | 模之屋；本地处理 | 由 models/gamedev_room 的部室模型生成 | 授权资料未齐，许可待核实 | 与原部室模型保留相同作者、平台和权利状态。 |

## 界面与字体

| 素材 / 位置 | 作者 | 平台 | 来源 | 许可与原文 | 备注 |
|---|---|---|---|---|---|
| 全景天空盒（10 张全收录）<br>`assets/sky` | 原作者未查明；爱给网整理 | 爱给网（下载整理平台） | 用户确认取得自爱给网 https://www.aigei.com/；具体资源页未留存 | 原始许可待核实 | 保留用户提供的下载来源。旧记录曾指向 AllSky Free / Richard Whitelock（https://github.com/rpgwhitelock/AllSkyFree_Godot），但尚无文件对应证据，不能据此认定当前整套天空盒为该作者或统一采用 MIT。原作者未查明，侵权必删。程序生成的末日天空另列。 |
| 空地地砖贴图 + 法线图<br>`assets/tex` | 本项目作者（程序生成） | 本项目（本地制作） | 本地来源，尚无外部链接 | MIT；原文 `LICENSE` | `tools/make_lot_paver.py` 生成，完全可平铺，不依赖外网素材 |
| 历史开场 PV 图片与超分版本（保留资产）<br>`assets/cg` | Blue Archive 游戏内画面（NEXON Games / Yostar）+ 使用者本地截图 | Blue Archive 游戏；本项目截图 | 使用者 2026-11-12 提供的 8 张截图（混有 Blue Archive 游戏内画面与本作截图），存于 assets/cg/pv/ | 专有：仅本地学习演示，不可再分发、不可商用 | 旧 PV 图片留存在 assets/cg/pv 与 pv_hd；当前开场改用 _arisu_captures/_shots 下的 PNG，另列。 |
| Fusion Pixel Font 12px（中文像素字体，整套 UI 的兜底字）<br>`assets/ui/font.ttf` | TakWolf | GitHub | https://github.com/TakWolf/fusion-pixel-font | SIL OFL 1.1（允许随软件分发）；原文 `assets/ui/LICENSE_FusionPixel_OFL.txt` | 覆盖 19214/20992 个 CJK 汉字；assets/ui_font/ 没放字时就用它 |
| 游戏开发部/服务器据点/机箱铭牌用的像素子集<br>`assets/ui/gamedev_sign_12px.ttf` | TakWolf（Fusion Pixel Font 子集） | GitHub | https://github.com/TakWolf/fusion-pixel-font | SIL OFL 1.1（允许随软件分发；仅保留招牌/铭牌用字与 notdef）；原文 `assets/ui/LICENSE_FusionPixel_OFL.txt` | 从 font.ttf 子集化（8 KB 级），含游戏开发部、楼梯、临时服务器据点、终点、8×5090x、按F开机、已在线、电竞房、凯伊、9995WX、DDR5 ECC 等；12 px 原生网格，导入关抗锯齿、关子像素定位、开 mipmap，Label3D 用 nearest 采样，招牌才是真·像素字 |
| Aa 字库「Aa暗夜深渊」（界面显示字体）<br>`assets/ui_font` | Aa 字库 / 翰美互通（厦门）科技有限公司 | 字体管家（字体内嵌官网）；实际下载站未查明 | 字体 name 表：设计者 Aa；版权 ©2020 HanMeiHutong (XiaMen) Technology Co.Ltd.；厂商/设计者网址 http://www.zitiguanjia.com | 字体内嵌名称标注“非商业使用”；具体发行与授权条款待原始页面核实 | 以上从当前 TTF 的版权、厂商与网址元数据核对；不能由内嵌官网反推用户实际下载页面。Mono 是另一个单独登记的等宽字体。 |
| 末日天空（程序生成）<br>`assets/sky/sky_doom.jpg` | AssassinHLQ（本项目作者） | 本项目（本地制作） | tools/gen_sky_doom.py | MIT；原文 `LICENSE` | 由本项目脚本生成，与爱给网整理的天空盒分开署名。 |
| 当前开场播放的 PNG 截图<br>`_arisu_captures/_shots` | AssassinHLQ（本作截图）；画面内素材作者分别见本清单 | 本项目（本地制作） | 用户指定的 _arisu_captures/_shots/*.png；scripts/title_intro.gd 按文件名读取 | 截图由使用者提供；画面内第三方素材保留各自权利 | 当前为 5 张 PNG。已取消导出排除，随游戏打包；Git 忽略截图产物与游戏导出包含图片是两件事。 |
| JetBrains Mono（终端等宽字体）<br>`assets/ui/mono.ttf` | The JetBrains Mono Project Authors；Philipp Nurullin、Konstantin Bulenkov（设计） | JetBrains 官网 / GitHub | https://github.com/JetBrains/JetBrainsMono；https://www.jetbrains.com/lp/mono/ | SIL OFL 1.1；原文 `assets/ui/LICENSE_JetBrainsMono_OFL.txt` | 字体文件名 mono.ttf，已从内嵌元数据确认。Mono 表示等宽，与支持 C# / .NET 的 Godot Mono 引擎版本不同。 |
| Sprout Lands 像素字体（pixelFont-7-8x14-sproutLands）<br>`assets/ui_sprout/font.ttf` | Cup Nooble | itch.io | https://cupnooble.itch.io/sprout-lands-ui-pack | 随 Sprout Lands UI Pack，按原包条款记录；不是 OFL 字体；原文 `assets/ui_sprout/LICENSE_SproutLands.txt` | TTF 内嵌设计者为 Cup Nooble。主要用于数字与拉丁字形，不提供中文字形；中文字体另列。 |

## 音效

结尾 PV：**Constant Moderato Piano Ver.（伊甸条约篇～第3章BGM）**，`assets/music/ending_theme.ogg`。作者与权利记录：**NEXON Games / Yostar（Blue Archive OST 权利记录；具体作曲与钢琴编曲署名待补）**。平台：**哔哩哔哩（音乐合集）**；收集整理：**雷月夜**（UID 76847448）。来源为用户指定的本地 Vol.1 P98 音频 MP4，完整转码约185.301秒，不裁剪、不循环。Blue Archive OST 专有版权；具体录音与作者条款适用。

| 素材 / 位置 | 作者 | 平台 | 来源 | 许可与原文 | 备注 |
|---|---|---|---|---|---|
| 商店配音（芹香 / 小桃 / 爱丽丝，GPT-SoVITS）<br>`story/voice/shop` | SLNeil（音色模型）；AssassinHLQ（台词与 GPT-SoVITS 合成）；NEXON Games / Yostar（原作角色） | 哔哩哔哩（SLNeil）；GitHub（GPT-SoVITS） | https://space.bilibili.com/523537077；GPT-SoVITS：https://github.com/RVC-Boss/GPT-SoVITS | 音色模型与角色声音按其原始条款；未核实额外再分发许可 | 用户确认：语音用 GPT-SoVITS 合成，音色模型均来自 SLNeil。保留角色、模型作者与合成工具三者的区别。 |
| 商店 BGM：UNDERTALE「Tem Shop」<br>`assets/music` | Toby Fox / Materia Collective | 依用户要求省略 | UNDERTALE | Toby Fox / Materia Collective 的原作音乐权利；未核实额外再分发许可 | 按用户要求，Toby Fox 保留作者名，不额外标注平台；本条只代表 Tem Shop，其余曲目逐项列出。 |
| 开场 PV 音乐：Blue Archive OST「Constant Moderato（PV1）」<br>`assets/music/pv_theme.mp3` | NEXON Games / Yostar（Blue Archive OST） | 哔哩哔哩（音乐合集） | B站「碧蓝档案OST🎵 音乐合集 Vol.1（320K）」P2；使用者 2026-11-12 指定；音乐合集收集整理：雷月夜（哔哩哔哩 UID 76847448），https://space.bilibili.com/76847448 | Blue Archive OST 专有版权；具体录音与作者条款适用 | 开场音乐为 Constant Moderato；PNG 图片换新不改变音乐作者。 音乐整理来源由用户补充；收集整理者与作曲者、原曲权利人分别署名，具体合集视频链接待补。 |
| 界面 / 武器 / 换弹音效（Interface Sounds、Sci-fi Sounds、RPG Audio）<br>`assets/sfx` | Kenney | Kenney.nl | https://kenney.nl/assets/interface-sounds | CC0 1.0（公有领域，可商用、无需署名）；原文 `assets/sfx/LICENSE_Kenney_CC0.md` | click_* / toggle_* / tick_* / open_* / close_*、laserSmall_000..004、metalLatch、metalClick |
| 枪声 gunshot_000..004（5 条）<br>`assets/sfx/gunshot_000.wav` | 本项目作者（Python 合成：噪声 + 包络 + 带通） | 本项目（本地制作） | 本地来源，尚无外部链接 | MIT；原文 `LICENSE` | 不是采样，是算出来的；替换 laserSmall_*.ogg 是为了听起来像枪（见 README §1.19）。2026-11-11 起 fire 改用爱丽丝原声（见下一条），这 5 条留在磁盘上做备份与 A/B 对比 |
| 爱丽丝轨道炮音效（开枪 / 换弹，裁自游戏内 SFX）<br>`assets/sfx/aris` | NEXON Games / Yostar（Blue Archive 游戏内 SFX）；裁剪：本项目作者（Python） | Blue Archive 游戏素材（本地提取） | 本地来源，尚无外部链接 | 专有版权 —— 仅本地学习 / 非商业演示，不得再分发、不得用于任何发布产物 | 由 _godot_editor_data/make_aris_sfx.py 从 SFX_Public_Aris / SFX_Aris_Hit / SFX_Common_RG_aris_Reload / SFX_Skill_Aris_Ex 裁出（前两条是连发枪声的候选，2026-11-11 用户听完 A/B 决定 fire 仍用合成枪声，故暂未接线）；逐条裁决见 assets/sfx/aris/README.md。音频本体被 .gitignore 排除，只留 *.wav.import |
| 凯伊 GPT-SoVITS 配音<br>`story/voice/kei` | SLNeil（音色模型）；AssassinHLQ（台词与 GPT-SoVITS 合成）；NEXON Games / Yostar（原作角色） | 哔哩哔哩（SLNeil）；GitHub（GPT-SoVITS） | https://space.bilibili.com/523537077；GPT-SoVITS：https://github.com/RVC-Boss/GPT-SoVITS | 音色模型与角色声音按其原始条款；未核实额外再分发许可 | 用户确认所有音色模型均来自 SLNeil。 |
| 开场及其他剧情语音（GPT-SoVITS）<br>`story/voice` | SLNeil（音色模型）；AssassinHLQ（台词与 GPT-SoVITS 合成）；NEXON Games / Yostar（原作角色） | 哔哩哔哩（SLNeil）；GitHub（GPT-SoVITS） | https://space.bilibili.com/523537077；GPT-SoVITS：https://github.com/RVC-Boss/GPT-SoVITS | 角色声音与音色模型的原始条款；不因剧情代码为 MIT 而改变 | 用户确认语音为 GPT-SoVITS 合成，音色模型均来源 SLNeil；商店与凯伊另列明细。 |
| Blue Archive OST「Pixel Time」<br>`assets/music/gamedev_theme.ogg` | NEXON Games / Yostar（Blue Archive OST 权利记录；具体作曲署名待补） | 哔哩哔哩（下载合集；原始发行属 Blue Archive） | 本地曲目与 scripts/music.gd 的映射；碧蓝档案 OST 音乐合集；音乐合集收集整理：雷月夜（哔哩哔哩 UID 76847448），https://space.bilibili.com/76847448 | 原作音乐专有版权；具体录音与作者条款适用 | 本项目只调整裁剪、循环与音量，不据此取得原曲版权。 音乐整理来源由用户补充；收集整理者与作曲者、原曲权利人分别署名，具体合集视频链接待补。 |
| Blue Archive OST「Colorful Mess」<br>`assets/music/esports_theme.ogg` | NEXON Games / Yostar（Blue Archive OST 权利记录；具体作曲署名待补） | 哔哩哔哩（下载合集；原始发行属 Blue Archive） | 本地曲目与 scripts/music.gd 的映射；碧蓝档案 OST 音乐合集；音乐合集收集整理：雷月夜（哔哩哔哩 UID 76847448），https://space.bilibili.com/76847448 | 原作音乐专有版权；具体录音与作者条款适用 | 本项目只调整裁剪、循环与音量，不据此取得原曲版权。 音乐整理来源由用户补充；收集整理者与作曲者、原曲权利人分别署名，具体合集视频链接待补。 |
| Blue Archive OST「Lemonade Diary」<br>`assets/music/art609_theme.ogg` | NEXON Games / Yostar（Blue Archive OST 权利记录；具体作曲署名待补） | 哔哩哔哩（下载合集；原始发行属 Blue Archive） | 本地曲目与 scripts/music.gd 的映射；碧蓝档案 OST 音乐合集；音乐合集收集整理：雷月夜（哔哩哔哩 UID 76847448），https://space.bilibili.com/76847448 | 原作音乐专有版权；具体录音与作者条款适用 | 本项目只调整裁剪、循环与音量，不据此取得原曲版权。 音乐整理来源由用户补充；收集整理者与作曲者、原曲权利人分别署名，具体合集视频链接待补。 |
| Blue Archive OST「Daily Routine 247」<br>`assets/music/hut_theme.ogg` | NEXON Games / Yostar（Blue Archive OST 权利记录；具体作曲署名待补） | 哔哩哔哩（下载合集；原始发行属 Blue Archive） | 本地曲目与 scripts/music.gd 的映射；碧蓝档案 OST 音乐合集；音乐合集收集整理：雷月夜（哔哩哔哩 UID 76847448），https://space.bilibili.com/76847448 | 原作音乐专有版权；具体录音与作者条款适用 | 本项目只调整裁剪、循环与音量，不据此取得原曲版权。 音乐整理来源由用户补充；收集整理者与作曲者、原曲权利人分别署名，具体合集视频链接待补。 |
| Blue Archive OST「Midsummer Cat」<br>`assets/music/mondrian_theme.ogg` | NEXON Games / Yostar（Blue Archive OST 权利记录；具体作曲署名待补） | 哔哩哔哩（下载合集；原始发行属 Blue Archive） | 本地曲目与 scripts/music.gd 的映射；碧蓝档案 OST 音乐合集；音乐合集收集整理：雷月夜（哔哩哔哩 UID 76847448），https://space.bilibili.com/76847448 | 原作音乐专有版权；具体录音与作者条款适用 | 本项目只调整裁剪、循环与音量，不据此取得原曲版权。 音乐整理来源由用户补充；收集整理者与作曲者、原曲权利人分别署名，具体合集视频链接待补。 |
| Blue Archive OST「Encroached Sky」<br>`assets/music/doom_theme.ogg` | NEXON Games / Yostar（Blue Archive OST 权利记录；具体作曲署名待补） | 哔哩哔哩（下载合集；原始发行属 Blue Archive） | 本地曲目与 scripts/music.gd 的映射；碧蓝档案 OST 音乐合集；音乐合集收集整理：雷月夜（哔哩哔哩 UID 76847448），https://space.bilibili.com/76847448 | 原作音乐专有版权；具体录音与作者条款适用 | 已核对实际曲目；doom_theme.ogg 的曲名是 Encroached Sky，不是 DOOM 音乐。 音乐整理来源由用户补充；收集整理者与作曲者、原曲权利人分别署名，具体合集视频链接待补。 |
| 蔚蓝档案音乐合集收集整理致谢<br>`assets/music` | 雷月夜（音乐收集整理者） | 哔哩哔哩 | https://space.bilibili.com/76847448 | 参考与致谢；原产品、文档、商标或素材按各自原始权利及条款记录 | 用户补充此账号为音乐收集整理来源；2026-11-14 经哔哩哔哩账号接口核对昵称与 UID 76847448。收集整理不等同作曲或原曲版权；原曲作者、录音权利与整理来源分别记录，具体合集视频链接待补。 |

## 剧情与图标

| 素材 / 位置 | 作者 | 平台 | 来源 | 许可与原文 | 备注 |
|---|---|---|---|---|---|
| 工具墙图标（7-Zip / GitHub / hashcat / Ollama / 知天下）<br>`assets/icons` | Simple Icons（CC0 矢量）+ 各商标持有人；hashcat / 知天下 图标由使用者提供 | Simple Icons 官网 / GitHub；用户提供 | https://simpleicons.org/ | 矢量图 CC0 1.0；图标本身是各厂商商标，仅作演示与识别用 | CC0 只覆盖著作权、不授予商标权；知天下图标对外发布前需向主办方确认 |
| 剧情文本（开场 / 设定）<br>`story` | 本项目作者 | 本项目（本地制作） | 本地来源，尚无外部链接 | MIT；原文 `LICENSE` | story/开场.txt、story/设定.md；角色名来自 Blue Archive，属同人创作 |
| 项目图标<br>`icon.png` | 待确认 | 待查（现有记录未注明来源平台） | 本地来源，尚无外部链接 | 待确认（若不是原创请替换） |  |
| 柴关电脑城配置单插图（B300 / 八卡 5090 两张）<br>`assets/story` | 本项目作者（Pillow 排版）+ AI 生成（GPT-Image 2.5，接口 usa0.top） | 本地 Pillow 排版；usa0.top（GPT-Image 2.5 接口） | https://usa0.top | 排版与文案为本项目原创（MIT）；B300 那张右侧为 AI 生成图，5090 那张右侧为网络整机图（见 SOURCES.md）；原文 `LICENSE` | 两张都是 1600×970：config_sheet.png（B300）、config_sheet_5090.png（八卡 5090）、hero_b300.png（AI 机器照）；中文用微软雅黑排版 |
| 游戏开发部活动室配图（买完电脑 · 确认收货地址）<br>`assets/story/gamedev_room.jpg` | Blue Archive 游戏内场景（NEXON Games / Yostar）；截图由使用者提供 | Blue Archive 游戏（用户提供截图） | 用户 2026-11 提供的桌面文件 BG_GameDevRoom.jpg | 专有：仅本地学习演示，不可商用、不可再分发 | 商店买完整机后，选「确认收货地址」弹出；下方配文「千禧年学院一年级游戏开发部活动室」。`.gitignore` 排除，缺图时对话会跳过这一步 |
| 配置单悬停用的零件照片（19 张）<br>`assets/story/parts` | NVIDIA / Intel / AMD / 三星 / 金百达 / 超花（Super Flower）/ Corsair 等厂商及知乎、IT之家、搜狐、什么值得买、阿里巴巴、中国制造网等媒体/商城 | 厂商官网；知乎 / IT之家 / 搜狐 / 什么值得买 / 阿里巴巴 / 中国制造网等 | 逐张出处见 assets/story/parts/SOURCES.md | 第三方新闻 / 商品图，**未获授权**：仅限本地学习演示，不得再分发、不得商用 | 逐张作者、平台与网址保留在 assets/story/parts/SOURCES.md，不将网络产品照片写成本项目原创。 |

## 参考与社区致谢

| 素材 / 位置 | 作者 | 平台 | 来源 | 许可与原文 | 备注 |
|---|---|---|---|---|---|
| 同花顺等交易软件的界面与交互参考<br>`scripts/parkour_futures.gd` | 同花顺产品、设计与开发团队 | 同花顺交易软件 / 官网 | https://www.10jqka.com.cn/；用户确认借鉴同花顺等交易软件的行情与交互表达 | 参考与致谢；原产品、文档、商标或素材按各自原始权利及条款记录 | 借鉴参照包括行情呈现、K 线、数字与涨跌颜色等交易软件界面语言；仅说明参考关系，不表示本项目与原产品存在合作或背书。 |
| 币安等交易软件的界面与交互参考<br>`scripts/parkour_futures.gd` | Binance（币安）产品、设计与开发团队 | Binance（币安）交易软件 / 官网 | https://www.binance.com/；用户补充的交易软件界面与交互参考 | 参考与致谢；原产品、文档、商标或素材按各自原始权利及条款记录 | 与同花顺等交易软件一并作为界面、行情与交易概念的参考；原产品名称和商标归相应权利人所有。 |
| Linux 系统与终端文化参考<br>`scripts/arch_terminal.gd` | Linus Torvalds 与 Linux 内核及开源社区贡献者 | kernel.org / Linux 开源社区 | https://www.kernel.org/；游戏内终端与系统概念参考 | 参考与致谢；原产品、文档、商标或素材按各自原始权利及条款记录 | 感谢 Linux 及相关开源社区提供的技术基础、终端文化与公开资料；本条为参考致谢，具体开源组件仍按各自许可记录。 |
| Arch Linux 发行版、官网与社区参考<br>`scripts/arch_web.gd` | Arch Linux 开发团队与社区贡献者 | Arch Linux 官网 / 开源社区 | https://archlinux.org/；游戏内 Arch 终端与仿浏览器页面参考 | 参考与致谢；原产品、文档、商标或素材按各自原始权利及条款记录 | 发行版、官网视觉和社区文化参考；游戏内仿浏览器由本项目绘制。Arch Linux 的标识与原站内容保留原权利和条款。 |
| ArchWiki 文档资料致谢<br>`scripts/hut_computer.gd` | ArchWiki 条目作者、编辑者与维护社区 | ArchWiki / Arch Linux | https://wiki.archlinux.org/；https://wiki.archlinux.org/title/Main_page_(简体中文) | 参考与致谢；原产品、文档、商标或素材按各自原始权利及条款记录 | 感谢公开维护的安装、配置、系统与软件使用资料；与 Arch Linux 发行版团队分别致谢，引用文档适用原站条款。 |
| 蔚蓝档案 Wiki 游戏资料参考<br>`scripts/cost_gauge.gd` | 蔚蓝档案 Wiki 社区维护者与条目贡献者 | 蔚蓝档案 Wiki（社区资料站） | 用户补充的蔚蓝档案 Wiki；现有源码保留的资料链接 https://bluearchive.wiki/wiki/Cost；具体中文 Wiki 站点未注明 | 参考与致谢；原产品、文档、商标或素材按各自原始权利及条款记录 | 感谢角色、技能与机制资料的社区整理。现有 Cost 源码注释区分了用户指定数值与曾尝试访问的 Wiki，本站点致谢不表示每个数值均已从 Wiki 查证。 |

## 免责声明

本项目仅供学习交流，无意分发。第三方名称、商标、角色、模型、图像、音乐及语音等权利归原作者或相应权利人所有。署名、致谢及本声明不替代原始授权，也不变更既有开源许可。如有侵权或署名遗漏，请联系项目作者核实、补正或删除。

## 核对依据与待补信息

- GDGS：GitHub 上游 contributors API 核对为 ReconWorldLab、4321ba、beiller、sodih3iw；本项目分支 contributors API 为 AssassinHLQ。以四位上游提交者加一位本项目分支作者列出五人，角色分开；2Retr0 与 PlayCanvas 是另列的算法上游。
- 上游核对接口：`https://api.github.com/repos/ReconWorldLab/godot-gaussian-splatting/contributors?per_page=100`；本项目分支接口：`https://api.github.com/repos/AssassinHLQ/godot-gaussian-splatting/contributors?per_page=100`。算法依据为上游 README 的 Acknowledgements 与本地源码署名。
- Aa暗夜深渊：直接读取 `assets/ui_font/Aa暗夜深渊.ttf` 的 name 表，确认 Aa、翰美互通、字体管家网址与“非商业使用”标注；实际下载站未找到。Fusion Pixel 与 JetBrains Mono 的来源、作者和 OFL 原文均在本地许可文件。
- 天空盒、硬件、电竞房：用户确认来自爱给网；原始作者与资源页未查明。天空盒的旧 AllSky 归属缺少当前文件对应证据，保留为未核实历史线索。原作者未查明，侵权必删。
- 模之屋作者、语音模型 SLNeil、蒙德里安制作方式及坦克小游戏恢复经过按使用者本次确认更新。语音作者统一拼写 SLNeil，与已有哔哩哔哩 UID 523537077 对应。
- 两组第 3 版视频作者按 `scripts/arch_terminal.gd` 的源素材注释补齐。部分视频具体链接、音乐作曲者和天空盒原作者仍待补，未编造。
- 坦克小游戏的用户同名 GitHub 仓库当前公开列表未找到，准确链接待补；内部素材授权暂按用户提供的来源说明保留待核记录。`JustDoIt0910/TankTrouble` 仅是已留有 MIT 原文的算法参考项目。

- 音乐收集整理者：用户提供哔哩哔哩 UID 76847448；通过 `https://api.bilibili.com/x/web-interface/card?mid=76847448` 核对昵称为“雷月夜”。音乐合集的具体视频链接待补，未将该账号写成原曲作曲者或权利人。
- 交易软件、Linux、Arch Linux、ArchWiki 与蔚蓝档案 Wiki 按用户补充列为界面、概念及资料参考。蔚蓝档案 Wiki 的具体中文站点未注明，保留现有源码中的 Blue Archive Wiki 资料链接及其查证范围。
