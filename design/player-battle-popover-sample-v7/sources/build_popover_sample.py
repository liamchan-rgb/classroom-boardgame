from pathlib import Path
import json,asyncio,re
from PIL import Image
from playwright.async_api import async_playwright
R=Path(__file__).resolve().parents[1]
# Byte-preserved v5 source defines only art, existing layout pieces and material CSS.
# Run its prefix in this version's scope; no old deliverable is written.
exec((R/'sources/v5-layout-reference.py.txt').read_text().split("doc=")[0])
manifest=json.loads((R/'asset-manifest.json').read_text());manifest['status']='battle-first-anchored-popover-awaiting-review';(R/'asset-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')

def diamonds(remaining=1,maximum=8):
    return '<span class="ap-slots" role="img" aria-label="行动力 '+str(remaining)+'，上限 '+str(maximum)+'">'+''.join('<svg viewBox="0 0 20 24" class="ap-diamond '+('filled' if i<remaining else 'empty')+'"><path d="M10 2 L18 12 L10 22 L2 12Z"/></svg>' for i in range(maximum))+'</span>'
def actor_v6(i,x,y):
    id,asset,hp,state=units[i];current,maximum=map(int,hp.split('/'));percent=current/maximum*100
    im=Image.open(R/'assets'/(asset+'.png'));foot=im.getchannel('A').getbbox()[3]/im.height
    return f'<div class="actor {state}" style="left:{x}px;top:calc(var(--stage-height)*{y});--foot:{foot}" tabindex="0" aria-label="{id} 生命{hp}，护盾0" title="{id} · 生命 {hp} · 护盾0">'+pic(asset,'body')+f'<span class="unit-id">{id}</span>'+('<span class="cross">×</span>' if state=='down' else '<span class="next-mark">◷</span>' if state=='next' else '')+f'<div class="health-bar" role="progressbar" aria-label="{id}生命" aria-valuenow="{current}" aria-valuemax="{maximum}" aria-valuemin="0"><span style="width:{percent}%"></span></div></div>'
fight=''.join(pic('battle_'+k,'scene '+k) for k in ['back','mid','ground','front'])
for i,(x,y) in enumerate([(80,.17),(300,.17),(520,.17),(740,.17),(110,.60),(350,.60),(590,.60),(980,.12),(980,.40),(980,.68)]):fight+=actor_v6(i,x,y)

details=[
 dict(id='runeSlash',kind='skill',name='符文斩',cost='2行动点',target='单敌 · 射程1 · 战斗 · 余2次',effect='目标伤害2D12+2；自身恢复4生命、护盾4',reason='行动点不足',available=False),
 dict(id='runeWard',kind='skill',name='符文庇护',cost='2行动点',target='节点全部队友 · 射程1 · 余2次',effect='目标恢复8生命、护盾6',reason='行动点不足',available=False),
 dict(id='battleRune',kind='skill',name='战斗符文',cost='1行动点',target='节点全部队友 · 射程1 · 余2次',effect='目标护盾4；伤害+3，持续2轮',reason='可用',available=True),
 dict(id='smallPotion',kind='item',name='小治疗药水',cost='1行动点',quantity=2,asset='item_small_potion',target='自己/队友 · 射程1 · 持有2',effect='恢复6生命；普通治疗不能救起倒地目标',reason='可用',available=True),
 dict(id='shieldPotion',kind='item',name='护盾药水',cost='1行动点',quantity=1,asset='item_shield_potion',target='自己/队友 · 射程1 · 持有1',effect='护盾8，与旧护盾取较高值',reason='可用',available=True),
 dict(id='revivalStone',kind='item',name='复活石',cost='2行动点',quantity=1,asset='item_revival_stone',target='同节点倒地队友 · 持有1',effect='复活半最大生命；当轮不能行动，下轮按原队列行动',reason='行动点不足',available=False),
]
def entry(d):
    art=pic(d['asset']) if d['kind']=='item' else '<span class="skill-glyph">✧</span>'
    qty='<span class="quantity">×'+str(d['quantity'])+'</span>' if d['kind']=='item' else ''
    return '<button class="entry liquid '+d['kind']+'" type="button" data-id="'+d['id']+'" aria-label="查看'+d['name']+'详情" aria-expanded="false">'+art+'<span>'+d['name']+'</span>'+qty+'</button>'
skills=''.join(entry(d) for d in details if d['kind']=='skill');items=''.join(entry(d) for d in details if d['kind']=='item')
mapart='<svg class="roads" viewBox="0 0 511.2 600"><path class="public-roads"/><path class="centerline"/><ellipse cx="320" cy="278" rx="150" ry="142"/></svg>'
mapart+=pic('node_start','node start-node')+pic('node_combat','node combat-node')
mapart+='<span class="node-label camp">1 · 营地</span><span class="node-label junction">2 · 森林路口</span>'
mapspots=[(240,0),(304,0),(368,0),(432,0),(262,84),(326,84),(390,84),(270,168),(334,168),(398,168)]
for i,(x,dy) in enumerate(mapspots):
    id,n,_,state=units[i]
    mapart+=f'<div class="map-unit {state}" style="left:{x}px;top:calc(var(--stage-height)*.27 + {dy}px)">'+pic(n)+f'<span>{id}</span>'+('<b>×</b>' if state=='down' else '<b>◷</b>' if state=='next' else '')+'</div>'
css+='''
.shell{grid-template-rows:88px 600px 100px 128px}.heading{width:auto;flex:1}.header .resources{display:none}.main{grid-template-columns:960px 744px}.map-foot{display:none}.junction{left:744px;top:362px}.camp{top:330px}.actor{height:174px}.actor .body{width:124px;height:130px;left:1px}.actor:before{top:116px;left:25px;width:76px}.actor .unit-id{top:130px;left:43px}.health-bar{position:absolute;left:11px;top:161px;width:104px;height:9px;border-radius:6px;background:#6b4a4a1f;border:1px solid #ffffffc7;overflow:hidden;box-shadow:inset 0 1px 2px #6a33331c}.health-bar span{display:block;height:100%;border-radius:5px;background:linear-gradient(90deg,#bd7774,#dc9a91)}.actor.active:after{top:117px}.actor .cross,.actor .next-mark{top:130px}.actor.enemy .body{width:108px;height:108px;left:9px}.actor.enemy:before{top:91px}.actor.enemy .unit-id{top:105px}.actor.enemy .health-bar{top:137px}.actor:focus-visible{outline:2px solid #4a8295;outline-offset:2px;border-radius:15px}.dock{display:flex;gap:24px;align-items:center;padding:14px 24px;overflow:visible}.summary{flex:0 0 390px;display:flex;flex-direction:column;gap:12px;border-right:1px solid #ffffffc0;padding-right:20px}.summary-resources{display:flex;align-items:center;gap:20px;font-size:25px;white-space:nowrap}.summary-ap{display:flex;align-items:center;gap:16px;font-size:24px;color:#53717b}.ap-slots{display:inline-flex;align-items:center;gap:6px}.ap-diamond{width:20px;height:24px;display:block}.ap-diamond path{stroke:#b79036;stroke-width:1.6}.ap-diamond.filled path{fill:#edca58}.ap-diamond.empty path{fill:none}.entry-group{display:flex;flex-direction:column;gap:9px;min-width:0}.entry-group.skills-group{flex:1}.entry-group.items-group{flex:1.47}.group-title{font-size:24px;color:#577581;line-height:27px}.entries{display:flex;gap:12px}.entry{font-family:inherit;min-height:54px;min-width:0;flex:1;border-radius:17px;padding:7px 13px;display:flex;gap:8px;justify-content:center;align-items:center;cursor:pointer;font-size:26px;white-space:nowrap}.entry img{height:34px;width:34px;object-fit:contain}.entry.item{font-size:24px}.entry .quantity{font-size:22px;color:#557382}.skill-glyph{color:#74929a;font-size:24px}.entry.inspected{box-shadow:inset 1px 2px 2px #ffffffed,inset -1px -2px 4px #60838d24,0 0 0 2px #79a4b760,0 6px 18px #173f501c}.inspector{position:absolute;left:24px;right:24px;bottom:20px;min-height:160px;z-index:30;padding:15px 22px;border-radius:22px;background:linear-gradient(130deg,#ffffffea,#f1f8f4d9);backdrop-filter:blur(26px) saturate(1.25);border:1px solid white;box-shadow:0 8px 24px #234c6126}.inspector[hidden]{display:none}.inspect-head{display:flex;align-items:center;gap:20px;line-height:34px;margin-bottom:2px}.inspect-head strong{font-size:29px}.inspect-cost{font-size:24px;color:#547183}.inspect-target,.inspect-effect{font-size:24px;line-height:31px;padding-right:110px}.inspect-reason{font-size:24px;color:#9d6659;line-height:30px}.inspect-reason.available{color:#367c83}.close-detail{position:absolute;right:16px;top:16px;width:44px;height:44px;border-radius:50%;font-size:25px;display:grid;place-items:center;cursor:pointer}.pin-note{position:absolute;right:24px;bottom:18px;font-size:22px;color:#5f7c89}.timer{margin-left:auto}.inspector .inspect-head{padding-right:80px}.scene.front{z-index:4}.actor .unit-hud{display:none}
'''
css+='''
.entry{height:54px;min-height:54px;background:linear-gradient(145deg,#ffffff78,#f7fdff28 46%,#edf6f744);border:1px solid #ffffffeb;backdrop-filter:blur(10px) saturate(1.4);box-shadow:inset 1px 2px 2px #ffffffed,inset -1px -2px 4px #60838d24,0 6px 18px #173f501c}.actor:before{top:110px}.actor .unit-id{top:118px}.health-bar{top:148px;height:12px}.actor.active:after{top:111px}.actor .cross,.actor .next-mark{top:118px}.actor.enemy:before{top:88px}.actor.enemy .unit-id{top:92px}.actor.enemy .health-bar{top:120px}
'''
css+='''
.shell{--stage-height:600px}.shell.inspecting{--stage-height:460px;grid-template-rows:88px 460px 100px 140px 128px;row-gap:14px}.dock{grid-row:4}.shell.inspecting .dock{grid-row:5}.shell.inspecting .group-title{visibility:hidden}.main{grid-template-columns:minmax(0,3fr) minmax(0,7fr)}.roads{width:100%;height:100%}.node.start-node{left:16px;top:calc(var(--stage-height)*.4 - 64px);width:128px;height:128px}.node.combat-node{left:240px;top:calc(var(--stage-height)*.4 - 80px);width:160px;height:160px}.camp{left:20px;top:calc(var(--stage-height)*.4 + 105px)}.junction{left:232px;top:calc(var(--stage-height)*.27 + 264px)}.map-unit{width:64px;height:82px}.map-unit img{width:64px;height:64px}.map-unit span{font-size:24px;line-height:27px;box-shadow:none}.map-unit.active:before{left:26px}.map-unit b{right:-1px;font-size:25px}.actor{--sprite:calc(var(--stage-height)*.28);width:180px;height:210px}.actor.enemy{--sprite:calc(var(--stage-height)*.2)}.actor{height:calc(var(--sprite)*var(--foot) + 58px)}.actor .body,.actor.enemy .body{width:var(--sprite);height:var(--sprite);left:calc((180px - var(--sprite))/2)}.actor:before,.actor.enemy:before{top:calc(var(--sprite)*var(--foot));left:38px;width:104px;height:12px}.actor .unit-id,.actor.enemy .unit-id{top:calc(var(--sprite)*var(--foot) + 5px);left:0;width:180px;font-size:26px;line-height:29px}.actor .health-bar,.actor.enemy .health-bar{top:calc(var(--sprite)*var(--foot) + 38px);left:26px;width:128px;height:12px}.actor .cross,.actor .next-mark{top:calc(var(--sprite)*var(--foot) + 4px);right:12px}.actor.active:after{top:calc(var(--sprite)*var(--foot) + 1px);left:32px;width:116px;height:15px}.inspector{position:fixed;left:0;right:auto;top:0;bottom:auto;width:720px;min-height:160px;margin:0;z-index:100;background:linear-gradient(130deg,#ffffffdc,#f1f8f4cb);backdrop-filter:blur(28px) saturate(1.25);overflow:visible}.inspector::after{content:"";position:absolute;bottom:-12px;left:var(--arrow-left,340px);width:22px;height:13px;background:#f5faf5f2;clip-path:polygon(0 0,100% 0,50% 100%);filter:drop-shadow(0 2px 2px #31576822)}.inspector .inspect-target,.inspector .inspect-effect{padding-right:90px}.inspector .pin-note{font-size:22px}.battle-heading{font-size:30px}
'''
script='''
const entries=ENTRIES;let pinned=null;let current=null;
const panel=document.querySelector('.inspector');
document.body.appendChild(panel);
const buttons=[...document.querySelectorAll('.entry')];
const shell=document.querySelector('.shell');
function layoutMap(){const map=document.querySelector('.map'),h=map.getBoundingClientRect().height,y=h*.4,s=map.querySelector('.roads');s.setAttribute('viewBox',`0 0 ${map.clientWidth} ${h}`);const d=`M80 ${y} H320 L610 ${y-270} M320 ${y} L610 ${y+270}`;s.querySelector('.public-roads').setAttribute('d',d);s.querySelector('.centerline').setAttribute('d',d);s.querySelector('ellipse').setAttribute('cy',y+38)}
function place(){if(!current||panel.hidden)return;const b=buttons.find(b=>b.dataset.id===current).getBoundingClientRect(),safeLeft=document.querySelector('.summary').getBoundingClientRect().right+24,w=panel.getBoundingClientRect().width,x=Math.max(safeLeft,Math.min(innerWidth-96-w,b.x+b.width/2-w/2)),bottom=b.top-12;panel.style.left=x+'px';panel.style.top=(bottom-panel.getBoundingClientRect().height)+'px';panel.style.setProperty('--arrow-left',Math.max(20,Math.min(w-42,b.x+b.width/2-x-11))+'px');layoutMap()}
function show(id,pin=false){const d=entries.find(e=>e.id===id);if(!d)return;current=id;if(pin)pinned=id;
 shell.classList.add('inspecting');
 panel.hidden=false;panel.querySelector('strong').textContent=d.name;panel.querySelector('.inspect-cost').textContent=d.cost;panel.querySelector('.inspect-target').textContent=d.target;panel.querySelector('.inspect-effect').textContent=d.effect;const reason=panel.querySelector('.inspect-reason');reason.textContent=d.reason;reason.classList.toggle('available',d.available);panel.querySelector('.pin-note').textContent=pinned?'已固定查看':'查看详情';
 buttons.forEach(b=>{b.classList.toggle('inspected',b.dataset.id===id);b.setAttribute('aria-expanded',b.dataset.id===id?'true':'false')});
 place();
}
function close(){pinned=null;current=null;panel.hidden=true;shell.classList.remove('inspecting');buttons.forEach(b=>{b.classList.remove('inspected');b.setAttribute('aria-expanded','false')});layoutMap()}
for(const b of buttons){b.addEventListener('pointerenter',()=>{if(!pinned)show(b.dataset.id)});b.addEventListener('focus',()=>{if(!pinned)show(b.dataset.id)});b.addEventListener('pointerleave',()=>{if(!pinned&&document.activeElement!==b)close()});b.addEventListener('blur',()=>{if(!pinned)close()});b.addEventListener('click',()=>{if(pinned===b.dataset.id)close();else show(b.dataset.id,true)})}
document.querySelector('.close-detail').addEventListener('click',close);
document.addEventListener('keydown',e=>{if(e.key==='Escape'){close();document.activeElement?.blur()}});
document.addEventListener('pointerdown',e=>{if(pinned&&!e.target.closest('.entry,.inspector'))close()});
window.addEventListener('resize',()=>{layoutMap();place()});layoutMap();
window.sample={show,close,place,get pinned(){return pinned},get current(){return current},inspectionOnly:true,engineCalls:0};
'''.replace('ENTRIES',json.dumps(details,ensure_ascii=False))
doc='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>晴空学园 · 玩家战斗按需详情 v6</title><style>'+css+'</style><body><div class="ambient" style="--environment:url('+src('battle_back')+')"></div><main class="shell"><header class="header frost"><div class="seal liquid">'+icon('sun')+'</div><div class="heading"><div class="eyebrow">PVE · 玩家回合</div><div class="name">晨曦森林守护者小队长安然</div></div><div class="timer"><span class="round">第1轮 · 已暂停</span><strong>剩余 17 秒</strong></div></header><div class="main"><section class="map frost"><div class="panel-heading">森林路口 · 地图</div><div class="map-actions">'+''.join('<button class="liquid" aria-label="'+label+'">'+icon(n)+'</button>' for n,label in [('focus','回到行动者'),('overview','地图总览'),('minus','缩小'),('plus','放大')])+'</div>'+mapart+'<aside class="inspector" hidden aria-live="polite" aria-label="当前条目详情"><div class="inspect-head"><strong></strong><span class="inspect-cost"></span></div><div class="inspect-target"></div><div class="inspect-effect"></div><div class="inspect-reason"></div><button class="close-detail liquid" aria-label="关闭详情">×</button><span class="pin-note"></span></aside></section><section class="battle frost">'+fight+'<div class="battle-heading">森林路口 · 同节点战斗</div></section></div><section class="track frost"><div class="track-line"></div><div class="queue">'+q+'</div></section><section class="dock frost"><div class="summary"><div class="summary-resources"><span class="team">● 蓝队</span><span>金币 0</span><span>积分 0</span></div><div class="summary-ap"><span>行动力</span>'+diamonds()+'</div></div><div class="entry-group skills-group"><div class="group-title">技能</div><div class="entries">'+skills+'</div></div><div class="entry-group items-group"><div class="group-title">个人物品</div><div class="entries">'+items+'</div></div></section></main><script>'+script+'</script></body></html>'
doc=doc.replace('玩家战斗按需详情 v6','玩家战斗7:3与毛玻璃浮窗 v7').replace('<div class="panel-heading">森林路口 · 地图</div>','<div class="panel-heading">地图</div>')
(R/'previews/player_battle_popover_16x9.html').write_text(doc)
(R/'sources/materials.css').write_text(css.rstrip()+'\n')
(R/'sources/display-fixture.json').write_text(json.dumps(dict(status='design-fixture-not-engine-receipt',actor='P3',currentAP=1,maximumAP=8,units=units,details=details,noGameWrites=True),ensure_ascii=False,indent=2)+'\n')
async def export():
    async with async_playwright() as p:
        browser=await p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox']);page=await browser.new_page(viewport={'width':1920,'height':1080},device_scale_factor=1)
        await page.route('**/*',lambda route:route.abort())
        await page.set_content(doc);await page.evaluate('document.fonts.ready')
        assert await page.locator('.inspector').is_hidden()
        async def check_layout(opened=False):
            geometry=await page.evaluate('''()=>{const r=s=>{let b=document.querySelector(s).getBoundingClientRect();return {x:b.x,y:b.y,w:b.width,h:b.height,right:b.right,bottom:b.bottom}};const m=r('.map'),f=r('.battle');return {map:m,battle:f,ratio:f.w/m.w,track:r('.track'),panel:r('.inspector'),card:sample.current?r('[data-id="'+sample.current+'"]'):null,summary:r('.summary'),hpInside:[...document.querySelectorAll('.battle .body,.battle .health-bar')].every(e=>{let b=e.getBoundingClientRect();return b.left>=f.x&&b.right<=f.right&&b.top>=f.y&&b.bottom<=f.bottom})}}''')
            assert abs(geometry['ratio']-7/3)<.002,geometry
            assert geometry['hpInside'],geometry
            if opened:
                p,c,t=geometry['panel'],geometry['card'],geometry['track']
                assert abs(p['bottom']-(c['y']-12))<1.5,geometry
                assert p['y']>=t['bottom'] and p['x']>=geometry['summary']['right']+23,geometry
                assert p['x']>=96 and p['right']<=1824.5,geometry
            return geometry
        default_geometry=await check_layout()
        assert await page.locator('.health-bar').count()==10
        assert await page.locator('.ap-diamond.filled').count()==1
        assert await page.locator('.ap-diamond.empty').count()==7
        assert await page.locator('.header .resources').count()==0
        assert await page.evaluate("[...document.querySelectorAll('.entry')].every(e=>{const b=e.getBoundingClientRect(),d=document.querySelector('.dock').getBoundingClientRect();return b.height===54&&b.top>=d.top&&b.bottom<=d.bottom})")
        assert await page.evaluate("[...document.querySelectorAll('.ap-diamond.empty path')].every(p=>getComputedStyle(p).fill==='none')")
        await page.screenshot(path=str(R/'previews/player_battle_popover_default_16x9.png'))
        await page.locator('[data-id="runeSlash"]').hover();assert await page.locator('.inspector').is_visible();assert await page.locator('.inspect-effect').text_content()=='目标伤害2D12+2；自身恢复4生命、护盾4'
        skill_geometry=await check_layout(True)
        await page.screenshot(path=str(R/'previews/player_battle_popover_skill_16x9.png'))
        await page.mouse.move(40,40);assert await page.locator('.inspector').is_hidden()
        await page.locator('[data-id="smallPotion"]').focus();assert await page.locator('.inspector strong').text_content()=='小治疗药水'
        await page.locator('[data-id="revivalStone"]').click();await page.mouse.move(40,40);assert await page.locator('.inspector').is_visible();assert await page.evaluate('sample.pinned')=='revivalStone'
        item_geometry=await check_layout(True)
        await page.screenshot(path=str(R/'previews/player_battle_popover_item_16x9.png'))
        await page.keyboard.press('Escape');assert await page.locator('.inspector').is_hidden()
        await page.locator('[data-id="battleRune"]').click();await page.locator('[data-id="battleRune"]').click();assert await page.locator('.inspector').is_hidden()
        await page.locator('[data-id="smallPotion"]').click();await page.mouse.click(40,40);assert await page.locator('.inspector').is_hidden()
        for detail in details:
            await page.evaluate('(id)=>sample.show(id,true)',detail['id']);await check_layout(True)
        await page.evaluate('sample.close()')
        report=await page.evaluate('''()=>({canvas:[innerWidth,innerHeight],queueUnits:document.querySelectorAll('.queue-unit').length,healthBars:document.querySelectorAll('.health-bar').length,visibleAPFilled:document.querySelectorAll('.ap-diamond.filled').length,visibleAPEmpty:document.querySelectorAll('.ap-diamond.empty').length,engineCalls:sample.engineCalls,overflow:[...document.querySelectorAll('.entry,.summary-resources,.name')].filter(e=>e.scrollWidth>e.clientWidth+1).map(e=>e.className)})''')
        assert not report['overflow'],report
        (R/'validation.json').write_text(json.dumps(dict(status='pass',browserOnly=True,nativeVerified=False,artApproved=False,hover=True,keyboardFocus=True,clickToPin=True,escapeToClose=True,clickAgainCloses=True,outsideClickCloses=True,offlineRequestsBlocked=True,battleToMapRatio='7:3 excluding the 24px gutter',popoverAnchorsChecked=6,defaultGeometry=default_geometry,skillGeometry=skill_geometry,itemGeometry=item_geometry,**report),ensure_ascii=False,indent=2)+'\n');await browser.close()
asyncio.run(export());print('Exported default, skill-hover, item-click previews; offline focus/click/escape checks passed.')
