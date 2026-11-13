# -*- coding: utf-8 -*-
"""用 GPT-SoVITS 给电脑里的阿洛娜 / 普拉娜**生成中文配音**。

## 为什么是这个路子

用户 2026-11-13：「arona 的配音也下好了，需要配音完整看看效果」。

- `D:\\BaiduNetdiskDownload\\阿罗娜\\` 和 `\\普拉娜\\` 里是**训练好的 GPT-SoVITS 模型**
  （`GPT_weights_v2/*.ckpt` + `SoVITS_weights_v2/*.pth`），阿罗娜还额外有一份**中配**
  （`ALuoNa_cn-*`）。
- 本机已经装好整套推理环境：`D:\\SOFTWARE\\gptsovits\\GPT-SoVITS-v2pro-20250604`，
  自带 python 3.9 + torch 2.0.0+cu118，RTX 4060 Laptop 可用（实测 `cuda.is_available()=True`）。
- 游戏里两个角色说的是**中文**，所以用 `text_lang=zh` + **日配参考音频**做跨语种合成：
  参考音频只提供**音色/韵律**，它自己说的「先生」**不会**出现在生成结果里
  —— 「她们不要喊老师」这条不受影响。

## 台词从哪来

**不在这里抄台词**。先跑：

    godot --headless --path . --script res://scripts/_dump_companion_lines.gd

导出 `_tools/_tmp/companion_lines.json`（数据源是 `arch_terminal.gd` 的 `COMPANIONS`），
再让本脚本读它。这样改了台词不会出现「屏幕上一句、配音另一句」。

## 用法

    cd D:\\SOFTWARE\\gptsovits\\GPT-SoVITS-v2pro-20250604
    runtime\\python.exe <本文件> --lines <...>/companion_lines.json \
        --out <...>/assets/companion_voice [--who arona] [--limit 1]

产物：`<out>/<who>/<open|loop>_<i:02d>.wav`（24 kHz 单声道），
外加 `<out>/manifest.json`（每句时长，探针用）。
"""

import argparse
import json
import os
import sys
import time

GSV_DIR = r"D:\SOFTWARE\gptsovits\GPT-SoVITS-v2pro-20250604"
BD = r"D:\BaiduNetdiskDownload"

# 每个角色的模型 + 参考音频。
#
# ⚠️ 参考音频用**日配**是有意的：日配参考文本是现成的（训练列表里就有），
#    中配那 90 个 wav **没有带文本**，prompt_text 对不上会让韵律崩掉。
#    参考音频只影响音色/韵律，它说的内容不会出现在输出里。
VOICES = {
    "arona": {
        "ckpt": os.path.join(BD, r"阿罗娜\日配数据集制\成品模型\GPT_weights_v2\ALuoNa-e15.ckpt"),
        "pth": os.path.join(BD, r"阿罗娜\日配数据集制\成品模型\SoVITS_weights_v2\ALuoNa_e16_s224.pth"),
        "ref": os.path.join(BD, r"阿罗娜\日配数据集制\参考音频\Arona_Academy_Talk_3.wav"),
        "ref_text": "通常授業！課外授業！自由時間！どれを選びますか？",
        "ref_lang": "ja",
    },
    "plana": {
        "ckpt": os.path.join(BD, r"普拉娜\日配数据集制\成品模型\GPT_weights_v2\Plana-e15.ckpt"),
        "pth": os.path.join(BD, r"普拉娜\日配数据集制\成品模型\SoVITS_weights_v2\Plana_e16_s208.pth"),
        "ref": os.path.join(BD, r"普拉娜\日配数据集制\参考音频\New_NP0035_Work_Talk_4.wav"),
        "ref_text": "混乱。理解できない行動です。つつかないでください。故障します。",
        "ref_lang": "ja",
    },
}


def build_tts(voice: dict, device: str, is_half: bool):
    from GPT_SoVITS.TTS_infer_pack.TTS import TTS, TTS_Config

    cfg = dict(TTS_Config.default_configs["v2"])
    cfg["device"] = device
    cfg["is_half"] = is_half
    # 直接把**微调后的**权重写进配置：`TTS._init_models()` 会拿这两个路径去 load，
    # 这样就省掉「先加载底模、再 init_*_weights 换掉」那一轮无谓的显存峰值。
    cfg["t2s_weights_path"] = voice["ckpt"]
    cfg["vits_weights_path"] = voice["pth"]
    # dict 必须包在 "custom" 键下：TTS_Config 里 `configs_.get("custom", configs_["v2"])`
    # 只认 custom / 版本名，平铺传进去会被默认 v2 顶掉（device 又变回 cpu）。
    return TTS({"custom": cfg})


def synth_one(tts, text: str, voice: dict, speed: float, seed: int):
    import soundfile as sf  # noqa: F401  (api_v2 也用它写盘)

    inputs = {
        "text": text,
        "text_lang": "zh",
        "ref_audio_path": voice["ref"],
        "prompt_text": voice["ref_text"],
        "prompt_lang": voice["ref_lang"],
        "top_k": 15,
        "top_p": 1.0,
        "temperature": 1.0,
        "text_split_method": "cut5",
        "batch_size": 1,
        "speed_factor": speed,
        "seed": seed,
        "parallel_infer": True,
        "repetition_penalty": 1.35,
    }
    sr = 32000
    chunks = []
    for rate, audio in tts.run(inputs):
        sr = rate
        chunks.append(audio)
    if not chunks:
        return sr, None
    import numpy as np

    return sr, np.concatenate(chunks)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lines", required=True, help="companion_lines.json（来自 _dump_companion_lines.gd）")
    ap.add_argument("--out", required=True, help="输出目录（assets/companion_voice）")
    ap.add_argument("--who", default="both", choices=["both", "arona", "plana"])
    ap.add_argument("--limit", type=int, default=0, help="只生成前 N 句（冒烟用）")
    ap.add_argument("--speed", type=float, default=1.0)
    ap.add_argument("--device", default="cuda")
    ap.add_argument("--no-half", action="store_true")
    ap.add_argument("--seed", type=int, default=20261113)
    args = ap.parse_args()

    # 必须在 import GPT_SoVITS 之前把工作目录切过去：TTS.py 顶部是
    # `now_dir = os.getcwd(); sys.path.append(now_dir)`，而且底模路径是相对路径。
    os.chdir(GSV_DIR)
    if GSV_DIR not in sys.path:
        sys.path.insert(0, GSV_DIR)

    import soundfile as sf

    with open(args.lines, "r", encoding="utf-8") as f:
        lines = json.load(f)

    whos = ["arona", "plana"] if args.who == "both" else [args.who]
    manifest = {}
    for who in whos:
        voice = VOICES[who]
        for key in ("ckpt", "pth", "ref"):
            if not os.path.exists(voice[key]):
                raise SystemExit("缺文件：%s" % voice[key])
        out_dir = os.path.join(args.out, who)
        os.makedirs(out_dir, exist_ok=True)

        print("\n══════ %s ══════" % who.upper(), flush=True)
        print("  GPT   %s" % os.path.basename(voice["ckpt"]))
        print("  SoVITS %s" % os.path.basename(voice["pth"]))
        print("  参考   %s" % os.path.basename(voice["ref"]))
        t0 = time.time()
        tts = build_tts(voice, args.device, not args.no_half)
        print("  模型已加载（%.1f s）" % (time.time() - t0), flush=True)

        manifest[who] = {}
        count = 0
        for group in ("open", "loop"):
            texts = lines[who][group]
            manifest[who][group] = []
            for i, text in enumerate(texts):
                if args.limit and count >= args.limit:
                    break
                count += 1
                name = "%s_%02d.wav" % (group, i)
                path = os.path.join(out_dir, name)
                t1 = time.time()
                sr, audio = synth_one(tts, text, voice, args.speed, args.seed + i)
                if audio is None:
                    print("  !! 空音频：%s" % text, flush=True)
                    manifest[who][group].append(0.0)
                    continue
                sf.write(path, audio, sr)
                dur = round(len(audio) / float(sr), 3)
                manifest[who][group].append(dur)
                print("  [%2d] %-12s %5.2f s  (%.1f s/%s) %s"
                      % (count, name, dur, time.time() - t1, "%.1f" % (time.time() - t1),
                         text[:24]), flush=True)
            if args.limit and count >= args.limit:
                break
        # 换人前把模型放掉，8 GB 显存塞不下两套
        del tts
        try:
            import torch
            torch.cuda.empty_cache()
        except Exception:
            pass

    os.makedirs(args.out, exist_ok=True)
    mpath = os.path.join(args.out, "manifest.json")
    with open(mpath, "w", encoding="utf-8") as f:
        json.dump({"speed": args.speed, "seed": args.seed, "lines": manifest},
                  f, ensure_ascii=False, indent=2)
    total = sum(len(v) for g in manifest.values() for v in g.values())
    print("\n完成：%d 句 → %s" % (total, args.out))
    print("清单：%s" % mpath)
    return 0


if __name__ == "__main__":
    sys.exit(main())
