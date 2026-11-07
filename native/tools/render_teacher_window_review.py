#!/usr/bin/env python3
"""Offline single-page structure schematic using unchanged battle samples; never App capture."""
import sys,json,argparse
from pathlib import Path
from PIL import Image,ImageDraw
p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
source=Path(__file__).with_name('render_teacher_output_review.py').read_text().split('map_panel=map_image()')[0]
old=sys.argv;sys.argv=[str(Path(__file__).with_name('render_teacher_output_review.py')),str(a.input),str(a.output)]
ns={'__file__':str(Path(__file__).with_name('render_teacher_output_review.py'))};exec(compile(source,'offline_existing_resource_setup','exec'),ns);sys.argv=old
text,battle,rows=ns['text'],ns['battle'],ns['rows']
map_source=Path(__file__).with_name('render_display_mirror_review.py').read_text().split('frames=[];phases=')[0]
old=sys.argv;sys.argv=['offline_map',str(a.input/'map.json'),str(a.output)]
map_ns={'__file__':str(Path(__file__).with_name('render_display_mirror_review.py'))};exec(compile(map_source,'offline_existing_map_setup','exec'),map_ns);sys.argv=old
map_im=map_ns['world'].crop((0,200,1280,1032)).resize((508,330),Image.Resampling.NEAREST)
frames=[]
def panel(im,box,color='#1b3225'):
 ImageDraw.Draw(im).rounded_rectangle(box,radius=10,fill=color,outline='#777450',width=1)
def button(im,box,label,selected=False):
 panel(im,box,'#cfb363' if selected else '#dbe5d5');text(im,(box[0]+10,box[1]+8),label,17,'#203b2a')
for i,row in enumerate(rows):
 public=Image.new('RGBA',(1280,720),'#0c1d13');d=ImageDraw.Draw(public)
 panel(public,(64,36,1216,112));text(public,(80,44),'林地遭遇 · 第1轮',25);text(public,(80,80),'P1 · 魔剑士行动 · 公开技能卡',17)
 public.alpha_composite(map_im,(64,124));public.alpha_composite(battle(row).resize((632,330),Image.Resampling.NEAREST),(584,124))
 panel(public,(64,466,1216,530))
 for j,label in enumerate(['P1','P2','鹿灵甲','鹿灵乙']):
  x=110+j*330;d.ellipse((x,481,x+31,512),outline='#e1c67c',width=2);text(public,(x+43,484),label,18)
 panel(public,(64,542,1216,684))
 text(public,(78,548),'生命 16/32',16);text(public,(437,548),'护盾 0/8',16);text(public,(800,548),'行动   ◆ ◆ ◆',16)
 for x,c in [(78,'#49c96c'),(437,'#59cbed'),(800,'#ebcb69')]:
  d.rectangle((x,576,x+295,585),fill='#08170d');d.rectangle((x,576,x+180,585),fill=c)
 titles=['普通攻击 · 1 AP','符文斩 · 2 AP','符文护盾 · 2 AP','战斗符文 · 1 AP']
 details=['当前武器 · 伤害骰','2D12＋2 · 恢复 / 护盾','目标队友恢复 / 护盾','目标队友护盾 / 增伤']
 for j in range(4):
  x=78+j*283.5;panel(public,(x,604,x+273.5,674),'#2b3f30');text(public,(x+10,609),titles[j],20);text(public,(x+10,644),details[j],16)
 if row['age']<0:
  d.rounded_rectangle((359,602,636,676),radius=8,outline='#f0d15d',width=2)
 # The schematic has a separate disclosure banner, not an added in-app component.
 f=Image.new('RGB',(1280,960),'#eaf0e7');dd=ImageDraw.Draw(f)
 text(f,(16,4),'一屏布局离线示意 · 非App/触摸回放 · 既有战斗采样正常速度',18,'#31513c')
 text(f,(26,44),'教师游戏 · v0.13.4',20,'#203c2b');text(f,(305,48),'电视已连接',15,'#526652')
 button(f,(1055,38,1138,78),'全屏');button(f,(1150,38,1253,78),'管理')
 for box,label in [((25,87,236,127),'目标 · 鹿灵甲'),((248,87,350,127),'道具'),((362,87,510,127),'暂停战斗'),((1100,87,1253,127),'结束行动')]:button(f,box,label)
 # Canvas fits as a single 16:9 image; teacher controls are outside captured source.
 f.paste(public.convert('RGB').resize((1248,702),Image.Resampling.NEAREST),(16,166))
 text(f,(27,907),'直接点击画面内技能卡 · 点角色选目标 · 管理栏只在教师端',18,'#244c33')
 # Cursor is an offline annotation, only teacher-side, not new game art.
 if row['age']<0:
  cx,cy=486,791;dd.polygon([(cx,cy),(cx+7,cy+23),(cx+12,cy+13),(cx+23,cy+10)],fill='#fff2be',outline='#203b29')
 frames.append(f)
contact=Image.new('RGB',(1280,960*3))
for j,n in enumerate([0,len(frames)//2,len(frames)-1]):contact.paste(frames[n],(0,j*960))
palette=contact.quantize(colors=256);q=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
q[0].save(a.output/'teacher-window-normal.gif',save_all=True,append_images=q[1:],duration=40,loop=0,disposal=1,optimize=True)
contact.save(a.output/'teacher-window-contact-sheet.png')
with Image.open(a.output/'teacher-window-normal.gif') as im:
 duration=0
 for k in range(im.n_frames):im.seek(k);im.load();duration+=im.info.get('duration',0)
 meta=dict(kind='offline single-page layout schematic',notAppCapture=True,notTouchReplay=True,notPerformanceMeasurement=True,sourceSamples=len(rows),sampleMS=40,totalMS=duration,decodedFrames=im.n_frames,publicCanvas=[1280,720],teacherToolbarCapturedByPublic=False,existingBattleSamples='runeSlash-lethal',limits='CPU layout approximate; actual UIKit and television must be checked by user.')
(a.output/'teacher-window-review-input.json').write_text(json.dumps(meta,indent=2)+'\n');print(json.dumps(meta))
