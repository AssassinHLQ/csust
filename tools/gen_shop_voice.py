"""用本机 GPT-SoVITS API 生成商店台词语音（桃井 / 爱丽丝 / 芹香）。

前置：api_v2.py 已在 127.0.0.1:9880 运行；权重与参考音频在 D:/gptsovits_models。
输出：story/voice/shop/*.wav（UTF-8 中文，直接由 DialogueBox 的 voice 字段播放）。

用法：
    python tools/gen_shop_voice.py
"""
import json
import os
import struct
import urllib.parse
import urllib.request
import wave

API = "http://127.0.0.1:9880"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "story", "voice", "shop")

MODELS = {
    "serika": {
        "gpt": "D:/gptsovits_models/QinXiang/gpt.ckpt",
        "sovits": "D:/gptsovits_models/QinXiang/sovits.pth",
        "ref": "D:/gptsovits_models/QinXiang/ref.wav",
        "prompt": "なんか……みんな忙しそうね。",
    },
    "momoi": {
        "gpt": "D:/gptsovits_models/Momoi/gpt.ckpt",
        "sovits": "D:/gptsovits_models/Momoi/sovits.pth",
        "ref": "D:/gptsovits_models/Momoi/ref.wav",
        "prompt": "ふっふっふん、見た？先生！今日のメイドモモイ、最高だったでしょ！",
    },
    "aris": {
        "gpt": "D:/gptsovits_models/AiLiSi/gpt.ckpt",
        "sovits": "D:/gptsovits_models/AiLiSi/sovits.pth",
        "ref": "D:/gptsovits_models/AiLiSi/ref.wav",
        "prompt": "先生、急いでください！イベントですよ、イベント！",
    },
}

LINES = {
    "serika": [
        ("serika_01", "你配电脑吗？"),
        ("serika_02", "老板，看这套配置怎么样？"),
        ("serika_03", "B300，288G显存，八卡一柜——光卡就四十来万一张，整机五百二十万，适合给老师送礼，配您正合适，我也多赚钱。"),
        ("serika_04", "……行吧，那给您换一张单子。"),
        ("serika_05", "八张5090加撕裂者，六十七万——这套才是真适合给木的。"),
        ("serika_06", "……先看看也行，不着急买。"),
        ("serika_07", "好嘞，马上给您拿过来！"),
        ("serika_08", "来，老板确认下是这个地址不？"),
        ("serika_09", "老板慢走！电脑我马上给您安排送货上门！"),
    ],
    "momoi": [
        ("momoi_01", "我超威，配电脑给我配好的啊。"),
        ("momoi_02", "要我说，5090的硬核才是王道，你那服务器卡根本就没技巧。"),
    ],
    "aris": [
        ("aris_01", "邦邦卡邦！就这套了！"),
    ],
}


def get(path: str, **params) -> str:
    url = API + path + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=300) as r:
        return r.read().decode("utf-8", "replace")


def tts(payload: dict) -> bytes:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(API + "/tts", data=data,
                                 headers={"Content-Type": "application/json; charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        print("  !! HTTP", e.code, e.read().decode("utf-8", "replace")[:500])
        raise


def duration(path: str) -> float:
    try:
        with wave.open(path) as w:
            return w.getnframes() / float(w.getframerate())
    except Exception:
        return -1.0


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for who, model in MODELS.items():
        print("== %s ==" % who)
        print("  gpt:", get("/set_gpt_weights", weights_path=model["gpt"]).strip())
        print("  vits:", get("/set_sovits_weights", weights_path=model["sovits"]).strip())
        for name, text in LINES[who]:
            wav = tts({
                "text": text,
                "text_lang": "zh",
                "ref_audio_path": model["ref"],
                "prompt_text": model["prompt"],
                "prompt_lang": "ja",
                "text_split_method": "cut5",
                "batch_size": 1,
                "media_type": "wav",
                "streaming_mode": False,
                "speed_factor": 1.0,
                "seed": -1,
                "parallel_infer": True,
            })
            path = os.path.join(OUT, name + ".wav")
            with open(path, "wb") as f:
                f.write(wav)
            if wav[:4] != b"RIFF":
                print("  !! %s 返回不是 wav：%r" % (name, wav[:120]))
            else:
                print("  %-10s %6.2f s  %d B" % (name, duration(path), len(wav)))


if __name__ == "__main__":
    main()
