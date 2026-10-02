"""Portable contact sheets and a small visual report for the asset pipeline."""
import html
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageStat


def preview_report(result, directory, title):
    directory=Path(directory)
    captures=result["captures"]
    sheet=Image.new("RGB",(1280,((len(captures)+1)//2)*390),"#e9eff2")
    draw=ImageDraw.Draw(sheet)
    cards=[]
    for i,item in enumerate(captures):
        with Image.open(item["path"]) as image:
            rgb=image.convert("RGB")
            item["pixel_stddev"] = ImageStat.Stat(rgb).stddev
            rgb.thumbnail((640,360))
            sheet.paste(rgb,((i%2)*640,(i//2)*390))
        draw.text(((i%2)*640+8,(i//2)*390+364),item["view"],fill="#183244")
        cards.append(f'<figure><a href="{html.escape(Path(item["path"]).name)}"><img src="{html.escape(Path(item["path"]).name)}" alt="{html.escape(item["view"])}"></a><figcaption>{html.escape(item["view"])}</figcaption></figure>')
    contact=directory/'contact.png';sheet.save(contact)
    page=directory/'preview.html'
    page.write_text(f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{html.escape(title)}</title><style>body{{background:#e9eff2;color:#183244;font:16px/1.6 "Microsoft YaHei",sans-serif;margin:24px}}main{{max-width:1300px;margin:auto}}h1{{font-size:26px}}section{{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:20px}}figure{{margin:0;background:white}}img{{width:100%;display:block}}figcaption{{padding:12px}}pre{{white-space:pre-wrap;overflow-wrap:anywhere;background:white;padding:20px}}</style><main><h1>{html.escape(title)}</h1><p>实际引擎渲染 / 纹理通道证据。结构检查通过不代表美术质量已获认可。</p><section>{''.join(cards)}</section><details><summary>测量与运行信息</summary><pre>{html.escape(json.dumps(result,ensure_ascii=False,indent=2))}</pre></details></main></html>''',encoding='utf-8')
    return {**result,"contact_sheet":str(contact),"report":str(page)}
