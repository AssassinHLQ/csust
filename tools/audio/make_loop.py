#!/usr/bin/env python3
"""把一首曲子裁成「可无缝循环」的一段，并给出推导过程。

用法：
    python make_loop.py <输入音频> <输出 wav> [--target 40.0] [--fade-ms 25]

例（本工程商店 BGM，UNDERTALE「Tem Shop」）：
    python make_loop.py "UNDERTALE Soundtrack - 44 Tem Shop_音频.mp4" shop_loop.wav --target 40

── 为什么不能「按用户说的整数秒直接切」──
用户的原话是「只要前面四十秒，这样子才能循环」。但 40.000 s 是不是循环点，
**必须量**：本喵对源文件做自相关，量到它自身的循环周期是 5.0262 s。
   · 切在 40.000 s：与开头的相关系数只有 +0.06，接缝跳变是曲子内部平均跳变的 1.8 倍
     （会「咔」一下）；
   · 切在 40.2094 s（= 5.0262 × 8，误差 0.2 ms）：相关系数 +0.66，接缝跳变 ×1.05。
差 0.21 s 听不出长短差别，但接缝干净得多。所以最终用 **40.2094 s**，
它和用户说的「四十秒」实质是同一个意思。

脚本做三件事：
  1. 用 FFT 自相关找循环周期 P，并在 target 附近按 0.1 ms 精度扫出最佳长度 L
     （优先取 P 的整数倍）；
  2. 按 L 裁剪，并在末尾做 **25 ms 环绕交叉淡化**（等功率曲线）——
     把尾巴与开头的副本混合，使 y[L⁻] ≈ y[0]，接缝连续；
  3. 峰值归一化到 -1 dBFS，写成 16 bit PCM wav（供 ffmpeg 编码成 ogg）。
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import wave

import numpy as np

SR = 44100


def load_audio(path: str) -> np.ndarray:
    """读成 (帧数, 声道) 的 float64，范围 [-1, 1]。用 ffmpeg 解码，什么格式都吃。"""
    raw = r"C:\Users\WY157\AppData\Local\Temp\_make_loop_decoded.wav"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", path,
         "-acodec", "pcm_s16le", "-ar", str(SR), "-ac", "2", raw],
        check=True)
    with wave.open(raw, "rb") as w:
        n_ch = w.getnchannels()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    return data.reshape(-1, n_ch).astype(np.float64) / 32768.0


def find_period(x: np.ndarray, lo_sec: float = 3.0, hi_sec: float = 30.0) -> float:
    """FFT 自相关找循环周期：lag 在 [lo, hi] 之间的最大峰值位置。"""
    n = len(x)
    mono = x.mean(axis=1)
    n_fft = 1 << int(np.ceil(np.log2(2 * n)))
    spec = np.fft.rfft(mono - mono.mean(), n_fft)
    ac = np.fft.irfft(spec * np.conj(spec), n_fft)[:n]
    ac /= max(ac[0], 1e-12)
    lo, hi = int(lo_sec * SR), min(int(hi_sec * SR), n - 1)
    seg = ac[lo:hi]
    peaks = [(float(seg[i]), (lo + i) / SR)
             for i in range(2, len(seg) - 2)
             if seg[i] > seg[i - 1] and seg[i] >= seg[i + 1]]
    if not peaks:
        return float("nan")
    peaks.sort(reverse=True)
    return peaks[0][1]


def loop_score(x: np.ndarray, L: int, tpl: np.ndarray) -> tuple[float, float]:
    """返回 (波形相关, 接缝跳变)。tpl 是开头一段（用来代表「循环回到这里」）。"""
    n = len(x)
    if L + len(tpl) > n:
        return -2.0, 1e9
    seg = x[L:L + len(tpl)].mean(axis=1)
    seg = seg - seg.mean()
    tn = np.linalg.norm(tpl)
    sn = np.linalg.norm(seg)
    r = float(np.dot(tpl, seg) / (tn * sn)) if tn > 1e-9 and sn > 1e-9 else -1.0
    seam = float(np.max(np.abs(x[L] - x[L - 1])))
    return r, seam


def best_length(x: np.ndarray, target: float, period: float,
                span: float = 0.5, coarse: float = 1e-3, fine: float = 1e-4) -> tuple[int, float]:
    """在 target±span 内找相关最高的 L。用 4 s 长模板提高分辨率。"""
    n = len(x)
    tpl_len = min(int(4.0 * SR), n // 4)
    tpl_audio = x[:tpl_len].mean(axis=1)
    tpl = tpl_audio - tpl_audio.mean()

    def scan(a: float, b: float, step: float) -> list[tuple[float, float, int]]:
        out = []
        L = a
        while L <= b:
            i = int(round(L * SR))
            if i > 0 and i + tpl_len <= n:
                r, seam = loop_score(x, i, tpl)
                out.append((r, seam, i))
            L += step
        return out

    def report(rows, title):
        rows = sorted(rows, key=lambda v: -v[0])[:6]
        print(f"\n{title}")
        for r, seam, i in rows:
            print("  L=%10.5f s  r=%+.4f  接缝 %.6f  样本 %d"
                  % (i / SR, r, seam, i))
        return rows

    # 第一步：如果目标值附近有周期的整数倍，就从它开始
    k = max(1, round(target / period)) if period == period else 0
    if k:
        centre = k * period
        print("自相关量到的循环周期 P = %.4f s；目标 %.3f s 对应 %d × P = %.4f s"
              % (period, target, k, centre))
    else:
        centre = target
    rows = report(scan(centre - span, centre + span, coarse),
                  f"粗扫 {centre - span:.3f} ~ {centre + span:.3f} s（步长 {coarse * 1000:.1f} ms）")
    if not rows:
        raise SystemExit("扫不到合适的长度")
    best = rows[0][2] / SR
    rows2 = report(scan(best - 0.02, best + 0.02, fine),
                   f"精扫 {best - 0.02:.3f} ~ {best + 0.02:.3f} s（步长 {fine * 1000:.2f} ms）")
    if not rows2:
        raise SystemExit("精扫失败")
    r, seam, i = rows2[0]
    print("\n选定 L = %.5f s（样本 %d），r = %+.4f，接缝 %.6f" % (i / SR, i, r, seam))
    if period == period:
        print("       = %.4f × P（误差 %.4f ms）" % (i / SR / period, (i / SR - k * period) * 1000))
    return i, period


def make_seamless(x: np.ndarray, L: int, fade_ms: float) -> np.ndarray:
    """裁 L，并在末尾做环绕交叉淡化（等功率）。"""
    F = int(round(fade_ms / 1000.0 * SR))
    if F * 2 >= L or L + F > len(x):
        F = max(1, min(F, L // 4, len(x) - L))
    y = x[:L].copy()
    t = np.linspace(0.0, 1.0, F, endpoint=False)
    fade_in = np.sqrt(t)             # 开头副本进来的
    fade_out = np.sqrt(1.0 - t)      # 末尾出去的
    y[L - F:L] = y[L - F:L] * fade_out[:, None] + x[:F] * fade_in[:, None]
    print("\n环绕交叉淡化 %.1f ms（%d 样本，等功率 sqrt 曲线）"
          % (fade_ms, F))
    return y


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--target", type=float, default=40.0,
                    help="期望的循环长度（秒），默认 40")
    ap.add_argument("--span", type=float, default=0.5,
                    help="在 target 附近扫多大范围（秒），默认 ±0.5")
    ap.add_argument("--fade-ms", type=float, default=25.0)
    args = ap.parse_args()

    x = load_audio(args.src)
    print("源：%d 帧 / %.4f s / %d 声道" % (len(x), len(x) / SR, x.shape[1]))

    period = find_period(x)
    print("自相关循环周期 P = %.5f s" % period)

    L, period = best_length(x, args.target, period, span=args.span)
    y = make_seamless(x, L, args.fade_ms)

    peak = float(np.max(np.abs(y)))
    gain = 10 ** (-1.0 / 20.0) / peak if peak > 0 else 1.0
    y = y * gain
    print("峰值 %.4f -> 增益 %.4f（归一化到 -1 dBFS）" % (peak, gain))

    out = np.clip(y * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(args.out, "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(out.tobytes())

    seam = float(np.max(np.abs(y[0] - y[-1])))
    inner = float(np.mean(np.abs(np.diff(y[:, 0]))))
    print("\n写出 %s（%.4f s，%d 帧）" % (args.out, len(out) / SR, len(out)))
    print("接缝跳变 %.6f；内部相邻平均跳变 %.6f（x%.2f）"
          % (seam, inner, seam / max(inner, 1e-9)))
    print("\n下一步：ffmpeg -i %s -c:a libvorbis -q:a 5 <工程>/assets/music/xxx.ogg"
          % args.out)
    print("        然后把 assets/music/xxx.ogg.import 里的 loop 改成 true"
          "（或导入后重新 --import）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
