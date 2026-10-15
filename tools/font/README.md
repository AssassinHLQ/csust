# tools/font/ —— 查字体「有没有你要的那些字」

换界面字体、或者剧本里写了生僻字名的时候，用这两个脚本查一遍，
**不需要装任何东西**（纯 Python 标准库，故意不用 `fontTools` —— 这台机器上没网络装不了）。

| 脚本 | 干什么 |
|---|---|
| `font_needed.py` | **最常用的那个**。把「游戏里实际会显示出来的每一个字」对着 cmap 查一遍，按界面分组报缺字，末尾给「可以整套换 / 不能整套换」并设置退出码 |
| `font_cmap_check.py` | 底层工具 + 覆盖率区块统计（汉字 / 标点 / 假名 / 谚文各覆盖多少）。`font_needed.py` 会 import 它 |

## 用法

```powershell
# 把「游戏里会显示的每一个字」查一遍（剧情那一组直接读 story/*.txt）
& <python> tools\font\font_needed.py assets\ui_font\Aa暗夜深渊.ttf

# 一次查多个，方便对比
& <python> tools\font\font_needed.py assets\ui_font\*.ttf assets\ui\font.ttf

# 只看覆盖率区块统计
& <python> tools\font\font_cmap_check.py assets\ui\font.ttf
```

`<python>` 在本机是
`C:\Users\WY157\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe`；
任何 Python 3.8+ 都行。

## 两个已经被这两个脚本抓出来的坑

1. **文件大小不等于有汉字。** Sprout 皮肤的 `font.ttf` 有 0.11 MB 却只有
   80 个拉丁字形、**0 个汉字**（设置界面一直是数字和拉丁，所以没暴露）；
   Fusion Pixel 是 6.68 MB / 19214 个汉字。只看大小会判错。
2. **不能直接数整个剧本文件。** 注释行和 `@指令` 的语法字符永远不会显示在屏幕上，
   算进去只会让结论虚高（第一版多算了 200 多个字，把 `#`、`@`、`═` 都算成了
   「会出现的字」）。所以 `font_needed.py` 按 `story_script.gd` 的语法只取
   「说话人 + 正文」。

## 判断标准

`font_cmap_check.py` 输出的 `CJK 汉字（URO）` 那一行是关键：

| 比例 | 大致是什么 | 够不够用 |
|---|---|---|
| ~91.5%（19214/20992） | 全字库级别（Fusion Pixel） | 够写任何中文 |
| ~32.7%（6864/20992） | GB2312 级别（Aa暗夜深渊） | 正常写作够，生僻字会缺 —— **所以要用 `font_needed.py` 对着实际用字确认** |
| 0% | 只有拉丁（Sprout 皮肤字体） | 中文全部靠系统回退 |
