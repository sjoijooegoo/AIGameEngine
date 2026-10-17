"""Make a frame-accurate review player, contact sheet and slow-motion WebP from Godot captures."""
import argparse
import html
import json
from pathlib import Path

from PIL import Image, ImageDraw


def build(sequence_path: Path, speed=1.0):
    if not 0.05 <= speed <= 4:
        raise ValueError("Playback speed must be 0.05..4")
    sequence_path = sequence_path.resolve()
    data = json.loads(sequence_path.read_text(encoding="utf-8"))
    frames = data["frames"]
    if not frames or len(frames) > 120:
        raise ValueError("Expected 1..120 frames")
    images = []
    for frame in frames:
        path = Path(frame["path"]).resolve()
        if path.parent != sequence_path.parent:
            raise ValueError("Frame must belong to the same session")
        with Image.open(path) as image:
            images.append(image.convert("RGB"))
    if len({im.size for im in images}) != 1:
        raise ValueError("Frame dimensions changed during capture")
    base = sequence_path.parent / data["name"]
    duration = round(1000 / data["fps"] / speed)
    webp = base.with_suffix(".webp")
    images[0].save(webp, save_all=True, append_images=images[1:], duration=duration, loop=0, lossless=True)
    width, height = images[0].size
    thumb_w, thumb_h = 320, round(height * 320 / width)
    stride = max(1, (len(images) + 19) // 20)
    selected = list(range(0, len(images), stride))
    sheet = Image.new("RGB", (thumb_w * 4, ((len(selected) + 3) // 4) * (thumb_h + 28)), "#edf1f4")
    draw = ImageDraw.Draw(sheet)
    for k, index in enumerate(selected):
        x, y = (k % 4) * thumb_w, (k // 4) * (thumb_h + 28)
        sheet.paste(images[index].resize((thumb_w, thumb_h)), (x, y))
        draw.text((x + 5, y + thumb_h + 5), f"Frame {index} / t={frames[index]['simulation_time']:.3f}s", fill="#183244")
    contact = base.with_suffix(".contact.jpg")
    sheet.save(contact)
    records = [{"path": Path(f["path"]).name, "time": f["simulation_time"], "state": f["state"]} for f in frames]
    encoded = json.dumps(records, ensure_ascii=False).replace("<", "\\u003c")
    viewer = base.with_suffix(".html")
    viewer.write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>连续帧检查</title>
<style>body{margin:24px;background:#edf1f4;color:#183244;font:16px/1.5 sans-serif}main{max-width:1280px;margin:auto}img{width:100%;background:#183244}button,select,input{font:inherit;margin:8px;padding:6px}input{width:55%}pre{white-space:pre-wrap;max-height:320px;overflow:auto;background:white;padding:16px}button:focus-visible{outline:3px solid #c39554}</style><main>
<h1>连续帧检查</h1><p>按模拟时间播放；原图和状态保留在同一目录。此回放不包含声音，不是实际帧率测量。</p>
<img id="frame" alt="当前游戏渲染帧"><div><button id="toggle">播放</button><button id="prev">上一帧</button><button id="next">下一帧</button><select id="speed" aria-label="播放速度"><option value="0.25">0.25 倍</option><option value="0.5">0.5 倍</option><option value="1" selected>1 倍</option></select><input id="position" type="range" min="0" value="0" aria-label="帧位置"><span id="label"></span></div><details><summary>当前帧状态</summary><pre id="state"></pre></details>
<script>const frames=''' + encoded + ''',fps=''' + str(data["fps"]) + ''';let index=0,timer=null;const el=id=>document.getElementById(id);el('position').max=frames.length-1;function show(){const f=frames[index];el('frame').src=f.path;el('position').value=index;el('label').textContent=`${index+1}/${frames.length} · ${f.time.toFixed(3)} 秒`;el('state').textContent=JSON.stringify(f.state,null,2);}function stop(){clearInterval(timer);timer=null;el('toggle').textContent='播放';}function play(){stop();el('toggle').textContent='暂停';timer=setInterval(()=>{index=(index+1)%frames.length;show();},1000/fps/Number(el('speed').value));}el('toggle').onclick=()=>timer?stop():play();el('prev').onclick=()=>{stop();index=Math.max(0,index-1);show();};el('next').onclick=()=>{stop();index=Math.min(frames.length-1,index+1);show();};el('position').oninput=e=>{stop();index=Number(e.target.value);show();};el('speed').onchange=()=>{if(timer)play();};show();</script></main></html>''', encoding="utf-8")
    return {"viewer": str(viewer), "animation": str(webp), "contact_sheet": str(contact), "count": len(images), "interval": data["interval"], "simulation_duration": frames[-1]["simulation_time"], "speed": speed}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sequence", type=Path)
    parser.add_argument("--speed", type=float, default=1)
    args = parser.parse_args()
    print(json.dumps(build(args.sequence, args.speed), ensure_ascii=False, indent=2))
