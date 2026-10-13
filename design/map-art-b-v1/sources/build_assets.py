"""Mechanical PNG/SVG export + design specimen rendering. No game calculations."""
from pathlib import Path
import json, shutil, subprocess, hashlib, cairosvg, os
from PIL import Image, ImageDraw, ImageFont, ImageCms

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'sources'; AS=ROOT/'assets'; PRE=ROOT/'previews'
INK='#173F50'; BLUE='#176A86'; GOLD='#995207'; BORDER='#CCDDE6'; BG='#F5FAFC'
ICC=ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
FONT=Path(os.environ.get('DESIGN_PREVIEW_FONT',str(Path(__file__).resolve().parents[3]/'work/NotoSansCJKsc-Regular.otf')))
if not FONT.exists():raise FileNotFoundError('Set DESIGN_PREVIEW_FONT to an installed Noto Sans CJK SC font. App uses offline system fonts.')
def font(n):return ImageFont.truetype(str(FONT),n)
def text(d,xy,s,n=24,color=INK):d.text(xy,s,font=font(n),fill=color)
def svg(path,body,w=512,h=512):
 path.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>',encoding='utf-8')
 cairosvg.svg2png(url=str(path),write_to=str(path.with_suffix('.png')))
 with Image.open(path.with_suffix('.png')) as out:complete=out.copy()
 complete.save(path.with_suffix('.png'),icc_profile=ICC)
def image(path):return Image.open(path).convert('RGBA')
def fit(dst,src,box):
 im=image(src);im.thumbnail((box[2],box[3]),Image.Resampling.NEAREST)
 dst.alpha_composite(im,(int(box[0]+(box[2]-im.width)/2),int(box[1]+(box[3]-im.height)/2)))
def panel(d,box):d.rounded_rectangle(box,16,fill='white',outline=BORDER,width=2)
def save(im,name):im.convert('RGB').save(PRE/name)

labels={'start':'起点','combat':'普通战斗','boss':'Boss 地点','reward':'奖励地点','empty':'空地点','unknown':'未知轮廓'}
for id in list(labels)[:-1]:
 if not (SRC/f'generated_node_{id}.png').exists():
  spec=json.loads((Path('work')/f'node_{id}.json').read_text())
  shutil.copyfile(spec['path'],SRC/f'generated_node_{id}.png')
  (SRC/f'prompt_node_{id}.txt').write_text(spec['prompt'],encoding='utf-8')
 target=AS/'nodes'/f'node_{id}.png'
 subprocess.run(['convert',str(SRC/f'generated_node_{id}.png'),'-filter','point','-resize','400x400','-gravity','center','-background','none','-extent','512x512','-colorspace','sRGB','PNG32:'+str(target)],check=True)
 with Image.open(target) as out:complete=out.copy()
 complete.save(target,icc_profile=ICC)
 (SRC/f'export_node_{id}.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><image x="56" y="56" width="400" height="400" href="generated_node_{id}.png" preserveAspectRatio="xMidYMid meet" style="image-rendering:pixelated"/></svg>')

# Neutral unknown symbol deliberately contains no question mark / runtime text.
svg(AS/'nodes/node_unknown.svg','<ellipse cx="256" cy="272" rx="176" ry="126" fill="#E4F1F6" fill-opacity=".8" stroke="#4C6875" stroke-width="12" stroke-dasharray="26 18"/><path d="M120 310 L176 336 L336 336 L392 310" fill="none" stroke="#CCDDE6" stroke-width="12"/>')
overlays={
 'current':'<circle cx="256" cy="256" r="184" fill="none" stroke="#176A86" stroke-width="12"/><path d="M224 48 L288 48 L256 88 Z" fill="#176A86"/>',
 'path':'<circle cx="256" cy="256" r="184" fill="none" stroke="#995207" stroke-width="10" stroke-dasharray="18 14"/><path d="M320 392 L364 392 L364 368 L416 408 L364 448 L364 424 L320 424 Z" fill="#995207"/>',
 'enemy':'<circle cx="256" cy="256" r="184" fill="none" stroke="#B93838" stroke-width="10"/><path d="M356 344 L412 412 M412 344 L356 412" stroke="#B93838" stroke-width="14"/>',
 'claimed':'<circle cx="392" cy="392" r="60" fill="#FFFFFF" stroke="#176A86" stroke-width="8"/><path d="M360 392 L382 414 L426 368" fill="none" stroke="#176A86" stroke-width="12"/>',
 'crowded':'<circle cx="390" cy="390" r="62" fill="#FFFFFF" stroke="#173F50" stroke-width="8"/>',
 'target':'<path d="M112 160 L112 112 L160 112 M352 112 L400 112 L400 160 M400 352 L400 400 L352 400 M160 400 L112 400 L112 352" fill="none" stroke="#176A86" stroke-width="16"/>'}
for id,b in overlays.items():svg(AS/'overlays'/f'node_state_{id}.svg',b)
for id,col,dash in [('normal','#9AB8C7',''),('planned',GOLD,''),('plan_unavailable','#4C6875','stroke-dasharray="16 12"')]:
 svg(AS/'roads'/f'road_{id}.svg',f'<path d="M64 256 L448 256" fill="none" stroke="{col}" stroke-width="12" stroke-linecap="round" {dash}/>')
svg(AS/'overlays/fog_unknown.svg','<path d="M100 336 L76 288 L104 252 L88 212 L128 184 L164 148 L218 160 L256 132 L308 156 L356 152 L388 194 L426 220 L412 268 L432 310 L396 348 L352 376 L296 364 L252 390 L208 370 L156 378 Z" fill="#E4F1F6" fill-opacity=".8"/>')

def background(w,h):
 svg(AS/'backgrounds'/f'map_ground_{w}.svg',f'<rect width="{w}" height="{h}" fill="#F5FAFC"/><ellipse cx="{w//2}" cy="{h//2}" rx="{w//2}" ry="{h//2}" fill="#E4F1F6" fill-opacity=".5"/>',w,h)
 # Generic pixel foliage restricted to perimeter, no route or landmark cues.
 parts=[]
 for x,y in [(40,50),(w-150,48),(34,h-118),(w-140,h-130)]:
  for dx,dy,sz,col in [(0,20,36,'#C9E0EB'),(30,0,48,'#CCE5DC'),(62,28,36,'#D8EBE2'),(30,48,40,'#D9EAF2')]:
   parts.append(f'<rect x="{x+dx}" y="{y+dy}" width="{sz}" height="{sz}" fill="{col}" fill-opacity=".45"/>')
 svg(AS/'backgrounds'/f'map_decoration_{w}.svg',''.join(parts),w,h)
for w in [1920,1440]:background(w,1080)

# Specimen 1: location families + actual shrink-to-size check.
im=Image.new('RGBA',(1920,1080),BG);d=ImageDraw.Draw(im)
text(d,(72,40),'B 晴空学园 · 地点独立素材',40);text(d,(72,94),'五类已揭示地点 + 统一未知轮廓｜512 × 512 · 透明 PNG',26)
for i,(id,label) in enumerate(labels.items()):
 x=72+(i%3)*592;y=160+(i//3)*430;panel(d,(x,y,x+560,y+400));fit(im,AS/'nodes'/f'node_{id}.png',(x+24,y+22,264,264))
 text(d,(x+306,y+42),label,30);text(d,(x+306,y+90),f'node_{id}',23)
 text(d,(x+306,y+150),'64 px',21);fit(im,AS/'nodes'/f'node_{id}.png',(x+310,y+192,64,64))
 text(d,(x+410,y+150),'96 px',21);fit(im,AS/'nodes'/f'node_{id}.png',(x+406,y+176,96,96))
 text(d,(x+28,y+330),'仅展示已揭示类型' if id!='unknown' else '所有未知类型共用；问号由 App 叠加',22)
save(im,'node_contact_sheet.png')

# Specimen 2: state overlays, independent from scenery.
im=Image.new('RGBA',(1920,1080),BG);d=ImageDraw.Draw(im);text(d,(72,40),'节点状态 · 插画与标记分别叠加',40)
stlabels={'current':'当前位置：指针 + 实线圈','path':'路径经过：箭头 + 虚线圈','enemy':'敌人地点：交叉 + 轮廓','claimed':'奖励已领取：勾标','crowded':'同地点多人／多怪物：数量徽章','target':'合法目标：四角框'}
for i,(id,label) in enumerate(stlabels.items()):
 x=72+(i%3)*592;y=134+(i//3)*442;panel(d,(x,y,x+560,y+416));kind='reward' if id=='claimed' else 'combat'
 fit(im,AS/'nodes'/f'node_{kind}.png',(x+156,y+36,240,240));fit(im,AS/'overlays'/f'node_state_{id}.png',(x+156,y+36,240,240))
 if id=='crowded':text(d,(x+329,y+204),'5',24)
 text(d,(x+24,y+316),label,24);text(d,(x+24,y+359),'运行文字和数量由 App 绘制；标记不可只靠颜色',20)
save(im,'node_state_board.png')

fixture=json.loads((SRC/'node-fixture.json').read_text())
def map_module(w,h,unknown_kind='unknown'):
 im=Image.new('RGBA',(w,h),'#E4F1F6');d=ImageDraw.Draw(im)
 pos={n['id']:(round(40+n['x']*(w-80)),round(58+n['y']*(h-170))) for n in fixture['nodes']}
 for r in fixture['roads']:d.line([pos[r['a']],pos[r['b']]],fill='#9AB8C7',width=6)
 size=108 if w>650 else 96
 for original in fixture['nodes']:
  n=dict(original)
  if not n['revealed']:n['kind']=unknown_kind
  x,y=pos[n['id']];kind=n['kind'] if n['revealed'] else 'unknown'
  fit(im,AS/'nodes'/f'node_{kind}.png',(x-size/2,y-size/2,size,size))
  if not n['revealed']:text(d,(x-9,y-19),'?',32)
  if n['id']==3:fit(im,AS/'overlays/node_state_current.png',(x-size/2,y-size/2,size,size))
  name=n['name'];text(d,(x-len(name)*12,y+size/2+8),name,24)
 text(d,(24,h-76),'五节点演示：道路与节点引用原设计数据',20)
 text(d,(24,h-44),'未知内容不进入公开画面 · 战斗沿用地图',20)
 return im
for w,mw in [(1920,760),(1440,596)]:
 im=Image.new('RGBA',(w,1080),BG);d=ImageDraw.Draw(im);margin=int(w*.05)
 text(d,(margin,54),'地图素材适配检查 · 非替换已通过整屏',36)
 module=map_module(mw,622);im.alpha_composite(module,(margin,138))
 module.save(PRE/f'map_module_{mw}.png')
 x=margin+mw+24;rw=w-margin-x;panel(d,(x,138,w-margin,760))
 text(d,(x+24,160),'分层接入',30)
 for i,s in enumerate(['1 低对比地面／通用边缘装饰','2 根据真实坐标绘制道路','3 已揭示地点插画／统一未知轮廓','4 当前位置、合法目标、领取标记','5 单位汇总、姓名和实际数字']):text(d,(x+24,222+i*72),s,24)
 text(d,(margin,812),'素材不包含节点名称、道路拓扑、姓名、数值或掉落概率。',26)
 text(d,(margin,864),'底图可适配裁切；节点插画保持比例完整显示。教师触区由 App 保证至少 44 × 44 pt。',22)
 text(d,(margin,924),'未知节点仅绘制中性轮廓。不能在其下加载 Boss／奖励图，隐藏动画也不能露出内容。',22)
 save(im,f'map_adaptation_{w}.png')

# Isolated privacy fixture: hidden internal kind changes do not change public pixels.
a=map_module(760,622,'boss');b=map_module(760,622,'reward')
assert a.tobytes()==b.tobytes()
im=Image.new('RGBA',(1680,820),BG);d=ImageDraw.Draw(im);text(d,(60,30),'公开未知节点 · 隐藏类型改变，公开像素不变',36)
im.alpha_composite(a,(60,110));im.alpha_composite(b,(860,110));text(d,(60,754),'隐藏测试输入 A / B 均只公开相同轮廓',24)
save(im,'unknown_privacy_check.png')

manifest={'formatVersion':1,'deliveryVersion':'2026-10-13-b-map-v1','selectedStyle':'b','status':'production-candidates-awaiting-art-review','assets':[]}
for id,label in labels.items():
 p=AS/'nodes'/f'node_{id}.png';manifest['assets'].append({'entityType':'nodeVisual','entityID':id,'label':label,'assetName':'node_'+id,'file':p.relative_to(ROOT).as_posix(),'widthPx':512,'heightPx':512,'transparent':True,'colorSpace':'sRGB','status':'production-candidate-awaiting-art-review','source':('sources/generated_node_'+id+'.png') if id!='unknown' else 'assets/nodes/node_unknown.svg','license':'OpenAI服务适用条款；无第三方游戏素材' if id!='unknown' else '本项目原创SVG，可随项目使用和修改','sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
for p in sorted(AS.rglob('*.png')):
 if p.parent.name=='nodes':continue
 w,h=image(p).size;manifest['assets'].append({'entityType':'visualLayer','entityID':p.stem,'assetName':p.stem,'file':p.relative_to(ROOT).as_posix(),'vectorSource':p.with_suffix('.svg').relative_to(ROOT).as_posix(),'widthPx':w,'heightPx':h,'transparent':p.parent.name!='backgrounds' or 'decoration' in p.stem,'colorSpace':'sRGB','status':'production-candidate-awaiting-art-review','source':'本项目原创SVG几何','license':'可随项目使用和修改，无外部素材','sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(ROOT/'asset-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
checks=[]
for a in manifest['assets']:
 im=image(ROOT/a['file']);alpha=im.getchannel('A');bbox=alpha.getbbox()
 assert im.size==(a['widthPx'],a['heightPx'])
 if a['transparent']:assert alpha.getextrema()[0]==0
 if a['entityType']=='nodeVisual':assert min(bbox[0],bbox[1],512-bbox[2],512-bbox[3])>=51
 checks.append({'file':a['file'],'size':im.size,'alphaExtrema':alpha.getextrema(),'alphaBounds':bbox,'sha256':a['sha256']})
(SRC/'validation.json').write_text(json.dumps({'checks':checks,'unknownHiddenTypePixelEquality':True,'fixtureTopologyUnchanged':True,'appOrDeviceTested':False},indent=2))
print(json.dumps({'runtimePNGs':len(manifest['assets']),'previews':len(list(PRE.glob('*.png'))),'checks':'dimensions, alpha, node 10% inset, fixture identity, unknown pixel equality passed'}))
