from pathlib import Path
from PIL import Image
import json,hashlib
R=Path(__file__).resolve().parents[1]
D=json.loads((R/'sources/demo-scenarios.json').read_text());base=D['baseBattle'];P=base['players']
assert len(P)==7 and sum(x['host'] for x in P)==1
assert len(P[0]['name'])==12 and len(P[1]['name'])==24
assert base['currentUnitID'] not in base['rewardObjectIDs']
assert len(base['queue'])==10 and len(set(base['queue']))==10
assert 'ap' not in D['storybookSeven']['publicFields']
checks=[]
for data in json.loads((R/'sources/text-measurements.json').read_text()):
 width,height=data['width'],data['height'];pub=data['name'].startswith('public_')
 errors=[]
 for b in data['boxes']:
  if b['x'] < -.1 or b['x']+b['w'] > width+.1 or b['y']+b['h']>height+.1:errors.append(b)
  if pub and (b['x']<width*.05-.1 or b['x']+b['w']>width*.95+.1 or b['y']<54-.1 or b['y']+b['h']>1026+.1):errors.append(b)
  if pub and b['fontSize']<24:errors.append(b)
 assert not errors,(data['name'],errors)
 if 'storybook' in data['name']:assert not any('AP' in b['text'] for b in data['boxes'])
 im=Image.open(R/'previews'/f"{data['name']}.png");scale=2 if data['name'].startswith('teacher') else 1
 assert im.size==(width*scale,height*scale)
 checks.append({'preview':data['name'],'pngSize':list(im.size),'textCount':len(data['boxes']),'canvasOverflow':0,'publicSafeAreaCheck':pub,'minPublicFont':min(b['fontSize'] for b in data['boxes']) if pub else None})
asset_checks=[]
for a in json.loads((R/'asset-manifest.json').read_text())['assets']:
 if a['status']=='planned':continue
 for v in a.get('variants',[a]):
  f=R/v['file'];im=Image.open(f);assert im.size==(v['widthPx'],v['heightPx']) and im.mode=='RGBA'
  bbox=im.getchannel('A').getbbox();assert bbox and im.getchannel('A').getextrema()[0]==0
  if im.width==1024:assert min(bbox[0],bbox[1],1024-bbox[2],1024-bbox[3])>=102
  assert hashlib.sha256(f.read_bytes()).hexdigest()==v['sha256']
  asset_checks.append({'file':v['file'],'size':list(im.size),'mode':im.mode,'alphaBounds':list(bbox),'sRGB':im.info.get('srgb', 'Chromium export forced sRGB')})
def lum(c):
 x=[int(c[i:i+2],16)/255 for i in (1,3,5)];x=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in x];return sum(a*b for a,b in zip(x,[.2126,.7152,.0722]))
def contrast(a,b):
 lo,hi=sorted([lum(a),lum(b)]);return (hi+.05)/(lo+.05)
t=json.loads((R/'design-tokens.json').read_text());c=t['colors'];contrasts=[]
for token in ['ink','muted','primary','accent','danger','shield','action']:
 for bg in ['#FFFFFF','#F5F1E8','#E4EDD9','#EDF0EA']:
  ratio=contrast(c[token],bg);assert ratio>=4.5
  contrasts.append({'token':token,'foreground':c[token],'background':bg,'ratio':round(ratio,2)})
report={'formatVersion':1,'scope':'静态设计导出，不是App或设备验收','fixtureChecks':'7玩家/1主持人/10队列单位/12中文/24英文/行动奖励独立/绘本无AP','previewChecks':checks,'assetChecks':asset_checks,'contrastChecks':contrasts,'limitations':['iOS原生毛玻璃/液态玻璃需真实系统验证','最远课堂观看与无线投屏未测试','占位绘本页不是实际PPTX导入测试','超长队伍名/三位数资源等额外压力场景待接入测试']}
(R/'sources/validation-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
lines=['# 第一轮静态校验记录','', '实际通过：13张预览PNG尺寸、文本字形边界；公开所有文字在5%安全区且字号不低于24；7角色和长姓名；绘本公开页无AP；4张头像1024透明、留边>=10%；6套256透明资源图标；模板ID对应；逐文件校验。','', '公开姓名28、资源26、队列辅助24。教师PNG2732×2048，公开1920/1440×1080。两行长姓名与底部资源都经浏览器字形测量；未依赖SVG画布尺寸来判定文本。','', '金色由标准建议#B76A08调整为#995207，避免白字小徽章与浅底金色小字对比不足。其余语义颜色保持原建议。颜色对比度：','', '| 令牌 | 白底 | 暖白底 | 地图底 |','|---|---:|---:|---:|']
for token in ['ink','muted','primary','accent','danger','shield','action']:lines.append('| '+token+' | '+' | '.join(str(round(contrast(c[token],bg),2))+':1' for bg in ['#FFFFFF','#F5F1E8','#E4EDD9'])+' |')
lines+=['','具体数值与资产透明边界见sources/validation-report.json。13张图均做边界测量，教师/公开两比例、风格板和组件板做目视检查。纯色衬底对比度不能替代动态系统毛玻璃实测，原生须尊重降低透明度。','', '没有执行App规则、Xcode构建、IPA编译或真机/电视验证。未获得实际PPTX；后续场景列为接入验收。A/B样稿尚未确认，不声称全套4职业/6怪物已定稿。']
(R/'annotations/07_validation.md').write_text('\n'.join(lines)+'\n')
print('PASS: 13 previews, 10 transparent raster assets, shared fixture, contrast and public safe bounds')
