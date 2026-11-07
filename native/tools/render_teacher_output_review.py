#!/usr/bin/env python3
"""Offline separation schematic + existing battle resources at normal time.

Not a UIKit, app, simulator or device capture. Map is the real generated topology;
battle samples come from the unchanged production MeadowSupportReviewExport.
"""
from pathlib import Path
import argparse,json,math,functools
from PIL import Image,ImageDraw,ImageFont,ImageOps,ImageChops,ImageFilter
from teacher_review_pose import ART,config,sample
p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
rows=[r for r in json.loads((a.input/'spellblade-frames.json').read_text()) if r['scenario']=='runeSlash-lethal'][::2]
layout=json.loads((a.input/'map.json').read_text());gait=json.loads((ART.parent/'hero-gait.json').read_text())
font_path='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
@functools.lru_cache(None)
def font(n):return ImageFont.truetype(font_path,n)
@functools.lru_cache(None)
def asset(name):
    folder=ART/(name+'.imageset');m=json.loads((folder/'Contents.json').read_text());f=next(i['filename'] for i in m['images'] if 'filename' in i)
    return Image.open(folder/f).convert('RGBA')
def text(im,xy,value,n=18,color='#ead69d'):
    ImageDraw.Draw(im).text(xy,value,font=font(n),fill=color)
def stamp(dst,im,center,size,alpha=1):
    if alpha<=0:return
    im=im.resize((max(1,round(size[0])),max(1,round(size[1]))),Image.Resampling.NEAREST)
    if alpha<1:im=im.copy();im.putalpha(im.getchannel('A').point(lambda v:round(v*max(0,min(1,alpha)))))
    dst.alpha_composite(im,(round(center[0]-im.width/2),round(center[1]-im.height/2)))
def crop(name,index,cw,ch,cols):
    im=asset(name);return im.crop(((index%cols)*cw,(index//cols)*ch,(index%cols+1)*cw,(index//cols+1)*ch))
@functools.lru_cache(300)
def hero(encoded):
    u=json.loads(encoded);rig=u.get('weaponPose')
    if rig:
        parts={k:((v['pivot']['x'],v['pivot']['y']),(v['offset']['x'],v['offset']['y']),v['rotation']) for k,v in rig['layers'].items()};root=(rig['rootOffset']['x'],rig['rootOffset']['y'])
    else:parts,root,*_=sample(u['clip'],u['progress'])
    armor=gait.get('armorVisuals',{}).get(u.get('armorID'),{});mapping=armor.get('battleLayers',{})
    names=armor.get('battleLayerOrder',config['layers'])
    for side in ['Far','Near']:
        thigh=parts.get('MeadowBattleHeroLeg'+side+'ThighWardrobe');body=parts.get('MeadowBattleHeroWardrobeCore')
        if thigh and body:
            angle=body[2]+max(-math.pi/22.5,min(math.pi/22.5,(thigh[2]-body[2])*0.35))
            parts['MeadowBattleHeroHem'+side+'Wardrobe']=(thigh[0],thigh[1],angle)
    if 'MeadowBattleHeroArmNearUpperWardrobe' in parts:parts['MeadowBattleHeroPauldronNearWardrobe']=parts['MeadowBattleHeroArmNearUpperWardrobe']
    out=Image.new('RGBA',(256,256))
    for name in names:
        if name=='MeadowBattleHeroJointUnderlay' and u['clip']=='idle':continue
        source=mapping.get(name,name)
        if name=='MeadowBattleHeroWeapon':source=gait['equipmentVisuals'].get(u.get('weaponID'),{}).get('battleAsset')
        if source is None or not (ART/(source+'.imageset')).exists():continue
        pivot,offset,angle=parts.get(name,((128,160),(0,0),0))
        im=asset(source).rotate(-math.degrees(angle),Image.Resampling.NEAREST,center=pivot)
        out.alpha_composite(im,(round(offset[0]+root[0]),round(offset[1]+root[1])))
    return out
feet={'p1':(165,420),'p2':(315,505),'m1':(650,395),'m2':(835,510)}
colors={'white':'#f4fbff','cyan':'#52dfff','blue':'#2365ff','gold':'#efbf59','green':'#56ff8b','violet':'#a268ff'}
plate=Image.new('RGBA',(1000,600))
for name in ['MeadowCampFarForest','MeadowCampGround','MeadowCampMidground']:
    im=asset(name).resize((1000,918),Image.Resampling.LANCZOS);plate.alpha_composite(im,(0,-159))
foreground=asset('MeadowCampForeground').resize((1000,918),Image.Resampling.LANCZOS)
def battle(row):
    f=plate.copy();f.alpha_composite(Image.new('RGBA',f.size,(0,0,0,round(row['darkness']*255))))
    d=ImageDraw.Draw(f)
    for u in row['units']:
        x,y=feet[u['id']];travel=row['travel'] if row['actor']==u['id'] else {'x':0,'y':0};x+=travel['x'];y+=travel['y']
        d.ellipse((x-26,y-6,x+26,y+6),fill=(0,0,0,110))
        if u['id'].startswith('p'):
            im=hero(json.dumps(u,sort_keys=True));f.alpha_composite(im.resize((213,213),Image.Resampling.NEAREST),(round(x-123*.83),round(y-214*.83)))
            if u['shield']>0:stamp(f,asset('BattleVFXRoundBarrier'),(x,y-65),(199,199),0.6)
        elif u.get('deathAge') is None:
            im=asset('MeadowBattleForestWarden');f.alpha_composite(im.resize((315,210),Image.Resampling.NEAREST),(round(x-178.5*.82),round(y-240*.82)))
        else:
            age=u['deathAge']
            if age<.8:stamp(f,crop('BattleVFXDeathBody60',min(47,int(age/.8*48)),384,256,8),(x,y-95),(315,210),max(0,1-age/.8))
            if age<2.3:stamp(f,crop('BattleVFXDeathWind60',min(115,int(age/.02)),448,320,8),(x+max(0,age)*90,y-78),(367,262),max(0,1-age/2.3))
        if u['vitalsVisible']:
            d=ImageDraw.Draw(f);d.rounded_rectangle((x-70,y-170,x+70,y-127),radius=5,fill='#11291f');text(f,(x-62,y-168),u['name'],16)
            d.rectangle((x-62,y-142,x+62,y-136),fill='#09160d');d.rectangle((x-62,y-142,x-62+124*u['hp']/max(1,u['maxHP']),y-136),fill='#40c76d')
    for glow in row['runes']['glows']:
        layer=Image.new('RGBA',f.size);c=glow['point'];rx,ry=glow['rx'],glow['ry'];ImageDraw.Draw(layer).ellipse((c['x']-rx,c['y']-ry,c['x']+rx,c['y']+ry),fill=colors.get(glow['color'],'#52dfff'));layer=layer.filter(ImageFilter.GaussianBlur(35));layer.putalpha(layer.getchannel('A').point(lambda v:round(v*glow['alpha']*.35)));f.alpha_composite(layer)
    for layer in row['runes']['spriteLayers']:stamp(f,asset(layer['asset']),(layer['center']['x'],layer['center']['y']),(layer['size'],layer['size']),layer['alpha'])
    d=ImageDraw.Draw(f)
    for mote in row['runes']['motes']:
        pt=mote['point'];s=mote['size']/2;c=colors.get(mote['color'],'#e9faff');d.polygon([(pt['x'],pt['y']-s),(pt['x']+s,pt['y']),(pt['x'],pt['y']+s),(pt['x']-s,pt['y'])],fill=c)
    for i,(die,poly) in enumerate(zip(row['dice'],row['poly'])):
        if poly['alpha']<=0:continue
        overlay=Image.new('RGBA',f.size);dd=ImageDraw.Draw(overlay)
        anchor=row['diceAnchor'];cx=anchor['x']+(i-(len(row['dice'])-1)/2)*40;cy=anchor['y'];radius=poly['radius']
        for face in poly['faces']:
            points=[(cx+p['x']*radius,cy+p['y']*radius) for p in face['points']]
            shade=face['shade'];color=(round(205*shade),round(155*shade),30) if die['color']=='gold' else (round(185*shade),35,30)
            dd.polygon(points,fill=color,outline='#edb7a1')
            if face['depth']>.6:text(overlay,(cx+face['center']['x']*radius-5,cy+face['center']['y']*radius-8),str(face['value']),12,'white')
        overlay.putalpha(overlay.getchannel('A').point(lambda v:round(v*poly['alpha'])));f.alpha_composite(overlay)
    for label in row['damageLabels']:
        age=row['time']-label['at']
        if 0<=age<1:text(f,(label['x'],label['y']-age*25),label['text'],23,'white')
    f.alpha_composite(foreground,(0,-159));return f
def map_image():
    im=Image.new('RGBA',(460,470),'#29412a');d=ImageDraw.Draw(im)
    for road in layout['roads']:
        points=[(p['x']/1280*460,p['y']/layout['coordinateHeight']*470) for p in road['points']];d.line(points,fill='#a98b4d',width=5)
    for prop in sorted(layout['props'],key=lambda p:p['y']):
        if prop.get('nodeID') is None:continue
        pic=asset(prop['asset']);w=prop['width']/1280*460*2;h=w*pic.height/pic.width
        stamp(im,pic,(prop['x']/1280*460,prop['y']/layout['coordinateHeight']*470-h*.3),(w,h))
    text(im,(10,10),'随机地图结构 · 真实生成数据',15)
    return im
map_panel=map_image()
def frame(row):
    f=Image.new('RGBA',(1400,850),'#101e16');d=ImageDraw.Draw(f)
    text(f,(18,12),'离线分屏示意 / 现有战斗资源正常速度 / 非 App 或实机截图',20)
    d.rounded_rectangle((16,55,340,830),radius=15,fill='#edf2e9');text(f,(32,72),'教师后台 · 操作与权限',22,'#204835')
    for i,label in enumerate(['随机地图 · 数量/滑块/种子','新行程 / 续档 / 保存','道路任意点移动 / 选人','节点编辑 / 怪物与奖励','移动购买 / 手动补满','生命 / AP / 金币调整','行囊与装备操作','技能 / 目标 / 结束回合','PPT / 教师备注']):
        y=125+i*67;d.rounded_rectangle((32,y,324,y+48),radius=8,fill='#d1dfce');text(f,(43,y+12),label,17,'#204835')
    text(f,(362,65),'公开游戏界面 · 地图 / 玩家信息 / 当前 demo 战斗',23)
    f.alpha_composite(map_panel.resize((460,470),Image.Resampling.NEAREST),(360,165))
    world=battle(row).resize((548,329),Image.Resampling.NEAREST);f.alpha_composite(world,(835,165))
    d=ImageDraw.Draw(f);d.rounded_rectangle((360,110,1380,150),radius=8,fill='#203a2b');text(f,(374,116),'符文斩 · 正常演出 / 同一套角色、骰子、特效资源',18)
    d.rounded_rectangle((835,505,1383,635),radius=10,fill='#1b3325');text(f,(851,518),'当前成员状态与行动顺序',19)
    for i,u in enumerate([x for x in row['units'] if x['id'].startswith('p')]):
        x=850+i*263;text(f,(x,550),u['name']+f"  {u['hp']}/{u['maxHP']}",17);d.rectangle((x,580,x+230,587),fill='#0a180f');d.rectangle((x,580,x+230*u['hp']/u['maxHP'],587),fill='#47c86d')
        for k in range(u['ap']):cx=x+8+k*22;cy=610;d.polygon([(cx,cy-6),(cx+6,cy),(cx,cy+6),(cx-6,cy)],fill='#e5c165')
    d.rounded_rectangle((360,655,1383,765),radius=10,fill='#1c3326');text(f,(376,668),'角色行囊和怪物预览按需要公开展示；绘本只投放页面。',19)
    text(f,(376,709),'节点修改、权限表单与教师备注留在后台。',18)
    text(f,(360,795),'此图仅说明信息分区及复用资源；原生布局和外接屏效果以用户实机截图为准。',14)
    return f.convert('RGB')
frames=[frame(r) for r in rows]
seed=Image.new('RGB',(1400,850*3))
for i,j in enumerate([0,len(frames)//2,len(frames)-1]):seed.paste(frames[j],(0,i*850))
palette=seed.quantize(colors=256);q=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
q[0].save(a.output/'teacher-public-normal.gif',save_all=True,append_images=q[1:],duration=40,loop=0,disposal=1,optimize=True)
sheet=Image.new('RGB',(1400,850*3))
for i,j in enumerate([0,len(frames)//2,len(frames)-1]):sheet.paste(frames[j],(0,i*850))
sheet.save(a.output/'teacher-public-contact-sheet.png')
(a.output/'teacher-backend-review-input.json').write_text(json.dumps(dict(map=layout,samples=rows),ensure_ascii=False,indent=2)+'\n')
print('Wrote normal-speed offline separation schematic:',len(frames),'samples,',len(frames)*40,'ms')
