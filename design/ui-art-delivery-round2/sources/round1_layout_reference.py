"""Original editable design drawings. No gameplay calculations or app code."""
from pathlib import Path
import json, html, base64, math, random

ROOT=Path(__file__).resolve().parents[1]
INK='#183B36'; MUTED='#526B64'; GREEN='#176B5B'; GOLD='#995207'; RED='#B93838'; BLUE='#315E9C'; PURPLE='#6650A4'
themes={'a':{'name':'晨光森林','sky':'#DFEADF','land':'#D4DFCA','tint':'#E4EDD9','accent':'#A65D08'},'b':{'name':'晴空学园','sky':'#DDECF0','land':'#D7E8DF','tint':'#DEEFF3','accent':'#316F87'}}
META=[]
def esc(s):return html.escape(str(s))
class S:
 def __init__(self,w,h):
  self.w=w;self.h=h;self.a=[];self.texts=[]
  self.a.append(f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><defs><linearGradient id="cream" x2="0" y2="1"><stop stop-color="#FBF9F2"/><stop offset="1" stop-color="#E8EEDC"/></linearGradient><linearGradient id="glass" x2="0.2" y2="1"><stop stop-color="#FFFFFF" stop-opacity=".96"/><stop offset="1" stop-color="#FFFFFF" stop-opacity=".83"/></linearGradient><filter id="shadow" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="6" stdDeviation="10" flood-color="#183B36" flood-opacity=".07"/></filter></defs>')
 def add(self,s):self.a.append(s)
 def rect(self,x,y,w,h,fill='#FFFFFF',r=16,stroke=None,sw=1,opacity=1):
  self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" opacity="{opacity}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+'/>')
 def glass(self,x,y,w,h):
  self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="16" fill="url(#glass)" stroke="#FFFFFF" stroke-width="2" filter="url(#shadow)"/>')
 def t(self,x,y,s,size=18,color=INK,weight=400,anchor='start'):
  self.add(f'<text x="{x}" y="{y}" fill="{color}" font-family="Noto Sans CJK SC, sans-serif" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}" style="font-variant-numeric:tabular-nums">{esc(s)}</text>')
  self.texts.append({'x':x,'baseline':y,'text':str(s),'fontSize':size,'weight':weight})
 def lines(self,x,y,ls,size=18,color=INK,step=None,weight=400):
  for i,z in enumerate(ls):self.t(x,y+i*(step or size*1.3),z,size,color,weight)
 def line(self,x1,y1,x2,y2,color,sw=2,dash=None):self.add(f'<path d="M{x1} {y1}L{x2} {y2}" fill="none" stroke="{color}" stroke-width="{sw}" stroke-linecap="round"'+(f' stroke-dasharray="{dash}"' if dash else '')+'/>')
 def circle(self,x,y,r,fill,stroke=None,sw=2):self.add(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+'/>')
 def image(self,p,x,y,w,h):
  if not Path(p).exists():return
  enc=base64.b64encode(Path(p).read_bytes()).decode()
  self.add(f'<image x="{x}" y="{y}" width="{w}" height="{h}" href="data:image/png;base64,{enc}" preserveAspectRatio="xMidYMid meet"/>')
 def btn(self,x,y,w,h,label,kind='normal',sub=None):
  fill={'normal':'#FFFFFF','primary':GREEN,'selected':'#E1EEE7','disabled':'#EDF0EA','reward':'#F5E8D2'}.get(kind,'#FFF')
  color='#FFFFFF' if kind=='primary' else MUTED if kind=='disabled' else INK
  self.rect(x,y,w,h,fill,12,GREEN if kind=='selected' else '#CDD8D0',2 if kind=='selected' else 1)
  if sub:self.t(x+16,y+26,label,18,color,600);self.t(x+16,y+51,sub,15,color)
  else:self.t(x+w/2,y+h/2+7,label,18,color,600,'middle')
 def badge(self,x,y,w,label,color=GREEN,size=15):
  self.rect(x,y,w,size+12,color,8);self.t(x+w/2,y+size+2,label,size,'#FFFFFF',600,'middle')
 def save(self,name,scale=1,label=''):
  self.add('</svg>');p=ROOT/'sources'/f'{name}.svg';p.write_text(''.join(self.a));META.append({'name':name,'width':self.w,'height':self.h,'scale':scale,'label':label,'text':self.texts})

def backdrop(s,theme='a'):
 th=themes[theme];s.rect(0,0,s.w,s.h,'url(#cream)',0)
 # Soft pixel silhouettes are decoration only. They do not encode map content.
 for i in range(26):
  x=i*s.w/25;y=s.h*.32+math.sin(i*.65)*s.h*.10
  s.rect(x-30,y,s.w/18,s.h,th['land'],0,opacity=.22)
  s.rect(x-30,y,s.w/25,24,th['tint'],0,opacity=.45)
 s.rect(0,0,s.w,8,GREEN,0)

def art(s,theme,which,x,y,w,h):s.image(ROOT/'assets'/f'style_{theme}'/f'{"class_adventurer" if which=="hero" else "monster_slime"}_portrait.png',x,y,w,h)
def avatar(s,p,theme,x,y,sz):
 s.rect(x,y,sz,sz,themes[theme]['tint'],12)
 if p.get('classID')=='adventurer':art(s,theme,'hero',x,y,sz,sz)
 else:
  # Neutral temporary template badge, not invented portrait or new profession.
  label={'ranger':'弓','spellblade':'剑','dragonKnight':'龙'}.get(p.get('classID'),'人')
  s.circle(x+sz/2,y+sz/2,sz*.34,'#FFF',GREEN,1);s.t(x+sz/2,y+sz*.64,label,24 if s.w>=1440 else max(15,sz*.32),GREEN,600,'middle')

def name_lines(p,limit=7):
 n=p['name'];return [n[i:i+limit] for i in range(0,len(n),limit)] if not n.isascii() else [n[i:i+12] for i in range(0,len(n),12)]

def get_players():
 p=ROOT/'sources/demo-scenarios.json'
 if p.exists():
  d=json.loads(p.read_text());b=d.get('baseBattle') or d.get('scenarios',{}).get('baseBattle')
  if b and 'players' in b:return b['players']
 return [dict(id=f'p_{c}',name=n,classID=cl,health=hp,maximumHealth=mx,shield=sh,ap=ap,coins=coin,score=sc,team=tm,host=i==6,current=i==0) for i,(c,n,cl,hp,mx,sh,ap,coin,sc,tm) in enumerate([
 ('a','晨曦森林守护者小队长安然','adventurer',9,12,4,3,20,2,'蓝队'),('b','AlexandriaWinterbrookJade','ranger',16,18,0,8,30,3,'蓝队'),('c','小禾','spellblade',20,24,6,2,10,1,'橙队'),('d','星星','dragonKnight',26,32,6,3,25,5,'橙队'),('e','阿乐','adventurer',0,12,0,2,15,1,'紫队'),('f','小满','ranger',13,18,4,3,10,2,'紫队'),('g','主持人','dragonKnight',32,32,0,3,0,0,'蓝队')])]

def field(p,k,default=0):
 aliases={'health':['health','hp'],'maximumHealth':['maximumHealth','maxHP','maxHealth'],'coins':['coins','gold'],'score':['score','points'],'team':['team','teamName'],'classID':['classID','classId','classTemplateID']}
 return next((p[x] for x in aliases.get(k,[k]) if x in p),default)

def node_map(s,x,y,w,h,theme='a',public=False):
 th=themes[theme];s.rect(x,y,w,h,th['tint'],16)
 data=json.loads((ROOT/'sources/demo-scenarios.json').read_text())['baseBattle']
 nodes=data['nodes'];pts={n['id']:(x+w*n['x'],y+h*n['y']) for n in nodes}
 for road in data['roads']:
  aa=pts[road['a']];bb=pts[road['b']];s.line(*aa,*bb,'#9FB1A2',10);s.line(*aa,*bb,'#F9FAF0',3)
 for n in nodes:
  nx,ny=pts[n['id']];cur=n['id']==3
  s.circle(nx,ny,26 if not public else 34,'#FFFFFF',GREEN if cur else '#AEBEAF',4 if cur else 2)
  s.t(nx,ny+8,str(n['id']) if n['revealed'] else '?',22 if not public else 28,MUTED,600,'middle')
  s.t(nx,ny+58 if public else ny+48,n['name'],26 if public else 17,INK,500,'middle')
 nx,ny=pts[3]
 s.badge(nx-(100 if public else 70),ny-87,200 if public else 140,'角色3 · 敌人2',GREEN,24 if public else 15)
 art(s,theme,'slime',nx+44,ny-38,64,64)
 nx,ny=pts[2];s.badge(nx-60,ny-74,120,'角色 × 3',GREEN,24 if public else 15)
 nx,ny=pts[4];s.badge(nx-50,ny-65,100,'敌人 × 1',RED,24 if public else 15)
 nx,ny=pts[1];s.badge(nx-50,ny-65,100,'角色 × 1',GREEN,24 if public else 15)
 s.t(x+20,y+32,'当前地图 · PVE' if not public else '战斗沿用当前地图',26 if public else 18,INK,600)
 s.t(x+20,y+h-18,'已揭示道路与地点' if public else '选择节点查看单位 · 道路距离计算',24 if public else 15,MUTED)

def roster(s,players,theme):
 s.glass(24,120,268,736);s.t(40,151,'角色与奖励对象',22,INK,600);s.t(40,175,'右侧勾选只用于发奖',15,MUTED)
 for i,p in enumerate(players):
  x=36;y=188+i*92;selected=i in [1,2];current=i==0;down=field(p,'health')==0
  s.rect(x,y,244,84,'#F0F3EF' if down else '#FFFFFF',12,GREEN if current else GOLD if selected else '#DAE3DA',3 if current or selected else 1)
  avatar(s,p,theme,x+8,y+9,38)
  ls=name_lines(p,7);s.lines(x+54,y+20,ls[:2],17,INK,20,600)
  if len(ls)==1:s.t(x+54,y+40,'主持人' if i==6 else '倒地' if down else '行动中' if current else field(p,'team','未分队'),15,RED if down else GREEN)
  s.t(x+8,y+61,f"生命 {field(p,'health')}/{field(p,'maximumHealth')}  盾 {field(p,'shield')}",17)
  s.t(x+8,y+80,f"行动点 {field(p,'ap')} · {field(p,'team','未分队')}"+(' · 行动中' if current else ''),15,PURPLE)
  # 44pt selection target, 22pt visible check square.
  s.rect(x+194,y+4,44,44,'#FFFFFF',8,opacity=0)
  s.rect(x+205,y+15,22,22,GOLD if selected else '#F3F5EF',6,GOLD if selected else '#8B9E90')
  if selected:s.t(x+216,y+32,'✓',17,'#FFFFFF',600,'middle')
  if current:s.rect(x,y+4,4,76,GREEN,2)

def teacher(theme='a'):
 ps=get_players();s=S(1366,1024);backdrop(s,theme)
 s.glass(24,24,1318,80);s.badge(40,43,62,'PVE');s.t(120,56,'第 1 轮',22,INK,600)
 s.t(120,85,'行动中：晨曦森林守护者小队长安然',18)
 s.badge(660,44,156,'暂停 · 保留17秒',GOLD,18);s.badge(842,44,126,'公开屏已连接',GREEN,15)
 s.btn(1094,36,232,56,'继续 · 空格')
 roster(s,ps,theme)
 s.glass(308,120,666,496);s.t(328,153,'同一张地图，继续战斗',22,INK,600)
 s.t(328,182,'固定队列',15,MUTED)
 q=['① 安然 · 行动中','② 史莱姆甲','③ 亚历山德里娅','④ 小禾','⑤ 森林狼','⑥ 星星','⑦ 阿乐 · 倒地跳过','⑧ 小满','⑨ 主持人','⑩ 史莱姆乙']
 s.t(418,182,'① 安然 → ② 史莱姆甲 → ③ Alex → ④ 小禾 → ⑤ 史莱姆乙',15)
 s.t(328,207,'⑥ 星星 → ⑦ 阿乐（倒地） → ⑧ 小满 → ⑨ 狼（下轮） → ⑩ 主持人',15,MUTED)
 node_map(s,324,225,634,375,theme)
 s.glass(308,632,666,224);s.t(328,665,'最近一次结算',22,INK,600)
 s.badge(802,645,150,'已提交结果',GREEN)
 s.t(328,706,'安然 → 史莱姆甲 · 强击',20,INK,600)
 s.rect(328,724,62,62,themes[theme]['tint'],12);s.t(359,764,'4',32,GREEN,600,'middle')
 s.t(406,747,'D6：4  ＋ 2 ＝ 6',20);s.t(406,778,'目标生命 8 → 2 · 护盾吸收 0',18)
 s.t(328,829,'行动点 4 → 3 · 强击剩余 1 次',17,MUTED)
 s.glass(990,120,352,736);s.t(1006,153,'当前行动者',22,INK,600)
 s.lines(1006,188,['晨曦森林守护者','小队长安然'],22,INK,28,600)
 s.t(1006,247,f"冒险者 · 生命 {ps[0]['health']}/{ps[0]['maximumHealth']} · 护盾 {ps[0]['shield']}",17)
 s.t(1006,270,f"行动点 {ps[0]['ap']}/8 · 金币 {ps[0]['coins']} · 积分 {ps[0]['score']}",17,PURPLE)
 s.btn(1006,286,152,52,'移动 · 每路1点');s.btn(1174,286,152,52,'普攻 · 1点')
 s.btn(1006,350,320,64,'强击 · 1行动点','selected','射程 0 · 剩余 1 次 · 1D6＋2')
 s.btn(1006,426,320,64,'喘息 · 1行动点','normal','自己 · 剩余 2 次 · 恢复4生命')
 s.btn(1006,502,320,64,'简易防护 · 1行动点','normal','自己 · 剩余 2 次 · 护盾4')
 s.btn(1006,578,152,52,'道具 · 1点');s.btn(1174,578,152,52,'救援 · 2点','disabled')
 s.t(1006,658,'目标：史莱姆乙 · 同节点',18,INK,600)
 s.t(1006,683,'合法目标 · 选中不扣点',15,MUTED)
 s.btn(1006,698,320,56,'施放强击 · 消耗1行动点','primary')
 s.btn(1006,770,320,52,'结束回合 · 保留余点')
 s.t(1006,842,'救援不可用：无同节点倒地队友',15,MUTED)
 s.glass(24,872,1318,128);s.badge(40,886,88,'奖励对象',GOLD)
 s.t(142,907,'Alex、小禾（2人）',18,INK,600)
 s.t(40,973,'发奖前检查：Alex 行动点8/8（已达上限）；小禾2/8',17,MUTED)
 s.btn(660,888,154,56,'金币 +10 · G','reward');s.btn(830,888,154,56,'行动点 +1','reward');s.btn(1000,888,154,56,'积分 +2','reward')
 s.btn(1170,888,156,56,'绘本 / 更多')
 s.t(660,975,'发奖不切换当前行动者',17,MUTED);s.btn(1170,950,156,44,'撤销最近一步')
 s.save(f'teacher_battle_{theme}',2,f'{themes[theme]["name"]}｜教师战斗 1366×1024')

def public_card(s,p,i,x,y,w,h,theme,storybook=False,compact=False):
 curr=i==0;down=field(p,'health')==0
 s.rect(x,y,w,h,'#F0F3EC' if down else 'url(#glass)',16,GREEN if curr else '#FFFFFF',3 if curr else 2)
 # Names have two full lines; numeric resources stay outside art.
 sz=40 if compact else 44;avatar(s,p,theme,x+12,y+14,sz)
 namex=x+64;ls=name_lines(p,7 if compact else 8)
 if p['name'].isascii():ls=[p['name'][:12],p['name'][12:]]
 fs=28
 if len(ls)==1:
  s.t(namex,y+34,ls[0],fs,INK,600)
  s.t(namex,y+62,'主持人' if i==6 else '倒地 · 跳过' if down else '行动中' if curr else field(p,'team','未分队'),24,RED if down else GREEN,600)
 else:s.lines(namex,y+30,ls,fs,INK,31,600)
 if compact:
  s.t(x+12,y+94,f"生命 {field(p,'health')}/{field(p,'maximumHealth')}   盾 {field(p,'shield')}",26)
  s.t(x+12,y+126,f"币 {field(p,'coins')} · 分 {field(p,'score')} · {field(p,'team','未分队')}",26)
  if not storybook:s.t(x+w-16,y+34,f"AP {field(p,'ap')}",24,PURPLE,600,'end') if len(ls)==1 else s.t(x+12,y+151,f"AP {field(p,'ap')}"+(' · 行动中' if curr else ''),24,PURPLE)
 else:
  if curr:s.badge(x+w-124,y+12,112,'行动中',GREEN,24)
  s.t(x+12,y+88,f"生命 {field(p,'health')}/{field(p,'maximumHealth')}  盾 {field(p,'shield')}"+(f"  AP {field(p,'ap')}" if not storybook else ''),26)
  s.t(x+12,y+114,f"币 {field(p,'coins')} · 分 {field(p,'score')} · {field(p,'team','未分队')}",26)

def public(theme='a',compact=False):
 W=1440 if compact else 1920;s=S(W,1080);backdrop(s,theme);ps=get_players();inset=72 if compact else 96
 s.glass(inset,54,W-2*inset,150 if compact else 156)
 s.t(inset+24,92,'PVE · 第 1 轮',30,INK,600)
 s.t(inset+24,144,'行动中：晨曦森林守护者小队长安然',36 if compact else 44,INK,600)
 s.t(W-inset-24,109,'已暂停 · 17 秒',40,INK,600,'end')
 s.t(inset+24,175,'① 安然 → ② 史莱姆甲 → ③ Alex → ④ 小禾 → ⑤ 史莱姆乙',24,INK)
 s.t(inset+24,202,'⑥ 星星 → ⑦ 阿乐（倒地跳过） → ⑧ 小满 → ⑨ 狼（第2轮） → ⑩ 主持人',24,MUTED)
 if compact:x,y,mw,mh,rx,rw=72,228,756,430,852,516
 else:x,y,mw,mh,rx,rw=96,234,1032,512,1152,672
 s.glass(x,y,mw,mh);node_map(s,x+16,y+16,mw-32,mh-32,theme,True)
 s.glass(rx,y,rw,mh);s.t(rx+24,y+46,'最近一次结算',32,INK,600);s.badge(rx+rw-176,y+20,152,'已结算',GREEN,24)
 s.t(rx+24,y+104,'安然 → 史莱姆甲',32,INK,600)
 art(s,theme,'slime',rx+rw-176,y+110,144,144)
 s.rect(rx+24,y+132,100,100,themes[theme]['tint'],16);s.t(rx+74,y+201,'4',56,GREEN,600,'middle')
 s.t(rx+142,y+174,'D6 ＋ 2',32,INK,600);s.t(rx+142,y+216,'伤害 6',32,RED,600)
 s.t(rx+24,y+284,'生命 8 → 2 · 盾吸收 0',28)
 s.t(rx+24,y+331,'安然 行动点 4 → 3',28,PURPLE)
 s.t(rx+24,y+mh-28,'强击 · 同节点目标',26,MUTED)
 if compact:
  cw=312;ch=156;ys=[682,854];gap=16
 else:cw=420;ch=124;ys=[770,902];gap=16
 for i,p in enumerate(ps):
  row=0 if i<4 else 1;col=i if i<4 else i-4
  public_card(s,p,i,inset+col*(cw+gap),ys[row],cw,ch,theme,False,compact)
 # Legend fills last cell rather than hiding a role.
 xx=inset+3*(cw+gap);s.rect(xx,ys[1],cw,ch,'#E5EDE3',16)
 s.t(xx+16,ys[1]+36,'资源说明',26,INK,600)
 s.lines(xx+16,ys[1]+70,['币：金币 · 分：积分','盾：护盾 · AP：行动点'],24,MUTED,31)
 s.save(f'public_battle_{theme}_{"4x3" if compact else "16x9"}',1,f'{themes[theme]["name"]}｜公开战斗 {W}×1080')

def style(theme):
 s=S(1800,1200);backdrop(s,theme);th=themes[theme]
 s.t(56,73,'英语课堂电子桌游',24,MUTED);s.t(56,145,f'{"A" if theme=="a" else "B"} / {th["name"]}',56,INK,700)
 s.t(56,199,'明亮绘本 × HD像素角色 × iOS毛玻璃',28)
 s.glass(56,238,820,676);s.t(80,281,'冒险者 · 职业模板样稿',26,INK,600)
 art(s,theme,'hero',120,304,490,530);art(s,theme,'hero',636,360,152,152);s.t(624,551,'152单位识别检查',24,MUTED)
 s.t(80,878,'保留完整轮廓 · 人名 / 数字 / 队伍由 App 叠加',24,MUTED)
 s.glass(900,238,844,380);s.t(924,281,'捣蛋史莱姆 · 怪物模板样稿',26,INK,600)
 art(s,theme,'slime',924,300,320,280);art(s,theme,'slime',1330,350,140,140);s.t(1500,407,'柔和光感',26);s.t(1500,447,'清楚轮廓',26);s.t(1500,487,'无血腥',26)
 s.glass(900,642,844,272);s.t(924,686,'统一组件语言',26,INK,600)
 s.btn(924,714,242,56,'执行强击','primary');s.btn(1182,714,242,56,'选择目标','selected');s.badge(1448,728,266,'行动中 / 奖励对象分开',GOLD,18)
 s.t(924,816,'生命 9/12',28,RED,600);s.t(1148,816,'护盾 4',28,BLUE,600);s.t(1328,816,'行动点 3',28,PURPLE,600)
 s.t(924,871,'文字落在干净面板，像素质感留给角色与装饰',24,MUTED)
 colors=[('#F5F1E8','暖白'),(INK,'墨绿'),(GREEN,'主操作'),(GOLD,'金色'),(th['tint'],'方向底色')]
 for i,(c,label) in enumerate(colors):
  xx=56+i*252;s.rect(xx,960,228,72,c,12);s.t(xx,1072,f'{label}  {c}',24)
 s.t(1360,991,'A：森林披风、温暖苔绿' if theme=='a' else 'B：学院剪裁、清爽湖蓝',24)
 s.t(1360,1031,'统一职业、技能与规则',24,MUTED)
 s.t(56,1150,'样稿供审美比较 · 尚未确认最终方向 · 不作为全部职业/怪物已完成的证明',24,MUTED)
 s.save(f'style_sample_{theme}',1,f'方向{"A" if theme=="a" else "B"}｜{th["name"]}样稿')

def component_board():
 s=S(1920,1600);backdrop(s);s.t(56,74,'组件与状态 / 同一语义，双端表达',44,INK,700)
 s.t(56,117,'大面板：系统毛玻璃   小按钮：纯色 / 液态玻璃   状态必须带文字或标记',26,MUTED)
 s.glass(48,152,1824,258);s.t(72,196,'01 角色卡 · 状态可以叠加',28,INK,600)
 labels=['普通','行动中','奖励选中','合法目标','受击','倒地','主持人','下轮可行动']
 for i,lab in enumerate(labels):
  x=72+i*224;y=222;co=[MUTED,GREEN,GOLD,GREEN,RED,RED,PURPLE,MUTED][i]
  s.rect(x,y,208,164,'#FFFFFF' if i!=5 else '#E8ECE6',16,co,3 if i in [1,2,3] else 1)
  s.badge(x+12,y+12,184,lab,co,18);s.t(x+16,y+77,'小禾',24,INK,600)
  s.t(x+16,y+113,'生命 0/24' if i==5 else '生命 20/24',24)
  s.t(x+16,y+146,'盾 0 · 橙队' if i==5 else '盾 6 · 橙队',20,BLUE)
 s.glass(48,434,888,330);s.t(72,479,'02 技能 / 道具按钮',28,INK,600)
 btns=[('可用 · 强击','1点 · 射程0 · 余2次','normal'),('选中 · 强击','待选合法目标，未扣点','selected'),('AP不足','当前0 / 需要1行动点','disabled'),('次数耗尽','剩余0次 · 本场不可用','disabled'),('无合法目标','射程不足 / 未选目标','disabled'),('阶段不允许','探索不可用战斗技能','disabled')]
 for i,(l,sub,k) in enumerate(btns):s.btn(72+(i%2)*420,500+(i//2)*82,396,68,l,k,sub)
 s.glass(960,434,912,330);s.t(984,479,'03 资源 · 不用颜色代替含义',28,INK,600)
 resources=[('生命','9 / 12',RED),('护盾','4',BLUE),('行动点','3 / 8',PURPLE),('金币','20',GOLD),('积分','2',GREEN),('队伍','橙队 ◆',GOLD)]
 for i,(lab,val,co) in enumerate(resources):
  xx=984+i%3*286;yy=506+i//3*118;s.rect(xx,yy,262,98,'#FFFFFF',12);s.t(xx+14,yy+32,lab,24,co,600);s.t(xx+14,yy+75,val,32,co,600)
  if i<5:s.image(ROOT/'assets/icons'/('icon_'+['health','shield','action','coin','score'][i]+'.png'),xx+198,yy+28,48,48)
 s.glass(48,788,888,324);s.t(72,834,'04 地图节点 · 道路距离，拥挤单独展开',28,INK,600)
 nodes=['已探索','未知轮廓','当前地点','路径经过','敌人地点','奖励已领取','同地点多人']
 for i,lab in enumerate(nodes):
  xx=112+(i%4)*212;yy=898+(i//4)*134;s.circle(xx,yy,28,'#FFFFFF',GREEN if i==2 else '#AABBAC',4 if i==2 else 2);s.t(xx,yy+9,'?' if i==1 else '✓' if i==5 else str(i+1),24,INK,600,'middle');s.t(xx,yy+64,lab,20,INK,400,'middle')
 s.glass(960,788,912,324);s.t(984,834,'05 固定队列与暂停',28,INK,600)
 for i,(lab,co) in enumerate([('① 当前',GREEN),('② 已行动',MUTED),('③ 倒地跳过',RED),('④ 下轮可行动',PURPLE)]):s.badge(984+i*214,858,198,lab,co,18)
 s.t(984,943,'手动暂停 · 保留17秒',32,GOLD,600)
 s.t(984,990,'绘本 / 编辑 / 历史暂停叠加，返回后保留原暂停',24)
 s.t(984,1040,'怪物行动 / 全员倒地：不消耗学生决策时间',24,MUTED)
 s.glass(48,1136,1824,402);s.t(72,1182,'06 已结算反馈与异常 · 原结果显示，不重新计算',28,INK,600)
 s.badge(72,1207,222,'自然20 · 穿透护盾',GOLD,18)
 s.t(72,1280,'节点3的三个目标全部倒地',26,RED,600)
 s.t(72,1321,'自疗、护盾、掉落、积分显示实际变化',24)
 s.t(72,1362,'结算完成后才显示战斗结束',24,MUTED)
 s.t(698,1240,'救援成功',28,GREEN,600);s.t(698,1291,'生命 0/13 → 7/13',30);s.t(698,1334,'第2轮可行动',26,PURPLE,600)
 s.t(698,1380,'消耗：2行动点 + 1复活石',24)
 s.t(1260,1240,'教师文件 / 纠错',28,INK,600)
 s.lines(1260,1284,['空资料 / 正在导入 / 导入失败','保存失败 / 恢复后暂停','断连：公开画面等待重连','撤销预览恢复范围 · 保留原骰子'],24,INK,42)
 s.rect(72,1398,538,66,'#FFFFFF',12,GREEN,3);s.badge(88,1416,160,'安然 · 行动中',GREEN,18);s.badge(266,1416,182,'✓ 奖励选中',GOLD,18)
 s.t(698,1450,'叠加示例：同一人可以同时行动中与被选作奖励对象',24,MUTED)
 s.t(72,1504,'按钮150ms · 面板220ms · 数字350ms · 骰子最长900ms · 减少动态效果直接显示完整结果',24,MUTED)
 s.save('component_states',1,'组件状态板｜角色、动作、资源、地图、队列、结果')

def storybook(compact=False):
 W=1440 if compact else 1920;s=S(W,1080);backdrop(s);inset=72 if compact else 96
 s.t(inset,94,'绘本 · 暂停中 · 保留17秒',32,INK,600)
 # 16:9 page fits, never clipped; no actual PPTX was attached.
 ph=506 if compact else 600;pw=ph*16/9;px=(W-pw)/2;py=120
 s.rect(px,py,pw,ph,'#FFFDF6',0,'#B8C9B8');s.t(W/2,py+ph*.45,'本地绘本页面',44,INK,600,'middle');s.t(W/2,py+ph*.57,'尚未提供实际绘本文件',28,MUTED,400,'middle')
 ps=get_players();cw=312 if compact else 420;ch=156 if compact else 124;gap=16;ys=[682,854] if compact else [770,902]
 for i,p in enumerate(ps):
  row=0 if i<4 else 1;col=i if i<4 else i-4;public_card(s,p,i,inset+col*(cw+gap),ys[row],cw,ch,'a',True,compact)
 xx=inset+3*(cw+gap);s.rect(xx,ys[1],cw,ch,'#E5EDE3',16);s.t(xx+16,ys[1]+42,'课堂暂停中',26,INK,600);s.lines(xx+16,ys[1]+78,['姓名 · 生命 · 护盾','金币 · 积分 · 队伍'],24,MUTED,31)
 s.save(f'public_storybook_{"4x3" if compact else "16x9"}',1,'绘本公开状态条｜7角色，无AP，等比页面')

def result_board():
 s=S(1600,1080);backdrop(s);s.t(56,76,'已提交结果 / 特殊结算与教师隔离',40,INK,700)
 s.glass(48,120,912,596);s.t(72,168,'自然20 · 同一节点群体结果',32,INK,600)
 s.badge(72,194,240,'D20 原始结果：20',GOLD,22)
 s.t(72,290,'遗迹魔龙、石像守卫、史莱姆 → 全部战败',28,RED,600)
 s.t(72,340,'护盾不能阻挡自然20 · 倒地后盾归0',26)
 s.lines(72,408,['行动者：星星 · 龙焰','实际自疗 +6 · 生命 26 → 32 / 32','实际护盾 +2 · 护盾 4 → 6','实际掉落：金币35、药水1、复活石1','实际积分 +7 · 普通怪物1+1，Boss5'],26,INK,48)
 s.t(72,680,'各目标独立掉落已完成 · 回放沿用这一批结果',24,MUTED)
 s.glass(984,120,568,596);s.t(1008,168,'救援成功',32,GREEN,600)
 s.t(1008,250,'生命 0/13 → 7/13',34,INK,600)
 s.badge(1008,282,296,'第2轮才可行动',PURPLE,24)
 s.lines(1008,372,['同节点队友','消耗2行动点、1复活石','救援者实际积分 +2','保持原队列位置'],26,INK,54)
 s.t(1008,680,'已提交结果 · 不因播放而再次发奖',24,MUTED)
 s.glass(48,740,1504,288);s.t(72,786,'教师选奖 / 私有备注 / 公共输出',28,INK,600)
 s.t(72,840,'行动者：安然   奖励对象：亚历山德里娅、小禾',26,INK,600)
 s.t(72,888,'AP奖励实际：亚历山德里娅 +0（上限8）；小禾 +1（2 → 3）',26)
 s.t(72,936,'教师查看备注时，公开端仅显示绘本与公开状态，不展示勾选对象或备注',26)
 s.t(72,986,'回到游戏仍保留手动暂停与17秒 · 日志只接收可公开的已提交结果',24,MUTED)
 s.save('settlement_and_privacy',1,'特殊结果与隐私｜自然20、救援、AP触顶、暂停')

def icons():
 paths={
 'health':f'<path d="M128 211L41 129C-10 71 66 23 128 81C190 23 266 71 215 129Z" fill="{RED}"/>',
 'shield':f'<path d="M128 25L220 61V125Q215 192 128 231Q41 192 36 125V61Z" fill="{BLUE}"/><path d="M128 50V201" stroke="#FFFFFF" stroke-width="10" opacity=".9"/>',
 'action':f'<path d="M147 20L52 143H116L99 235L208 103H143Z" fill="{PURPLE}"/>',
 'coin':f'<circle cx="128" cy="128" r="98" fill="{GOLD}"/><circle cx="128" cy="128" r="72" fill="none" stroke="#FFF4D8" stroke-width="14"/><path d="M128 76V180M98 106H153M98 150H153" stroke="#FFF4D8" stroke-width="12"/>',
 'score':f'<path d="M128 20L159 87L231 95L177 145L193 218L128 181L63 218L79 145L25 95L97 87Z" fill="{GREEN}"/>',
 'downed':f'<circle cx="128" cy="128" r="98" fill="{MUTED}"/><path d="M77 80L111 114M111 80L77 114M145 80L179 114M179 80L145 114M83 167H174" stroke="#FFFFFF" stroke-width="12" stroke-linecap="round"/>'}
 for name,shape in paths.items():
  doc=f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">{shape}</svg>'
  (ROOT/'assets/icons'/f'icon_{name}.svg').write_text(doc)

def density_board():
 s=S(1600,1080);backdrop(s);s.t(56,74,'单位展开 / 7角色 + 3怪物',40,INK,700)
 s.t(56,116,'教师点击节点展开名单，完整身份与状态可读；公开端仅展示已揭示单位',24,MUTED)
 data=json.loads((ROOT/'sources/demo-scenarios.json').read_text())['baseBattle'];units=data['players']+data['monsters']
 for i,p in enumerate(units):
  x=56+(i%3)*504;y=150+(i//3)*220;s.glass(x,y,480,196)
  if i<7:avatar(s,p,'a',x+16,y+18,64)
  elif p['templateID']=='slime':art(s,'a','slime',x+16,y+18,64,64)
  else:s.rect(x+16,y+18,64,64,'#E4EDD9',12);s.t(x+48,y+62,'狼',28,GREEN,600,'middle')
  s.lines(x+96,y+39,name_lines(p,12),26,INK,32,600)
  s.t(x+16,y+115,f"生命 {p['health']}/{p['maximumHealth']} · 护盾 {p['shield']} · AP {p['ap']}",26)
  lab=p.get('status','第2轮可行动' if p.get('eligibleFromRound')==2 else '已揭示怪物')
  s.t(x+16,y+156,f"{p['team']} · 节点{p['nodeID']} · {lab}",24,RED if p['health']==0 else GREEN,600)
 s.t(584,892,'同职业可多人使用同一模板头像',26,INK,600)
 s.t(584,944,'未定稿职业 / 森林狼使用中性占位图',24,MUTED)
 s.t(584,998,'头像不包含姓名、资源数字或队伍标记',24,MUTED)
 s.save('seven_roles_multi_monsters',1,'密度检查｜7角色、3怪物、长名字、下轮资格')

if __name__=='__main__':
 icons()
 for t in ['a','b']:teacher(t);public(t);public(t,True);style(t)
 component_board();storybook();storybook(True);result_board();density_board()
 (ROOT/'sources/preview-index.json').write_text(json.dumps(META,ensure_ascii=False,indent=2))
 print(f'Created {len(META)} editable layout sources')
