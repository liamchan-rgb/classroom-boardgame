#!/usr/bin/env python3
"""Offline save-transfer workflow schematic; no App, touch or performance capture."""
import argparse,json,math
from pathlib import Path
from functools import lru_cache
from PIL import Image,ImageDraw,ImageFont
p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
@lru_cache(None)
def font(n):return ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
def text(im,xy,value,n=21,color='#e9ebd9'):ImageDraw.Draw(im).text(xy,value,font=font(n),fill=color)
def box(im,rect,color='#243e2f'):ImageDraw.Draw(im).rounded_rectangle(rect,radius=10,fill=color)
phases=['勾选已保存的人物和行程槽','生成JSON → 系统文件保存窗口','选择备份 → 校验与目标槽预览','明确确认 → 先备份原槽再导入']
frames=[]
for n in range(100):
 phase=n//25;t=(n%25)/24;im=Image.new('RGB',(1440,900),'#102218');d=ImageDraw.Draw(im)
 text(im,(24,12),'存档导入导出 · 离线流程示意 · 非App截图 / 非实机录屏',24)
 box(im,(22,69,1418,125));text(im,(42,82),'教师：管理 → 存档与历史 → 导入导出',24)
 box(im,(22,147,652,746));box(im,(680,147,1418,746),'#192f23')
 if phase==0:
  text(im,(44,170),'导出备份 · 勾选槽位',27)
  for j,label in enumerate(['☑ 人物槽 1 · 林','☑ 行程槽 2 · 第一节课','□ 行程槽 3 · 第二节课']):
   box(im,(42,240+j*95,630,310+j*95),'#304d3a');text(im,(58,256+j*95),label,23)
  text(im,(44,584),'生成备份并存到文件（2项）',23,'#f0cd7a')
  text(im,(44,659),'仅导出已保存槽位，不自动覆盖当前进度',20)
  text(im,(708,176),'备份内容预览',26)
  text(im,(710,258),'人物：姓名 + 现有外观',24)
  text(im,(710,340),'行程：地图 / 队伍 / 战斗 / 移动条',24)
  text(im,(710,446),'可单个导出，也可合并多个槽位',22)
  text(im,(710,567),'当前游戏仍保持原状态',22,'#e8cb7d')
 elif phase==1:
  text(im,(44,170),'正在准备文件',27);text(im,(44,260),'Meadow-存档备份-日期.json',24)
  text(im,(44,348),'128MB上限 · 大行程可分开导出',22)
  text(im,(44,456),'JSON校验与编码在后台处理',23)
  text(im,(44,635),'取消文件窗口不会更改槽位',22)
  text(im,(708,176),'系统“文件”保存窗口（示意）',26)
  box(im,(710,240,1382,430),'#344e3c');text(im,(740,272),'保存到你选择的位置',25);text(im,(740,350),'存储位置 / 文件名 / 保存',23)
  text(im,(710,530),'文件由你保存与分享',23)
  text(im,(710,605),'不会自动上传设备内的课堂存档',21)
 elif phase==2:
  text(im,(44,170),'导入备份 · 校验通过',27)
  text(im,(44,252),'来源：Meadow-存档备份.json',23)
  for j,label in enumerate(['☑ 人物槽 1 → 人物槽 5','☑ 行程槽 2 → 行程槽 4']):text(im,(44,355+j*98),label,25)
  text(im,(44,600),'将覆盖：行程槽4 · 旧课时',23,'#f0cd7a')
  text(im,(44,665),'目标槽不能重复；可取消条目勾选',20)
  text(im,(708,176),'确认前 · 所有槽位保持原样',26)
  text(im,(710,280),'新旧JSON类型、版本与内容校验',23)
  text(im,(710,385),'可读旧版人物槽 / 行程槽 / 地图工作档',22)
  text(im,(710,510),'文件错误时保留原槽和错误说明',23)
  text(im,(710,620),'此时还没有应用到游戏',23,'#e8cb7d')
 else:
  text(im,(44,170),'确认导入到存档槽',27)
  text(im,(44,252),'2个条目 · 1个已有目标槽',25)
  text(im,(44,350),'人物槽 1 → 人物槽 5',25)
  text(im,(44,430),'行程槽 2 → 行程槽 4',25)
  text(im,(44,550),'先保留覆盖前原文件，再写入新槽',22)
  text(im,(44,648),'中断恢复日志防止暴露半份导入',21)
  text(im,(708,176),'完成后 · 新槽已可读取',26)
  text(im,(710,275),'上一页 → 选择人物/行程槽 → 读取',23)
  text(im,(710,390),'可从导入前备份重新进入预览恢复',22)
  text(im,(710,520),'当前正在玩的游戏不会自动切换',23,'#e8cb7d')
  text(im,(710,626),'未读取前，公开画面保持原样',22)
 # A moving signal illustrates data flow, not measured progress or a touch replay.
 y=782;d.line((44,y,1395,y),fill='#42684b',width=3);x=44+round(t*1351);d.ellipse((x-6,y-6,x+6,y+6),fill='#e5cb77')
 text(im,(24,805),phases[phase],24)
 text(im,(24,853),'正常节奏8秒 · 文件选择器为结构示意；实际iPad交互由用户安装复核',19)
 frames.append(im)
contact=Image.new('RGB',(1440,3600))
for i,index in enumerate([0,25,50,75]):contact.paste(frames[index],(0,i*900))
palette=contact.quantize(colors=256);q=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
q[0].save(a.output/'save-transfer-normal.gif',save_all=True,append_images=q[1:],duration=80,loop=0,disposal=1,optimize=True);contact.save(a.output/'save-transfer-contact-sheet.png')
with Image.open(a.output/'save-transfer-normal.gif') as im:
 duration=0
 for i in range(im.n_frames):im.seek(i);im.load();duration+=im.info['duration']
 meta=dict(kind='offline import/export workflow schematic',notAppCapture=True,notTouchReplay=True,notPerformanceMeasurement=True,sourceSamples=100,sampleMS=80,totalMS=duration,decodedFrames=im.n_frames,phases=phases,transferFormat='JSON v1',profileSlots=12,campaignSlots=8,liveCampaignNotChangedOnImport=True)
(a.output/'save-transfer-review-input.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n');print(json.dumps(meta))
