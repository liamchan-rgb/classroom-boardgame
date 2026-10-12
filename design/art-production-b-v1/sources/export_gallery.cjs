const fs=require('fs'),path=require('path');const {chromium}=require('playwright');
const ROOT=path.resolve(__dirname,'..');
(async()=>{const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--force-color-profile=srgb']});const page=await browser.newPage();
for(const job of JSON.parse(fs.readFileSync(path.join(ROOT,'sources/gallery-index.json')))){
 let svg=fs.readFileSync(path.join(ROOT,job.source),'utf8').replace(/href="([^"#]+\.png)"/g,(_,rel)=>`href="data:image/png;base64,${fs.readFileSync(path.resolve(path.dirname(path.join(ROOT,job.source)),rel)).toString('base64')}"`);
 await page.setViewportSize({width:job.width,height:job.height});await page.setContent('<style>html,body{margin:0}</style>'+svg);await page.evaluate(()=>document.fonts.ready);await page.screenshot({path:path.join(ROOT,job.file)});console.log('Exported '+job.name);
}await browser.close();})().catch(e=>{console.error(e);process.exit(1)});
