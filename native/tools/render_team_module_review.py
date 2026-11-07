#!/usr/bin/env python3
"""Offline team/warehouse schematic with reused actor assets. Not App capture."""
import sys,json,argparse,copy
from pathlib import Path
from PIL import Image,ImageDraw
p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
source=Path(__file__).with_name('render_teacher_output_review.py').read_text().split('map_panel=map_image()')[0]
old=sys.argv;sys.argv=[str(Path(__file__).with_name('render_teacher_output_review.py')),str(a.input),str(a.output)]
ns={'__file__':str(Path(__file__).with_name('render_teacher_output_review.py'))};exec(compile(source,'existing_resource_setup','exec'),ns);sys.argv=old
text=ns['text'];draw_battle=ns['battle'];base=copy.deepcopy(ns['rows'][0]);base['darkness']=0;base['runes']={'glows':[],'motes':[],'spriteLayers':[]};base['dice']=[];base['poly']=[];base['damageLabels']=[]
players=[]
for i in range(6):
 u=copy.deepcopy(base['units'][i%2]);u['id']='p'+str(i+1);u['name']='P'+str(i+1);u['clip']='idle';u['progress']=0;u['shield']=0;players.append(u)
base['units']=players+[u for u in base['units'] if u['id'].startswith('m')]
ns['feet'].update({'p3':(80,300),'p4':(280,315),'p5':(75,555),'p6':(440,555)})
plate=draw_battle(base).convert('RGB');frames=[]
phases=['六名学生 · 默认同队','拆成红蓝两队 · 个人资产不变','同队存仓与转交 · 战斗禁取仓','合并队伍 · 成员与仓库一起归入目标队']
for i in range(100):
 stage=i//25;im=Image.new('RGB',(1400,870),'#ecf1e7');d=ImageDraw.Draw(im)
 text(im,(20,8),'组队模块离线结构示意 · 非App/触摸回放/帧率测试',20,'#254a34')
 text(im,(22,48),'教师私有 · 管理 → 队伍与仓库',23,'#254a34')
 for n in range(6):
  y=110+n*58;d.rounded_rectangle((22,y,510,y+48),radius=8,fill='#d5e1cf')
  team='林间小队' if stage==0 else ('红队' if n<3 else '蓝队') if stage<3 else '蓝队'
  text(im,(38,y+10),f'P{n+1}     {team}',20,'#24482f')
 text(im,(30,478),'添加队伍 / 调整成员 / 保存分组',20,'#27472f')
 text(im,(30,522),'共享仓库：金币与物品分别保留',19,'#27472f')
 text(im,(30,562),'同队互转 · 存仓 · 取仓',19,'#27472f')
 text(im,(30,602),'行动点不转移 · 换队不重置技能',19,'#27472f')
 text(im,(30,645),'主持人席位：独立p7后台接口预留',18,'#526b51')
 text(im,(550,48),'公开战斗区域 · 原演员资源复用 / 六名学生可进入原队列',20,'#24472f')
 im.paste(plate.resize((824,494),Image.Resampling.NEAREST),(550,110))
 text(im,(558,630),'分队移动：最大AP平均 ×50，各队余额独立',20,'#24472f')
 text(im,(558,674),'学生最多6名；老师席位不占学生名额',20,'#24472f')
 text(im,(30,740),phases[stage],23,'#24472f')
 text(im,(30,785),'缺失项：P3—P7独立外观；当前复用现有素材，以编号/姓名区分。',19,'#526b51')
 text(im,(30,826),'此图仅审核结构与复用站位；实际UIKit布局、点击和电视效果由用户安装验证。',17,'#526b51')
 frames.append(im)
contact=Image.new('RGB',(1400,2610))
for j,n in enumerate([0,40,99]):contact.paste(frames[n],(0,j*870))
palette=contact.quantize(colors=256);q=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
q[0].save(a.output/'team-module-normal.gif',save_all=True,append_images=q[1:],duration=60,loop=0,disposal=1,optimize=True);contact.save(a.output/'team-module-contact-sheet.png')
with Image.open(a.output/'team-module-normal.gif') as im:
 duration=0
 for n in range(im.n_frames):im.seek(n);im.load();duration+=im.info.get('duration',0)
 meta=dict(kind='offline team module schematic',notAppCapture=True,notTouchReplay=True,notPerformanceMeasurement=True,samples=100,sampleMS=60,totalMS=duration,decodedFrames=im.n_frames,maximumStudents=6,reservedTeacherSeat='p7',phases=phases,artMissing='P3-P7 distinct appearances; existing resources reused',positions={k:v for k,v in ns['feet'].items() if k.startswith('p')})
(a.output/'team-module-review-input.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n');print(json.dumps(meta))
