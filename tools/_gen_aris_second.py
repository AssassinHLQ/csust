"""生成「就这套了！」三版，准备和正版『邦邦咔邦』拼起来。"""
import json
import os
import urllib.parse
import urllib.request

API = "http://127.0.0.1:9880"
OUT = r"C:/Users/WY157/Desktop/GODOT/_arisu_learn/_tmp_asr"
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

print(get("/set_gpt_weights", weights_path="D:/gptsovits_models/AiLiSi/gpt.ckpt"))
print(get("/set_sovits_weights", weights_path="D:/gptsovits_models/AiLiSi/sovits.pth"))
for i, (seed, temp, speed) in enumerate([(101, 1.0, 1.0), (202, 0.9, 1.0), (303, 1.1, 1.03)], 1):
    wav = tts({
        "text": "就这套了！", "text_lang": "zh",
        "ref_audio_path": "D:/gptsovits_models/AiLiSi/ref.wav",
        "prompt_text": "先生、急いでください！イベントですよ、イベント！",
        "prompt_lang": "ja", "text_split_method": "cut5",
        "batch_size": 1, "media_type": "wav", "streaming_mode": False,
        "parallel_infer": False, "seed": seed, "temperature": temp,
        "speed_factor": speed,
    })
    p = os.path.join(OUT, "second_v%d.wav" % i)
    open(p, "wb").write(wav)
    print("WROTE", p, len(wav))
