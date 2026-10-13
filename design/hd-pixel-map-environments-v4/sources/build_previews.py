from pathlib import Path
import asyncio,base64,json
from playwright.async_api import async_playwright
R=Path(__file__).resolve().parents[1]
style='html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#173846}.scene{position:absolute;inset:0;background-position:center;background-size:cover;image-rendering:pixelated}'
doc='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>雪地/火山地图资源预览</title><style>'+style+'</style><body><div class="scene"></div><script>const type=new URLSearchParams(location.search).get("scene")==="volcano"?"volcano":"snow";document.querySelector(".scene").style.backgroundImage="url(../assets/map_"+type+"_environment.png)";</script></body></html>'
(R/'previews/index.html').write_text(doc+'\n')
async def export():
    evidence=[]
    async with async_playwright() as p:
        b=await p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
        for name in ['snow','volcano']:
            url='data:image/png;base64,'+base64.b64encode((R/'assets'/f'map_{name}_environment.png').read_bytes()).decode()
            for ratio,w,h in [('16x9',1920,1080),('4x3',1440,1080)]:
                page=await b.new_page(viewport={'width':w,'height':h},device_scale_factor=1)
                await page.route('http**/*',lambda r:r.abort())
                await page.set_content('<html><style>'+style+'</style><div class="scene" style="background-image:url('+url+')"></div></html>')
                await page.wait_for_timeout(100);await page.screenshot(path=str(R/'previews'/f'{name}_{ratio}.png'))
                evidence.append({'scene':name,'aspect':ratio,'width':w,'height':h,'fit':'uniform cover','offline':True})
                await page.close()
        await b.close()
    (R/'evidence.json').write_text(json.dumps({'status':'pass','previews':evidence,'limits':'static decorative background only; not native integration or layered scene validation'},indent=2)+'\n')
asyncio.run(export())
