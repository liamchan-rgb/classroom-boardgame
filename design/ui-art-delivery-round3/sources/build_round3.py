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
  ref.META[-1]['revision']='round3'
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

def queue_bar(s,x,y,w,current_id=None):
 d=json.loads((ROOT/'sources/demo-scenarios.json').read_text())['baseBattle']
 units={u['id']:u for u in d['players']+d['monsters']}
 step=(w-112)/9;cy=y+41
 s.line(x+56,cy,x+w-56,cy,'#C4DAE6',8)
 s.add(f'<path d="M{x+w-38} {cy-7}L{x+w-28} {cy}L{x+w-38} {cy+7}Z" fill="#7C9CAA"/>')
 for i,uid in enumerate(d['queue']):
  u=units[uid];xx=x+56+i*step;current=uid==(current_id or d['currentUnitID']);monster=not u.get('player',False)
  color=PRIMARY if current else '#B93838' if monster else TEAMS[u['team']][0]
  s.add(f'<g data-queue-unit="{uid}" data-current="{str(current).lower()}"><title>{ref.esc(u["name"])}</title>')
  s.circle(xx,cy,30,'#FFFFFF',color,4 if current else 2)
  if not monster:
   if u['classID']=='adventurer':ref.art(s,'b','hero',xx-29,cy-29,58,58)
   else:
    # Neutral professional symbols; still not final portraits.
    if u['classID']=='ranger':
     s.add(f'<path d="M{xx-10} {cy-17}Q{xx+20} {cy} {xx-10} {cy+17}M{xx-10} {cy-17}V{cy+17}M{xx-16} {cy}H{xx+18}" fill="none" stroke="{PRIMARY}" stroke-width="3"/>')
    elif u['classID']=='spellblade':
     s.add(f'<path d="M{xx+12} {cy-18}L{xx+16} {cy-14}L{xx-6} {cy+8}L{xx-10} {cy+4}Z" fill="{PRIMARY}"/><path d="M{xx-14} {cy+1}L{xx-3} {cy+12}M{xx-8} {cy+7}L{xx-16} {cy+15}" stroke="{PRIMARY}" stroke-width="3"/>')
    else:
     s.add(f'<path d="M{xx} {cy-18}L{xx+15} {cy-10}V{cy+1}Q{xx+13} {cy+13} {xx} {cy+19}Q{xx-13} {cy+13} {xx-15} {cy+1}V{cy-10}Z" fill="none" stroke="{PRIMARY}" stroke-width="3"/>')
     s.add(f'<path d="M{xx} {cy-9}L{xx+7} {cy}L{xx} {cy+9}L{xx-7} {cy}Z" fill="{PRIMARY}"/>')
   team_marker(s,u['team'],xx+22,cy+22,7)
  elif u['templateID']=='slime':ref.art(s,'b','slime',xx-29,cy-29,58,58)
  else:
   # Neutral wolf slot, no new monster portrait. Paw marker is an interface symbol.
   s.add(f'<ellipse cx="{xx}" cy="{cy+7}" rx="10" ry="8" fill="{MUTED}"/>')
   for dx,dy in [(-12,-3),(-4,-9),(5,-9),(13,-3)]:s.circle(xx+dx,cy+dy,4,MUTED)
  state=d['queueStates'].get(uid,'')
  if current:
   s.add(f'<path d="M{xx-9} {cy-44}L{xx+9} {cy-44}L{xx} {cy-34}Z" fill="{PRIMARY}"/>')
  elif '倒地' in state:
   s.line(xx-15,cy-15,xx+15,cy+15,'#B93838',4);s.line(xx+15,cy-15,xx-15,cy+15,'#B93838',4)
  elif '第2轮' in state:
   s.circle(xx+23,cy-23,11,'#FFFFFF',ref.PURPLE,2)
   s.line(xx+23,cy-29,xx+23,cy-23,ref.PURPLE,2);s.line(xx+23,cy-23,xx+28,cy-23,ref.PURPLE,2)
  s.add('</g>')

def battle_cards(s,ps,x,y,totalw,compact,show_details=True,current_id=None):
 s.glass(x,y,totalw,80);queue_bar(s,x+8,y-1,totalw-16,current_id)
 if not show_details:return
 # This is the currently acting player's compact panel, never seven name cards.
 dy=y+98;s.glass(x,dy,totalw,144);p=ps[0]
 s.t(x+20,dy+35,'冒险者',28,INK,600);team_marker(s,p['team'],x+152,dy+24,8)
 labels=[f"生命 {p['health']}/{p['maximumHealth']}",f"盾 {p['shield']}",f"AP {p['ap']}",f"金币 {p['coins']}",f"积分 {p['score']}"]
 for i,label in enumerate(labels):s.t(x+180+i*(totalw-210)/5,dy+35,label,26,ref.PURPLE if i==2 else INK)
 catalog=json.loads((ROOT/'sources/reference_initial-content.json').read_text());skills={sk['id']:sk for sk in catalog['skills']}
 d=json.loads((ROOT/'sources/demo-scenarios.json').read_text())['baseBattle'];remaining={a['id']:a.get('remainingUses') for a in d['actionButtons']}
 cls=next(c for c in catalog['classes'] if c['id']==p['classID'])
 gap=12;cw=(totalw-40-3*gap)/4;cy=dy+50
 for i,sid in enumerate(cls['skills']):
  sk=skills[sid];xx=x+20+i*(cw+gap);s.rect(xx,cy,cw,74,'#EEF7FC',12,'#CDDFEA',1)
  s.t(xx+12,cy+29,sk['name'],28,PRIMARY,600);s.t(xx+cw-12,cy+29,f"{sk['cost']} AP",26,ref.PURPLE,600,'end')
  ef=sk['effects'][0]
  if ef['kind']=='damage':di=ef['dice'];label=f"射程{sk['range']} · {di['count']}D{di['sides']}+{di['flat']} · 余{remaining[sid]}次"
  elif ef['kind']=='heal':label=f"自身 · 恢复{ef['amount']}生命 · 余{remaining[sid]}次"
  else:label=f"自身 · 护盾{ef['amount']} · 余{remaining[sid]}次"
  s.t(xx+12,cy+62,label,24)
 xx=x+20+3*(cw+gap);s.rect(xx,cy,cw,74,'#F5FAFC',12,'#CDDFEA',1)
 s.t(xx+12,cy+29,'道具',28,PRIMARY,600);s.t(xx+12,cy+62,'个人背包',24,MUTED)
 # The review data has no inventory: no invented ownership or usable item counts.

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

def header(s,compact=False,battle=True,monster_turn=False):
 inset=72 if compact else 96;w=s.w-2*inset;s.glass(inset,54,w,60)
 s.t(inset+24,94,'PVE · 第1轮' if battle else '探索',30,INK,600)
 if battle:
  name='怪物行动：捣蛋史莱姆甲' if monster_turn else '行动中：晨曦森林守护者小队长安然'
  s.t(inset+270,94,name,28,INK,600)
  s.t(s.w-inset-24,94,'已暂停 · 17秒',28,INK,600,'end')

def battle_stage(s,x,y,w,h,compact):
 s.glass(x,y,w,h);s.t(x+22,y+40,'浅溪石桥 · 战斗',30,INK,600)
 stage_y=y+62;stage_h=h-82;s.rect(x+18,stage_y,w-36,stage_h,'#E8F3F8',18)
 size=290 if compact else 380;floor=stage_y+stage_h*.72
 for f,which in [(.27,'hero'),(.74,'slime')]:
  s.add(f'<ellipse cx="{x+w*f}" cy="{floor}" rx="{size*.30}" ry="14" fill="#B8D3DF" opacity=".45"/>')
  ref.art(s,'b',which,x+w*f-size/2,floor-size*.86,size,size)
 # Full-height stage remains available for later character animations.

def transient(s,compact=False):
 # One composite message from the last committed result; neither rules nor random draws.
 W=s.w;inset=72 if compact else 96;mapw=596 if compact else 760
 x=inset+mapw+24;w=W-2*inset-mapw-24
 s.add('<g id="committed-feedback" data-event-id="demo_committed_heavy_strike_001">')
 s.rect(x+28,212,w-56,92,'#FFFFFF',14,PRIMARY,2)
 s.t(x+48,244,'安然 AP −1',26,ref.PURPLE,600)
 s.t(x+48,281,'史莱姆甲 生命 −6',26,ref.RED,600)
 s.add('</g>')

def public_battle(compact=False,expanded=True,feedback=False,monster_turn=False):
 W=1440 if compact else 1920;inset=72 if compact else 96;total=W-2*inset
 s=S(W,1080);backdrop(s);header(s,compact,expanded,monster_turn)
 y=138;h=622;gap=24;mapw=(596 if compact else 760) if expanded else total
 s.glass(inset,y,mapw,h);node_map(s,inset+14,y+14,mapw-28,h-28)
 if expanded:battle_stage(s,inset+mapw+gap,y,total-mapw-gap,h,compact)
 battle_cards(s,ref.get_players(),inset,784,total,compact,expanded and not monster_turn,"m_slime_a" if monster_turn else None)
 if feedback:transient(s,compact)
 name=f'public_battle_b_{"4x3" if compact else "16x9"}' if expanded else f'public_exploration_b_{"4x3" if compact else "16x9"}'
 if feedback:name+='_feedback'
 if monster_turn:name+='_monster_turn'
 s.save(name,1,'公开战斗｜一次文字反馈中间帧' if feedback else '公开战斗｜怪物回合、玩家详情收起' if monster_turn else '公开战斗｜当前玩家紧凑技能/道具/资源' if expanded else '公开探索｜战斗区与玩家详情收起（布局示意）')

def storybook(compact=False,timer=False):
 W=1440 if compact else 1920; inset=72 if compact else 96; total=W-2*inset
 s=S(W,1080);backdrop(s)
 strip_h=186; strip_y=1080-54-strip_h
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
 if timer:
  # Enabled timer uses a separate strip, never covers actual page contents.
  s.t(W-inset,82,'已暂停 · 保留17秒',24,INK,600,'end')
 suffix='_timer_enabled' if timer else ''
 s.save(f'public_storybook_{"4x3" if compact else "16x9"}{suffix}',1,'公开绘本｜七人单条状态区｜'+('计时已启用' if timer else '计时未启用'))

if __name__=='__main__':
 ref.teacher('b')
 for compact in [False,True]:
  public_battle(compact);public_battle(compact,False);public_battle(compact,True,True);public_battle(compact,True,False,True)
  storybook(compact);storybook(compact,True)
 ref.component_board();ref.result_board();ref.density_board()
 (ROOT/'sources/preview-index.json').write_text(json.dumps(ref.META,ensure_ascii=False,indent=2))
 print(f'Created {len(ref.META)} round3 SVG previews')
