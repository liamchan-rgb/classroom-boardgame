from pathlib import Path
import json, asyncio
from playwright.async_api import async_playwright
ROOT=Path(__file__).resolve().parents[1]
async def main():
    rows=[]
    async with async_playwright() as p:
        browser=await p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
        page=await browser.new_page(device_scale_factor=1)
        for source in sorted((ROOT/'sources').glob('*.svg')):
            await page.set_content('<style>body{margin:0}svg{display:block}</style>'+source.read_text());await page.evaluate('document.fonts.ready')
            size=await page.evaluate('({w:document.querySelector("svg").width.baseVal.value,h:document.querySelector("svg").height.baseVal.value})')
            await page.set_viewport_size({'width':int(size['w']),'height':int(size['h'])})
            await page.screenshot(path=str(ROOT/'previews'/f'{source.stem}.png'))
            texts=await page.evaluate('''() => Array.from(document.querySelectorAll('text')).map(e=>{let b=e.getBBox();let m=e.getCTM();let p=new DOMPoint(b.x,b.y).matrixTransform(m);return {text:e.textContent,x:p.x,y:p.y,w:b.width*m.a,h:b.height*m.d,font:parseFloat(getComputedStyle(e).fontSize)}})''')
            overflow=[t for t in texts if t['x']<0 or t['y']<0 or t['x']+t['w']>size['w']+.1 or t['y']+t['h']>size['h']+.1]
            rows.append({'file':source.name,'canvas':size,'textCount':len(texts),'outsideCanvas':overflow,'texts':texts})
        await browser.close()
    (ROOT/'evidence/text-bounds.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
    print(json.dumps([{'file':r['file'],'outsideCanvas':len(r['outsideCanvas'])} for r in rows],ensure_ascii=False))
asyncio.run(main())
