from pathlib import Path
import json,hashlib,html,shutil
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
ref=json.loads((ROOT/'sources/reference-manifest.json').read_text())
jobs={a['entityID']:a for a in json.loads((ROOT/'sources/export-jobs.json').read_text())}
catalog=json.loads((ROOT/'sources/reference_initial-content.json').read_text())
assets=[];report=[]
for old in ref['assets']:
 a=dict(old);kind=a['entityType'];ID=a['entityID']
 if kind in ['classes','monsters','items']:
  a.pop('variants',None);a['file']=f"assets/{kind}/{a['assetName']}.png";p=ROOT/a['file'];im=Image.open(p)
  expected=512 if kind=='items' else 1024;assert im.size==(expected,expected) and im.mode=='RGBA'
  alpha=im.getchannel('A');bbox=alpha.getbbox();margin=min(bbox[0],bbox[1],im.width-bbox[2],im.height-bbox[3])/im.width
  assert margin>=.10 and alpha.getextrema()[0]==0,(ID,bbox)
  a.update(status='production-candidate-reused-style-sample' if ID in ['adventurer','slime'] else 'production-candidate-awaiting-art-review',styleVersion='b-production-v1',selectedStyle='b',widthPx=expected,heightPx=expected,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),colorSpace='sRGB',transparent=True)
  if ID in jobs:a['source']=jobs[ID]['source'];a['exportSource']=jobs[ID]['svg'];a['exportMethod']=jobs[ID]['method']
  else:a['source']='unchanged B round1 portrait';a['exportMethod']='byte-preserving copy'
  a['license']='OpenAI服务适用条款；原创生成，无第三方游戏素材，不声明独占权'
  report.append({'entityID':ID,'file':a['file'],'size':im.size,'mode':im.mode,'alphaBBox':bbox,'minimumTransparentInsetFraction':round(margin,4),'sha256':a['sha256']})
 elif kind=='uiResource':
  (ROOT/'assets/icons').mkdir(exist_ok=True)
  oldpath=ROOT.parent/'ui-art-delivery'/a['file'];shutil.copy(oldpath,ROOT/a['file'])
  if a.get('editableSource'):shutil.copy(ROOT.parent/'ui-art-delivery'/a['editableSource'],ROOT/a['editableSource'])
  svg=oldpath.with_suffix('.svg')
  if svg.exists():shutil.copy(svg,(ROOT/a['file']).with_suffix('.svg'))
  a['status']='reused-original-resource-icon'
 assets.append(a)

ids={a['entityID'] for a in assets if a['entityType'] in ['classes','monsters','items']}
assert ids=={a['id'] for k in ['classes','monsters','items'] for a in catalog[k]}
for ID,fn in [('adventurer','class_adventurer_portrait.png'),('slime','monster_slime_portrait.png')]:
 p=next(a for a in assets if a['entityID']==ID)
 assert (ROOT/p['file']).read_bytes()==(ROOT.parent/'ui-art-delivery/assets/style_b'/fn).read_bytes()
manifest={'formatVersion':1,'deliveryVersion':'2026-10-12-b-production-v1','selectedStyle':'b','status':'static-art-produced-animations-in-progress','counts':{'classes':4,'monsters':6,'items':18},'notes':['本轮有28张独立实体PNG；不把制作完成等同用户逐图审美通过。','2张沿用原B样稿，26张新增独立标准导出。','头像中的武器是职业象征，不修改新局赠送训练短剑或装备规则。','姓名/数字/队伍/价格/数量均由App生成，不在素材中。','nodeVisual地点与正式地图装饰仍planned；原6图标沿用。','基础动画另列animation-manifest，不能将变换型动效当成逐帧骨骼。'],'assets':assets}
(ROOT/'asset-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(ROOT/'sources/static-validation.json').write_text(json.dumps({'status':'passed','scope':'static-assets-only','entities':report,'catalogIDsMatch':True,'originalBSamplesUnchanged':True,'PPTXTested':False,'nativeTested':False},ensure_ascii=False,indent=2)+'\n')

def gallery(kind,cols,cellw,cellh):
 group=[a for a in assets if a['entityType']==kind];rows=(len(group)+cols-1)//cols;w=cols*cellw;h=rows*cellh+100
 parts=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}"><rect width="{w}" height="{h}" fill="#F2F8FC"/><text x="30" y="52" font-family="Noto Sans CJK SC,sans-serif" font-size="32" fill="#173F50">B 晴空学园 · {dict(classes="4职业",monsters="6怪物",items="18装备道具")[kind]}</text>']
 for i,a in enumerate(group):
  x=i%cols*cellw;y=i//cols*cellh+80
  parts.append(f'<rect x="{x+12}" y="{y+12}" width="{cellw-24}" height="{cellh-24}" rx="18" fill="#FFFFFF"/><image href="../{a["file"]}" x="{x+22}" y="{y+20}" width="{cellw-44}" height="{cellh-90}" preserveAspectRatio="xMidYMid meet"/><text x="{x+cellw/2}" y="{y+cellh-36}" text-anchor="middle" font-family="Noto Sans CJK SC,sans-serif" font-size="26" fill="#173F50">{html.escape(a["label"])}</text>')
 parts.append('</svg>');name=f'{kind}_contact_sheet';(ROOT/'sources'/f'{name}.svg').write_text(''.join(parts))
 return {'name':name,'width':w,'height':h,'source':'sources/'+name+'.svg','file':'previews/'+name+'.png'}
index=[gallery('classes',4,400,580),gallery('monsters',3,512,500),gallery('items',6,256,310)]
(ROOT/'sources/gallery-index.json').write_text(json.dumps(index,ensure_ascii=False,indent=2)+'\n')
print('PASS: 28 independent PNGs, exact catalog IDs, alpha margins and unchanged B references')
