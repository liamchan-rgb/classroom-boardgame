const fs=require('fs');
const path=require('path');
const { chromium }=require('playwright');
const ROOT=path.resolve(__dirname,'..');
const originals=[
 ['a','class_adventurer',path.join(ROOT,'sources','original_a_class_adventurer.png')],
 ['a','monster_slime',path.join(ROOT,'sources','original_a_monster_slime.png')],
 ['b','class_adventurer',path.join(ROOT,'sources','original_b_class_adventurer.png')],
 ['b','monster_slime',path.join(ROOT,'sources','original_b_monster_slime.png')]
];
(async()=>{
 const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--disable-dev-shm-usage','--force-color-profile=srgb']});
 const page=await browser.newPage({viewport:{width:1024,height:1024},deviceScaleFactor:1});
 if(process.argv.includes('--assets')){
  for(const [theme,id,src] of originals){
   const sourceTarget=path.join(ROOT,'sources',`original_${theme}_${id}.png`);if(src!==sourceTarget) fs.copyFileSync(src,sourceTarget);
   const data=fs.readFileSync(src).toString('base64');
   // Standard asset export: preserve art, place complete original on 1024 square
   // with 14% margins. No recoloring, retouching, silhouette edits or redrawing.
   const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"><image href="data:image/png;base64,${data}" x="144" y="144" width="736" height="736" preserveAspectRatio="xMidYMid meet"/></svg>`;
   const dst=path.join(ROOT,'sources',`export_${theme}_${id}.svg`);fs.writeFileSync(dst,svg);
   await page.setContent('<style>html,body{margin:0;background:transparent}</style>'+svg);await page.screenshot({path:path.join(ROOT,'assets',`style_${theme}`,`${id}_portrait.png`),omitBackground:true});
  }
 }else{
  for(const filename of fs.readdirSync(path.join(ROOT,'assets/icons')).filter(f=>f.endsWith('.svg'))){
   await page.setViewportSize({width:256,height:256});await page.setContent('<style>html,body{margin:0;background:transparent}</style>'+fs.readFileSync(path.join(ROOT,'assets/icons',filename),'utf8'));await page.screenshot({path:path.join(ROOT,'assets/icons',filename.replace('.svg','.png')),omitBackground:true});
  }
  const idx=JSON.parse(fs.readFileSync(path.join(ROOT,'sources','preview-index.json')));
  const measurements=[];
  for(const p of idx){
   await page.setViewportSize({width:p.width,height:p.height});
   await page.setContent('<style>html,body{margin:0}</style>'+fs.readFileSync(path.join(ROOT,'sources',`${p.name}.svg`),'utf8'));
   await page.evaluate(()=>document.fonts.ready);
   const boxes=await page.locator('text').evaluateAll(els=>els.map(e=>{const b=e.getBBox();return {text:e.textContent,x:b.x,y:b.y,w:b.width,h:b.height,fontSize:Number(e.getAttribute('font-size'))}}));
   measurements.push({name:p.name,width:p.width,height:p.height,boxes});
   if(p.scale===2){
    const context=await browser.newContext({viewport:{width:p.width,height:p.height},deviceScaleFactor:2});
    const high=await context.newPage();await high.setContent('<style>html,body{margin:0}</style>'+fs.readFileSync(path.join(ROOT,'sources',`${p.name}.svg`),'utf8'));await high.evaluate(()=>document.fonts.ready);await high.screenshot({path:path.join(ROOT,'previews',`${p.name}.png`)});await context.close();
   }else await page.screenshot({path:path.join(ROOT,'previews',`${p.name}.png`)});
   console.log(`Exported ${p.name}`);
  }
  fs.writeFileSync(path.join(ROOT,'sources','text-measurements.json'),JSON.stringify(measurements,null,2));
 }
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
