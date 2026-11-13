# 把「普拉娜」绿幕视频抠成 PNG 序列，供电脑屏幕里逐帧播放（终端敲 `plana`）。
#
# 用法（PowerShell，后台跑，不弹窗口）：
#     powershell.exe -NoProfile -ExecutionPolicy Bypass -File _tools\fetch_plana_frames.ps1
#
# ⚠️ 两个坑：
#   ① 必须带 `-ExecutionPolicy Bypass`（本机执行策略禁止直接跑未签名 .ps1）。
#   ② **这个文件必须存成「带 BOM 的 UTF-8」**：Windows PowerShell 5.1 会把无 BOM 的
#      UTF-8 当 ANSI 读，下面那个中文源路径会变乱码、然后报「找不到源视频」。
#      （踩过一次：文件是 UTF-8 无 BOM，跑出来是 `渚濇棧閫侀€侀€?` 这种。）
#
# 产物：`assets/plana_frames/f_0001.png … f_0443.png`
#       ⚠️ 第三方素材派生物，`/assets/plana_frames/` 已被 .gitignore 排除，不随仓库分发。
#          见 CREDITS.md 与 .gitignore 里的说明。
#
# ── 参数是怎么定的（都实测过）──
# 源视频：720×786 / 30 fps / 29.53 s，绿幕底色实测 **(70, 226, 0) = #46E200**，非常干净。
#   · chromakey=0x46E200:0.16:0.06
#       相似度 0.16 / 混合 0.06。试过 0.10 / 0.14 / 0.18，抠掉的面积完全一样
#       （60.3% 全透明），说明底色真的很纯。
#   · despill=type=green:mix=1:expand=0.3
#       **必须加**：不加的话剪影边缘有一圈亮绿边（白头发在绿幕上抗锯齿，
#       边缘像素被染绿）。加了之后还会多出约 2600 个半透明像素，边缘更自然。
#   · fps=15：源 30 → 15，帧数减半（886 → 443），动画感够用。
#   · scale=720:-1:flags=lanczos：**按原视频宽度出**，不再缩到 360。
#     ⚠️ 2026-11-13 用户实测立绘「画质变差」：360 宽是给旧的 832×664 画布定的，
#        新画布 1280×720 里立绘高 682 px、窗口再放大 ~2×，360 宽的图被拉三倍多。
#        现在出 720×786 原尺寸，画布里只是缩小，屏幕上接近 1:1。
#        代价：显存/磁盘变大，所以 `frame_anim.gd` 的 CACHE_MAX 从 48 降到 16。
#
# ── 为什么不直接用带 alpha 的 .ogv ──
# Godot 只支持 Theora(.ogv)。ffmpeg 能编 `-c:v libtheora -pix_fmt yuva420p`，
# 但**Godot 播出来 alpha 全是 255**（实测 `scripts/_probe_ogv_alpha.gd`：
# 帧格式确实是 RGBA8，但最小 alpha = 255、半透明采样 0 个），
# 而且 ffmpeg 自己回解这个 ogv 都报 `error in unpack_block_qpis`、解出来是 RGB。
# 所以只能走序列帧 + 流式加载（见 `scripts/plana_page.gd` 的环形缓冲）。

$ErrorActionPreference = "Stop"

$ffmpeg = "D:\SOFTWARE\ffmpeg\bin\ffmpeg.exe"
# 用户重下过一次素材：文件名多了个 `(1)`。按候选列表找，别写死。
$candidates = @(
    "C:\Users\WY157\Downloads\依旧送送送，普拉娜绿幕素材，想用的可以自己拿_视频.mp4",
    "C:\Users\WY157\Downloads\依旧送送送，普拉娜绿幕素材，想用的可以自己拿_视频(1).mp4"
)
$src = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$dst = Join-Path $PSScriptRoot "..\assets\plana_frames"

if (-not (Test-Path $ffmpeg)) { throw "找不到 ffmpeg: $ffmpeg" }
if (-not $src) { throw "找不到源视频，试过：$($candidates -join ' / ')" }

New-Item -ItemType Directory -Force -Path $dst | Out-Null
Get-ChildItem $dst -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

$filter = "chromakey=0x46E200:0.16:0.06,despill=type=green:mix=1:expand=0.3," +
          "fps=15,scale=720:-1:flags=lanczos,format=rgba"

& $ffmpeg -v error -i $src -vf $filter -vsync 0 -compression_level 6 `
    -y (Join-Path $dst "f_%04d.png")

$n = (Get-ChildItem $dst -Filter *.png).Count
$mb = [math]::Round(((Get-ChildItem $dst -Filter *.png | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host "[plana] 抠像完成：$n 帧 / $mb MB → $dst"
if ($n -lt 100) { Write-Warning "[plana] 帧数异常偏少，检查源视频路径与 chromakey 参数" }
