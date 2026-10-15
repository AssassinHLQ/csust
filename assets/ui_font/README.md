# assets/ui_font/ —— 界面显示字体的投放目录

把一套**带汉字的显示字体**放进这个目录，整套 UI（剧情正文、HUD、Esc 设置界面）
就会自动换成它。**不放进来的话会回退**到仓库自带的
`assets/ui/font.ttf`（Fusion Pixel 12px，OFL，可随仓库分发），不会报错。

## 现在放的是

`Aa暗夜深渊.ttf`（Aa 字库，**商用需授权**）。

⚠️ **这个文件不在版本库里。** `.gitignore` 排除了本目录，只保留这份说明 ——
理由和 `models/`、`splatdata/`、`assets/ui_sprout/` 一样：
**能本地用，但不能随仓库再分发**。放这个目录里的字体请自行确认授权，
本仓库不分发它们。详见 [../../THIRD_PARTY.md](../../THIRD_PARTY.md)。

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
