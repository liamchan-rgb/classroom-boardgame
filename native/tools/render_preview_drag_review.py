#!/usr/bin/env python3
"""Synthetic camera-drag rule review. Never an App, gesture or FPS capture."""
import argparse,sys,json,math
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
p=argparse.ArgumentParser();p.add_argument('map',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
# Reuse the existing resource compositor's map setup, not its old demonstration.
source=Path(__file__).with_name('render_display_mirror_review.py').read_text().split('frames=[];phases=')[0]
oldargs=sys.argv;sys.argv=[str(Path(__file__).with_name('render_display_mirror_review.py')),str(a.map),str(a.output)]
ns={'__file__':str(Path(__file__).with_name('render_display_mirror_review.py'))};exec(compile(source,'offline_map_setup','exec'),ns);sys.argv=oldargs
world=ns['world'];font=ns['font'];text=ns['text'];frames=[];rows=[]
for i in range(60):
 t=i*.04;p=min(1,max(0,(t-.32)/1.28));p=p*p*(3-2*p)
 top=round(240-160*p)
 view=world.crop((0,top,1280,top+720)).convert('RGB')
 f=Image.new('RGB',(1280,800),'#11251b');d=ImageDraw.Draw(f)
 text(f,(20,12),'地图拖动规则示意 · 非App/触摸回放/帧率测试',23)
 text(f,(20,50),'拖动平移视野；双指缩放；点道路移动人物',21)
 for x,title in [(24,'教师预览 · 960×540 / 30fps目标'),(656,'电视 · 同一地图相机 / 60fps目标')]:
  text(f,(x,116),title,20)
  picture=view.resize((960,540),Image.Resampling.NEAREST) if x==24 else view
  f.paste(picture.resize((600,338),Image.Resampling.NEAREST),(x,165))
  d.rectangle((x,165,x+599,502),outline='#9a9366',width=2)
  # Registration marks are solely for this review diagram.
  d.line((x+300,165,x+300,502),fill='#ddd2a3',width=1)
  d.line((x,334,x+600,334),fill='#ddd2a3',width=1)
 if .32<t<1.72:
  cy=265+round(75*p);d.ellipse((274,cy-13,300,cy+13),fill='#e9cc73',outline='#fff4d2',width=2)
  d.line((287,250,287,cy),fill='#f3d583',width=3)
 d.rounded_rectangle((24,540,624,712),radius=12,fill='#e4ebdf')
 text(f,(43,555),'教师操作（不投放）',20,'#234a35')
 text(f,(43,600),'角色 / 地点编辑 / 背包 / 技能',19,'#234a35')
 text(f,(43,648),'拖动抬手不下达走路指令',19,'#234a35')
 text(f,(658,555),'地图与透明公开界面层分别回传',21)
 text(f,(658,600),'静态HUD缓存；战斗界面按目标频率更新',18)
 text(f,(658,644),'此处仅演示规则，真实手感与性能由设备复核',17)
 text(f,(24,752),'复用地图资源；CPU道路/阴影近似，没有生成新人物或技能美术。',16)
 frames.append(f);rows.append({'time':t,'cameraCrop':[0,top,1280,top+720],'syntheticDragY':160*p})
seed=Image.new('RGB',(1280,2400))
for j,n in enumerate([0,30,59]):seed.paste(frames[n],(0,j*800))
palette=seed.quantize(colors=256);q=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
q[0].save(a.output/'preview-drag-normal.gif',save_all=True,append_images=q[1:],duration=40,loop=0,disposal=1,optimize=True)
seed.save(a.output/'preview-drag-contact-sheet.png')
(a.output/'preview-drag-review-input.json').write_text(json.dumps({'kind':'synthetic camera rule review','notAppOrDeviceCapture':True,'notPerformanceMeasurement':True,'durationMS':2400,'sampleMS':40,'teacherTarget':[960,540,30],'publicTargetFPS':60,'frames':rows},ensure_ascii=False,indent=2)+'\n')
with Image.open(a.output/'preview-drag-normal.gif') as im:
 duration=0
 for i in range(im.n_frames):im.seek(i);im.convert('RGB').load();duration+=im.info['duration']
 print(json.dumps({'decodedFrames':im.n_frames,'durationMS':duration,'kind':'offline camera rule illustration'}))
