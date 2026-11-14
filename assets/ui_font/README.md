# assets/ui_font/ —— 界面显示字体的投放目录

把一套**带汉字的显示字体**放进这个目录，整套 UI（剧情正文、HUD、Esc 设置界面）
就会自动换成它。**不放进来的话会回退**到仓库自带的
`assets/ui/font.ttf`（Fusion Pixel 12px，OFL，可随仓库分发），不会报错。

## 现在放的是

`Aa暗夜深渊.ttf`。2026-11-14 从当前字体文件的 `name` 表核实：

- 作者 / 厂商：Aa 字库、翰美互通（厦门）科技有限公司。
- 版权：©2020 HanMeiHutong (XiaMen) Technology Co.Ltd.
- 字体家族名：`Aa暗夜深渊 (非商业使用)`。
- 内嵌厂商 / 设计者官网：字体管家，`http://www.zitiguanjia.com`。
- 用户实际下载站与原始资源页未找到；内嵌官网不能证明实际下载渠道，完整发行条款仍待核。

字体本体被 Git 忽略；这只描述版本管理，不决定游戏导出包含规则。逐项署名见
[../../CREDITS.md](../../CREDITS.md)，许可记录见 [../../THIRD_PARTY.md](../../THIRD_PARTY.md)。

另外两款字体均有原始许可：`assets/ui/font.ttf` 为 TakWolf 的 Fusion Pixel（GitHub），
`assets/ui/mono.ttf` 为 JetBrains Mono（JetBrains 官网 / GitHub），均为 SIL OFL 1.1。
Mono 在字体名中指等宽，与支持 C# / .NET 的 Godot Mono 发行版不同。
`assets/ui_sprout/font.ttf` 是 Sprout Lands 包自带的像素字体，内嵌设计者为 Cup Nooble，
来源 itch.io，按素材包条款记录，主要用于数字与拉丁字形。

## 换成别的字体

1. 把 ttf/otf 丢进本目录；
2. 改 `scripts/ui_skin.gd` 的 `UI_FONT_CANDIDATES` —— **按优先级排**，
   第一个存在的会被用上；
3. **导入一次**，否则 `ResourceLoader.exists()` 认不出来：

   ```powershell
   & <godot> --headless --path . --import
   ```

## 挑字体前先查缺字（这一步别省）

显示字体经常只覆盖 GB2312 那 6763 个字，生僻一点的标点或人名就会变成**豆腐块**，
而且往往出现在很偏的角落。仓库里带了查字工具（纯 Python 标准库，不用装东西）：

```powershell
# ① 最重要的一个：把「游戏里实际会显示出来的每一个字」对着字体的 cmap 查一遍
#    剧情那一组会**直接读 story/*.txt**（按解析器的语法剥掉注释与 @指令），
#    所以你改了剧本之后再跑，查的就是你真正写下的那些字。
& <python> tools\font\font_needed.py assets\ui_font\你的字体.ttf

# ② 想看覆盖率区块统计（汉字 / 标点 / 假名各覆盖多少）
& <python> tools\font\font_cmap_check.py assets\ui_font\你的字体.ttf
```

`font_needed.py` 按「剧情 / 名字 / HUD / 设置界面 / 操作说明」分组报缺字，末尾给
「**可以整套换**」或「**不能整套换：共缺 N 个字**」，退出码也相应是 0 / 1
（方便丢进脚本当门禁）。

> ⚠️ 实测两个坑，别重犯：
> · 直接数整个剧本文件会把**注释行和 `@指令`的语法字符**也算进去（第一版多算了
>   200 多个字），所以工具里按解析器的语法只取「会显示」的部分；
> · 文件大小**不等于**有汉字 —— Sprout 那套皮肤字体 0.11 MB 只有 80 个拉丁字形，
>   Fusion Pixel 6.68 MB 覆盖 19214/20992 个汉字。必须解 `cmap` 表实测。
