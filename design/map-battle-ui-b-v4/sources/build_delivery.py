"""Offline design exporter. No App, engine, or rule writes. Run from any cwd.
Pillow is used only for byte-preserving input reads and mechanical whole-canvas
resampling; original art remains unchanged. New art is authored as editable SVG.
"""
from pathlib import Path
import base64, hashlib, json, math, random, subprocess, html, shutil
from PIL import Image, ImageCms

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
ART = REPO/'native/ClassroomProbe/Resources/Art'
INK='#173F50'; BLUE='#176A86'; MUTED='#496977'; GOLD='#B7863E'; CREAM='#FFFCF2'
def write(p,s):
    p=ROOT/p; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(s,encoding='utf-8')
def js(p,d): write(p,json.dumps(d,ensure_ascii=False,indent=2)+'\n')
def svg(w,h,s): return f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{s}</svg>'
def rect(x,y,w,h,fill='white',r=0,stroke='none',sw=1): return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>'
def circle(x,y,r,fill,stroke='none',sw=1): return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>'
def ellipse(x,y,rx,ry,fill): return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}"/>'
def line(x,y,a,b,c,sw=2,dash=''): return f'<path d="M{x},{y} L{a},{b}" fill="none" stroke="{c}" stroke-width="{sw}" stroke-linecap="round" stroke-dasharray="{dash}"/>'
def path(d,c,stroke='none',sw=1): return f'<path d="{d}" fill="{c}" stroke="{stroke}" stroke-width="{sw}"/>'
def text(x,y,t,size=24,c=INK,weight=400,anchor='start'):
    return f'<text x="{x}" y="{y}" font-family="Noto Sans CJK SC, sans-serif" font-size="{size}" font-weight="{weight}" fill="{c}" text-anchor="{anchor}">{html.escape(str(t))}</text>'
def wrap(s,n):
    # Chinese-heavy preview paragraphs; live layout must use native measured wrapping.
    result=[]; buf=''; count=0
    for ch in s:
        count+=1 if ord(ch)>255 else .55
        if count>n: result.append(buf);buf=ch;count=1 if ord(ch)>255 else .55
        else: buf+=ch
    return result+[buf] if buf else result
def uri(p): return 'data:image/png;base64,'+base64.b64encode(Path(p).read_bytes()).decode()
def img(p,x,y,w,h): return f'<image x="{x}" y="{y}" width="{w}" height="{h}" preserveAspectRatio="xMidYMid meet" href="{uri(p)}"/>'
def render_asset(name,w,h,s,folder='layers'):
    source=f'assets/{folder}/{name}.svg'; target=f'assets/{folder}/{name}.png'
    write(source,svg(w,h,s))
    subprocess.run(['inkscape',str(ROOT/source),'--export-type=png',f'--export-filename={ROOT/target}'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    return target

catalog=json.loads((REPO/'native/Packages/GameCore/Sources/ClassroomGameCore/Resources/initial-content.json').read_text())
js('sources/catalog-reference.json',catalog)
binding_source=json.loads((ART/'bindings.json').read_text())
binding_types={'classes':'class','monsters':'monster','items':'item','uiResource':'resource'}
bindings={binding_types.get(a['entityType'],a['entityType'])+':'+a['entityID']:a['file'] for a in binding_source['assets']}
units=[{'id':f'p{i+1}','templateID':cl,'name':nm,'nodeID':2,'health':hp,'maximumHealth':mx,'shield':0,'coins':0,'score':0,'team':'蓝队','teamID':'blue','player':True,'acted':i<2,'canActFromRound':2 if i==5 else 1} for i,(cl,nm,hp,mx) in enumerate([
 ('adventurer','安然',12,12),('ranger','AlexandriaWinterbrookJoy',18,18),('spellblade','晨曦森林守护者小队长安然',20,24),('dragonKnight','星星',32,32),('adventurer','阿乐',0,12),('ranger','小满',9,18),('dragonKnight','林老师',32,32)])]
units += [dict(id=id,templateID=cl,name=nm,nodeID=2,health=hp,maximumHealth=hp,shield=0,coins=0,score=0,team='敌方',teamID=None,player=False,acted=id=='m1',canActFromRound=1) for id,cl,nm,hp in [('m1','slime','捣蛋史莱姆',8),('m2','goblinArcher','哥布林弓手',12),('m3','caveTroll','洞穴巨魔',48)]]
byid={u['id']:u for u in units}; queue=['p1','m1','p2','p3','m2','p4','p5','p6','m3','p7']
nodes=[dict(id=1,name='营地',x=.10,y=.55,kind='start',revealed=True),dict(id=2,name='森林路口',x=.36,y=.55,kind='combat',revealed=True),dict(id=3,name='弓手哨点',x=.62,y=.26,kind='combat',revealed=True),dict(id=4,name='未探索地点4',x=.62,y=.78,kind=None,revealed=False),dict(id=5,name='未探索地点5',x=.90,y=.55,kind=None,revealed=False)]
roads=[[1,2],[2,3],[2,4],[3,5]] # Public road 4--5 is absent: neither endpoint revealed.
js('sources/design-fixture.json',dict(status='layout-fixture-not-an-engine-receipt',basis='main PVEGameFactory coordinates and roads; independent display scenarios',units=units,queueIDs=queue,nodes=nodes,roads=roads,current='p3',round=1,remainingSeconds=17,paused=True,inventory={'smallPotion':2,'shieldPotion':1,'revivalStone':1},skillUses={'runeSlash':0,'runeWard':0,'battleRune':0},availability=['行动点不足','行动点不足','可用'],notes=['Preview action points are 1; the count is not shown in public status.', 'Exploration puts p6/p7 at unknown node5 and hides monsters; not an executed gameplay test.']))

# Whole transparent canvases retained. Never crop a portrait into a walk sprite.
reuse=[]
srgb_profile=ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
for key,file in bindings.items():
    kind,id=key.split(':',1)
    if kind not in ['class','monster','item','nodeVisual','resource']: continue
    if kind in ['class','monster']: size=192
    elif kind=='nodeVisual': size=192
    elif kind=='item': size=96
    else: size=48
    src=ART/(file if file.endswith('.png') else file+'.png')
    if not src.exists(): continue
    out=ROOT/'assets/runtime'/src.name
    original=Image.open(src).convert('RGBA')
    resized=original.resize((size,size),Image.Resampling.LANCZOS)
    resized.save(out,icc_profile=srgb_profile)
    bounds=resized.getchannel('A').getbbox()
    reuse.append(dict(binding=key,file=str(out.relative_to(ROOT)),widthPx=size,heightPx=size,anchorPx=[size/2,bounds[3]],alphaBoundsPx=bounds,source=f'native/ClassroomProbe/Resources/Art/{src.name}',sourceSHA256=hashlib.sha256(src.read_bytes()).hexdigest(),method='full-canvas uniform resample; no semantic cropping',animation='static fallback, no direction/limb frames'))
js('sources/reuse-manifest.json',reuse)
effect_manifest=json.loads((ART/'animation-manifest.json').read_text())
for effect in effect_manifest['effects']:
    fn=Path(effect['file']).name
    destination=ROOT/'assets/effects'/fn
    destination.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(ART/fn,destination)
    effect['file']='assets/effects/'+fn
    effect['sha256']=hashlib.sha256(destination.read_bytes()).hexdigest()
effect_manifest['motionFile']='sources/reused-character-motion.json'
effect_manifest['note']='Original effects copied byte for byte; static-image transform profiles remain fallback, not pilot limb frames.'
js('reused-effects-manifest.json',effect_manifest)
shutil.copyfile(ART/'character-motion.json',ROOT/'sources/reused-character-motion.json')
def asset(kind,id):
    fn=bindings.get(f'{kind}:{id}')
    if not fn: raise KeyError((kind,id))
    return ROOT/'assets/runtime'/(fn if fn.endswith('.png') else fn+'.png')

# Original low-resolution pixel pilot; 64x64 cells, 4 directions, 16 frames/row.
# Art is reinterpreted from project's adventurer/slime palette, not cropped art.
def adventurer(direction,state,f):
    s=''; hair='#814830'; edge='#203A4A'; skin='#EFC29C'; cape='#238A9E'; gold='#D4AC5E'; boot='#694E42'
    def R(x,y,w,h,c): return rect(x,y,w,h,c)
    if state=='down':
        return R(17,45,32,8,edge)+R(18,43,14,10,cape)+R(41,43,9,10,hair)+R(35,47,9,5,skin)+R(14,51,15,3,boot)
    dy= -1 if state=='idle' and f else (f%2 if state=='walk' else 0)
    back=direction=='north'; side=direction in ('east','west')
    s+=R(20,28+dy,24,20,edge)+R(21,29+dy,22,17,cape)+R(23,29+dy,4,16,'#5BBDD0')+R(39,31+dy,4,16,'#136579')
    # Real alternating boots, not a floating full portrait.
    a=[0,-2,0,2][f%4] if state=='walk' else 0
    s+=R(25+a,44,6,12,edge)+R(34-a,44,6,12,edge)+R(25+a,45,5,10,boot)+R(34-a,45,5,10,boot)+R(23+a,54,9,3,edge)+R(34-a,54,9,3,edge)
    s+=R(27,29+dy,11,15,CREAM)+R(27,37+dy,11,3,gold)+R(30,38+dy,3,3,edge)
    s+=R(22,10+dy,22,19,edge)+R(24,11+dy,19,17,hair)+R(26,16+dy,14,14,skin)
    s+=R(25,12+dy,17,6,hair)+R(22,14+dy,5,7,hair)+R(28,10+dy,6,4,'#BB7449')+R(37,13+dy,4,3,'#BB7449')
    if back:
        s+=R(25,16+dy,17,12,hair)+R(27,19+dy,3,7,'#BB7449')
        s+=R(27,29+dy,12,16,cape)+R(33,29+dy,2,16,gold)
    else:
        ex=36 if direction=='east' else 27 if direction=='west' else 28
        s+=R(ex,21+dy,3,4,edge)+R(ex,21+dy,1,1,CREAM)
        if not side: s+=R(36,21+dy,3,4,edge)+R(36,21+dy,1,1,CREAM)
        s+=R(32,27+dy,3,1,'#AC765D')
    s+=R(18,31+dy,5,11,edge)+R(19,31+dy,4,6,CREAM)+R(19,38+dy,4,4,skin)
    arm= -9 if state in ('attack','cast') and f==1 else -4 if state in ('attack','cast') and f==2 else 0
    s+=R(43,31+dy+arm,5,11,edge)+R(44,32+dy+arm,3,6,CREAM)+R(44,39+dy+arm,3,3,skin)
    # Three genuinely different sword/arm poses, with generous transparent margins.
    if state=='attack' and f==1:
        s+=R(47,17,3,20,edge)+R(48,18,1,17,'#D0E9EC')+R(43,34,10,2,gold)
    elif state=='attack' and f==2:
        s+=R(47,31,10,3,edge)+R(47,32,9,1,'#D0E9EC')+R(46,27,2,10,gold)
    else:
        s+=R(47,40+arm,3,14,edge)+R(48,41+arm,1,11,'#D0E9EC')+R(44,41+arm,9,2,gold)
    if state=='cast': s+=R(49,24+arm,4,4,gold)+R(50,25+arm,2,2,CREAM)
    if state=='hurt': s+=R(27,23+dy,4,1,edge)+R(35,23+dy,4,1,edge)
    s+=R(28,30+dy,5,3,gold)
    return f'<g transform="translate({-2 if state=="hurt" and f==0 else 0},0)" shape-rendering="crispEdges">{s}</g>'
def slime(direction,state,f):
    if state=='down': return rect(14,49,37,7,'#187D91')+rect(17,47,30,7,'#8BDBCB')+rect(24,48,15,3,'#D4FAE5')
    y=26-(2 if state=='idle' and f else 3 if state=='walk' and f%2 else 0)
    if state=='attack' and f==1: y-=6
    s=path(f'M16,{y+8} h4 v-5 h7 v-5 h12 v-8 h7 v8 h-3 v5 h4 v5 h4 v7 h4 v12 h-4 v4 H17 v-4 h-4 v-12 h3 Z','#258DA0')
    s+=path(f'M19,{y+9} h4 v-5 h9 v-5 h8 v7 h5 v8 h4 v10 H18 v-9 Z','#8EE1CC')
    s+=rect(23,y+5,8,4,'#DDFBE9')+rect(19,y+11,4,5,'#C4F2D8')+rect(39,y+16,7,7,'#4ABCB4')
    if direction!='north':
        shift=4 if direction=='east' else -4 if direction=='west' else 0
        s+=rect(23+shift,y+16,4,5,INK)+rect(35+shift,y+16,4,5,INK)+rect(24+shift,y+16,1,1,CREAM)+rect(36+shift,y+16,1,1,CREAM)+rect(29+shift,y+23,5,1,INK)
    if state=='hurt': s+=rect(22,y+18,6,1,INK)+rect(35,y+18,6,1,INK)
    return '<g shape-rendering="crispEdges">'+s+'</g>'
directions=['south','east','north','west']; states=[('idle',2,800),('walk',4,440),('attack',3,360),('cast',3,480),('hurt',2,180),('down',1,0),('revive',1,0)]
motion=[]
for id,draw in [('adventurer',adventurer),('slime',slime)]:
    pieces=[]; profiles=[]
    for row,direction in enumerate(directions):
        col=0
        for state,count,ms in states:
            frames=[]
            for f in range(count):
                art=draw(direction,'idle' if state=='revive' else state,f)
                pieces.append(f'<g transform="translate({col*64},{row*64})">{art}</g>')
                frames.append([col*64,row*64,64,64]);col+=1
            profiles.append(dict(state=state,direction=direction,frames=frames,durationMs=ms,loop=state in ['idle','walk'],terminal='hold down frame' if state=='down' else 'idle frame0' if state not in ['idle','walk'] else 'idle on stop',reducedMotion='down frame0' if state=='down' else 'idle frame0; effects off'))
    file=render_asset(f'map_{id}_sheet',1024,256,''.join(pieces),'sprites')
    motion.append(dict(templateID=id,file=file,cell=[64,64],grid=[16,4],anchorPx=[32,57],directions=directions,profiles=profiles,status='original-pixel-pilot-awaiting-review',notes=['4 cardinal poses; no 8-direction sheet','revive is a terminal idle pose plus reused revive effect, not a new limb action']))
    # A separate idle image makes the runtime sample cheap to decode.
    render_asset(f'map_{id}_idle',64,64,draw('east' if id=='adventurer' else 'west','idle',0),'sprites')
js('animation-manifest.json',dict(version=4,pilots=motion,remainingTemplates=[dict(templateID=id,status='static-full-body-fallback; directional frames pending',required=['idle2','walk4','attack3','cast3 if applicable','hurt2','down1','revive terminal1'],directions=directions) for id in ['ranger','spellblade','dragonKnight','wolf','goblinArcher','stoneGuardian','caveTroll','ruinDragon']],facing='cardinal by committed road vector; diagonal uses dominant axis, tie retains prior facing',oneShotKey='gameID:receiptID',frameInterpolation='none; nearest sampling',effectsSource='main original animation-manifest.json IDs, no second numeric channel'))

# Original independent scene modules, no gameplay terrain/obstacles or node IDs.
r=random.Random(117)
bg=rect(0,0,1024,640,'#E2F1F2')+path('M0,250 Q200,170 400,245 T800,225 L1024,200 V640 H0Z','#B7D8D0')+path('M0,365 Q250,220 520,320 T1024,280 V640 H0Z','#9BC4BD')
for x in range(-20,1080,68):
    bg+=path(f'M{x},340 l28,-155 26,155Z','#A7CFC7')+path(f'M{x+16},350 l28,-115 26,115Z','#B9DAD0')
bg+=circle(790,100,54,'#F4EBC9')+circle(790,100,40,'#FFF8DD')
render_asset('battle_back',1024,640,bg)
mid=''
for x,y in [(45,180),(960,190)]:
    mid+=rect(x,y,22,350,'#74A69C')+rect(x+7,y,7,345,'#96BEB0')
    for dx,dy,rr in [(-50,20,85),(35,-8,110),(100,18,78)]: mid+=ellipse(x+dx,y+dy,rr,65,'#85BFB1')
render_asset('battle_mid',1024,640,mid)
ground=path('M0,290 Q450,235 1024,290 V640 H0Z','#DAE6C9')+path('M0,380 Q510,300 1024,350 V640 H0Z','#F3EED6')
for x,y,w in [(90,420,190),(365,350,170),(665,405,210),(260,560,230),(730,570,175)]: ground+=ellipse(x,y,w,20,'#E4DFC4')
for _ in range(80):
    x=r.randrange(1024);y=r.randrange(330,640)
    ground+=rect(x,y,r.randrange(2,6),2,'#C9D7B8')
render_asset('battle_ground',1024,640,ground)
fg=''
for x in list(range(0,220,24))+list(range(830,1024,23)):
    fg+=path(f'M{x},640 q-12,-50 0,-80 q5,45 12,63 q3,-32 18,-38 l-10,55Z','#A4BFA0')
render_asset('battle_front',1024,640,fg)
render_asset('contact_shadow',128,48,ellipse(64,24,46,12,'#173F5033'))
render_asset('soft_halo',128,128,'<defs><radialGradient id="a"><stop stop-color="#FFE8A2" stop-opacity=".5"/><stop offset="1" stop-color="#FFE8A2" stop-opacity="0"/></radialGradient></defs>'+circle(64,64,62,'url(#a)'))
render_asset('ground_module',256,128,ellipse(128,72,115,38,'#D4E4CE')+ellipse(128,64,108,34,'#F5F0D5')+ellipse(128,60,78,20,'#FAF7E8'))
render_asset('edge_arrow',64,64,path('M11,27 H36 V13 L56,32 36,51 V37 H11Z',BLUE),'ui')
render_asset('track_pointer',64,64,path('M13,15 H51 L32,49Z',BLUE),'ui')
render_asset('track_cap',64,64,circle(32,32,21,CREAM,GOLD,3)+circle(32,32,7,BLUE),'ui')
render_asset('camera_focus',64,64,circle(32,32,14,'none',BLUE,3)+line(32,8,32,18,BLUE,3)+line(32,46,32,56,BLUE,3)+line(8,32,18,32,BLUE,3)+line(46,32,56,32,BLUE,3),'ui')
render_asset('shop_entry',64,64,path('M12,25 H52 V53 H12Z','none',BLUE,3)+path('M8,25 L15,10 H49 L56,25Z',CREAM,BLUE,3)+line(24,11,21,25,BLUE,3)+line(40,11,43,25,BLUE,3)+rect(27,36,12,17,'none',0,BLUE,3),'ui')
js('scene-manifest.json',dict(canvas=[1024,640],layers=[dict(id=f'battle_{id}',z=z,file=f'assets/layers/battle_{id}.png',fit='crop only nonsemantic environment',parallaxFactor=p) for id,z,p in [('back',0,.03),('mid',1,.05),('ground',2,0),('front',5,.08)]],shadow=dict(file='assets/layers/contact_shadow.png',anchor=[.5,.5],widthRelativeToSprite=.72,opacity=.65),halo=dict(file='assets/layers/soft_halo.png',opacity=.2,only='committed cast/heal/shield, behind actor'),particles=dict(seed='receiptID',maximum=8,sizePx=[2,4],alpha=.15,lifetimeMs=450,color='#D4AC5E',area='environment side margins, never text/face'),reducedMotion=dict(parallax=0,particles=0,shake=0,actorTranslation=0,halo=0,terminal='immediate committed pose'),blur='environment only; none applied to text/icons/actor silhouettes',downTerminal='frame or whole-static-art 90deg pivot at feet; keep HUD clear'))

def label(x,y,t,w=150): return rect(x-w/2,y-28,w,38,CREAM,12,'#B7CFCE')+text(x,y,t,24,INK,600,'middle')
def body(u,x,y,h=76,pilot=False):
    # y is the displayed foot anchor, not the image center.
    s=ellipse(x,y+1,h*.22,6,'#173F5028')
    if pilot and u['templateID'] in ['adventurer','slime']:
        p=ROOT/f'assets/sprites/map_{u["templateID"]}_idle.png'; s+=img(p,x-h/2,y-h*.89,h,h)
    else:
        p=asset('class' if u['player'] else 'monster',u['templateID'])
        profile=next(a for a in reuse if a['file']==str(p.relative_to(ROOT)))
        s+=img(p,x-h/2,y-h*profile['anchorPx'][1]/profile['heightPx'],h,h)
    return s
def badge(u,x,y):
    c=BLUE if u['player'] else '#A94E43'
    s=rect(x-23,y-15,46,30,c,9)+text(x,y+8,u['id'].upper(),24,'white',700,'middle')
    if u['health']==0: s+=text(x+25,y-10,'×',28,'#B93838',700)
    elif u['canActFromRound']>1: s+=circle(x+27,y-13,12,CREAM,INK,2)+line(x+27,y-13,x+27,y-20,INK,2)+line(x+27,y-13,x+34,y-13,INK,2)
    return s
def map_view(w,h,phase,current='p3'):
    # Single isotropic world transform: never independently normalize x/y.
    cx,cy=.36,.55;scale=min((w-260)/.8,(h-320)/.52) if phase=='exploration' else (1160 if w>700 else 890)
    ox=w*.39 if phase=='exploration' else w*.62;oy=h*.52
    def pt(n):return ox+(n['x']-cx)*scale,oy+(n['y']-cy)*scale
    s=rect(0,0,w,h,'#EAF3E8',20)
    # Generic low-contrast brush clusters; independent from hidden map content.
    for x,y,rx,ry in [(w*.15,h*.18,190,95),(w*.82,h*.09,200,100),(w*.74,h*.90,230,80),(w*.05,h*.88,120,130)]:
        s+=ellipse(x,y,rx,ry,'#D3E6D5')+ellipse(x+35,y-12,rx*.75,ry*.65,'#DFECDA')
    for a,b in roads:
        A=pt(nodes[a-1]);B=pt(nodes[b-1]);s+=line(*A,*B,'#FAF6E6',18)+line(*A,*B,'#BFCDB8',2,'4 12')
    for n in nodes:
        x,y=pt(n)
        if not (95<x<w-95 and 142<y<h-140):continue
        size=180 if n['id']!=2 else 190
        s+=img(asset('nodeVisual',n['kind'] if n['revealed'] else 'unknown'),x-size/2,y-size*.78,size,size)
        if n['id']==2: s+=ellipse(x,y+12,106,76,'none').replace('fill="none"','fill="none" stroke="#B7863E" stroke-width="3"')
        if not n['revealed']:s+=text(x,y-32,'?',36,INK,700,'middle')
        lw=max(160,len(n['name'])*24+54);lx=min(w-lw/2-12,max(lw/2+12,x))
        s+=label(lx,y+(146 if n['id']==2 else 102),str(n['id'])+' · '+n['name'],lw)
    if phase!='exploration':
        # Context labels for public roads that leave the current viewport.
        s+=label(w-156,88,'3 · 弓手哨点 ↗',264)
        s+=label(w-174,h-32,'4 · 未探索地点4 ↘',300)
    shown=units if phase!='exploration' else units[:7]
    grouped={}
    for u in shown:
        node=5 if phase=='exploration' and u['id'] in ['p6','p7'] else 1 if phase=='exploration' and u['id']=='p5' else u['nodeID']
        grouped.setdefault(node,[]).append(u)
    off=[]
    for node,us in grouped.items():
        x,y=pt(nodes[node-1])
        if not (60<x<w-60 and 90<y<h-100):off.extend(us);continue
        # 10 identities around a shared node, centered on its real anchor.
        offsets=[(-80,-50),(0,-50),(80,-50),(-120,20),(-40,20),(40,20),(120,20),(-80,82),(0,82),(80,82)] if len(us)>4 else [(-60,-20),(25,-20),(-30,50),(55,50)]
        for u,(dx,dy) in zip(us,offsets):
            s+=body(u,x+dx,y+dy,96)+badge(u,x+dx,y+dy+9)
            if u['id']==current and phase!='exploration':s+=path(f'M{x+dx-9},{y+dy-69} h18 l-9,12Z',BLUE)
    # Distinct teacher-controlled public marker; position follows the world ray.
    if off:
        for i,u in enumerate(off[:2]):
            px=w-50;py=h*.48+i*90
            s+=circle(px,py,31,CREAM,BLUE,2)+img(asset('class',u['templateID']),px-28,py-28,56,56)+badge(u,px-44,py+22)
            s+=path(f'M{px+32},{py-8} l12,8 -12,8Z',BLUE)
    s+=rect(22,20,194,48,CREAM,14,'#C7D8CC')+text(42,52,'森林路口 · 地图',24,INK,600)
    s+=rect(22,h-66,230,44,CREAM,12)+text(38,h-36,'镜头：'+('手动查看' if phase=='exploration' else '跟随战斗节点'),24,MUTED)
    return s

def battle_view(w,h,current):
    s=rect(0,0,w,h,CREAM,20)
    for id in ['back','mid','ground']:
        s+=f'<image x="0" y="0" width="{w}" height="{h}" preserveAspectRatio="xMidYMid slice" href="{uri(ROOT/f"assets/layers/battle_{id}.png")}"/>'
    s+=rect(18,14,w-36,66,'#FFFCF2F2',14)+text(38,55,'森林路口 · 同节点战斗',28,INK,700)
    # 7 allied slots (4 then 3), 3 enemies; fixed HUD protected from pixels/FX.
    positions=[(.11,.35),(.29,.35),(.47,.35),(.65,.35),(.11,.74),(.29,.74),(.47,.74),(.85,.28),(.85,.53),(.85,.78)]
    hud=''
    for u,(fx,fy) in zip(units,positions):
        x=w*fx;y=h*fy
        s+=body(u,x,y,100 if u['player'] else 86,pilot=False)
        if u['id']==current:s+=ellipse(x,y+5,39,8,'none').replace('fill="none"','fill="none" stroke="#176A86" stroke-width="3"')
        hud+=badge(u,x,y+20)
        if u['player']:
            hud+=rect(x-56,y+40,112,56,'#FFFCF2F2',10)+text(x,y+64,f'♥ {u["health"]}/{u["maximumHealth"]}',24,'#963E3E',600,'middle')+text(x,y+89,f'◇ {u["shield"]}',24,'#315E9C',600,'middle')
        else:
            hud+=rect(x-76,y+40,152,34,'#FFFCF2F2',10)+text(x,y+65,f'♥{u["health"]}/{u["maximumHealth"]} ◇{u["shield"]}',24,'#963E3E',600,'middle')
    s+=f'<image x="0" y="0" width="{w}" height="{h}" preserveAspectRatio="xMidYMid slice" href="{uri(ROOT/"assets/layers/battle_front.png")}"/>'
    return s+hud
def track(w,current):
    s=rect(0,0,w,104,CREAM,18,'#C5D8DF')
    xs=[62+i*(w-124)/9 for i in range(10)];ci=queue.index(current); y=52
    s+=line(xs[0],y,xs[-1],y,'#BFD1D3',12)+line(xs[0],y,xs[ci],y,BLUE,12)
    s+=line(xs[0],y,xs[-1],y,CREAM,2)
    for i,(id,x) in enumerate(zip(queue,xs)):
        u=dict(byid[id])
        if current=='m2' and id=='p3': u['acted']=True
        s+=circle(x,y,29,CREAM,BLUE if i<=ci else '#A9C2CD',3 if i==ci else 2)
        s+=img(asset('class' if u['player'] else 'monster',u['templateID']),x-27,y-27,54,54)
        s+=text(x,96,id.upper(),24,INK,700,'middle')
        if u['health']==0:s+=text(x,y+10,'×',42,'#B93838',700,'middle')
        elif u['canActFromRound']>1:
            s+=circle(x+24,y-18,12,CREAM,INK,2)+line(x+24,y-18,x+24,y-25,INK,2)+line(x+24,y-18,x+31,y-18,INK,2)
        elif u['acted']:s+=circle(x+24,y-18,12,BLUE)+text(x+24,y-11,'✓',20,'white',700,'middle')
        if i==ci:s+=path(f'M{x-10},7 h20 l-10,12Z',BLUE)
    return s
def details(w,classID='spellblade',inventory=None,stage='battle'):
    s=rect(0,0,w,240,CREAM,18,'#C5D8DF'); gap=12;cw=(w-48)/3
    ids=next(c['skills'] for c in catalog['classes'] if c['id']==classID)
    desc={'runeSlash':['单敌 · 射程1 · 战斗 · 余2次','目标伤害2D12+2；自身恢复4生命、护盾4'], 'runeWard':['节点全部队友 · 射程1 · 余2次','目标恢复8生命、护盾6'], 'battleRune':['节点全部队友 · 射程1 · 余2次','目标护盾4；伤害+3，持续2轮']}
    for i,id in enumerate(ids):
        skill=next(k for k in catalog['skills'] if k['id']==id);x=12+i*(cw+gap)
        disabled=i<2; fill='#EDF1EC' if disabled else '#E2F0EE'
        s+=rect(x,12,cw,142,fill,12,'#BCCDC9')+text(x+14,43,skill['name'],27,INK,700)+text(x+cw-14,43,f'{skill["cost"]}行动点',24,MUTED,400,'end')
        s+=text(x+14,74,desc[id][0],24,INK)
        for j,t in enumerate(wrap(desc[id][1],(cw-28)/24)):s+=text(x+14,104+j*28,t,24,INK)
        s+=text(x+cw-14,146,'行动点不足' if disabled else '可用',24,'#8E4138' if disabled else BLUE,600,'end')
    s+=line(16,166,w-16,166,'#CDDED9',1)+text(24,199,'个人物品',24,INK,700)
    inv=inventory if inventory is not None else [('smallPotion',2),('shieldPotion',1),('revivalStone',1)]
    if not inv:s+=text(180,203,'空背包 · 当前角色没有个人物品',24,MUTED);return s
    ix=170; iw=(w-194)/3
    for i,(id,count) in enumerate(inv[:3]):
        it=next(k for k in catalog['items'] if k['id']==id);x=ix+i*iw
        s+=img(asset('item',id),x,177,48,48)+text(x+53,198,it['name']+f' ×{count}',24,INK,600)
        limit='同节点倒地队友 · 2点' if id=='revivalStone' else '自己/队友 · 射程1 · 1点'
        s+=text(x+53,227,limit,24,MUTED)
    return s
layouts={}
def preview(ratio,phase):
    W=1920 if ratio=='16x9' else 1440;H=1080;mx=96 if W==1920 else 72;cw=W-2*mx
    current='m2' if phase=='monster' else 'p3'; mainY=166; mainH=480 if phase=='player' else 738 if phase=='monster' else 860
    mw=(960 if W==1920 else 600) if phase!='exploration' else cw; bw=cw-mw-24
    s=rect(0,0,W,H,'#EFF5F3')+rect(mx,54,cw,88,CREAM,20,'#CFDDD7')
    name=byid[current]['name'] if phase!='exploration' else byid['p3']['name']
    s+=rect(mx+16,70,108,52,BLUE,14)+text(mx+70,105,'探索' if phase=='exploration' else 'PVE',28,'white',700,'middle')
    s+=text(mx+145,89,'地图查看' if phase=='exploration' else '行动中',24,MUTED,500)
    s+=text(mx+145,127,name,32,INK,700)
    if phase!='exploration':
        s+=text(W-mx-20,90,'第1轮 · 手动暂停',24,MUTED,500,'end')+text(W-mx-20,126,'剩余 17 秒',28,INK,700,'end')
    else:s+=text(W-mx-20,110,'晴空学园',28,BLUE,600,'end')
    s+=f'<defs><clipPath id="mapClip"><rect x="0" y="0" width="{mw}" height="{mainH}" rx="20"/></clipPath></defs><g transform="translate({mx},{mainY})" clip-path="url(#mapClip)">'+map_view(mw,mainH,'exploration' if phase=='exploration' else 'battle',current)+'</g>'
    if phase!='exploration':
        s+=f'<defs><clipPath id="battleClip"><rect width="{bw}" height="{mainH}" rx="20"/></clipPath></defs><g transform="translate({mx+mw+24},{mainY})" clip-path="url(#battleClip)">'+battle_view(bw,mainH,current)+'</g>'
        qy=mainY+mainH+18;s+=f'<g transform="translate({mx},{qy})">'+track(cw,current)+'</g>'
        if phase=='player':
            dy=qy+122;s+=f'<g transform="translate({mx},{dy})">'+details(cw)+'</g>'
            # status remains distinct from skill costs and inventory, six public fields.
    s+=text(mx+280,89,'♥ 12/12  ◇ 0  ◉ 0  ★ 0  敌方' if phase=='monster' else '♥ 20/24  ◇ 0  ◉ 0  ★ 0  ● 蓝队',24,MUTED)
    layouts[f'{phase}_{ratio}']=dict(canvas=[W,H],header=[mx,54,cw,88],map=[mx,mainY,mw,mainH],battle=None if phase=='exploration' else [mx+mw+24,mainY,bw,mainH],track=None if phase=='exploration' else [mx,mainY+mainH+18,cw,104],details=[mx,mainY+mainH+140,cw,240] if phase=='player' else None)
    write(f'sources/public_{phase}_{ratio}.svg',svg(W,H,s))
for ratio in ['16x9','4x3']:
    for phase in ['exploration','player','monster']:preview(ratio,phase)
js('layout-tokens.json',dict(status='awaiting-review',colors=dict(ink=INK,primary=BLUE,muted=MUTED,cream=CREAM,gold=GOLD),layouts=layouts,publicMinimumFontPx=24,teacherTouchMinimumPt=44,material='native regular Material; preview solid approximation',camera=dict(worldScaleIsotropic=True,minimumBodyDisplayPx=64,offscreenMarginPx=48,markerSpacingPx=90)))

# Small sample and explicit stress sheets, separate from the six public screens.
s=rect(0,0,1440,1080,'#EFF5F3')+text(72,96,'地图人物尺度与动作 · 冒险者 / 史莱姆',36,INK,700)+text(72,138,'原创像素试作；其余8模板仍使用完整静态素材，方向肢体帧待制作。',24,MUTED)
for i,(state,cnt,ms) in enumerate(states[:6]):
    x=88+i*220;s+=rect(x,190,202,540,CREAM,18)+text(x+101,236,{'idle':'待机','walk':'行走','attack':'攻击','cast':'施法','hurt':'受击','down':'倒地终态'}[state],28,INK,600,'middle')
    for j,fn in enumerate([adventurer,slime]):
        for f in range(min(cnt,3)):
            s+=f'<g transform="translate({x+13+f*62},{280+j*160}) scale(1)">'+fn('east' if j==0 else 'west',state,f)+'</g>'
    s+=text(x+101,686,f'{cnt}帧 · {ms}ms',24,MUTED,400,'middle')
s+=text(72,808,'64px 地图画布 / 96–112px 战斗画布；脚底锚点 (32,57)，透明留边。',26,INK)
for i,scale in enumerate([1,1.5,2]):s+=f'<g transform="translate({170+i*250},850) scale({scale})">'+adventurer('east','idle',0)+'</g>'
write('sources/sprite_scale_and_motion.svg',svg(1440,1080,s))

s=rect(0,0,1440,1080,'#EFF5F3')+text(72,100,'教师镜头控件 · 只改变公开视野',36,INK,700)+text(72,148,'追加在已通过教师地图工具区，44pt以上触区；奖励选择与当前回合不变。',24,MUTED)
s+=rect(72,198,850,510,CREAM,20,'#C5D8DF')+'<defs><clipPath id="teacherMap"><rect width="822" height="482" rx="18"/></clipPath></defs>'+f'<g transform="translate(86,212)" clip-path="url(#teacherMap)">'+map_view(822,482,'battle')+'</g>'
s+=rect(950,198,418,510,CREAM,20,'#C5D8DF')
for i,t in enumerate(['回到行动者','地图总览','跟随：开启','缩小 − / 放大 +']):
    s+=rect(978,230+i*90,360,62,BLUE if i==0 else '#E5EFEB',14)+text(1158,270+i*90,t,26,'white' if i==0 else INK,600,'middle')
s+=text(978,643,'视野外头像 → 镜头定位',24,MUTED)
s+=text(72,778,'商店入口规划（v0.9未实现，公开屏不放执行按钮）',30,INK,700)
for i,(t,c) in enumerate([('探索 · 商店关闭',INK),('探索 · 商店开放',BLUE),('战斗 · 商店不可用',MUTED)]):
    x=72+i*440;s+=rect(x,822,412,106,CREAM,16,'#C5D8DF')+img(ROOT/'assets/ui/shop_entry.png',x+18,840,60,60)+text(x+96,883,t,24,c,600)
s+=text(72,987,'教师手动开关；探索地点不限；本轮不展开买卖/仓库/交易/换装页面。',24,MUTED)
write('sources/teacher_camera_and_shop.svg',svg(1440,1080,s))

s=rect(0,0,1440,1080,'#EFF5F3')+text(72,95,'边界状态 · 队列身份 / 背包 / 离屏聚合',36,INK,700)
s+=f'<g transform="translate(72,146)">'+track(1296,'p3')+'</g>'
s+=text(72,300,'同职业同队：P1 / P5；倒地 ×；已行动 ✓；救援下轮时钟。',26,INK)
s+=rect(72,337,1296,90,CREAM,18)+text(98,390,'个人物品',26,INK,700)+text(268,390,'空背包 · 当前角色没有个人物品',26,MUTED)
s+=text(72,484,'18种物品压力稿 · 每页6种（2行×3列），分页仅查看，不执行。',26,INK)
for i,it in enumerate(catalog['items'][:6]):
    x=72+i%3*440;y=520+i//3*116;s+=rect(x,y,416,100,CREAM,14,'#C5D8DF')+img(asset('item',it['id']),x+10,y+20,60,60)+text(x+80,y+42,it['name']+' ×1',26,INK,600)+text(x+80,y+78,'装备 · 战斗不能换装',24,MUTED)
s+=text(1318,802,'1 / 3',26,BLUE,600,'end')
s+=rect(72,844,600,156,CREAM,18)+text(94,888,'同一边缘位置：头像栈 + 真实人数',24,INK,600)
for i,u in enumerate(units[5:7]):s+=circle(136+i*60,944,28,CREAM,BLUE,2)+img(asset('class',u['templateID']),108+i*60,916,56,56)+badge(u,136+i*60,980)
s+=text(284,953,'2人 →',28,BLUE,600)
s+=rect(696,844,672,156,CREAM,18)+text(720,888,'长姓名：顶部完整换行，不重复到底部',24,INK,600)+text(720,934,'AlexandriaWinterbrookJoy',28,INK,700)+text(720,978,'减少动态：立即终态，无位移/震屏/粒子。',24,MUTED)
write('sources/edge_cases.svg',svg(1440,1080,s))

# Preserve actual full skill effects under the densest class/set case.
s=rect(0,0,1440,1080,'#EFF5F3')+text(72,94,'最长技能 / 第4套装技能 · 信息不删减',36,INK,700)
summaries=[('dragonFlame','节点全部敌人 · 射程1 · 战斗 · 余1次','目标伤害1D20+6；自身恢复6生命、护盾6；自身伤害+2，持续2轮'),('dragonScaleWard','节点全部队友 · 射程1 · 通用 · 余2次','目标恢复12生命、护盾10；目标伤害+2，持续1轮'),('dragonOrder','节点全部队友 · 射程1 · 通用 · 余1次','目标恢复6生命、护盾8；目标伤害+4，持续2轮'),('dragonSoulWard','节点全部队友 · 射程1 · 战斗 · 余1次','目标恢复10生命、护盾10；目标伤害+3，持续2轮')]
for i,(id,scope,detail) in enumerate(summaries):
    x=72+i%2*660;y=180+i//2*230;k=next(v for v in catalog['skills'] if v['id']==id)
    s+=rect(x,y,636,206,CREAM,18,'#C5D8DF')+text(x+20,y+44,k['name'],30,INK,700)+text(x+616,y+44,f'{k["cost"]}行动点',26,MUTED,400,'end')+text(x+20,y+88,scope,24,INK)
    for j,t in enumerate(wrap(detail,23)):s+=text(x+20,y+125+j*32,t,26,INK)
    s+=text(x+20,y+192,'✓ 可用（由真实规则投影提供）',24,BLUE)
s+=text(72,745,'4:3最长技能：每页2张，2页；18物品另页每页6种，3页。',26,INK)
s+=text(72,790,'教师切页只改变展示；顶部固定当前行动者；公开端不显示教师选中的技能/目标。',24,MUTED)
s+=text(72,840,'不得按职业写死3技能；套装技能来自本局有效技能集合与剩余次数。',24,MUTED)
s+=text(72,920,'仅审图的压力样例：物品/套装拥有情况明确由场景fixture提供，不代表原存档。',24,MUTED)
write('sources/long_skills_and_set.svg',svg(1440,1080,s))

scene=rect(0,0,1440,1080,'#EFF5F3')+text(72,100,'分层2D战斗交接 · 接地与空间层次',36,INK,700)
for i,id in enumerate(['back','mid','ground','front']):
    x=72+i%2*660;y=160+i//2*310
    scene+=rect(x,y,636,276,CREAM,16,'#C5D8DF')+img(ROOT/f'assets/layers/battle_{id}.png',x+12,y+12,612,232)+text(x+20,y+265,id+(' / 独立PNG（不透明）' if id=='back' else ' / 独立透明PNG'),24,INK,600)
scene+=text(72,850,'阴影 z3 → 角色 z4 → 特效 z6 → HUD z7；所有角色/文字不做景深模糊。',24,INK)
scene+=img(ROOT/'assets/layers/contact_shadow.png',92,900,180,68)+img(ROOT/'assets/layers/soft_halo.png',334,882,100,100)+text(490,940,'环境粒子最多8点，450ms；减少动态全部关闭。',24,MUTED)
write('sources/hd2d_layers.svg',svg(1440,1080,scene))

files=sorted(p.name for p in (ROOT/'sources').glob('*.svg'))
write('previews/index.html','<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>晴空学园 round4 待审</title><style>body{background:#eff5f3;color:#173f50;font:18px system-ui;margin:24px}a{color:#176a86}img{width:100%;height:auto;border-radius:20px}section{margin:40px 0}h1{font-size:28px}</style><h1>晴空学园 · 大地图与战斗底栏 round4（待审）</h1><p>全部离线。整页图仅审图，运行时使用独立资产和原生文字。</p><p><a href="camera_transition_demo.html">镜头/切换/动作一次播放演示</a></p>'+''.join(f'<section><h2>{p[:-4]}</h2><a href="{p[:-4]}.png"><img src="{p[:-4]}.png"></a></section>' for p in files))
print('Exported editable SVGs:',len(files),'reused runtime assets:',len(reuse))
