// Mechanical SVG canvas export. Generated artwork is not repainted or recolored.
const fs=require('fs'),path=require('path');const {chromium}=require('playwright');
const ROOT=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--force-color-profile=srgb']});
 const page=await browser.newPage({deviceScaleFactor:1});
 const jobs=JSON.parse(fs.readFileSync(path.join(ROOT,'sources/export-jobs.json'),'utf8'));
 for(const job of jobs){
  let svg=fs.readFileSync(path.join(ROOT,job.svg),'utf8');
  svg=svg.replace(/href="([^"#]+\.png)"/g,(_,relative)=>{
   const source=path.resolve(path.dirname(path.join(ROOT,job.svg)),relative);
   return `href="data:image/png;base64,${fs.readFileSync(source).toString('base64')}"`;
  });
  await page.setViewportSize({width:job.size,height:job.size});
  await page.setContent('<style>html,body{margin:0;background:transparent}</style>'+svg);
  await page.screenshot({path:path.join(ROOT,job.file),omitBackground:true});
  console.log('Exported '+job.entityID);
 }
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
