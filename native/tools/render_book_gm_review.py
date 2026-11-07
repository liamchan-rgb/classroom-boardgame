#!/usr/bin/env python3
"""Offline book status / private GM schematic. Never an App or touch capture."""
import argparse,json
from pathlib import Path
from functools import lru_cache
from PIL import Image,ImageDraw,ImageFont
p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
@lru_cache(None)
def font(n):return ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
def text(im,xy,value,n=18,color='#24472f'):ImageDraw.Draw(im).text(xy,value,font=font(n),fill=color)
def box(im,rect,color='#d9e5d2'):ImageDraw.Draw(im).rounded_rectangle(rect,radius=9,fill=color)
phases=['绘本页选择奖励对象 · 无须切回游戏','发放AP与金币 · 公开状态更新','GM编辑P6草稿 · 公开仍保持旧值','保存GM · 仅公开玩家结果，不显示编辑表单']
frames=[]
for n in range(120):
 stage=n//30;im=Image.new('RGB',(1440,900),'#eef3e8')
 text(im,(18,8),'绘本与GM离线布局示意 · 非App/触摸回放/性能测试',21)
 text(im,(22,57),'教师端 · 绘本与备注 / GM窗口',23)
 box(im,(20,105,454,158));text(im,(32,119),'投放绘本  上一页  下一页  GM',19)
 box(im,(20,174,454,235));text(im,(32,186),'奖励对象 P1、P2   AP +1   金币 +10',17)
 if stage<2:
  box(im,(20,258,454,657),'#fbfcf7');text(im,(36,278),'教师备注（不投放）',21)
  text(im,(36,330),'绘本与状态条保持同一份数据',18)
  text(im,(36,378),'可选择单人 / 多人 / 全选',18)
  text(im,(36,426),'AP按个人上限封顶',18)
  text(im,(36,474),'地图移动条不受发放影响',18)
  text(im,(36,526),'快捷发放 / 撤销最近一次发放',18)
 else:
  box(im,(20,258,454,735),'#fbfcf7');text(im,(36,272),'GM · 任意玩家 / P6',21)
  for j,(label,value) in enumerate([('当前生命','35'),('基础最大生命','40'),('当前行动点','8'),('金币','88'),('大治疗药水 · 背包数量','8'),('增伤 / 技能次数','分别编辑')]):
   y=324+j*52;text(im,(36,y),label,18);text(im,(365,y),value,18)
  text(im,(36,649),'保存修改     关闭     撤销最近GM',18)
  text(im,(36,693),'穿戴与队伍仓库不随背包编辑改变',15)
 text(im,(483,57),'公开电视 · 绘本为主体，状态总高度9%',23)
 public=Image.new('RGB',(1280,720),'#0e1c14');d=ImageDraw.Draw(public)
 d.rectangle((0,0,1279,654),fill='#f5efdf')
 text(public,(245,180),'绘本图像保持原比例',43,'#405449')
 text(public,(245,280),'主体区域 91% · 不展示教师操作',30,'#64745f')
 text(public,(245,375),'示意占位，不会写入绘本或游戏素材',24,'#64745f')
 text(public,(1195,10),'1 / 3',18,'#64745f')
 for i in range(7):
  x=6+i*181;name='P'+str(i+1) if i<6 else '老师·容量示例'
  hp,maxhp=(35,40) if stage==3 and i==5 else (18,18)
  ap=4 if stage>=1 and i<2 else 8 if stage==3 and i==5 else 3
  coins=10 if stage>=1 and i<2 else 88 if stage==3 and i==5 else 0
  text(public,(x+3,658),name,15,'#f2f2e7')
  text(public,(x+3,680),f'HP {hp}/{maxhp}',13,'#f2f2e7')
  d.rectangle((x+89,690,x+173,693),fill='#24452b');d.rectangle((x+89,690,x+89+84*hp/maxhp,693),fill='#49c773')
  text(public,(x+3,701),f'◆ {ap}/8',12,'#edce72');text(public,(x+100,701),f'金币 {coins}',12,'#edce72')
 im.paste(public.resize((936,527),Image.Resampling.LANCZOS),(483,124))
 text(im,(491,685),'公开内容只含绘本、姓名、HP/AP/金币。',20)
 text(im,(491,728),'GM草稿与发放控件始终只在教师端。',20)
 text(im,(22,790),phases[stage],22)
 text(im,(22,835),'7人含老师仅为容量示例；老师启用入口仍预留。实际可读性/键盘/电视隐私由用户安装复核。',17)
 frames.append(im)
contact=Image.new('RGB',(1440,2700))
for j,n in enumerate([0,70,119]):contact.paste(frames[n],(0,j*900))
palette=contact.quantize(colors=256);q=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
q[0].save(a.output/'book-gm-normal.gif',save_all=True,append_images=q[1:],duration=50,loop=0,disposal=1,optimize=True);contact.save(a.output/'book-gm-contact-sheet.png')
with Image.open(a.output/'book-gm-normal.gif') as im:
 duration=0
 for n in range(im.n_frames):im.seek(n);im.load();duration+=im.info.get('duration',0)
 meta=dict(kind='offline book and GM structure schematic',notAppCapture=True,notTouchReplay=True,notPerformanceMeasurement=True,sourceSamples=120,sampleMS=50,totalMS=duration,decodedFrames=im.n_frames,publicCanvas=[1280,720],statusAreaFraction=.09,maximumCapacityExample=7,teacherHostEnableUI=False,privateDraftDoesNotChangePublicUntilSaved=True,phases=phases)
(a.output/'book-gm-review-input.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n');print(json.dumps(meta))
