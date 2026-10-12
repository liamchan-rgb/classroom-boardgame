const fs=require('fs'),path=require('path');const {chromium}=require('playwright');const ROOT=path.resolve(__dirname,'..');
(async()=>{const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--force-color-profile=srgb']});const page=await browser.newPage({viewport:{width:2048,height:256},deviceScaleFactor:1});
for(const fx of JSON.parse(fs.readFileSync(path.join(ROOT,'animation-manifest.json'))).effects){await page.setContent('<style>html,body{margin:0;background:transparent}</style>'+fs.readFileSync(path.join(ROOT,fx.source),'utf8'));await page.screenshot({path:path.join(ROOT,fx.file),omitBackground:true});console.log('Exported fx '+fx.effectID);}
await browser.close();})().catch(e=>{console.error(e);process.exit(1)});
