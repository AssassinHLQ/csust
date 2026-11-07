"""芹香 9 句全部用傲娇参考重生成 v1，并直接装到正式文件。"""
import json
import os
import shutil
import urllib.parse
import urllib.request
import wave

API = "http://127.0.0.1:9880"
ROOT = r"C:/Users/WY157/Desktop/GODOT/_arisu_learn"
AUD = os.path.join(ROOT, "story", "voice", "_audition", "shop")
FIN = os.path.join(ROOT, "story", "voice", "shop")

LINES = [
    ("serika_01", "你配电脑吗？"),
    ("serika_02", "老板，看这套配置怎么样？"),
    ("serika_03", "B300，288G显存，八卡一柜——光卡就四十来万一张，整机五百二十万，适合给老师送礼，配您正合适，我也多赚钱。"),
    ("serika_04", "……行吧，那给您换一张单子。"),
    ("serika_05", "八张5090加撕裂者，六十七万——这套才是真适合给木的。"),
    ("serika_06", "……先看看也行，不着急买。"),
    ("serika_07", "好嘞，马上给您拿过来！"),
    ("serika_08", "来，老板确认下是这个地址不？"),
    ("serika_09", "老板慢走！电脑我马上给您安排送货上门！"),
]


def get(path, **params):
    with urllib.request.urlopen(API + path + "?" + urllib.parse.urlencode(params), timeout=300) as r:
        return r.read().decode("utf-8", "replace")


def tts(payload):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(API + "/tts", data=data,
                                 headers={"Content-Type": "application/json; charset=utf-8"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return r.read()


def dur(p):
    w = wave.open(p)
    return w.getnframes() / float(w.getframerate())


os.makedirs(AUD, exist_ok=True)
os.makedirs(FIN, exist_ok=True)
print(get("/set_gpt_weights", weights_path="D:/gptsovits_models/QinXiang/gpt.ckpt"))
print(get("/set_sovits_weights", weights_path="D:/gptsovits_models/QinXiang/sovits.pth"))
for name, text in LINES:
    wav = tts({
        "text": text, "text_lang": "zh",
        "ref_audio_path": "D:/gptsovits_models/QinXiang/ref_tsun.wav",
        "prompt_text": "べ、別に、先生のために努力したわけじゃないからぁ！",
        "prompt_lang": "ja", "text_split_method": "cut5",
        "batch_size": 1, "media_type": "wav", "streaming_mode": False,
        "parallel_infer": False, "seed": 101, "temperature": 1.10,
        "speed_factor": 1.02, "top_k": 20, "top_p": 1.0,
    })
    p = os.path.join(AUD, name + "_tsun_v1.wav")
    open(p, "wb").write(wav)
    shutil.copyfile(p, os.path.join(FIN, name + ".wav"))
    print(name, "%.2fs" % dur(p), len(wav), flush=True)
print("DONE")
