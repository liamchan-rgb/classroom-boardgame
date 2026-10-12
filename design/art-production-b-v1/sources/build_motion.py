"""Original presentation-only animation resources. No gameplay calculations."""
from pathlib import Path
import json,math

ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'asset-manifest.json').read_text())
entities=[a for a in manifest['assets'] if a['entityType'] in ['classes','monsters']]
motions={
 'idle':{'durationMs':2400,'loop':True,'keyframes':[{'t':0,'x':0,'y':0,'scaleX':1,'scaleY':1,'rotationDeg':0,'opacity':1},{'t':.5,'x':0,'y':-.008,'scaleX':.996,'scaleY':1.012,'rotationDeg':0,'opacity':1},{'t':1,'x':0,'y':0,'scaleX':1,'scaleY':1,'rotationDeg':0,'opacity':1}]},
 'move':{'durationMs':600,'loop':False,'keyframes':[{'t':0,'x':0,'y':0,'rotationDeg':0},{'t':.25,'x':.01,'y':-.018,'rotationDeg':-1},{'t':.5,'x':0,'y':0,'rotationDeg':0},{'t':.75,'x':-.01,'y':-.018,'rotationDeg':1},{'t':1,'x':0,'y':0,'rotationDeg':0}]},
 'attack':{'durationMs':520,'loop':False,'keyframes':[{'t':0,'x':0,'y':0,'rotationDeg':0},{'t':.2,'x':-.018,'y':.004,'rotationDeg':-2},{'t':.45,'x':.045,'y':-.01,'rotationDeg':2},{'t':.65,'x':.035,'y':-.008,'rotationDeg':1},{'t':1,'x':0,'y':0,'rotationDeg':0}]},
 'hurt':{'durationMs':280,'loop':False,'keyframes':[{'t':0,'x':0,'rotationDeg':0},{'t':.2,'x':-.018,'rotationDeg':-1},{'t':.4,'x':.014,'rotationDeg':1},{'t':.65,'x':-.008,'rotationDeg':-1},{'t':1,'x':0,'rotationDeg':0}]},
 'down':{'durationMs':450,'loop':False,'holdFinalFrame':True,'keyframes':[{'t':0,'x':0,'y':0,'rotationDeg':0,'opacity':1,'saturation':1},{'t':.45,'x':0,'y':.012,'rotationDeg':3,'opacity':.7,'saturation':.6},{'t':1,'x':0,'y':.02,'rotationDeg':5,'opacity':.55,'saturation':.25}]},
 'revive':{'durationMs':680,'loop':False,'keyframes':[{'t':0,'y':.02,'rotationDeg':5,'scaleX':1,'scaleY':1,'opacity':.55,'saturation':.25},{'t':.45,'y':-.014,'rotationDeg':0,'scaleX':1.018,'scaleY':1.018,'opacity':1,'saturation':1},{'t':1,'y':0,'rotationDeg':0,'scaleX':1,'scaleY':1,'opacity':1,'saturation':1}]}}
profiles=[]
for a in entities:
 heavy=a['entityID'] in ['stoneGuardian','caveTroll','ruinDragon']
 profiles.append({'entityID':a['entityID'],'entityType':a['entityType'],'image':a['file'],'motionSet':'basic-transform-v1','anchor':[.5,.82 if not heavy else .78],'amplitudeMultiplier':.65 if heavy else 1.12 if a['entityID']=='slime' else 1,'facingDirection':-1 if a['entityType']=='monsters' else 1,'minimumCanvasOverflowFraction':.08,'status':'authored-transform-profile-not-skeletal'})
motion={'formatVersion':1,'version':'b-basic-motion-v1','units':'x/y fractions of displayed image width/height; rotation degrees; t normalized 0..1','motionSet':'basic-transform-v1','motions':motions,'entityProfiles':profiles,'reducedMotion':{'idle':'off','move':'instant visual placement from committed path','attack':'static pose + brief effect','hurt':'static pose + impact glyph','down':'instant persistent down styling','revive':'instant final pose + brief glyph'},'eventPolicy':{'presentationOnly':True,'eventKey':'gameSessionID + operationResultID','oneShotPlaysPerResult':1,'replayOnRenderOrReconnect':False,'mayCallRulesEngine':False,'mayRollDice':False,'mayChangeDecisionTimer':False,'unknownEntityMayRender':False,'publicResourceDeltaMode':'one consolidated fade-in/hold/fade-out text','resourceCountersTween':False,'inactiveUnitsKeepDownOrEligibilityMarkers':True}}
(ROOT/'animations/character-motion.json').write_text(json.dumps(motion,ensure_ascii=False,indent=2)+'\n')

# Independent vector effect atlas: eight transparent 256px frames per effect.
FX=['impact','shield','heal','revive','coin','score','natural20','dice6','dice20','rune','flame','projectile']
(ROOT/'assets/effects').mkdir(exist_ok=True)
def star(cx,cy,r,n=5):
 pts=[]
 for j in range(n*2):
  angle=-math.pi/2+j*math.pi/n;rad=r if j%2==0 else r*.44;pts.append(f'{cx+math.cos(angle)*rad:.2f},{cy+math.sin(angle)*rad:.2f}')
 return ' '.join(pts)
def shape(kind,p):
 blue='#315E9C';teal='#176A86';gold='#995207';purple='#6650A4';red='#B93838';cream='#FFF3CD'
 if kind in ['impact','natural20']:
  c=gold if kind=='natural20' else red;r=24+58*p
  s=f'<polygon points="{star(128,128,r,8 if kind=="impact" else 5)}" fill="{c}"/><polygon points="{star(128,128,r*.58,8 if kind=="impact" else 5)}" fill="{cream}"/>'
  if kind=='natural20':s+=f'<polygon points="128,92 162,112 153,151 111,151 95,112" fill="#FFFDF5" stroke="{gold}" stroke-width="4"/><path d="M128 92L111 151L162 112L95 112L153 151Z" fill="none" stroke="{gold}" stroke-width="2"/>'
  return s
 if kind=='shield':return f'<path d="M128 58L188 82V124Q184 173 128 203Q72 173 68 124V82Z" fill="#C9E4FA" fill-opacity=".55" stroke="{blue}" stroke-width="6"/><path d="M128 82V173" stroke="#FFFFFF" stroke-width="5"/>'
 if kind in ['heal','revive']:
  y=142-28*p;c=teal if kind=='heal' else purple
  s=f'<path d="M128 {y+37}L91 {y+2} C68 {y-24} 101 {y-49} 128 {y-18} C155 {y-49} 188 {y-24} 165 {y+2} Z" fill="{c}"/>'
  if kind=='revive':s+=f'<circle cx="128" cy="128" r="{48+28*p}" fill="none" stroke="{purple}" stroke-width="5"/><path d="M115 118H141M128 105V131" stroke="#FFFFFF" stroke-width="5"/>'
  else:s+=f'<path d="M122 {y-7}H134M128 {y-13}V{y-1}" stroke="#FFFFFF" stroke-width="4"/>'
  return s
 if kind=='coin':return f'<ellipse cx="128" cy="134" rx="{40+12*math.sin(math.pi*p)}" ry="48" fill="{gold}"/><ellipse cx="128" cy="134" rx="29" ry="36" fill="none" stroke="{cream}" stroke-width="5"/><path d="M128 108V160M113 124H143M113 145H143" stroke="{cream}" stroke-width="4"/>'
 if kind=='score':return f'<polygon points="{star(128,128,55)}" fill="{teal}"/><polygon points="{star(128,128,31)}" fill="#CDEFFA"/>'
 if kind=='dice6':return f'<path d="M128 63L188 96V163L128 197L68 163V96Z" fill="#F3F9FC" stroke="{teal}" stroke-width="5"/><path d="M68 96L128 130L188 96M128 130V197" fill="none" stroke="{teal}" stroke-width="4"/>'
 if kind=='dice20':return f'<polygon points="128,53 190,91 179,165 128,205 77,165 66,91" fill="#E5F3FA" stroke="{teal}" stroke-width="5"/><path d="M128 53L77 165L190 91L128 205L66 91L179 165Z" fill="none" stroke="{teal}" stroke-width="3"/>'
 if kind=='rune':return f'<circle cx="128" cy="128" r="{48+20*p}" fill="none" stroke="{purple}" stroke-width="5"/><polygon points="128,67 189,128 128,189 67,128" fill="none" stroke="{purple}" stroke-width="4"/><polygon points="128,94 162,128 128,162 94,128" fill="none" stroke="#97BFE2" stroke-width="3"/>'
 if kind=='flame':return f'<path d="M128 54C119 97 77 109 91 164C102 207 165 201 171 157C175 127 153 110 159 82C140 101 130 116 130 139C113 113 126 83 128 54Z" fill="{gold}"/><path d="M130 110C124 138 110 147 117 173C131 190 153 172 144 149Z" fill="{cream}"/>'
 if kind=='projectile':
  cx=69+118*p;return f'<path d="M{cx-35} 128H{cx+28}" stroke="{teal}" stroke-width="5"/><path d="M{cx+13} 114L{cx+34} 128L{cx+13} 142Z" fill="{gold}"/><path d="M{cx-25} 128L{cx-34} 118M{cx-25} 128L{cx-34} 138" stroke="{teal}" stroke-width="4"/>'
effects=[]
for kind in FX:
 parts=['<svg xmlns="http://www.w3.org/2000/svg" width="2048" height="256" viewBox="0 0 2048 256">']
 for i in range(8):
  p=i/7;opacity=0 if i==7 else .45 if i==0 else min(1,(1-p)*1.45)
  rotation=(1-p)*30 if kind.startswith('dice') else 0
  parts.append(f'<g transform="translate({i*256} 0)" opacity="{opacity:.4f}"><g transform="rotate({rotation:.2f} 128 128)">{shape(kind,p)}</g>')
  if kind not in ['dice6','dice20','projectile']:
   for j in range(6):
    angle=j*math.pi/3;radius=42+40*p;x=128+math.cos(angle)*radius;y=128+math.sin(angle)*radius
    parts.append(f'<rect x="{x-3:.2f}" y="{y-3:.2f}" width="6" height="6" fill="#B2DDEF"/>')
  parts.append('</g>')
 parts.append('</svg>');source=f'sources/fx_{kind}.svg';(ROOT/source).write_text(''.join(parts))
 effects.append({'effectID':kind,'source':source,'file':f'assets/effects/fx_{kind}_sheet.png','widthPx':2048,'heightPx':256,'frameCount':8,'frameWidthPx':256,'frameHeightPx':256,'frameOrder':'left-to-right','durationMs':900 if kind.startswith('dice') or kind=='natural20' else 650,'terminalFrameTransparent':True,'loop':False,'playsPerCommittedResult':1,'sourceType':'original-editable-vector','noBakedNumbers':True,'reducedMotion':'middle-frame static brief glyph then remove'})
animation_manifest={'formatVersion':1,'version':'b-basic-motion-v1','status':'authored-presentation-resources-not-native-tested','entityProfileCount':10,'characterMotionStateCount':6,'motionFile':'animations/character-motion.json','effects':effects,'resourceText':{'durationMs':1300,'fadeInMs':150,'holdMs':900,'fadeOutMs':250,'bakedText':False,'playsPerCommittedResult':1,'replayOnRender':False,'publicBookExcludesAP':True},'integrationPolicy':{'noRulesWrites':True,'consumeCommittedResultsOnly':True,'natural20FromRawDamageD20FlagOnly':True,'diceFacesReadCommittedValueOnly':True,'teacherMayInspectFullGameHistory':True},'limitations':['transform-based static-art animation, not skeletal or hand-drawn limb poses','no directional walk sprite sheets','native SwiftUI and external-display behavior untested']}
(ROOT/'animation-manifest.json').write_text(json.dumps(animation_manifest,ensure_ascii=False,indent=2)+'\n')
print('Authored six character motion states for ten entities and twelve eight-frame effect atlases')
