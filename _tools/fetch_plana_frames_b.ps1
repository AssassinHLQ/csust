# 普拉娜 · **第二版**素材（近景版）：绿幕 → 带 alpha 的 PNG 序列
#
# 来源：bilibili UP「**星冻qwq**」的《普拉娜自己取》，
#       1280×720 / 30 fps / 20.0 s，绿幕底色实测 (0,220,34) = #00DC22。
#
# ── 和第一版（`fetch_plana_frames.ps1`）的区别 ──
#   · 这是**近景**素材（头 + 肩 + 光环），第一版是半身带裙；
#   · 绿不一样：#00DC22 vs #46E200，所以 chromakey 要单独标；
#   · **左上角有上传者水印「小星野大叔 bilibili」**（白色半透明字）。
#     只抠绿是去不掉白字的，而且水印上方就是光环，不能靠裁掉顶部解决
#     （第一版阿洛娜那支是裁顶部；这支一裁就把光环削掉）。
#     所以用 drawbox 把那块刷成**纯绿**（纯绿正好是 key 色，抠完 alpha=0），
#     水印消失、光环一根头发都不少。
#   · 主体在画面中间偏右、比例接近竖构图，所以先按包围盒裁一刀再缩放。
#
# ── 裁切 ──
#   crop=560:718:372:2：
#     实测两帧的主体 alpha 包围盒是 x[377,926] y[1,719]，
#     取整留边 → x 372 起 560 宽、y 2 起 718 高（正好到画面底）。
#     ⚠️ 这些数字是**这支片子**的，换素材要重新量（量法：先抽一帧 key 出来，
#        用 alpha>24 的像素求 bbox）。
#
# ── 其他参数 ──
#   · fps=15：20 秒 → 300 帧，和第一版同帧率。
#   · 不放大：裁完就是 560×718，终端里要画的高度约 675 → 只缩小，够清晰。
#
# ⚠️ 本文件必须存成**带 BOM 的 UTF-8**：Windows PowerShell 5.1 会把无 BOM 的
#    UTF-8 当 ANSI 读，中文路径立刻变乱码、报「找不到源视频」。

$ErrorActionPreference = "Stop"

$ffmpeg = "D:\SOFTWARE\ffmpeg\bin\ffmpeg.exe"
$candidates = @(
    "C:\Users\WY157\Downloads\普拉娜自己取_视频.mp4"
)
$src = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$dst = Join-Path $PSScriptRoot "..\assets\plana_frames_b"

if (-not (Test-Path $ffmpeg)) { throw "找不到 ffmpeg: $ffmpeg" }
if (-not $src) { throw "找不到源视频，试过：$($candidates -join ' / ')" }

New-Item -ItemType Directory -Force -Path $dst | Out-Null
Get-ChildItem $dst -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

# ① drawbox：把左上角水印那块刷成纯绿（必须在 chromakey **之前**）
# ② crop：按主体包围盒裁
# ③ chromakey / despill：去绿幕、去绿边（参数与第一版同口径）
# ④ fps=15
$filter = "drawbox=x=0:y=0:w=320:h=95:color=0x00DC22:t=fill," +
          "crop=560:718:372:2," +
          "chromakey=0x00DC22:0.16:0.06," +
          "despill=type=green:mix=1:expand=0.3," +
          "fps=15,format=rgba"

& $ffmpeg -v error -i $src -vf $filter -vsync 0 -compression_level 6 `
    -y (Join-Path $dst "f_%04d.png")

$n = (Get-ChildItem $dst -Filter *.png).Count
$mb = [math]::Round(((Get-ChildItem $dst -Filter *.png | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host "[plana_b] 抠像完成：$n 帧 / $mb MB → $dst"
if ($n -lt 60) { Write-Warning "[plana_b] 帧数异常偏少，检查源视频路径与 chromakey 参数" }
