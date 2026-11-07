"""芹香傲娇参考测试：同一句「你配电脑吗？」用 Growup_1 的傲娇参考生成 5 版。"""
import json
import os
import urllib.parse
import urllib.request

API = "http://127.0.0.1:9880"
OUT = r"C:/Users/WY157/Desktop/GODOT/_arisu_learn/story/voice/_audition/shop"
os.makedirs(OUT, exist_ok=True)

def get(path, **params):
    with urllib.request.urlopen(API + path + "?" + urllib.parse.urlencode(params), timeout=300) as r:
        return r.read().decode("utf-8", "replace")

def tts(payload):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(API + "/tts", data=data,
                                 headers={"Content-Type": "application/json; charset=utf-8"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()

print(get("/set_gpt_weights", weights_path="D:/gptsovits_models/QinXiang/gpt.ckpt"))
print(get("/set_sovits_weights", weights_path="D:/gptsovits_models/QinXiang/sovits.pth"))
takes = [
    (101, 1.10, 1.02), (202, 1.00, 1.00), (303, 1.05, 1.05),
    (404, 0.95, 0.98), (505, 1.15, 1.03),
]
for i, (seed, temp, speed) in enumerate(takes, 1):
    wav = tts({
        "text": "你配电脑吗？", "text_lang": "zh",
        "ref_audio_path": "D:/gptsovits_models/QinXiang/ref_tsun.wav",
        "prompt_text": "べ、別に、先生のために努力したわけじゃないからぁ！",
        "prompt_lang": "ja", "text_split_method": "cut5",
        "batch_size": 1, "media_type": "wav", "streaming_mode": False,
        "parallel_infer": False, "seed": seed, "temperature": temp,
        "speed_factor": speed, "top_k": 20, "top_p": 1.0,
    })
    p = os.path.join(OUT, "serika_01_tsun_v%d.wav" % i)
    open(p, "wb").write(wav)
    print("WROTE", p, len(wav))
