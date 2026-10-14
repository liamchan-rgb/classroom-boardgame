"""Measure atlas source rectangles/foot anchors; source PNGs stay byte-identical."""
from pathlib import Path
import json
from PIL import Image

root=Path(__file__).resolve().parents[1]
art=root/'Native/Resources/Art'
scene=[]

def measure(image,region):
    alpha=image.getchannel('A').crop(region)
    bbox=alpha.point(lambda x:255 if x>32 else 0).getbbox()
    if bbox is None:raise ValueError('Empty atlas region: '+str(region))
    x0,y0,x1,y1=bbox
    tight=(region[0]+x0,region[1]+y0,region[0]+x1,region[1]+y1)
    rect=(max(region[0],tight[0]-6),max(region[1],tight[1]-6),min(region[2],tight[2]+6),min(region[3],tight[3]+6))
    return rect,tight

image=Image.open(art/'modules_clean_v4_atlas.png')
regions=[('oak_single',(0,20,638,700)),('fir_single',(638,20,1018,705)),('rock_outcrop',(1018,290,1536,710)),
         ('terrace',(0,698,676,1024)),('bank',(676,710,1258,1024)),('ground_tuft',(1260,730,1536,1024))]
for name,region in regions:
    rect,bbox=measure(image,region)
    scene.append(dict(id=name,kind='modules_clean_v4',sourceRect=[rect[0],rect[1],rect[2]-rect[0],rect[3]-rect[1]],
                      anchorPx=[(bbox[0]+bbox[2])/2-rect[0],bbox[3]-rect[1]-2],opaqueBounds=list(bbox),method='alpha>32 measured subject region'))
image=Image.open(art/'landmarks_v4_atlas.png')
for name,region in [('camp_a',(0,70,850,768)),('tower_a',(910,0,1450,768)),('tower_b',(1620,70,2048,768))]:
    rect,bbox=measure(image,region)
    scene.append(dict(id=name,kind='landmarks_v4',sourceRect=[rect[0],rect[1],rect[2]-rect[0],rect[3]-rect[1]],
                      anchorPx=[(bbox[0]+bbox[2])/2-rect[0],bbox[3]-rect[1]-2],opaqueBounds=list(bbox),method='alpha>32 measured subject region'))
image=Image.open(art/'actor_frames_v4.png');frames=[]
for index in range(10):
    row,col=divmod(index,4)
    region=(col*image.width//4,row*image.height//3,(col+1)*image.width//4,(row+1)*image.height//3)
    rect,bbox=measure(image,region)
    # Feet, not sword/cape/staff width, define the physical animation anchor.
    alpha=image.getchannel('A');band=max(4,int((bbox[3]-bbox[1])*0.05));total=weighted=0
    for y in range(bbox[3]-band,bbox[3]):
        for x in range(bbox[0],bbox[2]):
            value=alpha.getpixel((x,y))
            if value>32:total+=value;weighted+=x*value
    anchor=weighted/total if total else (bbox[0]+bbox[2])/2
    frames.append(dict(index=index,sourceRect=[rect[0],rect[1],rect[2]-rect[0],rect[3]-rect[1]],
                       anchorPx=[anchor-rect[0],bbox[3]-rect[1]-1],opaqueBounds=list(bbox),
                       state='east-walk' if index<4 else ('idle' if index<8 else 'ranger' if index==8 else 'spellblade')))
(art/'modular-manifest.json').write_text(json.dumps(dict(sceneModules=scene,actorFrames=frames,actorWorldHeight=74,walkLoopMs=600),ensure_ascii=False,indent=2)+'\n')
print('Measured',len(scene),'scene modules and',len(frames),'actor frames; PNG bytes unchanged.')
