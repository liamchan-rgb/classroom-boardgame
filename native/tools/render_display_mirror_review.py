#!/usr/bin/env python3
"""Offline map/letterbox demonstration, never a UIKit/Metal/device capture."""
from pathlib import Path
from functools import lru_cache
import json,math,argparse
from PIL import Image,ImageDraw,ImageFont,ImageFilter
p=argparse.ArgumentParser();p.add_argument('map',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
r=Path(__file__).resolve().parents[1];assets=r/'ClassroomProbe/Resources/Assets.xcassets';layout=json.loads(a.map.read_text());height=round(layout['coordinateHeight'])
fontpath='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
@lru_cache(None)
def font(n):return ImageFont.truetype(fontpath,n)
@lru_cache(None)
def asset(name):
 folder=assets/(name+'.imageset');c=json.loads((folder/'Contents.json').read_text());file=next(x['filename'] for x in c['images'] if 'filename' in x);return Image.open(folder/file).convert('RGBA')
def text(im,pos,s,size=18,color='#efdfb4'):ImageDraw.Draw(im).text(pos,s,font=font(size),fill=color)
# Existing map assets only; roads, shadows and light below are explicitly approximate.
tile=asset('MeadowGround').resize((440,440));world=Image.new('RGBA',(1280,height))
for y in range(0,height,440):
 for x in range(0,1280,440):world.alpha_composite(tile,(x,y))
d=ImageDraw.Draw(world)
for road in layout['roads']:d.line([(p['x'],p['y']) for p in road['points']],fill='#7d704b',width=28,joint='curve')
props=[]
for prop in sorted(layout['props'],key=lambda p:p['y']):
 im=asset(prop['asset']);w=round(prop['width']);h=round(w*im.height/im.width);im=im.resize((w,h),Image.Resampling.LANCZOS);x,y=prop['x'],prop['y']
 shadow=Image.new('RGBA',world.size);ImageDraw.Draw(shadow).ellipse((x-w*.25,y-3,x+w*.4,y+w*.12),fill=(5,18,8,70));world.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(3)))
 props.append((im,(round(x-w/2),round(y-h*.91))))
for im,pos in props:world.alpha_composite(im,pos)
spawn=layout['spawn'];cx=max(640,min(640,spawn['x']));cy=max(360,min(height-360,spawn['y']))
canvas=world.crop((round(cx-640),round(cy-360),round(cx+640),round(cy+360))).convert('RGB')
# Visible registration crosses are review marks, not new game UI/assets.
for x,y in [(120,120),(640,360),(1160,610)]:
 d=ImageDraw.Draw(canvas);d.line((x-12,y,x+12,y),fill='#f4da8b',width=2);d.line((x,y-12,x,y+12),fill='#f4da8b',width=2)
text(canvas,(25,20),'同一1280×720游戏画布 · 离线地图资源示意',23)
def fitted(im,box):
 x,y,w,h=box;out=Image.new('RGB',(w,h),'#050d09');scale=min(w/1280,h/720);nw,nh=round(1280*scale),round(720*scale);out.paste(im.resize((nw,nh),Image.Resampling.NEAREST),((w-nw)//2,(h-nh)//2));return out
frames=[];phases=['iPad初始 · 本机实际预览','连接电视 · 教师回传同一游戏画面','电视保持16:9 · 教师操作栏不投放','断开电视 · 同一画布回到iPad','再次连接 · 地图与相机保持']
for i in range(100):
 stage=i//20;f=Image.new('RGB',(1280,850),'#11231a');d=ImageDraw.Draw(f)
 text(f,(20,12),'固定画布/连接切换规则示意 · 非App/Metal截图，非设备修复复验',21)
 text(f,(20,48),phases[stage],21)
 # Teacher controls are outside the sampled game area.
 d.rounded_rectangle((16,92,610,812),radius=14,fill='#e8eee4');text(f,(30,102),'教师iPad · 游戏与私有操作',21,'#1d4633')
 f.paste(fitted(canvas,(0,0,564,390)),(30,145))
 for j,s in enumerate(['角色选择 / 相机与道路选点','后台编辑地点 / 背包与资源','移动补充 / 战斗技能与目标']):
  y=555+j*63;d.rounded_rectangle((32,y,590,y+49),radius=8,fill='#c4d6c3');text(f,(46,y+10),s,19,'#214533')
 text(f,(650,104),'公开电视 · 只有游戏内容',21)
 if stage in [1,2,4]:f.paste(fitted(canvas,(0,0,600,337)),(650,175))
 else:
  d.rectangle((650,175,1250,512),fill='#050d09');text(f,(810,320),'电视未连接',23)
 text(f,(652,550),'内部坐标、地图、相机不随窗口改变',20)
 text(f,(652,591),'控件与编辑弹窗只在教师端',20)
 text(f,(652,632),'实际电视/断开后的对齐仍需用户截图验证',17)
 text(f,(20,822),'资源复用；离线道路/阴影近似。这里只审核显示规则，不模拟真实投屏连接。',15)
 frames.append(f)
seed=Image.new('RGB',(1280,850*3))
for j,index in enumerate([0,45,65]):seed.paste(frames[index],(0,j*850))
palette=seed.quantize(colors=256);q=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
q[0].save(a.output/'display-mirror-normal.gif',save_all=True,append_images=q[1:],duration=80,loop=0,disposal=1,optimize=True)
seed.save(a.output/'display-mirror-contact-sheet.png')
(a.output/'display-mirror-review-input.json').write_text(json.dumps(dict(kind='offline fixed-canvas demonstration',notNativeCapture=True,notDeviceRepairVerification=True,canvas=[1280,720],phases=phases,normalFrameMS=80,totalMS=8000,map=layout),ensure_ascii=False,indent=2)+'\n')
with Image.open(a.output/'display-mirror-normal.gif') as im:
 total=0
 for n in range(im.n_frames):im.seek(n);im.convert('RGB').load();total+=im.info['duration']
 print(json.dumps(dict(decodedFrames=im.n_frames,totalDurationMS=total,normalSpeed=True)))
