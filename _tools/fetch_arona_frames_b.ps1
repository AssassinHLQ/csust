# 阿洛娜 · **第二版**素材（木偶版）：绿幕 → 带 alpha 的 PNG 序列
#
# 来源：bilibili UP「**忧郁的优_**」的《阿罗娜木偶，可直接用，也可艾特》，
#       1290×1078 / 30 fps / 15.0 s，绿幕底色实测 (5,213,4) = #05D504。
#
# ── 和第一版（`fetch_arona_frames.ps1`）的区别 ──
#   · 这是**半身**素材（腰以上 + 举着一个白色纸盒），第一版是全身；
#   · 绿不一样：#05D504 vs #2EDC01，所以 chromakey 要单独标；
#   · 主体不在画面正中（偏左，右边拖着一截白色尾巴状的东西），
#     直接铺进终端右半屏会**明显偏一边**，所以先按主体包围盒裁一刀。
#
# ── 裁切 ──
#   crop=1000:1068:280:10：
#     实测两帧的主体 alpha 包围盒是 x[291,1271] y[13,1077]，
#     取整再各留一点边 → x 280 起 1000 宽、y 10 起 1068 高（正好到画面底）。
#     ⚠️ 这些数字是**这支片子**的，换素材要重新量（两支脚本里都写了量法：
#        先抽一帧 key 出来，用 alpha>24 的像素求 bbox）。
#
# ── 其他参数 ──
#   · fps=12：15 秒 → 180 帧，和第一版同帧率，切版本时节奏不跳。
#   · scale=720:-1：和第一版同宽，显存账好算（约 2.2 MB/帧）。
#   · 没有水印，不需要 drawbox 那一步（第一版有「浅羽香草 bilibili」）。
#
# ⚠️ 本文件必须存成**带 BOM 的 UTF-8**：Windows PowerShell 5.1 会把无 BOM 的
#    UTF-8 当 ANSI 读，中文路径立刻变乱码、报「找不到源视频」。

$ErrorActionPreference = "Stop"

$ffmpeg = "D:\SOFTWARE\ffmpeg\bin\ffmpeg.exe"
$candidates = @(
    "C:\Users\WY157\Downloads\阿罗娜木偶，可直接用，也可艾特_视频.mp4"
)
$src = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$dst = Join-Path $PSScriptRoot "..\assets\arona_frames_b"

if (-not (Test-Path $ffmpeg)) { throw "找不到 ffmpeg: $ffmpeg" }
if (-not $src) { throw "找不到源视频，试过：$($candidates -join ' / ')" }

New-Item -ItemType Directory -Force -Path $dst | Out-Null
Get-ChildItem $dst -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

$filter = "crop=1000:1068:280:10,chromakey=0x05D504:0.16:0.06," +
          "despill=type=green:mix=1:expand=0.3," +
          "fps=12,scale=720:-1:flags=lanczos,format=rgba"

& $ffmpeg -v error -i $src -vf $filter -vsync 0 -compression_level 6 `
    -y (Join-Path $dst "f_%04d.png")

$n = (Get-ChildItem $dst -Filter *.png).Count
$mb = [math]::Round(((Get-ChildItem $dst -Filter *.png | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host "[arona_b] 抠像完成：$n 帧 / $mb MB → $dst"
if ($n -lt 60) { Write-Warning "[arona_b] 帧数异常偏少，检查源视频路径与 chromakey 参数" }
