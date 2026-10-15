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
而且往往出现在很偏的角落。本仓库带了一个查字工具：

```powershell
# 把「游戏里实际会出现的每一个字」对着字体的 cmap 查一遍
& <python> ..\_hud_preview\font_needed.py <字体路径>

# 想看覆盖率区块统计（汉字/标点/假名各覆盖多少）
& <python> ..\_hud_preview\font_cmap_check.py <字体路径>
```

`font_needed.py` 会按「剧情 / 名字 / HUD / 设置界面 / 操作说明」分组报缺字，
末尾给一句「可以整套换」或「不能整套换：共缺 N 个字」。
