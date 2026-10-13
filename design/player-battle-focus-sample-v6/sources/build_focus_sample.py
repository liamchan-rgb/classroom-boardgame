from pathlib import Path
import json,asyncio,re
from playwright.async_api import async_playwright
R=Path(__file__).resolve().parents[1]
# Byte-preserved v5 source defines only art, existing layout pieces and material CSS.
# Run its prefix in this version's scope; no old deliverable is written.
exec((R/'sources/v5-layout-reference.py.txt').read_text().split("doc=")[0])
manifest=json.loads((R/'asset-manifest.json').read_text());manifest['status']='focus-detail-sample-awaiting-review';(R/'asset-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')

def diamonds(remaining=1,maximum=8):
    return '<span class="ap-slots" role="img" aria-label="行动力 '+str(remaining)+'，上限 '+str(maximum)+'">'+''.join('<svg viewBox="0 0 20 24" class="ap-diamond '+('filled' if i<remaining else 'empty')+'"><path d="M10 2 L18 12 L10 22 L2 12Z"/></svg>' for i in range(maximum))+'</span>'
def actor_v6(i,x,y):
    id,asset,hp,state=units[i];current,maximum=map(int,hp.split('/'));percent=current/maximum*100
    return f'<div class="actor {state}" style="left:{x}px;top:{y}px" tabindex="0" aria-label="{id} 生命{hp}，护盾0" title="{id} · 生命 {hp} · 护盾0">'+pic(asset,'body')+f'<span class="unit-id">{id}</span>'+('<span class="cross">×</span>' if state=='down' else '<span class="next-mark">◷</span>' if state=='next' else '')+f'<div class="health-bar" role="progressbar" aria-label="{id}生命" aria-valuenow="{current}" aria-valuemax="{maximum}" aria-valuemin="0"><span style="width:{percent}%"></span></div></div>'
fight=''.join(pic('battle_'+k,'scene '+k) for k in ['back','mid','ground','front'])
for i,(x,y) in enumerate([(25,109),(155,109),(285,109),(415,109),(25,365),(155,365),(285,365),(563,103),(563,263),(563,423)]):fight+=actor_v6(i,x,y)

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
mapart=re.sub(r'<span class="direction-label.*?</span>','',mapart)
css+='''
.shell{grid-template-rows:88px 600px 100px 128px}.heading{width:auto;flex:1}.header .resources{display:none}.main{grid-template-columns:960px 744px}.map-foot{display:none}.junction{left:744px;top:362px}.camp{top:330px}.actor{height:174px}.actor .body{width:124px;height:130px;left:1px}.actor:before{top:116px;left:25px;width:76px}.actor .unit-id{top:130px;left:43px}.health-bar{position:absolute;left:11px;top:161px;width:104px;height:9px;border-radius:6px;background:#6b4a4a1f;border:1px solid #ffffffc7;overflow:hidden;box-shadow:inset 0 1px 2px #6a33331c}.health-bar span{display:block;height:100%;border-radius:5px;background:linear-gradient(90deg,#bd7774,#dc9a91)}.actor.active:after{top:117px}.actor .cross,.actor .next-mark{top:130px}.actor.enemy .body{width:108px;height:108px;left:9px}.actor.enemy:before{top:91px}.actor.enemy .unit-id{top:105px}.actor.enemy .health-bar{top:137px}.actor:focus-visible{outline:2px solid #4a8295;outline-offset:2px;border-radius:15px}.dock{display:flex;gap:24px;align-items:center;padding:14px 24px;overflow:visible}.summary{flex:0 0 390px;display:flex;flex-direction:column;gap:12px;border-right:1px solid #ffffffc0;padding-right:20px}.summary-resources{display:flex;align-items:center;gap:20px;font-size:25px;white-space:nowrap}.summary-ap{display:flex;align-items:center;gap:16px;font-size:24px;color:#53717b}.ap-slots{display:inline-flex;align-items:center;gap:6px}.ap-diamond{width:20px;height:24px;display:block}.ap-diamond path{stroke:#b79036;stroke-width:1.6}.ap-diamond.filled path{fill:#edca58}.ap-diamond.empty path{fill:none}.entry-group{display:flex;flex-direction:column;gap:9px;min-width:0}.entry-group.skills-group{flex:1}.entry-group.items-group{flex:1.47}.group-title{font-size:24px;color:#577581;line-height:27px}.entries{display:flex;gap:12px}.entry{font-family:inherit;min-height:54px;min-width:0;flex:1;border-radius:17px;padding:7px 13px;display:flex;gap:8px;justify-content:center;align-items:center;cursor:pointer;font-size:26px;white-space:nowrap}.entry img{height:34px;width:34px;object-fit:contain}.entry.item{font-size:24px}.entry .quantity{font-size:22px;color:#557382}.skill-glyph{color:#74929a;font-size:24px}.entry.inspected{box-shadow:inset 1px 2px 2px #ffffffed,inset -1px -2px 4px #60838d24,0 0 0 2px #79a4b760,0 6px 18px #173f501c}.inspector{position:absolute;left:24px;right:24px;bottom:20px;min-height:160px;z-index:30;padding:15px 22px;border-radius:22px;background:linear-gradient(130deg,#ffffffea,#f1f8f4d9);backdrop-filter:blur(26px) saturate(1.25);border:1px solid white;box-shadow:0 8px 24px #234c6126}.inspector[hidden]{display:none}.inspect-head{display:flex;align-items:center;gap:20px;line-height:34px;margin-bottom:2px}.inspect-head strong{font-size:29px}.inspect-cost{font-size:24px;color:#547183}.inspect-target,.inspect-effect{font-size:24px;line-height:31px;padding-right:110px}.inspect-reason{font-size:24px;color:#9d6659;line-height:30px}.inspect-reason.available{color:#367c83}.close-detail{position:absolute;right:16px;top:16px;width:44px;height:44px;border-radius:50%;font-size:25px;display:grid;place-items:center;cursor:pointer}.pin-note{position:absolute;right:24px;bottom:18px;font-size:22px;color:#5f7c89}.timer{margin-left:auto}.inspector .inspect-head{padding-right:80px}.scene.front{z-index:4}.actor .unit-hud{display:none}
'''
css+='''
.entry{height:54px;min-height:54px;background:linear-gradient(145deg,#ffffff78,#f7fdff28 46%,#edf6f744);border:1px solid #ffffffeb;backdrop-filter:blur(10px) saturate(1.4);box-shadow:inset 1px 2px 2px #ffffffed,inset -1px -2px 4px #60838d24,0 6px 18px #173f501c}.actor:before{top:110px}.actor .unit-id{top:118px}.health-bar{top:148px;height:12px}.actor.active:after{top:111px}.actor .cross,.actor .next-mark{top:118px}.actor.enemy:before{top:88px}.actor.enemy .unit-id{top:92px}.actor.enemy .health-bar{top:120px}
'''
script='''
const entries=ENTRIES;let pinned=null;let current=null;
const panel=document.querySelector('.inspector');
const buttons=[...document.querySelectorAll('.entry')];
function show(id,pin=false){const d=entries.find(e=>e.id===id);if(!d)return;current=id;if(pin)pinned=id;
 panel.hidden=false;panel.querySelector('strong').textContent=d.name;panel.querySelector('.inspect-cost').textContent=d.cost;panel.querySelector('.inspect-target').textContent=d.target;panel.querySelector('.inspect-effect').textContent=d.effect;const reason=panel.querySelector('.inspect-reason');reason.textContent=d.reason;reason.classList.toggle('available',d.available);panel.querySelector('.pin-note').textContent=pinned?'已固定查看':'查看详情';
 buttons.forEach(b=>{b.classList.toggle('inspected',b.dataset.id===id);b.setAttribute('aria-expanded',b.dataset.id===id?'true':'false')});
}
function close(){pinned=null;current=null;panel.hidden=true;buttons.forEach(b=>{b.classList.remove('inspected');b.setAttribute('aria-expanded','false')})}
for(const b of buttons){b.addEventListener('pointerenter',()=>{if(!pinned)show(b.dataset.id)});b.addEventListener('focus',()=>{if(!pinned)show(b.dataset.id)});b.addEventListener('pointerleave',()=>{if(!pinned&&document.activeElement!==b)close()});b.addEventListener('blur',()=>{if(!pinned)close()});b.addEventListener('click',()=>{if(pinned===b.dataset.id)close();else show(b.dataset.id,true)})}
document.querySelector('.close-detail').addEventListener('click',close);
document.addEventListener('keydown',e=>{if(e.key==='Escape'){close();document.activeElement?.blur()}});
document.addEventListener('pointerdown',e=>{if(pinned&&!e.target.closest('.entry,.inspector'))close()});
window.sample={show,close,get pinned(){return pinned},get current(){return current},inspectionOnly:true,engineCalls:0};
'''.replace('ENTRIES',json.dumps(details,ensure_ascii=False))
doc='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>晴空学园 · 玩家战斗按需详情 v6</title><style>'+css+'</style><body><div class="ambient" style="--environment:url('+src('battle_back')+')"></div><main class="shell"><header class="header frost"><div class="seal liquid">'+icon('sun')+'</div><div class="heading"><div class="eyebrow">PVE · 玩家回合</div><div class="name">晨曦森林守护者小队长安然</div></div><div class="timer"><span class="round">第1轮 · 已暂停</span><strong>剩余 17 秒</strong></div></header><div class="main"><section class="map frost"><div class="panel-heading">森林路口 · 地图</div><div class="map-actions">'+''.join('<button class="liquid" aria-label="'+label+'">'+icon(n)+'</button>' for n,label in [('focus','回到行动者'),('overview','地图总览'),('minus','缩小'),('plus','放大')])+'</div>'+mapart+'<aside class="inspector" hidden aria-live="polite" aria-label="当前条目详情"><div class="inspect-head"><strong></strong><span class="inspect-cost"></span></div><div class="inspect-target"></div><div class="inspect-effect"></div><div class="inspect-reason"></div><button class="close-detail liquid" aria-label="关闭详情">×</button><span class="pin-note"></span></aside></section><section class="battle frost">'+fight+'<div class="battle-heading">森林路口 · 同节点战斗</div></section></div><section class="track frost"><div class="track-line"></div><div class="queue">'+q+'</div></section><section class="dock frost"><div class="summary"><div class="summary-resources"><span class="team">● 蓝队</span><span>金币 0</span><span>积分 0</span></div><div class="summary-ap"><span>行动力</span>'+diamonds()+'</div></div><div class="entry-group skills-group"><div class="group-title">技能</div><div class="entries">'+skills+'</div></div><div class="entry-group items-group"><div class="group-title">个人物品</div><div class="entries">'+items+'</div></div></section></main><script>'+script+'</script></body></html>'
(R/'previews/player_battle_focus_16x9.html').write_text(doc)
(R/'sources/materials.css').write_text(css.rstrip()+'\n')
(R/'sources/display-fixture.json').write_text(json.dumps(dict(status='design-fixture-not-engine-receipt',actor='P3',currentAP=1,maximumAP=8,units=units,details=details,noGameWrites=True),ensure_ascii=False,indent=2)+'\n')
async def export():
    async with async_playwright() as p:
        browser=await p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox']);page=await browser.new_page(viewport={'width':1920,'height':1080},device_scale_factor=1)
        await page.route('**/*',lambda route:route.abort())
        await page.set_content(doc);await page.evaluate('document.fonts.ready')
        assert await page.locator('.inspector').is_hidden()
        assert await page.locator('.health-bar').count()==10
        assert await page.locator('.ap-diamond.filled').count()==1
        assert await page.locator('.ap-diamond.empty').count()==7
        assert await page.locator('.header .resources').count()==0
        assert await page.evaluate("[...document.querySelectorAll('.entry')].every(e=>{const b=e.getBoundingClientRect(),d=document.querySelector('.dock').getBoundingClientRect();return b.height===54&&b.top>=d.top&&b.bottom<=d.bottom})")
        assert await page.evaluate("[...document.querySelectorAll('.ap-diamond.empty path')].every(p=>getComputedStyle(p).fill==='none')")
        await page.screenshot(path=str(R/'previews/player_battle_focus_default_16x9.png'))
        await page.locator('[data-id="runeSlash"]').hover();assert await page.locator('.inspector').is_visible();assert await page.locator('.inspect-effect').text_content()=='目标伤害2D12+2；自身恢复4生命、护盾4'
        await page.screenshot(path=str(R/'previews/player_battle_focus_skill_16x9.png'))
        await page.mouse.move(40,40);assert await page.locator('.inspector').is_hidden()
        await page.locator('[data-id="smallPotion"]').focus();assert await page.locator('.inspector strong').text_content()=='小治疗药水'
        await page.locator('[data-id="revivalStone"]').click();await page.mouse.move(40,40);assert await page.locator('.inspector').is_visible();assert await page.evaluate('sample.pinned')=='revivalStone'
        await page.screenshot(path=str(R/'previews/player_battle_focus_item_16x9.png'))
        await page.keyboard.press('Escape');assert await page.locator('.inspector').is_hidden()
        await page.locator('[data-id="battleRune"]').click();await page.locator('[data-id="battleRune"]').click();assert await page.locator('.inspector').is_hidden()
        await page.locator('[data-id="smallPotion"]').click();await page.mouse.click(40,40);assert await page.locator('.inspector').is_hidden()
        report=await page.evaluate('''()=>({canvas:[innerWidth,innerHeight],queueUnits:document.querySelectorAll('.queue-unit').length,healthBars:document.querySelectorAll('.health-bar').length,visibleAPFilled:document.querySelectorAll('.ap-diamond.filled').length,visibleAPEmpty:document.querySelectorAll('.ap-diamond.empty').length,engineCalls:sample.engineCalls,overflow:[...document.querySelectorAll('.entry,.summary-resources,.name')].filter(e=>e.scrollWidth>e.clientWidth+1).map(e=>e.className)})''')
        assert not report['overflow'],report
        (R/'validation.json').write_text(json.dumps(dict(status='pass',browserOnly=True,nativeVerified=False,artApproved=False,hover=True,keyboardFocus=True,clickToPin=True,escapeToClose=True,clickAgainCloses=True,outsideClickCloses=True,offlineRequestsBlocked=True,**report),ensure_ascii=False,indent=2)+'\n');await browser.close()
asyncio.run(export());print('Exported default, skill-hover, item-click previews; offline focus/click/escape checks passed.')
