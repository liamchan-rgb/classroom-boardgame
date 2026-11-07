#!/usr/bin/env python3
"""Offline workflow schematic using approved atlas art, never an App capture."""
import argparse,json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
from functools import lru_cache
p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
r=Path(__file__).resolve().parents[1];assets=r/'ClassroomProbe/Resources/Assets.xcassets'
@lru_cache(None)
def font(n):return ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
def text(im,xy,s,n=20,c='#e7e7cb'):ImageDraw.Draw(im).text(xy,s,font=font(n),fill=c)
def box(im,xy,c='#233c2d'):ImageDraw.Draw(im).rounded_rectangle(xy,radius=9,fill=c)
source=next((assets/'Hero1Directions.imageset').glob('*.png'));atlas=Image.open(source).convert('RGBA');cell=atlas.height//4;hero=atlas.crop((0,0,cell,cell));hero=hero.resize((240,240),Image.Resampling.NEAREST)
phases=['保存人物档案 · 姓名和装扮独立于整局状态','选择完整行程槽 · 读取前自动备份','操作历史 · 保留选中条目并撤回后续操作','老师加入独立P7席位 · 六名学生保持']
frames=[]
for i in range(120):
 stage=i//30;im=Image.new('RGB',(1440,900),'#102218');text(im,(24,14),'人物档案 / 行程槽 / 历史 / 老师参战 · 离线流程示意，非App截图',23)
 box(im,(22,70,1408,124));text(im,(40,82),'教师管理：  人物档案    行程槽位    操作历史    老师参战',24)
 box(im,(22,144,650,752));box(im,(674,144,1408,752),'#192f22')
 text(im,(696,163),'公开界面 · 保持当前游戏/绘本',24)
 if stage==0:
  text(im,(42,164),'人物槽 01 · 林',27);text(im,(42,220),'姓名：林',23);text(im,(42,268),'外观：林间绿衣 / 跟随实际护甲',23)
  im.paste(hero,(174,300),hero)
  text(im,(42,564),'保存档案 → 下次新行程按成员读取',22)
  text(im,(42,620),'档案不含金币、背包、职业或地图进度',20)
  text(im,(42,674),'应用到当前角色需明确点击确认',20)
 elif stage==1:
  text(im,(42,164),'行程槽 01 · 第一节课',27)
  for j in range(4):
   box(im,(42,224+j*88,630,294+j*88),'#2c4936');text(im,(56,236+j*88),f'行程槽 {j+1:02d} · '+('第一节课 / 6人 / 10节点' if j==0 else '空槽'),21)
  text(im,(42,614),'保存完整地图、队伍、战斗和移动条',21)
  text(im,(42,666),'读档前自动备份 · 可从恢复列表读取',21)
 elif stage==2:
  text(im,(42,164),'回退到选中操作之后',27)
  for j,label in enumerate(['#14 发放金币 +10','▶ #13 更新人物档案','   #12 老师加入P7']):text(im,(42,240+j*95),label,24)
  text(im,(42,551),'保留第13条 → 撤回其后1条操作',23)
  text(im,(42,612),'恢复骰子、队列、移动检查点并暂停',21)
  text(im,(42,670),'回退前也会备份当前行程',21)
 else:
  text(im,(42,164),'老师参战 · 独立席位 P7',27)
  for j,label in enumerate(['人物名：老师','职业：冒险者 / 游侠 / 魔剑士 / 龙骑士','队伍：林间小队','装扮：使用人物编辑区的现有装扮']):text(im,(42,237+j*78),label,22)
  text(im,(42,592),'仅探索且停止移动时加入',22)
  text(im,(42,654),'1—6学生 + 1老师 · 同一正式战斗引擎',21)
 text(im,(720,230),'教师表单与存档列表不会投放',25)
 for j in range(7 if stage==3 else 6):
  x=716+(j%4)*160;y=310+(j//4)*155
  im.paste(hero.resize((130,130),Image.Resampling.NEAREST),(x,y),hero.resize((130,130),Image.Resampling.NEAREST))
  text(im,(x+43,y+132),'P'+str(j+1),18,'#e8c66e')
 text(im,(714,676),'既有角色素材示意；不代表新的体型美术',18)
 text(im,(24,782),phases[stage],25)
 text(im,(24,838),'正常节奏6秒 · 原素材复用 · 不运行App/模拟器/实机；实际点击与电视表现由用户安装复核',19)
 frames.append(im)
contact=Image.new('RGB',(1440,3600))
for j in range(4):contact.paste(frames[j*30],(0,j*900))
palette=contact.quantize(colors=256);q=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
q[0].save(a.output/'player-slots-normal.gif',save_all=True,append_images=q[1:],duration=50,loop=0,disposal=1,optimize=True);contact.save(a.output/'player-slots-contact-sheet.png')
with Image.open(a.output/'player-slots-normal.gif') as gif:
 total=0
 for i in range(gif.n_frames):gif.seek(i);gif.load();total+=gif.info.get('duration',0)
 meta=dict(kind='offline workflow schematic with existing approved atlas',notAppCapture=True,notTouchReplay=True,notPerformanceMeasurement=True,sourceSamples=120,sampleMS=50,totalMS=total,decodedFrames=gif.n_frames,profileSlots=12,campaignSlots=8,teacherHostEnableUI=True,phases=phases)
(a.output/'player-slots-review-input.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n');print(json.dumps(meta))
