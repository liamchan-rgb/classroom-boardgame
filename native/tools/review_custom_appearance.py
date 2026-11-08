#!/usr/bin/env python3
"""Review actual packaged components offline, with the existing battle sampler."""
from pathlib import Path
import sys,json,importlib.util,hashlib,itertools
import numpy as np
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[2];A=Path(sys.argv[1]);D=R/'docs/integration/custom-appearance-review-v0.19.0';D.mkdir(exist_ok=True,parents=True);RES=R/'native/ClassroomProbe/Resources';M=json.loads((RES/'custom-appearance.json').read_text());G=json.loads((RES/'hero-gait.json').read_text())
def module(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);sys.modules[name]=m;s.loader.exec_module(m);return m
battle=module('appearance24_battle',A/'scripts/build-chat-apparel-b-battle.py');binding=module('appearance24_binding',A/'scripts/appearance-scene-binding.py');timing=module('appearance24_clock',A/'scripts/review-synchronized-appearance.py');s=binding.SceneBindings();cache={}
def img(name):
 if name not in cache:cache[name]=Image.open(RES/'Assets.xcassets'/(name+'.imageset')/(name+'.png')).convert('RGBA')
 return cache[name]
dirs=[['down','left','up','right'],['down-right','down-left','up-left','up-right']];columns=[('idle',0)]+[('walk',i) for i in range(1,9)]+[('walk-start',1),('walk-start',2),('walk-stop',1),('walk-stop',2)]
def walk(outfit,hair,face,d,clip,f,weapon='none'):
 half=0 if d in dirs[0] else 1;row=dirs[half].index(d);col=columns.index((clip,f));box=(col*256,row*256,(col+1)*256,(row+1)*256);im=Image.new('RGBA',(256,256))
 for name in [M['bodyAtlases'][outfit+'|'+weapon][half],M['faceAtlases'][face][half],M['hairAtlases'][hair][half],M['foregroundAtlases'][outfit][half]]:im.alpha_composite(img(name).crop(box))
 return im
# Check the resources actually copied into the app, including native bow material.
for row in M['derivedFiles']:
 b=(RES/row['file']).read_bytes();assert hashlib.sha256(b).hexdigest()==row['sha256']
for group,table,key in [('hair',s.hair,'battleHair'),('face',s.faces,'battleFaces')]:
 for id,row in table.items():assert img(M[key][id]).tobytes()==Image.open(A/next(iter(row['battleLayers'].values()))).convert('RGBA').tobytes()
for item in ['starlightArmor','dragonArmor']:
 data=json.loads((A/'Art/Parts/P1-Battle/chat-apparel-b-v1'/item/'battle-manifest.json').read_text());binding=G['armorVisuals'][item]
 for name,rel in data['genericParts'].items():assert img(binding['battleLayers'][name]).tobytes()==Image.open(A/'Art/Parts/P1-Battle/chat-apparel-b-v1'/item/rel).convert('RGBA').tobytes()
 for key,target in [('bowAtlas','bowAtlas'),('bowTorso','bowTorso')]:assert img(binding[key]).tobytes()==Image.open(A/'Art/Parts/P1-Battle/chat-apparel-b-v1'/item/data[target]).convert('RGBA').tobytes()
c=battle.art.Compositor(A,s.file(s.data['walkingCatalog']),s.file(s.data['walkingMotion']));checks=0;maxdiff=0
for hair,face,item in itertools.product(s.hair,s.faces,['starlightArmor','dragonArmor']):
 oid='p1-chat-'+('starlight' if item=='starlightArmor' else 'dragon')+'-armor-v2'
 for d,clip,f in c.frames:
  result=walk(item,hair,face,d,clip,f);expected=c.render(s.data['baseID'],[s.data['lowerBodyID'],oid,hair,face],d,clip,f);delta=int(np.abs(np.asarray(result).astype(int)-np.asarray(expected).astype(int)).max());assert delta<=2,(item,hair,face,d,clip,f,delta);maxdiff=max(maxdiff,delta);checks+=1
print('PASS actual app component PNGs:',checks,'composites; max RGBA rounding',maxdiff,flush=True)
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',14);choices=[s.preset(x) for x in ['m1-short','m2-sidepart','m3-topknot','f1-bob','f2-ponytail','f3-bun']];renderers=[battle.Renderer.for_appearance(s,x) for x in choices]
roster=Image.new('RGB',(1536,1120),'#1e3428');dr=ImageDraw.Draw(roster)
for i,(choice,renderer) in enumerate(zip(choices,renderers)):
 item=s.outfits[choice.outfit]['battleItem'];x=i%3*512;y=i//3*560
 for j,d in enumerate(['down','right']):roster.paste(walk(item,choice.hair,choice.face,d,'idle',0),(x+j*256,y),walk(item,choice.hair,choice.face,d,'idle',0))
 im=renderer.actor('huntingBow','idle',0);roster.paste(im,(x+128,y+280),im);dr.text((x+5,y+258),choice.hair.removeprefix('p1-custom-hair-')+' / '+choice.face.removeprefix('p1-custom-face-'),font=font,fill='#f3e1b8')
roster.save(D/'custom-appearance-roster-1x.png')
# Six styles, walking and bow on the unmodified normal clocks, full figures.
frames=[]
for i in range(135):
 frame=Image.new('RGB',(1536,560),'#1e3428');dr=ImageDraw.Draw(frame)
 for col,(choice,renderer) in enumerate(zip(choices,renderers)):
  item=s.outfits[choice.outfit]['battleItem'];im=walk(item,choice.hair,choice.face,'right','walk',i//6%8+1);frame.paste(im,(col*256,0),im)
  clip,p=timing.attack(i*.02,'huntingBow');im=renderer.actor('huntingBow',clip,p);frame.paste(im,(col*256,280),im);dr.text((col*256+5,258),['M1','M2','M3','F1 ear-cover','F2','F3'][col],font=font,fill='#f3e1b8')
 frames.append(frame)
sample=Image.new('RGB',(1536*4,560*2))
for j,i in enumerate(np.linspace(0,134,8).astype(int)):sample.paste(frames[i],(j%4*1536,j//4*560))
palette=sample.quantize(colors=256);encoded=[im.quantize(palette=palette,dither=Image.Dither.NONE) for im in frames];path=D/'custom-appearance-normal.gif';encoded[0].save(path,save_all=True,append_images=encoded[1:],duration=20,loop=0,disposal=1,optimize=True)
with Image.open(path) as im:
 total=0
 for i in range(im.n_frames):im.seek(i);im.convert('RGB').load();total+=im.info['duration']
 assert total==2700
 for i in [0,im.n_frames//2,im.n_frames-1]:im.seek(i);im.convert('RGB').save(D/f'normal-decoded-{i:03}.png')
 media={'frames':im.n_frames,'durationMs':total,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
(D/'verification.json').write_text(json.dumps({'artSource':M['sourceCommit'],'packagedComponentCompositesChecked':checks,'maximumRGBACompositingRounding':maxdiff,'newAssetFiles':len(M['derivedFiles']),'battlePNGsMatchReviewedSource':True,'samePlayerRecordAllScenes':True,'GIF':media,'noAppSimulatorOrDeviceRun':True,'GIFScope':'Offline actual walk component composites and existing battle sampler; not UIKit capture or device performance proof'},indent=2)+'\n')
print(json.dumps(media),flush=True)
