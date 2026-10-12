const {chromium}=require('playwright');
const fs=require('fs');const path=require('path');
const ROOT=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
 const cases=[];
 for(const aspect of ['16x9','4x3']){
  const page=await browser.newPage();
  // Read only the local design document into DOM; no file URL or network needed.
  await page.setContent(fs.readFileSync(path.join(ROOT,'previews',`public_feedback_once_${aspect}.html`),'utf8'));
  const duplicate=await page.evaluate(()=>window.reviewMotion.showCommittedDelta('demo_committed_heavy_strike_001'));
  if(duplicate!==false)throw Error('Duplicate event replayed');
  await page.waitForFunction(()=>Number(getComputedStyle(document.querySelector('#committed-feedback')).opacity)>.98,{},{timeout:1000});
  await page.waitForFunction(()=>Number(getComputedStyle(document.querySelector('#committed-feedback')).opacity)===0&&document.querySelector('#committed-feedback').getAnimations().every(a=>a.playState==='finished'),{},{timeout:2000});
  const state=await page.evaluate(()=>({played:window.reviewMotion.played,durationMs:window.reviewMotion.durationMs,opacity:Number(getComputedStyle(document.querySelector('#committed-feedback')).opacity),duplicateAgain:window.reviewMotion.showCommittedDelta('demo_committed_heavy_strike_001')}));
  if(state.played!==1||state.duplicateAgain!==false||state.opacity!==0)throw Error(JSON.stringify(state));
  cases.push({aspect,...state});await page.close();
 }
 await browser.close();
 fs.writeFileSync(path.join(ROOT,'sources/motion-validation.json'),JSON.stringify({scope:'offline-review-demo-only',status:'passed',cases,appLifecycleVerified:false,fileURLTested:false,method:'Local HTML read into browser DOM; no network or App state'},null,2)+'\n');
 console.log('PASS: two feedback previews fade once and reject duplicate event IDs');
})().catch(e=>{console.error(e);process.exit(1)});
