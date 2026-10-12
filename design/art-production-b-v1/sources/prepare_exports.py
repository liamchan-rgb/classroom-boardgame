"""Read-only alpha analysis + editable SVG export definitions; no PNG editing."""
from pathlib import Path
import json
from PIL import Image
import numpy as np
from scipy import ndimage

ROOT=Path(__file__).resolve().parents[1]
ref=json.loads((ROOT/'sources/reference-manifest.json').read_text())
by_id={a['entityID']:a for a in ref['assets'] if a['entityType'] in ['classes','monsters','items']}
jobs=[]
for meta in json.loads((ROOT/'sources/generated-portraits.json').read_text()):
 entity=by_id[meta['entityID']];name=entity['assetName']+'.png'
 kind='classes' if entity['entityType']=='classes' else 'monsters'
 image=Path(meta['source']).name
 svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><image href="{image}" x="144" y="144" width="736" height="736" preserveAspectRatio="xMidYMid meet"/></svg>'
 svgfile='sources/export_'+entity['entityID']+'.svg';(ROOT/svgfile).write_text(svg)
 jobs.append({'entityID':entity['entityID'],'size':1024,'svg':svgfile,'file':f'assets/{kind}/{name}','source':meta['source'],'method':'full original sprite aspectFit in 14%-inset standard canvas'})

if (ROOT/'sources/items_clean_sheet.png').exists():
 # Atlas component selection is engineering export, preserving original RGB/alpha.
 # Pixel colors are read only; the selection becomes an editable SVG clip path.
 img=Image.open(ROOT/'sources/items_clean_sheet.png');alpha=np.array(img.getchannel('A'))
 labels,n=ndimage.label(alpha>128);sizes=np.bincount(labels.ravel())
 comps=[]
 for i,sl in enumerate(ndimage.find_objects(labels),1):
  if sl and sizes[i]>500:
   x0,y0,x1,y1=sl[1].start,sl[0].start,sl[1].stop,sl[0].stop
   comps.append({'index':i,'bbox':[x0,y0,x1,y1],'cx':(x0+x1)/2,'cy':(y0+y1)/2,'area':int(sizes[i])})
 assert len(comps)==18,len(comps)
 comps.sort(key=lambda c:c['cy']);rows=[sorted(comps[i:i+6],key=lambda c:c['cx']) for i in [0,6,12]]
 items=[a for a in ref['assets'] if a['entityType']=='items'];ordered=[c for row in rows for c in row]
 selections=[]
 for item,c in zip(items,ordered):
  x0,y0,x1,y1=c['bbox'];pad=3;x0=max(0,x0-pad);y0=max(0,y0-pad);x1=min(img.width,x1+pad);y1=min(img.height,y1+pad)
  selected=ndimage.binary_dilation(labels==c['index'],iterations=2)
  # Row spans retain antialias edges and exclude adjacent objects whose boxes overlap.
  paths=[]
  for yy in range(y0,y1):
   row=selected[yy,x0:x1];changes=np.diff(np.concatenate(([False],row,[False])).astype(np.int8))
   for aa,bb in zip(np.flatnonzero(changes==1),np.flatnonzero(changes==-1)):
    paths.append(f'M{x0+aa} {yy}h{bb-aa}v1h{-int(bb-aa)}Z')
  clip=''.join(paths);bw=x1-x0;bh=y1-y0
  svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><svg x="64" y="64" width="384" height="384" viewBox="{x0} {y0} {bw} {bh}" preserveAspectRatio="xMidYMid meet"><defs><clipPath id="item"><path d="{clip}"/></clipPath></defs><image href="items_clean_sheet.png" width="{img.width}" height="{img.height}" clip-path="url(#item)"/></svg></svg>'
  source='sources/export_'+item['entityID']+'.svg';(ROOT/source).write_text(svg)
  jobs.append({'entityID':item['entityID'],'size':512,'svg':source,'file':'assets/items/'+item['assetName']+'.png','source':'sources/items_clean_sheet.png','sourceSelectionBBox':[x0,y0,x1,y1],'method':'connected atlas silhouette selected in SVG; original color/alpha preserved; 12.5% canvas inset'})
  selections.append({'entityID':item['entityID'],**c,'selectedBBox':[x0,y0,x1,y1]})
 (ROOT/'sources/item-atlas-selections.json').write_text(json.dumps(selections,ensure_ascii=False,indent=2)+'\n')
(ROOT/'sources/export-jobs.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2)+'\n')
print(f'Prepared {len(jobs)} standard exports')
