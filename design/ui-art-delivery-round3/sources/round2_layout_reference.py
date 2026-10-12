"""Editable UI drawings only. Reuses unchanged round1 B artwork; no gameplay code."""
from pathlib import Path
import json, math
import round1_layout_reference as ref

ROOT=Path(__file__).resolve().parents[1]
INK='#173F50'; MUTED='#4C6875'; PRIMARY='#176A86'; GOLD='#995207'
ref.ROOT=ROOT
ref.INK=INK; ref.MUTED=MUTED; ref.GREEN=PRIMARY
ref.themes['b'].update(sky='#E5F1F6',land='#C9E0EB',tint='#E4F1F6')
OLD_S=ref.S
COLORS={'#183B36':INK,'#526B64':MUTED,'#176B5B':PRIMARY,'#E4EDD9':'#E4F1F6',
        '#E5EDE3':'#E3EEF4','#F0F3EC':'#EAF0F3','#F0F3EF':'#EAF0F3',
        '#E1EEE7':'#E1EFF6','#EDF0EA':'#EAF0F3','#CDD8D0':'#CCDDE6',
        '#DAE3DA':'#D5E3EB','#8B9E90':'#819EAC','#F3F5EF':'#EEF5F8'}
class S(OLD_S):
 def __init__(self,w,h):
  super().__init__(w,h)
  self.a[0]=self.a[0].replace('#FBF9F2','#F5FAFC').replace('#E8EEDC','#E3EFF5').replace('#183B36',INK)
 def rect(self,x,y,w,h,fill='#FFFFFF',r=16,stroke=None,sw=1,opacity=1):
  super().rect(x,y,w,h,COLORS.get(fill,fill),r,COLORS.get(stroke,stroke),sw,opacity)
 def t(self,x,y,text,size=18,color=INK,weight=400,anchor='start'):
  super().t(x,y,text,size,COLORS.get(color,color),weight,anchor)
 def save(self,name,scale=1,label=''):
  super().save(name,scale,label)
  ref.META[-1]['revision']='round2'
ref.S=S
original_art=ref.art
def b_art(s,theme,which,x,y,w,h):original_art(s,'b',which,x,y,w,h)
ref.art=b_art

def backdrop(s,theme='b'):
 s.rect(0,0,s.w,s.h,'url(#cream)',0)
 # Low contrast decorative skylines only, no logical map content.
 for i in range(15):
  x=i*s.w/14; y=s.h*.40+math.sin(i*.7)*s.h*.08
  s.rect(x-30,y,s.w/12,s.h,'#BFDCE9',0,opacity=.11)
  s.rect(x-30,y,s.w/15,18,'#D8ECF5',0,opacity=.25)
 s.rect(0,0,s.w,6,PRIMARY,0)
ref.backdrop=backdrop

TEAMS={'蓝队':('#315E9C','●'),'橙队':('#995207','◆'),'紫队':('#6650A4','▲')}
def team_marker(s,team,x,y,r=8):
 color,shape=TEAMS[team]
 if shape=='●':s.circle(x,y,r,color)
 elif shape=='◆':s.add(f'<path d="M{x} {y-r}L{x+r} {y}L{x} {y+r}L{x-r} {y}Z" fill="{color}"/>')
 else:s.add(f'<path d="M{x} {y-r}L{x+r} {y+r}L{x-r} {y+r}Z" fill="{color}"/>')

def icon(s,key,x,y,size=26):s.image(ROOT/'assets/icons'/f'icon_{key}.png',x,y,size,size)
def team_legend(s,x,y,fs=24):
 for i,(name,(co,shape)) in enumerate(TEAMS.items()):
  xx=x+i*118;team_marker(s,name,xx,y-8,8);s.t(xx+17,y,name,fs,MUTED)

def player_name(s,p,x,y,w,fs=28):
 # Character breaks remain display-only; all original characters retained.
 n=p['name']; limit=max(1,int(w/(fs*(.60 if n.isascii() else 1))))
 if n.isascii():limit=min(12,limit)
 ls=[n[i:i+limit] for i in range(0,len(n),limit)]
 s.lines(x,y,ls,fs,INK,fs+3,600)
 return len(ls)

def battle_cards(s,ps,x,y,totalw,compact):
 gap=0 if compact else 8
 widths=[222,222]+[(totalw-444)/5]*5 if compact else [(totalw-6*gap)/7]*7
 ch=186
 s.glass(x,y,totalw,ch)
 for i,p in enumerate(ps):
  cw=widths[i];xx=x+sum(widths[:i])+i*gap
  if p['current']:s.rect(xx+2,y+2,cw-4,ch-4,'none',14,PRIMARY,3)
  if i:s.line(xx-gap/2,y+12,xx-gap/2,y+ch-12,'#C9DDE7',1)
  team_marker(s,p['team'],xx+12,y+19,7)
  s.t(xx+cw-8,y+25,f"AP {p['ap']}",26,ref.PURPLE,600,'end')
  player_name(s,p,xx+8,y+53,cw-16,28)
  status='主持人' if p['host'] else '倒地' if p['health']==0 else ''
  if status:s.t(xx+8,y+90,status,24,ref.RED if p['health']==0 else PRIMARY,600)
  ry=y+132
  icon(s,'health',xx+8,ry-22);s.t(xx+40,ry,f"{p['health']}/{p['maximumHealth']}",26)
  icon(s,'shield',xx+cw-59,ry-22);s.t(xx+cw-27,ry,str(p['shield']),26)
  icon(s,'coin',xx+8,ry+7);s.t(xx+40,ry+29,str(p['coins']),26)
  icon(s,'score',xx+cw-59,ry+7);s.t(xx+cw-27,ry+29,str(p['score']),26)
 team_legend(s,x+16,y+ch+28)
 for j,(key,label) in enumerate([('health','生命'),('shield','护盾'),('coin','金币'),('score','积分')]):
  ix=x+totalw-420+j*106;icon(s,key,ix,y+ch+7,24);s.t(ix+28,y+ch+28,label,24,MUTED)

def node_map(s,x,y,w,h,public=True):
 s.rect(x,y,w,h,'#E4F1F6',16)
 d=json.loads((ROOT/'sources/demo-scenarios.json').read_text())['baseBattle']
 # Alternate drawing positions preserve the original graph, IDs and statuses.
 coords={1:(.15,.62),2:(.32,.24),3:(.53,.60),4:(.80,.18),5:(.84,.80)}
 pts={k:(x+w*a,y+h*b) for k,(a,b) in coords.items()}
 for rd in d['roads']:
  a=pts[rd['a']];b=pts[rd['b']];s.line(*a,*b,'#96B7C5',7);s.line(*a,*b,'#F8FCFF',2)
 for n in d['nodes']:
  nx,ny=pts[n['id']];s.circle(nx,ny,29,'#FFFFFF',PRIMARY if n['id']==3 else '#AEC6D1',4 if n['id']==3 else 2)
  s.t(nx,ny+10,str(n['id']) if n['revealed'] else '?',28,INK,600,'middle')
  s.t(nx,ny+61,n['name'],26,INK,500,'middle')
 for node,label,color in [(1,'角色 1',PRIMARY),(2,'角色 3',PRIMARY),(3,'角色 3 · 敌人 2',PRIMARY),(4,'敌人 1',ref.RED)]:
  nx,ny=pts[node]; width=198 if node==3 else 114
  s.badge(nx-width/2,ny-77,width,label,color,24)
 s.t(x+20,y+36,'当前地图',30,INK,600)

def header(s,compact=False,battle=True):
 inset=72 if compact else 96; w=s.w-2*inset
 s.glass(inset,54,w,150)
 s.t(inset+24,94,'PVE · 第1轮' if battle else '探索',30,INK,600)
 s.t(inset+24,142,'行动中：晨曦森林守护者小队长安然' if battle else '已揭示道路与地点',36 if compact else 44,INK,600)
 if battle:
  s.t(s.w-inset-24,96,'已暂停 · 17秒',32,INK,600,'end')
  s.t(inset+24,173,'① 安然 → ② 史莱姆甲 → ③ Alex → ④ 小禾 → ⑤ 史莱姆乙',24)
  s.t(inset+24,201,'⑥ 星星 → ⑦ 阿乐（倒地） → ⑧ 小满 → ⑨ 狼（第2轮） → ⑩ 主持人',24,MUTED)

def battle_stage(s,x,y,w,h,compact):
 s.glass(x,y,w,h)
 s.t(x+22,y+42,'浅溪石桥 · 战斗',32,INK,600)
 s.t(x+w-22,y+42,'已结算',24,MUTED,500,'end')
 # Static stage: existing B art only. No new character asset, no animation.
 stage_h=170 if compact else 220
 stage_y=y+60
 s.rect(x+18,stage_y,w-36,stage_h,'#E8F3F8',18)
 s.add(f'<ellipse cx="{x+w*.28}" cy="{stage_y+stage_h-14}" rx="70" ry="10" fill="#B8D3DF" opacity=".45"/>')
 s.add(f'<ellipse cx="{x+w*.75}" cy="{stage_y+stage_h-14}" rx="60" ry="10" fill="#B8D3DF" opacity=".45"/>')
 sz=180 if compact else 230
 ref.art(s,'b','hero',x+w*.28-sz/2,stage_y-10,sz,sz)
 ref.art(s,'b','slime',x+w*.75-sz/2,stage_y-10,sz,sz)
 s.t(x+w*.28,stage_y+stage_h-3,'安然',26,INK,600,'middle')
 s.t(x+w*.75,stage_y+stage_h-3,'史莱姆甲',26,INK,600,'middle')
 by=stage_y+stage_h+40
 s.t(x+22,by,'强击',30,PRIMARY,600)
 s.t(x+w-22,by,'D6：4 + 2 = 6',28,INK,600,'end')
 s.t(x+22,by+40,'生命 8 → 2 · 护盾吸收 0',26)
 s.t(x+22,by+77,'安然 AP 4 → 3',26,ref.PURPLE)
 # Skill history is read-only and comes from the committed action.
 sy=by+100
 s.rect(x+18,sy,w-36,68,'#DCECF5',14)
 s.t(x+34,sy+28,'强击 · 已执行',26,PRIMARY,600)
 s.t(x+34,sy+60,'目标：史莱姆甲',24,MUTED)

def public_battle(compact=False,expanded=True):
 W=1440 if compact else 1920; inset=72 if compact else 96; total=W-2*inset
 s=S(W,1080);backdrop(s);header(s,compact,expanded)
 y=228; h=552; gap=24
 mapw=(596 if compact else 760) if expanded else total
 s.glass(inset,y,mapw,h);node_map(s,inset+14,y+14,mapw-28,h-28)
 if expanded:battle_stage(s,inset+mapw+gap,y,total-mapw-gap,h,compact)
 battle_cards(s,ref.get_players(),inset,800,total,compact)
 name=f'public_battle_b_{"4x3" if compact else "16x9"}' if expanded else f'public_exploration_b_{"4x3" if compact else "16x9"}'
 s.save(name,1,'公开战斗展开' if expanded else '公开探索｜战斗区收起（布局示意，单位沿用密度测试数据）')

def storybook(compact=False,timer=False):
 W=1440 if compact else 1920; inset=72 if compact else 96; total=W-2*inset
 s=S(W,1080);backdrop(s)
 strip_h=186; strip_y=1080-54-strip_h-40
 page_top=94 if timer else 54
 page_maxh=strip_y-page_top-20
 pw=min(total,page_maxh*16/9); ph=pw*9/16; px=(W-pw)/2; py=page_top+(page_maxh-ph)/2
 s.rect(px,py,pw,ph,'#FFFFFF',0,'#C7DDE8')
 s.t(W/2,py+ph*.46,'本地绘本页面',44,INK,600,'middle')
 s.t(W/2,py+ph*.56,'占位页 · 尚未提供实际PPTX',28,MUTED,400,'middle')
 gap=0 if compact else 8
 widths=[222,222]+[(total-444)/5]*5 if compact else [(total-6*gap)/7]*7
 s.glass(inset,strip_y,total,strip_h)
 for i,p in enumerate(ref.get_players()):
  cw=widths[i];xx=inset+sum(widths[:i])+i*gap
  if i:s.line(xx-gap/2,strip_y+12,xx-gap/2,strip_y+strip_h-12,'#C9DDE7',1)
  team_marker(s,p['team'],xx+12,strip_y+19,7)
  # Variable 4:3 widths reserve more space for the two long names.
  player_name(s,p,xx+8,strip_y+53,cw-16,28)
  ry=strip_y+132
  icon(s,'health',xx+8,ry-22); s.t(xx+40,ry,f"{p['health']}/{p['maximumHealth']}",26)
  icon(s,'shield',xx+cw-59,ry-22);s.t(xx+cw-27,ry,str(p['shield']),26)
  if compact:
   icon(s,'coin',xx+8,ry+7);s.t(xx+40,ry+29,str(p['coins']),26)
   icon(s,'score',xx+cw-59,ry+7);s.t(xx+cw-27,ry+29,str(p['score']),26)
  else:
   icon(s,'coin',xx+8,ry+7);s.t(xx+40,ry+29,str(p['coins']),26)
   icon(s,'score',xx+cw-77,ry+7);s.t(xx+cw-45,ry+29,str(p['score']),26)
  status='主持人' if p['host'] else '倒地' if p['health']==0 else ''
  if status:s.t(xx+8,strip_y+90,status,24,ref.RED if p['health']==0 else PRIMARY,600)
 # Color + vector shapes give stable offline team identity; names remain in key.
 team_legend(s,inset+16,strip_y+strip_h+28,24)
 for j,(key,label) in enumerate([('health','生命'),('shield','护盾'),('coin','金币'),('score','积分')]):
  ix=W-inset-420+j*106;icon(s,key,ix,strip_y+strip_h+7,24);s.t(ix+28,strip_y+strip_h+28,label,24,MUTED)
 if timer:
  # Enabled timer uses a separate strip, never covers actual page contents.
  s.t(W-inset,82,'已暂停 · 保留17秒',24,INK,600,'end')
 suffix='_timer_enabled' if timer else ''
 s.save(f'public_storybook_{"4x3" if compact else "16x9"}{suffix}',1,'公开绘本｜七人单条状态区｜'+('计时已启用' if timer else '计时未启用'))

if __name__=='__main__':
 ref.teacher('b')
 for compact in [False,True]:
  public_battle(compact);public_battle(compact,False)
  storybook(compact);storybook(compact,True)
 ref.component_board();ref.result_board();ref.density_board()
 (ROOT/'sources/preview-index.json').write_text(json.dumps(ref.META,ensure_ascii=False,indent=2))
 print(f'Created {len(ref.META)} round2 SVG previews')
