#!/usr/bin/env python3
"""Bake registered component atlases from a SHA-verified experiment input cache.
No new art or motion; heads combine once per selected loadout, never per tick.
"""
from pathlib import Path
import sys,json,importlib.util,hashlib,itertools,shutil
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];SOURCE=Path(sys.argv[1]);ART=Path(sys.argv[2]);OUT=ROOT/'native/ClassroomProbe/Resources';ASSETS=OUT/'Assets.xcassets'
spec=importlib.util.spec_from_file_location('composer',ART/'scripts/compose-character-parts.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Composer(m.Compositor):
 def asset(self,identifier):
  if identifier not in self.assets:
   p=self.entries[identifier];a=json.loads(p.read_text());self.assets[identifier]=(a,p,{m.key(b):b for b in a['bindings']})
  return self.assets[identifier]
c=Composer(SOURCE,SOURCE/'catalog.json',SOURCE/'Art/Integration/P1-modular-eight-way-v1/motion.json');record=json.loads((SOURCE/'inputs.json').read_text());files=[]
def put(name,im):
 p=ASSETS/(name+'.imageset');p.mkdir(exist_ok=True);im.save(p/(name+'.png'));(p/'Contents.json').write_text(json.dumps({'images':[{'filename':name+'.png','idiom':'universal'}],'info':{'author':'xcode','version':1}})+'\n')
 for f in sorted(p.iterdir()):files.append({'file':f.relative_to(OUT).as_posix(),'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'bytes':f.stat().st_size,'sourceCommit':record['sourceCommit'],'derivation':'registered component bake; original gait and source layers unchanged'})
 return name
base='p1-eight-way-base-v1';lower='p1-eight-way-lower-v1';cols=[('idle',0)]+[('walk',i) for i in range(1,9)]+[('walk-start',1),('walk-start',2),('walk-stop',1),('walk-stop',2)];directions=[['down','left','up','right'],['down-right','down-left','up-left','up-right']]
def sheets(render,prefix):
 names=[]
 for half,dirs in enumerate(directions):
  atlas=Image.new('RGBA',(3328,1024))
  for row,d in enumerate(dirs):
   for col,(clip,frame) in enumerate(cols):atlas.paste(render(d,clip,frame),(col*256,row*256))
  names.append(put(prefix+str(half),atlas))
 return names
ids={key:next(row['id'] for row in json.loads((SOURCE/'catalog.json').read_text())['assets'] if '/'+key+'/' in row['manifest']) for key in ['leatherArmor','runeArmor','hunting-bow-v1','greatSword','legendaryStaff']}
weapons={'none':None,'trainingSword':'p1-eight-way-weapon-v1','huntingBow':ids['hunting-bow-v1'],'greatSword':ids['greatSword'],'legendaryStaff':ids['legendaryStaff']}
outfits={'forester':'p1-eight-way-forester-v1','wayfarer':'p1-eight-way-wayfarer-v1','leatherArmor':ids['leatherArmor'],'runeArmor':ids['runeArmor'],'starlightArmor':'p1-chat-starlight-armor-v2','dragonArmor':'p1-chat-dragon-armor-v2'}
manifest={'schemaVersion':1,'sourceCommit':record['sourceCommit'],'bodyAtlases':{},'foregroundAtlases':{},'hairAtlases':{},'faceAtlases':{},'battleHair':{},'battleFaces':{},'sourceInputs':record,'derivedFiles':files}
def body_layer(selected,d,clip,f,front=False):
 out=Image.new('RGBA',(256,256));order=c.frames[d,clip,f]['drawOrder'];boundary=order.index('hair.front')
 for slot,im in c.layers(base,selected,d,clip,f):
  if (order.index(slot)>boundary)==front:out.alpha_composite(im)
 return out
for i,(outfit,oid) in enumerate(outfits.items()):
 manifest['foregroundAtlases'][outfit]=sheets(lambda d,cl,f:body_layer([lower,oid],d,cl,f,True),f'CustomForeground{i}H')
 for wi,(weapon,wid) in enumerate(weapons.items()):
  selected=[lower,oid]+([wid] if wid else [])
  manifest['bodyAtlases'][outfit+'|'+weapon]=sheets(lambda d,cl,f:body_layer(selected,d,cl,f),f'CustomBody{i}W{wi}H')
 print('baked body',outfit,flush=True)
# Face/hair keep their original head-local->canvas matrices for all 104 poses.
for group,rows,old in [('hair',json.loads((SOURCE/'Art/Integration/Appearance-battle-custom-heads-v1/scene-bindings.json').read_text())['hair'],['hair-chestnut','hair-silver']),('face',json.loads((SOURCE/'Art/Integration/Appearance-battle-custom-heads-v1/scene-bindings.json').read_text())['faces'],['face-blue','face-amber'])]:
 selections=[(x['id'],x['id']) for x in rows]+[(key,'p1-eight-way-'+key+'-v1') for key in old]
 for i,(key,aid) in enumerate(selections):
  def layer(d,clip,f):
   out=Image.new('RGBA',(256,256))
   for slot,im in c.layers(base,[aid],d,clip,f):
    if slot.startswith('hair.') if group=='hair' else slot.startswith('face.'):out.alpha_composite(im)
   return out
  manifest[group+'Atlases'][key]=sheets(layer,f'Custom{group.title()}{i}H')
  if i<len(rows):
   battle=next(iter(rows[i]['battleLayers'].values()));manifest['battleHair' if group=='hair' else 'battleFaces'][key]=put(f'CustomBattle{group.title()}{i}',Image.open(ART/battle).convert('RGBA'))
# Add reviewed battle armor layers and preserve original skin/leg registrations.
gait=json.loads((OUT/'hero-gait.json').read_text())
for item in ['starlightArmor','dragonArmor']:
 folder=ART/'Art/Parts/P1-Battle/chat-apparel-b-v1'/item;a=json.loads((folder/'battle-manifest.json').read_text());mapping=dict(gait['armorVisuals']['runeArmor']['battleLayers'])
 for key,rel in a['genericParts'].items():mapping[key]=put('Custom'+item+key,Image.open(folder/rel).convert('RGBA'))
 gait['armorVisuals'][item]={'itemID':item,'iconAsset':'','battleLayers':mapping,'battleLayerOrder':a['genericLayerOrder'],'bowAtlas':put('Custom'+item+'BowAtlas',Image.open(folder/a['bowAtlas']).convert('RGBA')),'bowTorso':put('Custom'+item+'BowTorso',Image.open(folder/a['bowTorso']).convert('RGBA'))}
# Verify decomposed component assembly equals the author compositor for every pose.
checks=0
for hair,face in itertools.product(list(manifest['hairAtlases'])[:6],list(manifest['faceAtlases'])[:4]):
 for outfit in ['starlightArmor','dragonArmor']:
  for d,clip,f in c.frames:
   parts=[lower,outfits[outfit],hair,face];layers=c.layers(base,parts,d,clip,f);body=body_layer([lower,outfits[outfit]],d,clip,f);features=Image.new('RGBA',(256,256));hair_layer=features.copy()
   for slot,im in layers:
    if slot.startswith('face.'):features.alpha_composite(im)
    elif slot.startswith('hair.'):hair_layer.alpha_composite(im)
   body.alpha_composite(features);body.alpha_composite(hair_layer);body.alpha_composite(body_layer([lower,outfits[outfit]],d,clip,f,True));expected=c.render(base,parts,d,clip,f)
   diff=np.abs(np.asarray(body).astype(int)-np.asarray(expected).astype(int));assert diff.max()<=2,(hair,face,outfit,d,clip,f,int(diff.max()));checks+=1
manifest['mechanicalWholeBodyChecks']=checks
manifest['maximumAllowedRGBACompositingRounding']=2
(OUT/'custom-appearance.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':'))+'\n');(OUT/'hero-gait.json').write_text(json.dumps(gait,ensure_ascii=False,separators=(',',':'))+'\n')
print('PASS',checks,'composites within two RGBA units;',len(files),'new asset files')

# Preserve original head options when only one independent field is selected.
r=OUT;s=SOURCE;m=json.loads((r/'custom-appearance.json').read_text())
def put(name,im):
 p=r/'Assets.xcassets'/(name+'.imageset');p.mkdir(exist_ok=True);im.save(p/(name+'.png'));(p/'Contents.json').write_text(json.dumps({'images':[{'filename':name+'.png','idiom':'universal'}],'info':{'author':'xcode','version':1}})+'\n')
 for f in p.iterdir():m['derivedFiles'].append({'file':f.relative_to(r).as_posix(),'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'bytes':f.stat().st_size,'sourceCommit':m['sourceCommit'],'derivation':'original profile head, same fixed battle registration'})
 return name
for key in ['hair-chestnut','hair-silver']:
 p=s/'Art/Parts/P1-v1/eight-way-v1'/key;a=json.loads((p/'asset.json').read_text());b=next(b for b in a['bindings'] if b['direction']=='right' and b['clip']=='idle');im=Image.new('RGBA',(256,256));im.alpha_composite(Image.open(p/b['layers']['hair.front']).convert('RGBA'),(82,60));m['battleHair'][key]=put('CustomBattle'+key,im)
original=Image.open(r/'Assets.xcassets/MeadowBattleHeroFace.imageset/MeadowBattleHeroFace.png').convert('RGBA')
for key in ['face-blue','face-amber']:
 p=s/'Art/Parts/P1-v1/eight-way-v1'/key;a=json.loads((p/'asset.json').read_text());b=next(b for b in a['bindings'] if b['direction']=='right' and b['clip']=='idle');im=Image.new('RGBA',(256,256))
 for slot,offset in {'face.eyes':(82,65),'face.brows':(82,64),'face.mouth':(79,65)}.items():im.alpha_composite(Image.open(p/b['layers'][slot]).convert('RGBA'),offset)
 im.alpha_composite(original.crop((146,116,153,125)),(146,116));m['battleFaces'][key]=put('CustomBattle'+key,im)
(r/'custom-appearance.json').write_text(json.dumps(m,ensure_ascii=False,separators=(',',':'))+'\n')
