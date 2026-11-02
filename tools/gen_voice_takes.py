"""生成配音候选（每句 5 个版本），供人工挑选。

- 商店 12 句：芹香 9、小桃 2（第 1 句已改成「我超威，配电脑给我配好的啊」）、爱丽丝 1。
- 开场 3 句旁白：用爱丽丝音色。
- 顺序请求、每次间隔 1.5 s、关掉并行推理，尽量不抢正在推流的 GPU。
- 输出：story/voice/_audition/shop|opening/<名字>_v1..5.wav + manifest.json
- 商店每句的 v1 同时复制到 story/voice/shop/<名字>.wav 先顶用；挑好再换。
"""
import json
import os
import shutil
import time
import urllib.parse
import urllib.request
import wave

API = "http://127.0.0.1:9880"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUD = os.path.join(ROOT, "story", "voice", "_audition")
SHOP_FINAL = os.path.join(ROOT, "story", "voice", "shop")

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

SHOP_LINES = {
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

OPENING = [
    ("开场_01", "2067年。世界陷入一场前无古人、后无来者的毁灭性灾难当中。"),
    ("开场_02", "为了拯救长沙理工大学，学生们把老师护在身后，铤而走险，对抗「色彩」。"),
    ("开场_03", "她们集结在最后的基地——画室609，商讨着如何击败敌军。"),
]

TAKES = [
    {"seed": 101, "temperature": 1.00, "speed": 1.00, "top_p": 1.00, "top_k": 15},
    {"seed": 202, "temperature": 0.90, "speed": 0.97, "top_p": 0.95, "top_k": 12},
    {"seed": 303, "temperature": 1.10, "speed": 1.03, "top_p": 1.00, "top_k": 18},
    {"seed": 404, "temperature": 1.00, "speed": 0.95, "top_p": 1.00, "top_k": 15},
    {"seed": 505, "temperature": 0.95, "speed": 1.05, "top_p": 0.98, "top_k": 15},
]


def get(path: str, **params) -> str:
    url = API + path + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=300) as r:
        return r.read().decode("utf-8", "replace")


def tts(payload: dict) -> bytes:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(API + "/tts", data=data,
                                 headers={"Content-Type": "application/json; charset=utf-8"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return r.read()


def duration(path: str) -> float:
    try:
        with wave.open(path) as w:
            return w.getnframes() / float(w.getframerate())
    except Exception:
        return -1.0


def main() -> None:
    os.makedirs(os.path.join(AUD, "shop"), exist_ok=True)
    os.makedirs(os.path.join(AUD, "opening"), exist_ok=True)
    os.makedirs(SHOP_FINAL, exist_ok=True)
    manifest = []
    for who in ("serika", "momoi", "aris"):
        model = MODELS[who]
        print("[takes] 切换 %s" % who, flush=True)
        get("/set_gpt_weights", weights_path=model["gpt"])
        get("/set_sovits_weights", weights_path=model["sovits"])
        for name, text in SHOP_LINES[who]:
            for i, take in enumerate(TAKES, 1):
                payload = {
                    "text": text,
                    "text_lang": "zh",
                    "ref_audio_path": model["ref"],
                    "prompt_text": model["prompt"],
                    "prompt_lang": "ja",
                    "text_split_method": "cut5",
                    "batch_size": 1,
                    "media_type": "wav",
                    "streaming_mode": False,
                    "parallel_infer": False,
                    "seed": take["seed"],
                    "temperature": take["temperature"],
                    "speed_factor": take["speed"],
                    "top_p": take["top_p"],
                    "top_k": take["top_k"],
                }
                wav = tts(payload)
                path = os.path.join(AUD, "shop", "%s_v%d.wav" % (name, i))
                open(path, "wb").write(wav)
                d = duration(path)
                manifest.append({"group": "shop", "who": who, "name": name,
                                 "take": i, "text": text, "file": os.path.relpath(path, ROOT),
                                 "duration": round(d, 3), **take})
                print("[takes] %s v%d %.2fs" % (name, i, d), flush=True)
                if i == 1:
                    shutil.copyfile(path, os.path.join(SHOP_FINAL, name + ".wav"))
                time.sleep(1.5)
    model = MODELS["aris"]
    get("/set_gpt_weights", weights_path=model["gpt"])
    get("/set_sovits_weights", weights_path=model["sovits"])
    for name, text in OPENING:
        for i, take in enumerate(TAKES, 1):
            payload = {
                "text": text,
                "text_lang": "zh",
                "ref_audio_path": model["ref"],
                "prompt_text": model["prompt"],
                "prompt_lang": "ja",
                "text_split_method": "cut5",
                "batch_size": 1,
                "media_type": "wav",
                "streaming_mode": False,
                "parallel_infer": False,
                "seed": take["seed"],
                "temperature": take["temperature"],
                "speed_factor": take["speed"],
                "top_p": take["top_p"],
                "top_k": take["top_k"],
            }
            wav = tts(payload)
            path = os.path.join(AUD, "opening", "%s_v%d.wav" % (name, i))
            open(path, "wb").write(wav)
            d = duration(path)
            manifest.append({"group": "opening", "who": "aris", "name": name,
                             "take": i, "text": text, "file": os.path.relpath(path, ROOT),
                             "duration": round(d, 3), **take})
            print("[takes] %s v%d %.2fs" % (name, i, d), flush=True)
            time.sleep(1.5)
    with open(os.path.join(AUD, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print("[takes] DONE %d 条" % len(manifest), flush=True)


if __name__ == "__main__":
    main()
