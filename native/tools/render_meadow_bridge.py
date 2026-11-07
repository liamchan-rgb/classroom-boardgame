#!/usr/bin/env python3
"""Offline resource/pose review, NOT a UIKit/device or external-display capture.

First export real command results with meadow_fixture_export.swift linked to the
tested GameCore objects. This compositor reads those public-only JSON fixtures.
"""
from pathlib import Path
import argparse,json,math
from PIL import Image,ImageDraw,ImageFont,ImageOps
from meadow_pose_review import render,ART

p=argparse.ArgumentParser();p.add_argument('fixtures',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=True);doc=json.loads(a.fixtures.read_text())
W,H=960,540;S=.5;BOX=(36,96,1884,726);stage=(924,315)
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
font=lambda n:ImageFont.truetype(FONT,n)
cache={}
def image(name):
    if name not in cache:cache[name]=Image.open(ART/(name+'.png')).convert('RGBA')
    return cache[name]
def stamp(dst,im,center,size):
    im=im.resize((max(1,round(size[0])),max(1,round(size[1]))),Image.Resampling.NEAREST)
    dst.alpha_composite(im,(round(center[0]-im.width/2),round(center[1]-im.height/2)))
def fit(im,size):return ImageOps.fit(im,size,Image.Resampling.NEAREST)
def crop(name,index,cols,rows):
    im=image(name);cw,ch=im.width//cols,im.height//rows
    return im.crop(((index%cols)*cw,(index//cols)*ch,(index%cols+1)*cw,(index//cols+1)*ch))
def text(im,xy,s,n=13,color='#f5e6b0'):
    ImageDraw.Draw(im).text(xy,s,font=font(n),fill=color,stroke_width=0)
def smooth(t):
    x=min(1,max(0,t));return x*x*(3-2*x)
def approach(age):
    if age<.12:return 0
    if age<.38:return smooth((age-.12)/.26)
    if age<.58:return 1
    return 1-smooth((age-.58)/.57)
def shell(snapshot,mode):
    im=Image.new('RGBA',(W,H),'#102219')
    text(im,(18,16),'MEADOW / '+mode,19)
    text(im,(610,20),'PUBLIC DISPLAY / read-only',14)
    text(im,(18,521),'OFFLINE COMPOSITE / public command fixtures / no app, simulator or device launched',10)
    return im
def bars(im,units):
    players=[u for u in units if u['player']];d=ImageDraw.Draw(im)
    for i,u in enumerate(players):
        x=18+i*462;y=430;d.rounded_rectangle((x,y,x+450,y+65),radius=6,fill='#0c1912')
        text(im,(x+8,y+5),u['name'],13);text(im,(x+8,y+23),f"HP {u['health']}/{u['maximumHealth']}    SHIELD {u['shield']}",12)
        d.rectangle((x+8,y+42,x+440,y+46),fill='#152719');d.rectangle((x+8,y+42,x+8+432*u['health']/max(1,u['maximumHealth']),y+46),fill='#43c666')
        for j in range(u['ap']):
            cx=x+12+j*12;cy=y+55;d.polygon([(cx,cy-4),(cx+4,cy),(cx,cy+4),(cx-4,cy)],fill='#e8c56c')
        text(im,(x+300,y+51),f"G {u['coins']}   SCORE {u['score']}",10)
def draw_map(age,post=False):
    f=doc['runeSlash'] if post else doc['arrival'] if age>=0 else doc['exploration'];snap=f['snapshot'];im=shell(snap,'EXPLORATION')
    ground=image('MeadowCampGround');ground=ground.crop((0,ground.height*2//3,ground.width,ground.height))
    bg=fit(ground,(924,365));im.alpha_composite(bg,(18,48));d=ImageDraw.Draw(im)
    nodes={n['id']:n for n in snap['nodes']}
    cam=f['camera'];cx,cy=cam['center']['x'],cam['center']['y'];zoom=cam['zoom']
    def point(x,y):return (18+462+(x-cx)*(924-70)*zoom,48+182+(y-cy)*(365-70)*zoom)
    for road in snap['roads']:
        if road['a'] in nodes and road['b'] in nodes:
            n,m=nodes[road['a']],nodes[road['b']];d.line([point(n['x'],n['y']),point(m['x'],m['y'])],fill='#8f7440',width=7)
    for n in nodes.values():
        x,y=point(n['x'],n['y']);d.ellipse((x-7,y-7,x+7,y+7),fill='#d4b66b');text(im,(x-17,y+9),str(n['id']) if n['revealed'] else '?',11)
    for i,u in enumerate([u for u in snap['units'] if u['player']]):
        n=nodes[u['nodeID']];x,y=n['x'],n['y']
        if age>=0 and not post:
            move=next(m for m in f['presentations'][0]['mapMoves'] if m['unitID']==u['id']);start,end=move['points'][0],move['points'][-1];t=min(1,age/1.3)
            x=start['x']+(end['x']-start['x'])*t;y=start['y']+(end['y']-start['y'])*t
        px,py=point(x,y);cell=crop('Hero1Directions',3*13+(1+int(age/.12)%8),13,4) if age>=0 and not post else crop('Hero1Directions',0,13,4)
        stamp(im,cell,(px+i*19,py-11),(45,45));text(im,(px-12+i*19,py+14),u['id'],10)
    bars(im,snap['units']);return im
def draw_battle(age):
    f=doc['runeSlash'];e=f['presentations'][0];before=e['before'];after=f['snapshot'];im=shell(before,'BATTLE');bg=Image.new('RGBA',stage)
    for name in ['MeadowCampFarForest','MeadowCampGround','MeadowCampMidground']:bg.alpha_composite(fit(image(name),stage))
    bg.alpha_composite(Image.new('RGBA',stage,(0,0,0,110)))
    old={u['id']:u for u in before['units']};new={u['id']:u for u in after['units']};units=[]
    for u in before['units']:
        threshold=.72 if u['player'] else .46
        units.append(new.get(u['id'],u) if age>=threshold else u)
    def pos(u):
        peers=[p for p in units if p['player']==u['player']];i=next(i for i,p in enumerate(peers) if p['id']==u['id']);row=i%4;col=i//4
        return (stage[0]*(.19 if u['player'] else .77)+col*(-50 if u['player'] else 50)+(row%2)*25,stage[1]*(.34+row*.15 if len(peers)>2 else .60+row*.18))
    target=next(u for u in units if not u['player']);tx,ty=pos(target)
    for u in units:
        x,y=pos(u);size=105
        cue=next((c for c in e['units'] if c['id']==u['id']),None)
        if u['id']=='p1':v=approach(age);x+=(tx-x-size*.65)*v;y+=(ty-y)*v
        d=ImageDraw.Draw(bg);d.ellipse((x-24,y+size*.34-4,x+24,y+size*.34+4),fill=(0,0,0,100))
        if cue and u['id']=='p1' and age>=.72:
            index=min(19,int((age-.72)/.58*20));heal=crop('BattleVFXHealingStandardSheet',index,5,4);stamp(bg,heal,(x,y),(size*1.8,size*1.8))
        if u['player']:
            clip='attack' if u['id']=='p1' else 'idle';progress=min(1,max(0,age/.9)) if clip=='attack' else (age%2.4)/2.4
            art=render(clip,progress);stamp(bg,art,(x,y-size*.16),(size*1.65,size*1.65))
        else:
            dead=u['health']==0
            index=min(39,int(max(0,age-.46)/.8*40)) if dead else int((age%2.4)/2.4*12)
            if not dead or age<1.26:stamp(bg,crop('MeadowMonsterSlime'+('Death' if dead else 'Motion'),index,8,5 if dead else 7),(x,y-size*.15),(size*1.7,size*1.7))
        if u['shield']>0:
            alpha=min(1,max(0,(age-.72)/.25));shield=Image.new('RGBA',stage);ImageDraw.Draw(shield).ellipse((x-size*.575,y-size*.675,x+size*.575,y+size*.475),outline=(50,190,255,round(alpha*220)),width=2);bg.alpha_composite(shield)
        if cue and not u['player'] and age>=.22:
            progress=(age-.22)/.24*.5 if age<.46 else .5+(age-.46)/.84*.5
            index=min(19,int(progress*20));fx=image(f'MeadowRuneSlashAttack{index+1:02d}');stamp(bg,fx,(x,y),(size*1.8,size*1.8))
        if cue and not u['player'] and age>=.46:
            t=min(1,(age-.46)/.64);d=ImageDraw.Draw(bg)
            for i in range(18):
                angle=i*2.399;radius=size*(.1+t*.9);px=x+math.cos(angle)*radius;py=y+math.sin(angle)*radius*.6-t*size*.25;d.rectangle((px,py,px+2,py+4),fill=(245,207,80,round(255*(1-t))) if i%3==0 else (80,205,255,round(255*(1-t))))
            text(bg,(x-20,y-size*.35-max(0,age-.46)*15),str(cue['healthChange']),20,'white')
        if u['health']>0:
            d=ImageDraw.Draw(bg);d.rounded_rectangle((x-38,y-size*.9-14,x+38,y-size*.9+13),radius=3,fill='#0b2018');text(bg,(x-32,y-size*.9-12),u['name'],9);d.rectangle((x-32,y-size*.9+2,x+32*u['health']/u['maximumHealth'],y-size*.9+5),fill='#48cf62')
    bg.alpha_composite(fit(image('MeadowCampForeground'),stage));im.alpha_composite(bg,(18,48))
    text(im,(22,385),'ACTION ORDER    '+ ' > '.join(before['queueIDs']),13)
    bars(im,units);text(im,(22,505),'Rune Slash / hit .46s / heal + shield .72s / committed dice 3 + 4',11)
    return im

frames=[]
for i in range(90):
    t=i/30
    frames.append((draw_map(t) if t<1.3 else draw_battle(t-1.3) if t<2.6 else draw_map(t,post=True)).convert('RGB'))
seed=Image.new('RGB',(W,H*3));seed.paste(frames[0],(0,0));seed.paste(frames[53],(0,H));seed.paste(frames[65],(0,H*2));palette=seed.quantize(colors=256)
quantized=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
quantized[0].save(a.output/'meadow-public-normal.gif',save_all=True,append_images=quantized[1:],duration=[30,30,40]*30,loop=0,disposal=1,optimize=True)
sheet=Image.new('RGB',(W,H*3));
for i,k in enumerate([0,48,63]):sheet.paste(frames[k],(0,H*i))
sheet.save(a.output/'meadow-public-contact-sheet.png')
print('Wrote 3-second normal-speed offline GIF and full-scene contact sheet.')
