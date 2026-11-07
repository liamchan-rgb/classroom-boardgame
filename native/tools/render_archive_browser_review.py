#!/usr/bin/env python3
"""Offline archive-browser and art-contract schematic. Not an App capture."""
import argparse,json
from pathlib import Path
from functools import lru_cache
from PIL import Image,ImageDraw,ImageFont
p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
@lru_cache(None)
def font(n):return ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
def text(im,xy,s,n=22,c='#e9ebd9'):ImageDraw.Draw(im).text(xy,s,font=font(n),fill=c)
def box(im,xy,c='#243e2f'):ImageDraw.Draw(im).rounded_rectangle(xy,radius=9,fill=c)
phases=['行程查找 · 原槽号保持','历史分类 · 显示原始序号','回退确认 · 包括筛选隐藏的后续操作','美术对接文档 · 固定来源提交与配套依赖']
frames=[]
for n in range(100):
 stage=n//25;t=(n%25)/24;im=Image.new('RGB',(1440,900),'#102218');d=ImageDraw.Draw(im)
 text(im,(24,12),'行程与历史筛选 / experiment美术对接 · 离线示意，非App截图',24)
 box(im,(22,70,1418,126));text(im,(42,82),'教师管理 → 存档与历史     /     两仓库对接规范',24)
 box(im,(22,148,652,748));box(im,(680,148,1418,748),'#192f23')
 if stage==0:
  text(im,(42,173),'查找已保存行程',27)
  for j,label in enumerate(['搜索：林','状态：战斗中','人数：2人','排序：最近保存优先']):text(im,(42,246+j*72),label,24)
  text(im,(42,590),'匹配 1 / 已保存 3',24,'#efd17e');text(im,(42,665),'清除筛选可恢复完整列表',21)
  text(im,(706,173),'行程槽 7 · 第一节课',27)
  text(im,(708,274),'战斗中 · 2人 · 原保存时间',23)
  text(im,(708,382),'覆盖保存      导出      读取',24)
  text(im,(708,530),'搜索或排序不会把槽7改成槽1',23,'#efd17e')
  text(im,(708,630),'空槽和坏档提示单独保留',22)
 elif stage==1:
  text(im,(42,173),'查找操作',27)
  for j,label in enumerate(['类别：战斗','涉及对象：林 · p2','搜索：普通攻击','排序：最新在前']):text(im,(42,246+j*72),label,24)
  text(im,(42,592),'匹配 2 / 全部 12',24,'#efd17e')
  text(im,(706,173),'原始历史序号',27)
  for j,label in enumerate(['#12 · 战斗 · 普通攻击','#9  · 战斗 · 普通攻击']):box(im,(706,260+j*106,1388,332+j*106),'#304d3a');text(im,(722,277+j*106),label,24)
  text(im,(708,526),'展开可看骰值和成员数值变化',23)
  text(im,(708,632),'索引后台整理，每次先显示50条',22)
 elif stage==2:
  text(im,(42,173),'回退到原第9条之后？',27)
  text(im,(42,272),'保留 #9',27,'#efd17e')
  text(im,(42,370),'撤回原 #10、#11、#12 共3条',24)
  text(im,(42,476),'包括当前未显示的资源/外观操作',22)
  text(im,(42,602),'先备份当前行程，再回退并暂停',22)
  text(im,(706,173),'筛选只改变列表',27)
  for j,label in enumerate(['#10 · 资源（被筛选隐藏）','#11 · 外观（被筛选隐藏）','#12 · 战斗（当前可见）']):text(im,(708,270+j*100),label,23)
  text(im,(708,633),'骰子状态、队列、移动检查点一并恢复',21)
 else:
  text(im,(42,173),'experiment · 制作与交付',27)
  for j,label in enumerate(['固定完整提交SHA','PNG / 图集 + 骨骼JSON + 姿态代码','配饰握点 / 遮挡 / 技能时序 / UI依赖','正常GIF + 实际认可范围 + 缺图项']):text(im,(42,262+j*92),label,22)
  text(im,(42,665),'协议与模板已写进两仓库AGENTS入口',20,'#efd17e')
  text(im,(706,173),'课堂端 · 按清单接入',27)
  for j,label in enumerate(['只读差异盘点 → 选择性合并','保留教师权限、7人和存档适配','离线审核 → 设备Release与包检','正常GIF + 直接IPA + 可恢复归档']):text(im,(708,262+j*92),label,23)
  text(im,(708,665),'本轮未导入未来美术，无自动热更新',20,'#efd17e')
 y=782;d.line((42,y,1396,y),fill='#47654e',width=3);x=42+round(t*1354);d.ellipse((x-5,y-5,x+5,y+5),fill='#e8cb7a')
 text(im,(24,806),phases[stage],24);text(im,(24,852),'正常节奏8秒 · 图中数据为示例；未运行App/模拟器/实机，实际操作由用户安装复核',19)
 frames.append(im)
contact=Image.new('RGB',(1440,3600))
for j,index in enumerate([0,25,50,75]):contact.paste(frames[index],(0,j*900))
palette=contact.quantize(colors=256);q=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
q[0].save(a.output/'archive-browser-normal.gif',save_all=True,append_images=q[1:],duration=80,loop=0,disposal=1,optimize=True);contact.save(a.output/'archive-browser-contact-sheet.png')
with Image.open(a.output/'archive-browser-normal.gif') as im:
 ms=0
 for i in range(im.n_frames):im.seek(i);im.load();ms+=im.info['duration']
 meta=dict(kind='offline archive browser and art contract schematic',notAppCapture=True,notTouchReplay=True,notPerformanceMeasurement=True,totalMS=ms,decodedFrames=im.n_frames,sourceSamples=100,sampleMS=80,phases=phases,artResourcesUpdated=False)
(a.output/'archive-browser-review-input.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n');print(json.dumps(meta))
