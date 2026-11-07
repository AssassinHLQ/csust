import glob
import html
import json
import os

root = r"C:/Users/WY157/Desktop/GODOT/_arisu_learn/story/voice/_audition"
manifest = json.load(open(os.path.join(root, "manifest.json"), encoding="utf-8"))
groups = {}
for e in manifest:
    groups.setdefault((e["group"], e["name"]), []).append(e)

rows = []
for (group, name), items in groups.items():
    items.sort(key=lambda x: x["take"])
    text = html.escape(items[0]["text"])
    cells = []
    for it in items:
        src = it["file"].replace("\\", "/")
        src = src.split("_audition/", 1)[-1]
        dur = it["duration"]
        cells.append(
            '<div class="take"><div class="t">v%d · %.2fs · seed %d · T%.2f · x%.2f</div>'
            '<audio controls preload="none" src="%s"></audio>'
            '<label class="pick"><input type="radio" name="pick_%s" value="%d" onchange="updatePicks()"> 选这个</label></div>'
            % (it["take"], dur, it["seed"], it["temperature"], it["speed"], src,
               html.escape(name), it["take"]))
    rows.append(
        '<section><h2>%s <span class="tag">%s</span></h2><p class="txt">%s</p>'
        '<div class="grid">%s</div></section>'
        % (html.escape(name), group, text, "".join(cells)))

extra = []
auth = sorted(glob.glob(os.path.join(root, "aris_01_authentic_v*.wav")))
if auth:
    cells = []
    for path in auth:
        take = os.path.basename(path).split("_v")[-1].split(".")[0]
        cells.append(
            '<div class="take"><div class="t">正版开头 · v%s</div>'
            '<audio controls preload="none" src="%s"></audio>'
            '<label class="pick"><input type="radio" name="pick_aris_01_authentic" value="%s" onchange="updatePicks()"> 选这个</label></div>'
            % (take, os.path.basename(path), take))
    extra.append('<section><h2>aris_01（正版「邦邦咔邦」开头）</h2>'
                 '<p class="txt">前半句来自视频原声，后半句「就这套了」是 TTS；现在是 v1 顶用。</p>'
                 '<div class="grid">%s</div></section>' % "".join(cells))

tsun = sorted(glob.glob(os.path.join(root, "shop", "serika_01_tsun_v*.wav")))
if tsun:
    cells = []
    for path in tsun:
        take = os.path.basename(path).split("_v")[-1].split(".")[0]
        cells.append(
            '<div class="take"><div class="t">傲娇参考 · v%s</div>'
            '<audio controls preload="none" src="shop/%s"></audio>'
            '<label class="pick"><input type="radio" name="pick_serika_01_tsun" value="%s" onchange="updatePicks()"> 选这个</label></div>'
            % (take, os.path.basename(path), take))
    extra.append('<section><h2>serika_01（傲娇参考测试）</h2>'
                 '<p class="txt">同一句「你配电脑吗？」改用「べ、別に、先生のために…」的傲娇参考；v1..v5 对比。</p>'
                 '<div class="grid">%s</div></section>' % "".join(cells))

page = """<!doctype html><meta charset="utf-8"><title>配音候选</title>
<style>
body{background:#15171c;color:#e8e6e1;font:15px/1.5 "Microsoft YaHei",system-ui;margin:24px;max-width:1100px}
h1{font-size:20px;margin:0 0 6px} h2{font-size:16px;margin:22px 0 4px}
.tag{font-size:11px;background:#2b2f3a;color:#9fb4d8;padding:2px 7px;border-radius:9px;vertical-align:2px}
.txt{color:#b9b4aa;margin:2px 0 8px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.take{background:#1e2129;border:1px solid #2c3140;border-radius:9px;padding:8px}
.t{font-size:12px;color:#8f98a8;margin-bottom:4px}
audio{width:100%;height:32px}
.pick{display:flex;align-items:center;gap:6px;margin-top:6px;font-size:12px;color:#c9d3e3}
#bar{position:sticky;top:0;z-index:5;background:#15171cee;border:1px solid #2c3140;border-radius:10px;padding:10px 12px;margin:12px 0;display:flex;gap:12px;align-items:flex-start}
#picks{white-space:pre-wrap;margin:0;color:#a8e6b0;font:12px/1.5 Consolas,monospace;flex:1}
#bar button{background:#2b6cff;color:#fff;border:0;border-radius:7px;padding:7px 12px;cursor:pointer}
</style><h1>商店 / 开场配音候选</h1>
<p class="txt">每句 5 个 take；点「选这个」挑好，最上面的结果会实时汇总，复制给本喵即可。</p>
""" + "\n".join(extra + rows) + "\n"
open(os.path.join(root, "index.html"), "w", encoding="utf-8", newline="\n").write(page)
print("WROTE", os.path.join(root, "index.html"))
