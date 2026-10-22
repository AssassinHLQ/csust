# assets/icons —— 「工具墙」用的图标

2026-10-22 用户：「后续需要找 7zip 图标素材、hashcat 图标、github、ollama、知天下 AI 图标」

| 文件 | 来源 | 许可 | 状态 |
|---|---|---|---|
| `7zip.svg` | [Simple Icons](https://simpleicons.org/)（`simple-icons@13/icons/7zip.svg`） | **CC0 1.0** | ✅ 官方风格，可直接用 |
| `github.svg` | 同上（`github.svg`） | **CC0 1.0** | ✅ |
| `ollama.svg` | 同上（`ollama.svg`） | **CC0 1.0** | ✅ |
| `hashcat.svg` | **本喵手绘占位** | 本项目自制 | ⚠️ 非官方：Simple Icons 里没有 hashcat（404），要用官方 logo 得从 hashcat 仓库/官网抠 |
| `zhitianxia.svg` | **本喵手绘占位** | 本项目自制 | ⚠️ 非官方：「知天下」是主办方，logo 必须向主办方要源文件 |

## 用法

SVG 在 Godot 里会被当成图片导入（`Texture2D`），三种尺寸都能用：

```gdscript
var tex: Texture2D = load("res://assets/icons/github.svg")
# 想做 32×32 的图标：SVG 会按目标尺寸栅格化，缩放不糊
```

⚠️ `hashcat.svg` / `zhitianxia.svg` 的配色写死在文件里（hashcat 红 `#e04b4b`、知天下蓝
`#3aa0ff` / `#7fd4ff`）。如果要跟着 UI 主题变色，把 `stroke` / `fill` 里的色值改成
`currentColor`，再用 `modulate` 上色。

## 还差什么

- **hashcat 官方 logo**：hashcat 的仓库（`hashcat/hashcat`）里没有独立 logo 文件，
  社区一般用那个「骷髅 + 撬锁」的位图；要用矢量得自己描。
- **知天下官方 logo**：向主办方索取。
- **7-Zip 官方图标**也是位图（`7zFM.exe` 里的 ico）；这里用的 Simple Icons 版本是
  社区重绘的单色版，比原版干净，但**不是官方原图**。
