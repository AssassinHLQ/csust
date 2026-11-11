#!/usr/bin/env bash
# 把使用者的 CG（多半是 mp4）转成 **Godot 唯一认识的格式：Ogg Theora (.ogv)**。
#
#   _tools/mp4_to_ogv.sh <输入.mp4> [输出.ogv]
#
# 不给输出名就写到 src/assets/cg/opening.ogv（`title_intro.gd` 认这个路径）。
#
# ── 为什么非转不可 ──
# Godot 4 的 `VideoStreamPlayer` **只支持 Ogg Theora**。mp4/H.264、webm/VP9
# 一律播不了，这不是本项目的限制，是引擎的支持范围。所以不用折腾播放器，
# 统一在导入这一步转掉最省事 —— 使用者照常导出 mp4 就行。
#
# ── 参数为什么这么选 ──
#   libtheora   `-q:v 8`：Theora 是有损的老编码器，质量档给高一点
#               （`-q:v 10` 是上限，再往上只涨体积不涨画质）
#   libvorbis   音频必须转成 Vorbis —— Theora 容器里放 AAC 是能封装，
#               但 Godot 用的 Ogg demuxer 不保证认，实测会静音
#   `-pix_fmt yuv420p`  有些 CG 是 RGB 或 4:4:4，Theora 要 4:2:0
#   `-cropdetect` 之类一概不用：开场 CG 就该按作者给的画幅原样播
#
# ⚠️ 转完**必须再进一次 Godot 编辑器**（或跑一次 headless import），
#    否则 `.ogv` 没有可用的 `.import`，运行时 `load()` 拿不到东西。

set -u

IN="${1:?用法: mp4_to_ogv.sh <输入视频> [输出.ogv]}"
if [ ! -f "$IN" ]; then
  echo "找不到输入文件：$IN" >&2
  exit 1
fi

HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${2:-$HERE/assets/cg/opening.ogv}"

# 自带的 ffmpeg 优先，其次 PATH 上的
FFMPEG="/d/SOFTWARE/ffmpeg/bin/ffmpeg.exe"
[ -x "$FFMPEG" ] || FFMPEG="$(command -v ffmpeg || true)"
if [ -z "$FFMPEG" ] || [ ! -x "$FFMPEG" ]; then
  echo "没找到 ffmpeg（试过 /d/SOFTWARE/ffmpeg 和 PATH）" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

# 先把源信息打出来 —— 出问题时这一屏就是证据
echo "── 源 ──"
"$FFMPEG" -hide_banner -i "$IN" 2>&1 | grep -E "Duration|Stream #" || true

echo
echo "── 转码 ── $IN → $OUT"
"$FFMPEG" -y -hide_banner -loglevel warning \
  -i "$IN" \
  -c:v libtheora -q:v 8 \
  -c:a libvorbis -q:a 5 \
  -pix_fmt yuv420p \
  "$OUT"
RC=$?

if [ $RC -ne 0 ]; then
  echo "✗ 转码失败（ffmpeg 退出码 $RC）" >&2
  exit $RC
fi

echo
echo "── 结果 ──"
"$FFMPEG" -hide_banner -i "$OUT" 2>&1 | grep -E "Duration|Stream #" || true
ls -lh "$OUT"
echo
echo "✓ 好了。注意："
echo "  1. 直接进游戏会播它（title_intro.gd 里 CG_VIDEO 指向这个路径）；"
echo "  2. 换成别的文件名就改 CG_VIDEO；"
echo "  3. 想退回程序化标题卡，把 assets/cg/opening.ogv 删掉即可（会自动降级）。"
